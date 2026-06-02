//
//  AlistClassify.swift
//  Stan
//
//  Slices C + D of the alist parser.
//
//  Slice C: walks the lowered statements and assigns every identifier
//  to one of five roles —
//    - outcome (LHS of the first scalar sample, by McElreath convention)
//    - scalarParam (other scalar sample LHSes)
//    - varyingParam (indexed sample LHSes)
//    - indexColumn (the bracketed name in a varying-sample LHS)
//    - dataColumn (everything else referenced from link RHS or
//      distribution args)
//
//  Slice D: layered on top — every scalar parameter that appears in
//  the σ slot of some `.normal` / `.cauchy` / `.lognormal` /
//  `.gamma` (scale-shape) distribution gets a `lower: 0` truncation in
//  its final declaration. This recovers McElreath's half-Cauchy /
//  half-normal conventions without explicit `T[0,]` in the alist.
//

import Foundation

internal struct ClassifiedAlist: Equatable {
  internal struct Statement: Equatable {
    internal enum Kind: Equatable {
      case likelihood
      case scalarPrior
      case varyingPrior(indexedBy: String)
      /// Promoted from `.scalarSample` when classify detects the LHS
      /// also appears as the σ-vector of a `.varyingVectorSample`'s
      /// `diag_pre_multiply(σ, L)` chol arg. `length` is the cardinality
      /// symbol (v1: hard-coded "J").
      case vectorPrior(length: String)
      /// Chapter-14 correlated varying effects: `c(a, b)[cafe] ~ dmvnormchol(...)`
      /// lowered to a packed parameter (`name = "ab"`) with `length`
      /// = `c(...)` arity, same cardinality symbol the companion
      /// `vectorPrior` uses.
      case varyingVectorPrior(indexedBy: String, length: String)
      /// `L_Omega ~ dlkjcorr(eta)` lowered through `.lkjCorrCholesky`,
      /// classified directly as the matching DSL prior. `dim` is the
      /// shared cardinality symbol (v1: "J") supplied by the companion
      /// `.varyingVectorSample`; without one the classify pass falls
      /// back to "J" and the user must supply it via data.
      case lkjCorrCholeskyPrior(dim: String)
      case link(LinkFunction)
    }
    internal let kind: Kind
    internal let name: String          // outcome / param / link target
    internal let dist: Distribution?   // nil for links
    internal let truncation: Truncation
    internal let linkRhs: ExpressionNode?  // non-nil only for links
  }

  internal let statements: [Statement]
  internal let outcome: String
  internal let scalarParams: [String]
  internal let varyingParams: [String]
  /// σ-vector parameters promoted from scalar (e.g. `sigma_ab` from
  /// `sigma_ab ~ dexp(1)` paired with `c(a,b)[cafe] ~ dmvnormchol(…, sigma_ab)`).
  internal let vectorParams: [String]
  /// Packed varying-vector parameters (e.g. `ab` from `c(a, b)[cafe]`).
  internal let varyingVectorParams: [String]
  /// `lengthSymbol → integer length` bindings synthesised by classify
  /// from the LHS `c(...)` arity. v1 hard-codes the symbol as "J".
  internal let lengthBindings: [String: Int]
  internal let indexColumns: [String]
  internal let dataColumns: [String]
}

internal enum AlistClassifyError: Error, CustomStringConvertible {
  case noLikelihood

  internal var description: String {
    switch self {
    case .noLikelihood:
      return "AlistClassify: alist has no `~`-shaped likelihood statement"
    }
  }
}

internal enum AlistClassify {
  /// v1 cardinality symbol used by every `.varyingVectorSample` and the
  /// promoted σ-vector(s) it implies. Multi-grouping models with
  /// distinct vector lengths aren't supported yet — they would collide
  /// on this single symbol.
  private static let varyingVectorLengthSymbol = "J"

