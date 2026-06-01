//
//  DSLNodes.swift
//  Stan
//
//  Phase 1 of the ulam port: the four DSL surface types used inside an
//  `UlamModel { ... }` body. Each lowers to one `Statement`.
//

import Foundation

public struct Likelihood: ModelStatement {
  public let lhs: String
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool

  public init(_ lhs: String,
              _ distribution: Distribution,
              truncation: Truncation = .none,
              useLpdf: Bool = false) {
    self.lhs = lhs
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
  }

  public var statement: Statement {
    .likelihood(lhs: lhs, distribution: distribution,
                truncation: truncation, useLpdf: useLpdf)
  }
}

public struct Prior: ModelStatement {
  public let name: String
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool

  public init(_ name: String,
              _ distribution: Distribution,
              truncation: Truncation = .none,
              useLpdf: Bool = false) {
    self.name = name
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
  }

  public var statement: Statement {
    .prior(name: name, distribution: distribution,
           truncation: truncation, useLpdf: useLpdf)
  }
}

/// Phase 6: `mu ~ multi_normal(zero, Sigma)` — plain vector parameter
/// with a multivariate-normal prior. The generator declares
/// `vector[<length>] mu;` in `parameters`. `length` is a cardinality
/// symbol that must be bound by some data column carrying that numeric
/// length (typically the `K` shared with `zero`, `Sigma_prior`,
/// `Sigma_obs` in a bivariate mean-estimation model).
public struct VectorPrior: ModelStatement {
  public let name: String
  public let length: String
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool

  public init(_ name: String,
              length: String,
              _ distribution: Distribution,
              truncation: Truncation = .none,
              useLpdf: Bool = false) {
    self.name = name
    self.length = length
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
  }

  public var statement: Statement {
    .vectorPrior(name: name,
                 length: length,
                 distribution: distribution,
                 truncation: truncation,
                 useLpdf: useLpdf)
  }
}

/// Phase 5: `a[group] ~ normal(a_bar, sigma_a)` — varying-intercept
/// (or varying-coefficient) prior. The generator declares `a` as
/// `vector[N_group]` and `group` as a bounded integer index column.
/// Pass `countSymbol:` to override the auto-derived `N_<indexedBy>`
/// cardinality variable name (e.g. `countSymbol: "K"` to get
/// `vector[K] a;` instead of `vector[N_group] a;`).
///
/// Phase 5.5 Slice E: pass `nonCentered: true` to emit the Matt
/// Trick non-centred parameterisation (`a_raw ~ std_normal();`
/// in `model {}`, `a = a_bar + sigma_a * a_raw;` in
/// `transformed parameters {}`). Only supported with `.normal(...)`
/// and an empty truncation.
public struct VaryingPrior: ModelStatement {
  public let name: String
  public let indexedBy: String
  public let countSymbol: String?
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool
  public let nonCentered: Bool

  public init(_ name: String,
              indexedBy: String,
              _ distribution: Distribution,
              countSymbol: String? = nil,
              truncation: Truncation = .none,
              useLpdf: Bool = false,
              nonCentered: Bool = false) {
    self.name = name
    self.indexedBy = indexedBy
    self.countSymbol = countSymbol
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
    self.nonCentered = nonCentered
  }

  public var statement: Statement {
    .varyingPrior(name: name,
                  indexedBy: indexedBy,
                  countSymbol: countSymbol,
                  distribution: distribution,
                  truncation: truncation,
                  useLpdf: useLpdf,
                  nonCentered: nonCentered)
  }
}

/// SUR Slice A (2026-05-30): `matrix[<rows>, <cols>] <name>;` parameter.
/// The generator declares the matrix in `parameters {}` and emits an
/// iid prior over every entry via `to_vector(<name>) ~ <dist>(args);`
/// — the idiomatic Stan way to put one prior on a whole matrix.
///
/// Used as the per-outcome coefficient matrix β in Seemingly Unrelated
/// Regressions:
///
/// ```swift
/// MatrixPrior("beta", rows: "K", cols: "J", .normal(0, 1))
/// ```
///
/// Both `rows` and `cols` are cardinality symbols (strings) — they
/// must be bound by either a scalar-int data column carrying that
/// name (`"K": .scalarInt(2)`) or a matrix data column whose shape
/// supplies the value.
public struct MatrixPrior: ModelStatement {
  public let name: String
  public let rows: String
  public let cols: String
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool

