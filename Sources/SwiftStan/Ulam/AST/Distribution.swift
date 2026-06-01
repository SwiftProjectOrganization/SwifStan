//
//  Distribution.swift
//  Stan
//
//  Phase 1 introduced the small Bernoulli/Beta/Normal/Binomial/Exponential
//  set used for the canonical Statistical Rethinking opening example.
//  Phase 3 widens this to Poisson, Gamma, Cauchy, LogNormal, Uniform,
//  and Student-t.
//

import Foundation

/// A scalar argument to a distribution — either a numeric literal or a
/// reference to a named symbol (parameter or data value).
public enum DistributionArg: Hashable, Sendable {
  case literal(Double)
  case symbol(String)
}

extension DistributionArg: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) {
    self = .literal(Double(value))
  }
}

extension DistributionArg: ExpressibleByFloatLiteral {
  public init(floatLiteral value: Double) {
    self = .literal(value)
  }
}

extension DistributionArg: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .symbol(value)
  }
}

public enum Distribution: Hashable, Sendable {
  // Phase 1
  case normal(_ mu: DistributionArg, _ sigma: DistributionArg)
  case bernoulli(p: DistributionArg)
  case binomial(n: DistributionArg, p: DistributionArg)
  case beta(_ alpha: DistributionArg, _ beta: DistributionArg)
  case exponential(_ rate: DistributionArg)
  // Phase 3
  case poisson(_ rate: DistributionArg)
  case gamma(_ shape: DistributionArg, _ rate: DistributionArg)
  case cauchy(_ mu: DistributionArg, _ sigma: DistributionArg)
  case lognormal(_ mu: DistributionArg, _ sigma: DistributionArg)
  case uniform(_ lower: DistributionArg, _ upper: DistributionArg)
  case studentT(_ nu: DistributionArg, _ mu: DistributionArg, _ sigma: DistributionArg)
  // Phase 6 — multivariate normal. `mu` is a vector-typed symbol;
  // `sigma` is a matrix-typed symbol (cov_matrix). The DistributionArg
  // stays scalar-typed in v1 — the symbols are emitted verbatim and
  // Stan catches type mismatches at compile time.
  case multivariateNormal(_ mu: DistributionArg, _ sigma: DistributionArg)
  // Multivariate hierarchical priors (2026-05-31) — LKJ prior on a
  // Cholesky-factored correlation matrix. Used as the prior on a
  // `cholesky_factor_corr[J]` parameter. The single `eta` arg shapes
  // the LKJ density (η=1 → uniform over correlation matrices, η>1
  // concentrates around the identity).
  case lkjCorrCholesky(_ eta: DistributionArg)
  // Multivariate hierarchical priors (2026-05-31) — multivariate
  // normal taking a Cholesky factor of the covariance directly. The
  // mean arg is typically a row-vector expression
  // (`[a_bar, b_bar]'`); the chol arg is typically a
  // `diag_pre_multiply(sigma, L_Omega)` call. Both render into Stan
  // source verbatim; identifier symbols inside the source strings are
  // discovered by tokenisation in DistributionCatalog so the
  // generator doesn't flag them as undeclared.
  case multivariateNormalCholesky(_ mean: DistributionArg, _ chol: DistributionArg)
}