  internal static func classify(_ lowered: [LoweredAlistStatement]) throws -> ClassifiedAlist {
    // Pre-pass: collect σ-vector promotion targets and the J length
    // binding from any `.varyingVectorSample` statements. The σ-name is
    // captured at lowering time so we don't have to re-parse the
    // diag_pre_multiply chol arg here.
    var vectorPromotions: [String: String] = [:]   // sigmaName → "J"
    var lengthBindings: [String: Int] = [:]        // "J" → 2
    var halfPositive: Set<String> = []
    for stmt in lowered {
      if case .varyingVectorSample(_, _, let len, let sName, _, _) = stmt {
        vectorPromotions[sName] = varyingVectorLengthSymbol
        lengthBindings[varyingVectorLengthSymbol] = len
        // σ-vectors flanking a Cholesky scale are conventionally
        // positive; promote them into the half-positive set the
        // truncation post-pass already consults.
        halfPositive.insert(sName)
      }
    }

    // McElreath convention: the first `~` statement (whose LHS is a
    // plain identifier, i.e. scalarSample) is the likelihood. Every
    // subsequent scalar sample is a prior on a parameter.
    var outcome: String? = nil
    var scalarParams: [String] = []
    var varyingParams: [String] = []
    var vectorParams: [String] = []
    var varyingVectorParams: [String] = []
    var indexColumns: [String] = []
    var statements: [ClassifiedAlist.Statement] = []
    var seenScalar = false

    for stmt in lowered {
      switch stmt {
      case .scalarSample(let name, let dist, let trunc):
        if !seenScalar {
          outcome = name
          seenScalar = true
          statements.append(.init(kind: .likelihood,
                                  name: name,
                                  dist: dist,
                                  truncation: trunc,
                                  linkRhs: nil))
        } else if let lengthSym = vectorPromotions[name] {
          vectorParams.append(name)
          statements.append(.init(kind: .vectorPrior(length: lengthSym),
                                  name: name,
                                  dist: dist,
                                  truncation: trunc,
                                  linkRhs: nil))
        } else if case .lkjCorrCholesky = dist {
          // dlkjcorr lowers to `.lkjCorrCholesky`; promote to the
          // dedicated DSL prior with `dim` taken from the same
          // cardinality symbol the companion varying-vector uses.
          // Track as a vector param so it isn't double-counted as a
          // scalar (the generator allocates `cholesky_factor_corr[J]`).
          vectorParams.append(name)
          statements.append(.init(
            kind: .lkjCorrCholeskyPrior(dim: varyingVectorLengthSymbol),
            name: name,
            dist: dist,
            truncation: trunc,
            linkRhs: nil))
        } else {
          scalarParams.append(name)
          statements.append(.init(kind: .scalarPrior,
                                  name: name,
                                  dist: dist,
                                  truncation: trunc,
                                  linkRhs: nil))
        }
      case .varyingSample(let name, let idx, let dist, let trunc):
        varyingParams.append(name)
        indexColumns.append(idx)
        statements.append(.init(kind: .varyingPrior(indexedBy: idx),
                                name: name,
                                dist: dist,
                                truncation: trunc,
                                linkRhs: nil))
      case .varyingVectorSample(let name, let idx, _, _, let dist, let trunc):
        varyingVectorParams.append(name)
        indexColumns.append(idx)
        statements.append(.init(
          kind: .varyingVectorPrior(indexedBy: idx,
                                    length: varyingVectorLengthSymbol),
          name: name,
          dist: dist,
          truncation: trunc,
          linkRhs: nil))
      case .link(let fn, let target, let rhs):
        statements.append(.init(kind: .link(fn),
                                name: target,
                                dist: nil,
                                truncation: .none,
                                linkRhs: rhs))
      }
    }

    guard let outcomeName = outcome else {
      throw AlistClassifyError.noLikelihood
    }

    // Data columns = every other identifier referenced anywhere in
    // link RHSes or distribution args, minus the names we already
    // know are outcomes/parameters/index columns.
    var known: Set<String> = [outcomeName]
    known.formUnion(scalarParams)
    known.formUnion(varyingParams)
    known.formUnion(vectorParams)
    known.formUnion(varyingVectorParams)
    known.formUnion(indexColumns)
    // The synthesised cardinality symbols (e.g. "J") aren't user data.
    known.formUnion(lengthBindings.keys)
    var referenced: Set<String> = []
    for stmt in statements {
      if let dist = stmt.dist {
        for arg in distributionSymbols(dist) {
          referenced.insert(arg)
        }
      }
      if let rhs = stmt.linkRhs {
        for ref in rhs.symbolReferences() {
          referenced.insert(ref.name)
        }
      }
    }
    let dataColumns = referenced.subtracting(known).sorted()

    // Slice D: σ-slot truncation inference. Walk every distribution
    // and collect names that appear as the *last* positional arg of
    // a normal / cauchy / lognormal / gamma — these are scale
    // parameters and conventionally non-negative. Augmented above
    // with σ-vector names from `.varyingVectorSample`.
    for stmt in statements {
      guard let dist = stmt.dist else { continue }
      if let scaleArg = scaleArgIfApplicable(dist),
         case .symbol(let scaleName) = scaleArg {
        halfPositive.insert(scaleName)
      }
    }
    let adjusted = statements.map { s -> ClassifiedAlist.Statement in
      let promotable: Bool = {
        if case .scalarPrior = s.kind { return true }
        if case .vectorPrior = s.kind { return true }
        return false
      }()
      if promotable, halfPositive.contains(s.name) {
        // Merge `lower: 0` into the parameter's existing truncation.
        let trunc = mergeLowerZero(s.truncation)
        return .init(kind: s.kind,
                     name: s.name,
                     dist: s.dist,
                     truncation: trunc,
                     linkRhs: s.linkRhs)
      }
      return s
    }

    return ClassifiedAlist(
      statements: adjusted,
      outcome: outcomeName,
      scalarParams: scalarParams,
      varyingParams: varyingParams,
      vectorParams: vectorParams,
      varyingVectorParams: varyingVectorParams,
      lengthBindings: lengthBindings,
      indexColumns: indexColumns.uniqued(),
      dataColumns: dataColumns)
  }