  public init(_ name: String,
              rows: String,
              cols: String,
              _ distribution: Distribution,
              truncation: Truncation = .none,
              useLpdf: Bool = false) {
    self.name = name
    self.rows = rows
    self.cols = cols
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
  }

  public var statement: Statement {
    .matrixPrior(name: name,
                 rows: rows,
                 cols: cols,
                 distribution: distribution,
                 truncation: truncation,
                 useLpdf: useLpdf)
  }
}

/// SUR Slice B (2026-05-30): `cov_matrix[<dim>] <name>;` parameter.
/// v1 emits no explicit prior — Stan's positive-definite constraint
/// gives the sampler a workable default. Used as the row-level error
/// covariance Σ in SUR models.
///
/// ```swift
/// CovMatrixPrior("Sigma", dim: "J")
/// ```
public struct CovMatrixPrior: ModelStatement {
  public let name: String
  public let dim: String

  public init(_ name: String, dim: String) {
    self.name = name
    self.dim = dim
  }

  public var statement: Statement {
    .covMatrixPrior(name: name, dim: dim)
  }
}

/// Multivariate hierarchical priors Slice A (2026-05-31):
/// `cholesky_factor_corr[<dim>] <name>;` parameter with an LKJ-Cholesky
/// prior on the implied correlation matrix:
///
/// ```swift
/// LKJCorrCholeskyPrior("L_Omega", dim: "J", eta: 2)
/// ```
///
/// Emits the parameter declaration plus
/// `<name> ~ lkj_corr_cholesky(<eta>);` in the model block. `dim` is a
/// cardinality symbol the user binds to a scalar-int data column.
public struct LKJCorrCholeskyPrior: ModelStatement {
  public let name: String
  public let dim: String
  public let eta: DistributionArg

  public init(_ name: String, dim: String, eta: DistributionArg) {
    self.name = name
    self.dim = dim
    self.eta = eta
  }

  public var statement: Statement {
    .lkjCorrCholeskyPrior(name: name, dim: dim, eta: eta)
  }
}

/// Wishart prior on a `cov_matrix[<dim>]` parameter:
///
/// ```swift
/// WishartPrior("Omega", dim: "K", nu: "nu", V: "V_scale")
/// ```
///
/// Declares `cov_matrix[K] Omega;` in the parameters block and emits
/// `Omega ~ wishart(nu, V_scale);` in the model block. `dim` is a
/// cardinality symbol bound to a scalar-int data column; `V` is a symbol
/// referencing a `cov_matrix`-typed data column (the scale matrix).
public struct WishartPrior: ModelStatement {
  public let name: String
  public let dim: String
  public let nu: DistributionArg
  public let V: DistributionArg

  public init(_ name: String, dim: String,
              nu: DistributionArg, V: DistributionArg) {
    self.name = name
    self.dim = dim
    self.nu = nu
    self.V = V
  }

  public var statement: Statement {
    .wishartPrior(name: name, dim: dim, nu: nu, V: V)
  }
}

/// Multivariate hierarchical priors Slice C (2026-05-31):
/// `array[N_<indexedBy>] vector[<length>] <name>;` — vector-valued
/// varying effects with a multivariate prior over the per-group vector:
///
/// ```swift
/// VaryingVectorPrior(
///   "ab", indexedBy: "cafe", length: "J",
///   .multivariateNormalCholesky("[a_bar, b_bar]'",
///                               "diag_pre_multiply(sigma_ab, L_Omega)")
/// )
/// ```
///
/// `indexedBy` is the group-id data column (same role as in
/// `VaryingPrior`); `length` is the inner-vector cardinality (typically
/// the same one used by the companion `LKJCorrCholeskyPrior`).
/// `countSymbol`, when non-nil, overrides the auto-derived `N_<col>`
/// outer cardinality.
public struct VaryingVectorPrior: ModelStatement {
  public let name: String
  public let indexedBy: String
  public let length: String
  public let countSymbol: String?
  public let distribution: Distribution
  public let truncation: Truncation
  public let useLpdf: Bool

