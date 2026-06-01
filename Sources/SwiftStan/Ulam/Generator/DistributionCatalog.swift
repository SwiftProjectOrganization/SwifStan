//
//  DistributionCatalog.swift
//  Stan
//
//  Render Distribution values to Stan source, report which symbols they
//  reference, classify them as discrete vs continuous (for the
//  `_lpmf`/`_lpdf` choice), and render Truncation suffixes.
//
//  Per-distribution arg-order conversion lives here so the rest of the
//  generator stays distribution-agnostic. Argument orderings happen to
//  match Stan in every Phase 1/3 case we ship — the table below makes
//  that visible.
//

import Foundation

enum DistributionCatalog {

  // MARK: - Sampling form: `dist(args)`

  static func render(_ distribution: Distribution) -> String {
    "\(name(distribution))(\(args(distribution)))"
  }

  /// Stan distribution name with no parens. Used as the base for
  /// `_lpdf`/`_lpmf` emission.
  static func name(_ distribution: Distribution) -> String {
    switch distribution {
    case .normal: return "normal"
    case .bernoulli: return "bernoulli"
    case .binomial: return "binomial"
    case .beta: return "beta"
    case .exponential: return "exponential"
    case .poisson: return "poisson"
    case .gamma: return "gamma"
    case .cauchy: return "cauchy"
    case .lognormal: return "lognormal"
    case .uniform: return "uniform"
    case .studentT: return "student_t"
    case .multivariateNormal: return "multi_normal"
    case .lkjCorrCholesky: return "lkj_corr_cholesky"
    case .multivariateNormalCholesky: return "multi_normal_cholesky"
    }
  }

  /// Comma-separated argument list (no parens). Useful for both the
  /// `dist(args)` and `dist_lpdf(y | args)` forms.
  static func args(_ distribution: Distribution) -> String {
    switch distribution {
    case .normal(let mu, let sigma):        return "\(arg(mu)), \(arg(sigma))"
    case .bernoulli(let p):                 return "\(arg(p))"
    case .binomial(let n, let p):           return "\(arg(n)), \(arg(p))"
    case .beta(let a, let b):               return "\(arg(a)), \(arg(b))"
    case .exponential(let r):               return "\(arg(r))"
    case .poisson(let r):                   return "\(arg(r))"
    case .gamma(let shape, let rate):       return "\(arg(shape)), \(arg(rate))"
    case .cauchy(let mu, let sigma):        return "\(arg(mu)), \(arg(sigma))"
    case .lognormal(let mu, let sigma):     return "\(arg(mu)), \(arg(sigma))"
    case .uniform(let lower, let upper):    return "\(arg(lower)), \(arg(upper))"
    case .studentT(let nu, let mu, let s):  return "\(arg(nu)), \(arg(mu)), \(arg(s))"
    case .multivariateNormal(let mu, let s):return "\(arg(mu)), \(arg(s))"
    case .lkjCorrCholesky(let eta):         return "\(arg(eta))"
    case .multivariateNormalCholesky(let mean, let chol):
                                            return "\(arg(mean)), \(arg(chol))"
    }
  }

  /// Distributions with integer support — Stan uses `_lpmf` (mass)
  /// rather than `_lpdf` (density) for these.
  static func isDiscrete(_ distribution: Distribution) -> Bool {
    switch distribution {
    case .bernoulli, .binomial, .poisson:
      return true
    case .normal, .beta, .exponential, .gamma, .cauchy, .lognormal, .uniform,
         .studentT, .multivariateNormal, .lkjCorrCholesky,
         .multivariateNormalCholesky:
      return false
    }
  }

  /// True for distributions whose LHS is a vector / matrix
  /// rather than a scalar. Phase 6 uses this to reject truncation on
  /// the multivariate-normal case (Stan doesn't support `T[...]` on
  /// multivariate distributions). LKJ-Cholesky takes a scalar `eta`
  /// arg but samples a triangular matrix, so it counts as
  /// multivariate for the truncation-rejection purpose.
  static func isMultivariate(_ distribution: Distribution) -> Bool {
    switch distribution {
    case .multivariateNormal, .lkjCorrCholesky, .multivariateNormalCholesky:
      return true
    case .normal, .bernoulli, .binomial, .beta, .exponential, .poisson,
         .gamma, .cauchy, .lognormal, .uniform, .studentT:
      return false
    }
  }

  // MARK: - Symbol extraction

  static func symbolsReferenced(_ distribution: Distribution) -> [String] {
    // Multivariate hierarchical priors (2026-05-31): the args of
    // `multi_normal_cholesky` are compound source-string expressions
    // (`[a_bar, b_bar]'`, `diag_pre_multiply(sigma_ab, L_Omega)`)
    // rather than bare identifiers. Tokenise them into individual
    // identifiers and filter Stan helpers so DataInference's
    // referenced-symbol check sees only the user-named symbols.
    if case .multivariateNormalCholesky(let mean, let chol) = distribution {
      let strings = [mean, chol].compactMap {
        if case .symbol(let s) = $0 { return s } else { return nil }
      }
      return strings.flatMap { tokenizeIdentifiers($0) }
    }
    let parts: [DistributionArg]
    switch distribution {
    case .normal(let a, let b):             parts = [a, b]
    case .bernoulli(let p):                 parts = [p]
    case .binomial(let n, let p):           parts = [n, p]
    case .beta(let a, let b):               parts = [a, b]
    case .exponential(let r):               parts = [r]
    case .poisson(let r):                   parts = [r]
    case .gamma(let a, let b):              parts = [a, b]
    case .cauchy(let a, let b):             parts = [a, b]
    case .lognormal(let a, let b):          parts = [a, b]
    case .uniform(let a, let b):            parts = [a, b]
    case .studentT(let a, let b, let c):    parts = [a, b, c]
    case .multivariateNormal(let a, let b): parts = [a, b]
    case .lkjCorrCholesky(let eta):         parts = [eta]
    case .multivariateNormalCholesky:       parts = [] // handled above
    }
    return parts.compactMap {
      if case .symbol(let s) = $0 { return s } else { return nil }
    }
  }

