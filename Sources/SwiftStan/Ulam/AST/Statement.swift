//
//  Statement.swift
//  Stan
//
//  Phase 1 of the ulam port: the canonical AST node every DSL surface
//  lowers to. The generator only reads `Statement`, so future front-ends
//  (string parser, macro) can reuse the same backend.
//

import Foundation

public enum Statement: Hashable, Sendable {
  /// `y ~ Distribution(...) T[lower, upper];` — sampling statement over
  /// observed data. `truncation` adds the optional `T[...]` suffix.
  /// `useLpdf` switches to the `target += dist_lp[m]df(y | args)` form
  /// (combining `useLpdf` with non-empty truncation is rejected by the
  /// generator — Stan's truncation auto-normalisation only applies to
  /// the `~` form).
  case likelihood(lhs: String, distribution: Distribution, truncation: Truncation, useLpdf: Bool)

  /// `name ~ Distribution(...) T[lower, upper];` — sampling statement
  /// over a parameter. Same `truncation` / `useLpdf` semantics as
  /// `likelihood`.
  case prior(name: String, distribution: Distribution, truncation: Truncation, useLpdf: Bool)

  /// Phase 5: `name[indexedBy] ~ Distribution(...)` — varying-intercept
  /// (or varying-coefficient) sampling statement. The generator declares
  /// `name` as `vector[N_<col>]` in `parameters` (rather than scalar
  /// `real`), and the integer data column `indexedBy` as a tightly-
  /// bounded index column in `data`. `countSymbol`, when non-nil,
  /// overrides the auto-derived `N_<col>` cardinality symbol. Same
  /// `truncation` / `useLpdf` semantics as `prior`.
  ///
  /// Phase 5.5 Slice E: `nonCentered: true` emits the Matt Trick
  /// non-centred parameterisation (`name_raw ~ std_normal();` plus a
  /// `transformed parameters` block that defines
  /// `name = a_bar + sigma * name_raw;`). Only supported when the
  /// distribution is `.normal(...)` with empty truncation and the
  /// `~` sampling form (useLpdf: false).
  case varyingPrior(name: String,
                    indexedBy: String,
                    countSymbol: String?,
                    distribution: Distribution,
                    truncation: Truncation,
                    useLpdf: Bool,
                    nonCentered: Bool)

  /// Phase 6: `name ~ Distribution(...)` with `name` declared as
  /// `vector[<length>]` in `parameters`. Used for plain vector
  /// parameters that aren't keyed on a data index column — typically
  /// the LHS of a `multi_normal` prior (`mu ~ multi_normal(zero, Sigma)`).
  /// `length` is the cardinality symbol the vector size is keyed on;
  /// it must be bound by a Phase 6 data column that carries its
  /// numeric length, or the generator throws. Truncation is rejected
  /// on multivariate distributions — Stan doesn't auto-normalise them.
  case vectorPrior(name: String,
                   length: String,
                   distribution: Distribution,
                   truncation: Truncation,
                   useLpdf: Bool)

  /// SUR Slice A (2026-05-30): `matrix[<rows>, <cols>] name;` parameter
  /// with an iid prior applied to every entry via the idiomatic
  /// `to_vector(name) ~ <dist>(args);` sampling line. Used as the
  /// per-outcome coefficient matrix β in Seemingly Unrelated
  /// Regressions: `y[n] ~ multi_normal(x[n] * β, Σ)`. Both `rows` and
  /// `cols` are cardinality symbols (the user passes them as strings)
  /// that must be bound by either a scalar-int data column carrying
  /// that name or a matrix data column whose shape supplies the value.
  case matrixPrior(name: String,
                   rows: String,
                   cols: String,
                   distribution: Distribution,
                   truncation: Truncation,
                   useLpdf: Bool)

  /// SUR Slice B (2026-05-30): `cov_matrix[<dim>] name;` parameter.
  /// v1 emits no explicit prior — Stan's positive-definite constraint
  /// gives the sampler a workable default. Used as the row-level error
  /// covariance Σ in SUR models. `dim` is a cardinality symbol bound
  /// the same way as `matrixPrior`'s `rows` / `cols`.
  case covMatrixPrior(name: String,
                      dim: String)

  /// Multivariate hierarchical priors Slice A (2026-05-31):
  /// `cholesky_factor_corr[<dim>] <name>;` parameter with an LKJ-Cholesky
  /// prior on the Cholesky factor of the implied correlation matrix.
  /// Emits `<name> ~ lkj_corr_cholesky(<eta>);` in the model block.
  /// `dim` is a cardinality symbol that the user binds to a scalar-int
  /// data column. Used as the prior on the Cholesky factor of the
  /// per-group correlation matrix in idiomatic Stan code for
  /// McElreath-style correlated varying effects.
  case lkjCorrCholeskyPrior(name: String,
                            dim: String,
                            eta: DistributionArg)

  /// `cov_matrix[<dim>] <name>;` parameter with a Wishart prior.
  /// Emits `<name> ~ wishart(<nu>, <V>);` in the model block.
  /// `dim` is a cardinality symbol bound to a scalar-int data column.
  /// `V` is a symbol referencing a `cov_matrix`-typed data column.
  case wishartPrior(name: String,
                    dim: String,
                    nu: DistributionArg,
                    V: DistributionArg)

  /// Multivariate hierarchical priors Slice C (2026-05-31):
  /// `array[N_<indexedBy>] vector[<length>] <name>;` parameter — vector-
  /// valued varying effects, one J-dim vector per group. `indexedBy` is
  /// a data column whose values index groups (same role as in
  /// `varyingPrior`); `length` is the inner-vector cardinality symbol
  /// (typically the same one used by the companion `lkjCorrCholeskyPrior`).
  /// `countSymbol`, when non-nil, overrides the auto-derived `N_<col>`
  /// outer-array cardinality symbol. The sampling line over the outer
  /// array vectorises automatically — Stan applies the multivariate
  /// distribution to each vector entry.
  case varyingVectorPrior(name: String,
                          indexedBy: String,
                          length: String,
                          countSymbol: String?,
                          distribution: Distribution,
                          truncation: Truncation,
                          useLpdf: Bool)

  /// Gaussian process prior (2026-06-01) on an N-length latent vector,
  /// using the squared-exponential of a precomputed N×N distance matrix
  /// (McElreath's `cov_GPL2`). v1 only supports the squared-exponential
  /// kernel and the cardinality `N` (one observation per group). The
  /// latent vector is declared in `transformed parameters` via the
  /// non-centred form `<name> = cholesky_decompose(K) * <name>_z` with
  /// `<name>_z` declared as a `vector[N]` parameter with a standard
  /// normal prior. The K matrix is built inside a nested block using
  /// `etasq * exp(-rhosq * square(<distanceMatrix>[i, j]))` plus a
  /// fixed diagonal jitter. The user must supply scalar priors on the
  /// hyperparameter symbols `etasq` / `rhosq` separately — by
  /// convention these are positive (e.g. `Prior("etasq", .exponential(2),
  /// truncation: Truncation(lower: 0))`).
  case gaussianProcessPrior(name: String,
                            indexedBy: String,
                            distanceMatrix: String,
                            etasq: DistributionArg,
                            rhosq: DistributionArg,
                            jitter: Double)

  /// `function(lhs) <- rhs` — deterministic assignment via an inverse link.
  case link(function: LinkFunction, lhs: String, rhs: Expression)

  /// `lhs <- rhs` — plain deterministic assignment.
  case deterministic(lhs: String, rhs: Expression)
}
