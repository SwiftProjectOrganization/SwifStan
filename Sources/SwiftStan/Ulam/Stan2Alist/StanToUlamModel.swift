//
//  StanToUlamModel.swift
//  Stan
//
//  Slice C of Docs/Stan2AlistCommandPlan.md — reverse of
//  `AlistToUlamModel` + `DataInference`. Takes a parsed `StanProgram`
//  and reconstructs the canonical `[Statement]` list that the alist
//  emitter (Slice D) renders back to McElreath `alist()` syntax.
//
//  Role inference leans on Stan's block structure, which already
//  separates data from parameters — the hard part the forward
//  `DataInference` had to *infer*:
//    - likelihood   = the `~` line whose LHS is a (non-index) data vector
//    - varyingPrior = the `~` line whose LHS is a vector parameter whose
//                     size symbol matches an index column's `upper` bound
//    - prior        = the `~` line whose LHS is a scalar parameter
//    - link/det     = `lhs = inv_logit(rhs)` / `lhs = exp(rhs)` / `lhs = rhs`
//
//  Deliberately lossy, per the v1 plan:
//    - Declaration `<lower=…, upper=…>` constraints are DROPPED. They are
//      re-derived on the forward pass by `AlistClassify` (σ-slot
//      positivity, bounded-support priors). A constraint with no such
//      source isn't representable in alist text and is simply dropped.
//    - `<offset=…, multiplier=…>` affine non-centering is stripped — the
//      reconstructed varying prior is centred (semantically identical).
//    - `generated quantities` / `transformed *` blocks were already
//      dropped by the parser; we surface them here as warnings.
//

import Foundation

enum StanToUlamError: Error, CustomStringConvertible {
  case noLikelihood
  case multipleLikelihoods([String])
  case unsupportedDeclaration(String)
  case unsupportedModelStatement(String)

  var description: String {
    switch self {
    case .noLikelihood:
      return "stan2alist: no likelihood found (no `~` statement over a data variable)"
    case .multipleLikelihoods(let names):
      return "stan2alist: multiple likelihood candidates \(names) — v1 supports a single outcome"
    case .unsupportedDeclaration(let s):
      return "stan2alist: unsupported declaration \"\(s)\""
    case .unsupportedModelStatement(let s):
      return "stan2alist: unsupported model statement — \(s)"
    }
  }
}

enum StanToUlamModel {

  struct Result {
    let statements: [Statement]
    /// Non-fatal notes (dropped blocks, etc.) surfaced to the user.
    let warnings: [String]
  }