  /// Multivariate hierarchical priors (2026-05-31): identifier
  /// tokeniser for compound distribution-arg source strings. Returns
  /// every `[A-Za-z_][A-Za-z0-9_]*` token that isn't a recognised
  /// Stan helper. Used by `symbolsReferenced` for distributions whose
  /// args are full source-level expressions rather than bare symbols.
  private static func tokenizeIdentifiers(_ source: String) -> [String] {
    let pattern = "[A-Za-z_][A-Za-z0-9_]*"
    let regex = try! NSRegularExpression(pattern: pattern)
    let nsString = source as NSString
    let matches = regex.matches(in: source,
                                range: NSRange(location: 0, length: nsString.length))
    let tokens = matches.map { nsString.substring(with: $0.range) }
    return tokens.filter { !stanHelperBuiltins.contains($0) }
  }

  /// Stan helper functions that may appear inside compound
  /// distribution-arg source strings. Filtered out by
  /// `tokenizeIdentifiers` so DataInference doesn't reject the model
  /// with `undeclaredSymbol(...)`.
  private static let stanHelperBuiltins: Set<String> = [
    "diag_pre_multiply",
    "diag_post_multiply",
    "cholesky_decompose",
    "quad_form_diag",
    "to_vector",
    "to_row_vector",
    "transpose",
  ]

  static func symbolsReferenced(_ truncation: Truncation) -> [String] {
    var symbols: [String] = []
    if let lower = truncation.lower, case .symbol(let s) = lower {
      symbols.append(s)
    }
    if let upper = truncation.upper, case .symbol(let s) = upper {
      symbols.append(s)
    }
    return symbols
  }

  // MARK: - Truncation suffix

  /// Render ` T[lower, upper]` for the `~` sampling form. Returns an
  /// empty string when neither bound is set. One-sided is supported:
  /// `T[0, ]` (lower only), `T[ , 1]` (upper only).
  static func renderTruncation(_ truncation: Truncation) -> String {
    if truncation.isEmpty { return "" }
    let lower = truncation.lower.map { arg($0) } ?? ""
    let upper = truncation.upper.map { arg($0) } ?? ""
    return " T[\(lower), \(upper)]"
  }

  // MARK: - Bound rendering

  /// Render a Truncation as a parameter-declaration constraint suffix
  /// — e.g. `<lower=0>`, `<upper=1>`, `<lower=0, upper=1>`, or `""`
  /// when no bound is set. Used to constrain parameter declarations
  /// derived from prior truncations.
  static func renderConstraint(_ truncation: Truncation) -> String {
    if truncation.isEmpty { return "" }
    var parts: [String] = []
    if let lower = truncation.lower { parts.append("lower=\(arg(lower))") }
    if let upper = truncation.upper { parts.append("upper=\(arg(upper))") }
    return "<" + parts.joined(separator: ", ") + ">"
  }

  // MARK: - Outcome bounds

  /// Bound constraints emitted on the integer-vector data declaration
  /// for a likelihood's LHS. Continuous-outcome distributions return
  /// `(nil, nil)`; the generator falls back to an unbounded `vector[N]`
  /// declaration in that case.
  struct OutcomeBounds: Hashable, Sendable {
    let lower: String?
    let upper: String?
    var isEmpty: Bool { lower == nil && upper == nil }
  }

  static func outcomeBounds(_ distribution: Distribution) -> OutcomeBounds {
    switch distribution {
    case .bernoulli:
      return OutcomeBounds(lower: "0", upper: "1")
    case .binomial, .poisson:
      // Binomial's upper bound is per-row (`trials[i]`); flat array
      // declarations can't express that. Leave upper unset for Phase 4
      // and revisit if a `transformed data` validation block lands.
      return OutcomeBounds(lower: "0", upper: nil)
    case .normal, .beta, .exponential, .gamma, .cauchy,
         .lognormal, .uniform, .studentT, .multivariateNormal,
         .lkjCorrCholesky, .multivariateNormalCholesky:
      return OutcomeBounds(lower: nil, upper: nil)
    }
  }

  // MARK: - Argument rendering

  static func arg(_ a: DistributionArg) -> String {
    switch a {
    case .literal(let x):
      // Whole numbers render without ".0" to match hand-written Stan.
      if x == x.rounded() && abs(x) < 1e15 {
        return String(Int(x))
      } else {
        return String(x)
      }
    case .symbol(let s):
      return s
    }
  }
}
