//
//  AlistTextEmitter.swift
//  Stan
//
//  Slice D of Docs/Stan2AlistCommandPlan.md — renders the reconstructed
//  `[Statement]` list (Slice C) as McElreath `alist()` R source. This is
//  the text that `stan2alist` writes to `Preliminaries/<name>.alist.R`.
//
//  The emitter does NOT aim for byte-identical alist text — the round-trip
//  oracle is at the Stan level (alist → stancode → stan2alist → stancode).
//  It only has to produce alist source that `AlistParser` accepts and that
//  re-classifies to the same model. Two deliberate choices:
//
//    - `bernoulli(p)` is rendered as McElreath's `dbinom(1, p)` idiom.
//    - Distribution arg ORDER is reused verbatim from
//      `DistributionCatalog.args(_:)` — it matches the `rethinking`
//      R-side order for every univariate distribution in v1 scope
//      (dnorm↔normal, dbinom↔binomial, dcauchy↔cauchy, dunif↔uniform, …).
//
//  `c(a, b, c) ~ dnorm(...)` regrouping is intentionally NOT performed:
//  three separate `~` priors lower to the same Stan as one grouped line,
//  so the Stan-level oracle is unaffected (see plan §9).
//

import Foundation

enum AlistTextEmitError: Error, CustomStringConvertible {
  case unsupportedStatement(String)
  case unsupportedLink(String)

  var description: String {
    switch self {
    case .unsupportedStatement(let s):
      return "stan2alist: cannot render statement to alist — \(s)"
    case .unsupportedLink(let s):
      return "stan2alist: link function '\(s)' has no alist representation"
    }
  }
}

enum AlistTextEmitter {

  /// Render the statement list as a full `alist( … )` block, one
  /// statement per line, 2-space indented, comma-separated, trailing
  /// newline.
  static func emit(_ statements: [Statement]) throws -> String {
    let lines = try statements.map(renderStatement)
    let body = lines.map { "  " + $0 }.joined(separator: ",\n")
    return "alist(\n\(body)\n)\n"
  }

  // MARK: - Statements

  private static func renderStatement(_ statement: Statement) throws -> String {
    switch statement {
    case let .likelihood(lhs, dist, _, _):
      return "\(lhs) ~ \(renderDistribution(dist))"
    case let .prior(name, dist, _, _, _, _):
      return "\(name) ~ \(renderDistribution(dist))"
    case let .varyingPrior(name, indexedBy, _, dist, _, _, _, _, _):
      return "\(name)[\(indexedBy)] ~ \(renderDistribution(dist))"
    case let .link(function, lhs, rhs):
      let fn = try linkName(function)
      return "\(fn)(\(lhs)) <- \(rhs.source)"
    case let .deterministic(lhs, rhs):
      return "\(lhs) <- \(rhs.source)"
    default:
      throw AlistTextEmitError.unsupportedStatement(String(describing: statement))
    }
  }

  private static func linkName(_ function: LinkFunction) throws -> String {
    switch function {
    case .logit: return "logit"
    case .log:   return "log"
    case .invLogit:
      // Stan's `logit(x)` inverse-link has no McElreath alist spelling.
      // Not produced by any v1-scope model; fail loud if it ever is.
      throw AlistTextEmitError.unsupportedLink("invLogit")
    }
  }

  // MARK: - Distributions

  private static func renderDistribution(_ dist: Distribution) -> String {
    // McElreath spells a Bernoulli as a single-trial Binomial.
    if case let .bernoulli(p) = dist {
      return "dbinom(1, \(DistributionCatalog.arg(p)))"
    }
    return "\(DistributionCatalog.mcElreathName(dist))(\(DistributionCatalog.args(dist)))"
  }
}