  static func build(_ program: StanProgram) throws -> Result {
    var warnings: [String] = []
    for block in program.droppedBlocks {
      warnings.append("dropped Stan block '\(block)' — no alist representation; not translated")
    }

    // MARK: Classify data declarations.
    var dataVectorNames: Set<String> = []
    var indexColumnNames: Set<String> = []
    var columnByCardinality: [String: String] = [:]   // size symbol → index column
    for decl in program.dataDecls {
      switch decl.type {
      case .int, .real:
        // Scalar — a cardinality symbol (`N`, `N_x`) or a scalar data
        // value. Neither contributes a statement; consumed silently.
        continue
      case .vector, .arrayReal:
        dataVectorNames.insert(decl.name)
      case .arrayInt:
        dataVectorNames.insert(decl.name)
        // An integer per-row column whose `upper` bound is a symbol is a
        // group-index column (`array[N] int<lower=1, upper=N_county> county`).
        if let upper = decl.constraints.upper, isSymbol(upper) {
          indexColumnNames.insert(decl.name)
          columnByCardinality[upper] = decl.name
        }
      case .other(let spec):
        throw StanToUlamError.unsupportedDeclaration("\(spec) \(decl.name)")
      }
    }

    // MARK: Classify parameter declarations.
    var scalarParams: Set<String> = []
    var vectorParamSize: [String: String] = [:]   // name → size symbol
    for decl in program.parameterDecls {
      switch decl.type {
      case .real, .int:
        scalarParams.insert(decl.name)
      case .vector(let size):
        vectorParamSize[decl.name] = size
      case .arrayInt, .arrayReal, .other:
        throw StanToUlamError.unsupportedDeclaration(decl.raw)
      }
    }

    // MARK: Walk the model block.
    var likelihoods: [Statement] = []
    var links: [Statement] = []
    var priors: [Statement] = []

    for stmt in program.modelStatements {
      switch stmt {
      case let .assignment(lhs, rhs):
        links.append(reconstructAssignment(lhs: lhs, rhs: rhs))

      case let .sampling(lhs, distName, args, trunc):
        let dist = try DistributionCatalog.distribution(fromStanName: distName, args: args)
        let truncation = toTruncation(trunc)

        if dataVectorNames.contains(lhs) && !indexColumnNames.contains(lhs) {
          likelihoods.append(.likelihood(lhs: lhs,
                                         distribution: dist,
                                         truncation: truncation,
                                         useLpdf: false))
        } else if scalarParams.contains(lhs) {
          priors.append(.prior(name: lhs,
                               distribution: dist,
                               truncation: truncation,
                               constraints: .none,
                               start: nil,
                               useLpdf: false))
        } else if let size = vectorParamSize[lhs] {
          guard let indexColumn = columnByCardinality[size] else {
            throw StanToUlamError.unsupportedModelStatement(
              "vector parameter '\(lhs)' is not indexed by a known data column (plain vector priors are out of v1 scope)")
          }
          priors.append(.varyingPrior(name: lhs,
                                      indexedBy: indexColumn,
                                      countSymbol: nil,
                                      distribution: dist,
                                      truncation: truncation,
                                      constraints: .none,
                                      start: nil,
                                      useLpdf: false,
                                      nonCentered: false))
        } else {
          throw StanToUlamError.unsupportedModelStatement(
            "sampling target '\(lhs)' is neither a data outcome nor a declared parameter")
        }
      }
    }

    guard !likelihoods.isEmpty else { throw StanToUlamError.noLikelihood }
    guard likelihoods.count == 1 else {
      throw StanToUlamError.multipleLikelihoods(likelihoods.map(likelihoodName))
    }

    // McElreath order: likelihood first (so re-classification picks the
    // outcome), then the linear model, then the priors.
    let statements = likelihoods + links + priors
    return Result(statements: statements, warnings: warnings)
  }

  // MARK: - Helpers

  /// `lhs = inv_logit(rhs)` → `.link(.logit, …)`, `exp` → `.log`,
  /// `logit` → `.invLogit`; anything else is a plain deterministic
  /// assignment. The case names follow ulam (the link), the Stan
  /// emission is the inverse — see `LinkFunction`.
  private static func reconstructAssignment(lhs: String, rhs: String) -> Statement {
    if let inner = singleCall(rhs, "inv_logit") {
      return .link(function: .logit, lhs: lhs, rhs: Expression(inner))
    }
    if let inner = singleCall(rhs, "exp") {
      return .link(function: .log, lhs: lhs, rhs: Expression(inner))
    }
    if let inner = singleCall(rhs, "logit") {
      return .link(function: .invLogit, lhs: lhs, rhs: Expression(inner))
    }
    return .deterministic(lhs: lhs, rhs: Expression(rhs))
  }

  /// If `rhs` is exactly `fn(<balanced>)` — the call wraps the whole
  /// expression — return its inner source; otherwise nil. Guards against
  /// `exp(x) + exp(y)`, where the trailing `)` doesn't match the first `(`.
  private static func singleCall(_ rhs: String, _ fn: String) -> String? {
    let prefix = fn + "("
    guard rhs.hasPrefix(prefix), rhs.hasSuffix(")") else { return nil }
    let chars = Array(rhs)
    let openIdx = fn.count   // index of the '(' right after the name
    var depth = 0
    for i in openIdx..<chars.count {
      if chars[i] == "(" { depth += 1 }
      else if chars[i] == ")" {
        depth -= 1
        if depth == 0 {
          return i == chars.count - 1 ? String(chars[(openIdx + 1)..<i]) : nil
        }
      }
    }
    return nil
  }

  private static func toTruncation(_ t: StanTruncation?) -> Truncation {
    guard let t else { return .none }
    return Truncation(lower: t.lower.map { DistributionCatalog.distributionArg(from: $0) },
                      upper: t.upper.map { DistributionCatalog.distributionArg(from: $0) })
  }

  /// Identifier-like and not a numeric literal.
  private static func isSymbol(_ s: String) -> Bool {
    if Double(s) != nil { return false }
    guard let first = s.first, first == "_" || first.isLetter else { return false }
    return s.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
  }

  private static func likelihoodName(_ s: Statement) -> String {
    if case let .likelihood(lhs, _, _, _) = s { return lhs }
    return ""
  }
}
