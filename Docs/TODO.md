# TODO

## Purpose

This file is a forward-looking checklist of work that's planned but not yet scheduled.

## 1. Features

- [x] ✅ **SUR (Seemingly Unrelated Regressions)** — shipped 2026-05-30/31. Adds `MatrixPrior` / `CovMatrixPrior` DSL nodes, the `UlamColumn.realMatrix` data shape, and a `Deterministic` + multivariate-normal `Likelihood` pair-detection pass that emits `for (n in 1:N) { row_vector[J] mu = …; y[n] ~ multi_normal(…, Sigma); }`. End-to-end test against `WaffleDivorce.csv` (50 states).

- [x] ✅ **Multivariate hierarchical priors** (McElreath Chapter 14 cafe-style) — shipped 2026-05-31. Adds `LKJCorrCholeskyPrior` (`cholesky_factor_corr[J]` + `lkj_corr_cholesky(η)`), `VaryingVectorPrior` (`array[N_group] vector[J]`), the `.multivariateNormalCholesky` and `.lkjCorrCholesky` distributions, chained-indexed RHS shape (`ab[cafe][k]`), and a `diag_pre_multiply` symbol-tokenising path. End-to-end cafe test recovers true parameters with R-hat ≤ 1.05.

- [ ] `dlkjcorr` / `dwishart` priors on covariance / correlation matrices.

- [ ] Gaussian process priors.

- [ ] Ordered logit / probit likelihoods.

- [ ] Monotonic effects (`mo()` in McElreath's syntax).

- [ ] `start=` / `constraints=` overrides on `Prior` / `VaryingPrior`. v1 expresses constraints only through richer prior types + truncation.

- [ ] `cores=` / parallel-chain control beyond cmdstan's existing pass-through arguments.

- [ ] Nested groupings (`a[country, region]` style). Slightly different from two-grouping above; involves multi-dimensional index columns.

- [ ] Crossed random effects with correlations (needs `dlkjcorr`).


## 2. Known limitations / polish (any time)

Quality-of-life items not gated on a particular phase.

- [ ] **`countSymbol` collision check.** If a user provides `countSymbol: "N"` or any value that collides with an existing data symbol, the generator currently produces invalid Stan. Add a sanity check in `DataInference.classify(_:)`.

- [ ] **Index column value validation.** `DataMarshaller` computes `<countSymbol>: max(values)` but doesn't verify all values are `>= 1`. A 0 or negative would compile fine but fail Stan's `<lower=1>` data validation at runtime with a less-than-obvious error.

- [ ] **Per-row binomial outcome bounds.** Binomial outcomes are declared `array[N] int<lower=0>`; the tighter `<lower=0, upper=trials[i]>` form needs a `transformed data` validation block. Low priority — Stan still catches violations during sampling.

- [ ] **`distribution.studentT` label ergonomics.** Phase 3 single-arg distributions (`poisson`, `exponential`) use unlabeled call shape (`.poisson("lambda")`) while two-arg ones use unlabeled positional and `bernoulli` keeps the `p:` label. Worth a small consistency pass — the inconsistency was caught during Phase 3 testing.

- [x] ✅ **Unused-variable warning** in `SwiftSyncFileExec.swift` — fixed in commit `ae62ffe` alongside the cmdstan-failure-surfacing fix.

- [ ] **DSL-level `init:` / `inits:` knob.** cmdstan's default unconstrained init range U(-2, 2) is too narrow for models whose posteriors live far from 0 — e.g. McElreath's m4.1 over Howell1 adult heights with `mu ~ Normal(178, 20)`. Without explicit inits, the leapfrog integrator diverges immediately and the sampler can't recover. `V2WorkflowTests.howellPipelineEndToEnd` currently asserts only artifact emission for this reason; add a real R-hat assertion once inits are wired through.


## 3. Cross-project / external

Not strictly part of the Ulam port but tracked since they consume its output.

- [ ] **stansummary `num_chains` assumption.** The pipeline currently hard-codes `num_chains=4` in `Commands/Sample.swift`. Logged in the original `README.md`'s "To do" section. Should generalise once a model wants different chain counts.


## References

- [`CLAUDE.md`](CLAUDE.md) — architecture notes for the Ulam module.
- McElreath, *Statistical Rethinking* (2nd ed.) — Chapters 13 (multilevel, ✅ Phase 5) and 14 (correlated varying effects — out of scope for v1).
