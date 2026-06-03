# TODO

## Purpose

This file is a forward-looking checklist of work that's planned but not yet scheduled.

## 1. Features

- [x] ✅ **SUR (Seemingly Unrelated Regressions)** — shipped 2026-05-30/31. Adds `MatrixPrior` / `CovMatrixPrior` DSL nodes, the `UlamColumn.realMatrix` data shape, and a `Deterministic` + multivariate-normal `Likelihood` pair-detection pass that emits `for (n in 1:N) { row_vector[J] mu = …; y[n] ~ multi_normal(…, Sigma); }`. End-to-end test against `WaffleDivorce.csv` (50 states).

- [x] ✅ **Multivariate hierarchical priors** (McElreath Chapter 14 cafe-style) — shipped 2026-05-31. Adds `LKJCorrCholeskyPrior` (`cholesky_factor_corr[J]` + `lkj_corr_cholesky(η)`), `VaryingVectorPrior` (`array[N_group] vector[J]`), the `.multivariateNormalCholesky` and `.lkjCorrCholesky` distributions, chained-indexed RHS shape (`ab[cafe][k]`), and a `diag_pre_multiply` symbol-tokenising path. End-to-end cafe test recovers true parameters with R-hat ≤ 1.05.

- [x] ✅ **`dwishart` prior** — shipped 2026-06-01. Adds `WishartPrior("Omega", dim: "K", nu: "nu", V: "V_scale")` DSL node, `.wishart` Distribution case, `wishartPrior` Statement case, and `wishartScaleColumns` exclusion from Phase-6 cardinality binding so `realCovMatrix` scale-matrix data columns aren't mistaken for cardinality anchors.

- [x] ✅ **`dmvnormchol` + `dlkjcorr` alist aliases** (paired) — shipped 2026-06-01. Maps McElreath's R-alist shape `c(a, b)[cafe] ~ dmvnormchol(c(a_bar, b_bar), L_Omega, sigma_cafe)` and `L_Omega ~ dlkjcorr(eta)` to the existing `VaryingVectorPrior` + `LKJCorrCholeskyPrior` + `diag_pre_multiply` Stan output shipped 2026-05-31 with the cafe model. No new DSL nodes added; classify pass synthesises the `J` cardinality from the LHS `c(...)` arity, promotes the σ-named scalar `~ dexp(...)` companion to `VectorPrior(length: "J")`, and routes `dlkjcorr` to `LKJCorrCholeskyPrior(dim: "J", ...)`. Known limitation: single grouping level only — multi-grouping models with distinct vector lengths would collide on the hard-coded `"J"` symbol.