  // MARK: - Helpers

  private static func distributionSymbols(_ d: Distribution) -> [String] {
    // multivariateNormalCholesky's args are compound source-string
    // expressions (`[a_bar, b_bar]'`, `diag_pre_multiply(sigma, L)`).
    // Delegate to the same tokenizer DataInference uses so the alist
    // pipeline's symbol tracking sees the embedded identifiers (not
    // the whole source string).
    if case .multivariateNormalCholesky = d {
      return DistributionCatalog.symbolsReferenced(d)
    }
    func sym(_ a: DistributionArg) -> [String] {
      if case .symbol(let n) = a { return [n] }
      return []
    }
    switch d {
    case .normal(let a, let b), .cauchy(let a, let b),
         .lognormal(let a, let b), .uniform(let a, let b),
         .beta(let a, let b), .gamma(let a, let b),
         .multivariateNormal(let a, let b):
      return sym(a) + sym(b)
    case .bernoulli(let p), .exponential(let p), .poisson(let p):
      return sym(p)
    case .binomial(let n, let p):
      return sym(n) + sym(p)
    case .studentT(let nu, let mu, let sigma):
      return sym(nu) + sym(mu) + sym(sigma)
    case .lkjCorrCholesky(let eta):
      return sym(eta)
    case .multivariateNormalCholesky:
      return []  // handled above
    case .wishart(let nu, let V):
      return sym(nu) + sym(V)
    case .orderedLogistic(let eta, let cp),
         .orderedProbit(let eta, let cp):
      return sym(eta) + sym(cp)
    }
  }

  /// The σ / scale arg for distributions where it makes sense to
  /// infer `lower: 0`. Returns nil for distributions without a
  /// well-defined positive-scale slot.
  private static func scaleArgIfApplicable(_ d: Distribution) -> DistributionArg? {
    switch d {
    case .normal(_, let sigma):     return sigma
    case .cauchy(_, let sigma):     return sigma
    case .lognormal(_, let sigma):  return sigma
    case .studentT(_, _, let sigma): return sigma
    case .gamma(_, let rate):       return rate
    // multivariateNormal's σ is a covariance matrix — handled by V1
    // outside the lower:0 path.
    default:                        return nil
    }
  }

  private static func mergeLowerZero(_ trunc: Truncation) -> Truncation {
    if trunc.lower != nil { return trunc }
    return Truncation(lower: 0, upper: trunc.upper)
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen: Set<Element> = []
    var out: [Element] = []
    for x in self where seen.insert(x).inserted { out.append(x) }
    return out
  }
}

// MARK: - Stub-data heuristic (shared by AlistEmitter + AlistToUlamModel)
//
// Per Docs/AlistParser.md Q1(b): integer columns are likelihood
// outcomes of bernoulli/binomial/poisson and any column used as a
// `[col]` index; everything else is real. The actual values come
// from the CSV downstream (csv2json).

internal enum StubDataKind: Equatable {
  case integer
  case real
}

extension ClassifiedAlist {
  internal func stubKind(for column: String) -> StubDataKind {
    if indexColumns.contains(column) { return .integer }
    if column == outcome,
       let likelihood = statements.first(where: { $0.kind == .likelihood }),
       let dist = likelihood.dist,
       Self.isIntegerOutcome(dist) {
      return .integer
    }
    return .real
  }

  private static func isIntegerOutcome(_ d: Distribution) -> Bool {
    switch d {
    case .bernoulli, .binomial, .poisson: return true
    default: return false
    }
  }
}