  public init(_ name: String,
              indexedBy: String,
              length: String,
              _ distribution: Distribution,
              countSymbol: String? = nil,
              truncation: Truncation = .none,
              useLpdf: Bool = false) {
    self.name = name
    self.indexedBy = indexedBy
    self.length = length
    self.countSymbol = countSymbol
    self.distribution = distribution
    self.truncation = truncation
    self.useLpdf = useLpdf
  }

  public var statement: Statement {
    .varyingVectorPrior(name: name,
                        indexedBy: indexedBy,
                        length: length,
                        countSymbol: countSymbol,
                        distribution: distribution,
                        truncation: truncation,
                        useLpdf: useLpdf)
  }
}

/// Gaussian process prior (2026-06-01) — McElreath Chapter 14 oceanic
/// tools shape. Declares an N-length latent vector with a
/// squared-exponential GP prior keyed on a precomputed `distanceMatrix`
/// data column (must be `matrix[N, N]`). v1 ships the squared-exponential
/// (`cov_GPL2`) kernel only; cardinality is hard-coded to `N` (one
/// observation per group — McElreath's oceanic case). The user supplies
/// scalar priors on the hyperparameters separately:
///
/// ```swift
/// GaussianProcessPrior("g", indexedBy: "society",
///                      distanceMatrix: "Dmat",
///                      etasq: "etasq", rhosq: "rhosq")
/// Prior("etasq", .exponential(2), truncation: Truncation(lower: 0))
/// Prior("rhosq", .exponential(0.5), truncation: Truncation(lower: 0))
/// ```
///
/// Emits the non-centred form internally: declares `vector[N] <name>_z;`
/// in `parameters`, gives it a `std_normal()` prior, declares
/// `vector[N] <name>;` in `transformed parameters`, builds the kernel
/// matrix with the diagonal jitter, and assigns
/// `<name> = cholesky_decompose(K) * <name>_z;`.
public struct GaussianProcessPrior: ModelStatement {
  public let name: String
  public let indexedBy: String
  public let distanceMatrix: String
  public let etasq: DistributionArg
  public let rhosq: DistributionArg
  public let jitter: Double

  public init(_ name: String,
              indexedBy: String,
              distanceMatrix: String,
              etasq: DistributionArg,
              rhosq: DistributionArg,
              jitter: Double = 0.01) {
    self.name = name
    self.indexedBy = indexedBy
    self.distanceMatrix = distanceMatrix
    self.etasq = etasq
    self.rhosq = rhosq
    self.jitter = jitter
  }

  public var statement: Statement {
    .gaussianProcessPrior(name: name,
                          indexedBy: indexedBy,
                          distanceMatrix: distanceMatrix,
                          etasq: etasq,
                          rhosq: rhosq,
                          jitter: jitter)
  }
}

public struct Link: ModelStatement {
  public let function: LinkFunction
  public let lhs: String
  public let rhs: Expression

  public init(_ function: LinkFunction, lhs: String, rhs: Expression) {
    self.function = function
    self.lhs = lhs
    self.rhs = rhs
  }

  public var statement: Statement {
    .link(function: function, lhs: lhs, rhs: rhs)
  }
}

public struct Deterministic: ModelStatement {
  public let lhs: String
  public let rhs: Expression

  public init(_ lhs: String, _ rhs: Expression) {
    self.lhs = lhs
    self.rhs = rhs
  }

  public var statement: Statement {
    .deterministic(lhs: lhs, rhs: rhs)
  }
}