- [x] ✅ **Gaussian process priors** — shipped 2026-06-01. Adds `GaussianProcessPrior("g", indexedBy: "society", distanceMatrix: "Dmat", etasq: "etasq", rhosq: "rhosq", jitter: 0.01)` DSL node, `Statement.gaussianProcessPrior` AST case, `GPSpec` inference, and a `squareMatrixColumns` flag that emits `matrix[N, N] Dmat;` instead of the literal-cols form. v1 ships the squared-exponential (`cov_GPL2`) kernel only, with cardinality hard-coded to `N` (one observation per group — McElreath's oceanic-tools shape). The latent vector is declared in `transformed parameters` via the non-centred Cholesky form (`g = cholesky_decompose(K) * g_z;`); the raw z-vector gets a `std_normal()` prior in the model block. Hyperparameter priors (`etasq` / `rhosq`) are user-supplied as regular `Prior(..., truncation: Truncation(lower: 0))` lines. Deferred: alist `dgpl2` alias, additional kernels (Matérn, periodic, `cov_GPL1`), non-Euclidean distance, multi-grouping GP.

- [x] ✅ **Ordered logit / probit likelihoods** — shipped 2026-06-02. Adds `OrderedCutpoints("cutpoints", K: "K")` DSL node (declaration-only — paired with a separate `Prior("cutpoints", .normal(0, 1.5))` for the iid prior across K-1 cutpoints, mirroring McElreath's alist split), `Statement.orderedCutpointsPrior`, `Distribution.orderedLogistic` / `.orderedProbit` cases, `orderedCutpointParameters` inference, and a `DataInference` post-fix that patches `outcomeBoundsByLhs[lhs].upper = K` for ordered likelihoods. Parameters emit as `ordered[K-1] cutpoints;`; outcome data emits as `array[N] int<lower=1, upper=K> R;`. K is supplied via `"K": .scalarInt(...)` data, matching the cafe/SUR convention. Deferred: alist `dordlogit` / `dordprobit` aliases, K inferred from R's max value, per-index cutpoint priors, explicit truncation rejection.

- [x] ✅ **Monotonic effects** (McElreath Chapter 12 / brms `mo()`) — shipped 2026-06-02. Adds `MonotonicEffect("delta", scale: "bE", predictor: "edu", levels: "K_edu", targetLhs: "mu")` DSL node, paired with a declaration-only `SimplexPrior("delta", length: "K_edu")` + a regular `Prior("delta", .dirichlet("alpha"))` for the iid Dirichlet prior. New `Distribution.dirichlet(_:)`, `Statement.simplexPrior` / `.monotonicEffect`. The `MonotonicEffect` node consumes its matching `Link`/`Deterministic` whose LHS is `targetLhs` and emits a single combined per-row for-loop augmenting the base RHS with `<scale> * sum(<name>[1:<predictor>[i]])`. The `K_edu` cardinality is anchored by the Dirichlet's `alpha` vector via the existing Phase-6 path — the user doesn't supply K_edu separately. Reuses the SUR per-row-loop detection machinery; no parser changes (no range-indexing syntax was added). Deferred: `append_row(0, delta)` 0-indexed trick (lets predictor=0 mean baseline), multiple monotonic predictors per single targetLhs (architectural support exists; ordering not yet covered by tests), alist `mo()` alias.

- [ ] `start=` / `constraints=` overrides on `Prior` / `VaryingPrior`. v1 expresses constraints only through richer prior types + truncation.

- [ ] `cores=` / parallel-chain control beyond cmdstan's existing pass-through arguments.

- [ ] Nested groupings (`a[country, region]` style). Slightly different from two-grouping above; involves multi-dimensional index columns.

- [ ] Crossed random effects with correlations — `LKJCorrCholeskyPrior` + `VaryingVectorPrior` are already in place; what remains is the multi-grouping index wiring and any alist-side `dlkjcorr` alias (see above).


## 2. Known limitations / polish (any time)

Quality-of-life items not gated on a particular phase.

- [ ] **`countSymbol` collision check.** If a user provides `countSymbol: "N"` or any value that collides with an existing data symbol, the generator currently produces invalid Stan. Add a sanity check in `DataInference.classify(_:)`.

- [ ] **Index column value validation.** `DataMarshaller` computes `<countSymbol>: max(values)` but doesn't verify all values are `>= 1`. A 0 or negative would compile fine but fail Stan's `<lower=1>` data validation at runtime with a less-than-obvious error.

- [ ] **Per-row binomial outcome bounds.** Binomial outcomes are declared `array[N] int<lower=0>`; the tighter `<lower=0, upper=trials[i]>` form needs a `transformed data` validation block. Low priority — Stan still catches violations during sampling.

- [ ] **`distribution.studentT` label ergonomics.** Phase 3 single-arg distributions (`poisson`, `exponential`) use unlabeled call shape (`.poisson("lambda")`) while two-arg ones use unlabeled positional and `bernoulli` keeps the `p:` label. Worth a small consistency pass — the inconsistency was caught during Phase 3 testing.

- [x] ✅ **Unused-variable warning** in `SwiftSyncFileExec.swift` — fixed in commit `ae62ffe` alongside the cmdstan-failure-surfacing fix.

- [x] ✅ **DSL-level `Inits([...])` knob** — shipped 2026-06-02. Adds an `Inits(["mu": 178.0, "sigma": 25.0])` DSL node (`Sources/SwiftStan/Ulam/Builder/DSLNodes.swift`), backed by a `Statement.inits(values:)` AST case, `InferredModel.initValues` collection, and a new `InitMarshaller` paralleling `DataMarshaller`. Three on-disk emission paths: (i) the V1 `ulam(...)` in-process orchestrator writes `Results/<model>.init.json` alongside `Results/<model>.data.json`; (ii) auto-generated smoke drivers (via `AlistEmitter`) print the init JSON to stdout after a `// === SWIFTSTAN_INITS ===` sentinel line that `dsl2stan` splits into two output files; (iii) the new top-level `stanInits(_:)` helper lets hand-authored `*.ulam.swift` smoke drivers emit inits with the same shape. `Methods/StanSample.swift` auto-detects `<model>.init.json` and prepends `init=<path>` to the cmdstan argv — disk presence is the activation trigger, no new parameter needed. `V2WorkflowTests.howellPipelineEndToEnd` now asserts `R-hat < 1.05` on `mu` and `sigma` (recovered values: 1.00038 / 1.00137 — the McElreath m4.1 Howell1 case converges cleanly with explicit inits). Deferred: auto-inference of init values from prior means, per-chain inits, vector / array inits (v1 ships scalars only), alist `start = list(...)` syntactic support.


## 3. Cross-project / external

Not strictly part of the Ulam port but tracked since they consume its output.

- [ ] **stansummary `num_chains` assumption.** The pipeline currently hard-codes `num_chains=4` in `Commands/Sample.swift`. Logged in the original `README.md`'s "To do" section. Should generalise once a model wants different chain counts.


## References

- [`CLAUDE.md`](CLAUDE.md) — architecture notes for the Ulam module.
- McElreath, *Statistical Rethinking* (2nd ed.) — Chapters 13 (multilevel, ✅ Phase 5) and 14 (correlated varying effects — out of scope for v1).
