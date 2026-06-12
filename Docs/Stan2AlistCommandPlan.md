# Stan2Alist Command Plan

The `stan2alist` subcommand is the inverse of `stancode`: it reads
`Results/<name>.stan` and writes `Preliminaries/<name>.alist.R` in
McElreath's `alist()` R syntax.

## 1. Goal & success criteria

Two-tier acceptance, because the motivating real-world example
(`~/Documents/StanCases/radon_pp/Results/radon_pp.stan`) is *hand-written*
Stan, not generator output:

| Input class | Criterion |
|---|---|
| Generator output (a `.stan` produced by `stancode` / `dsl2stan`) | Round-trip `stan2alist` → `stancode` is **byte-identical** to the original `.stan` (modulo the known `c(...)`-grouping cosmetic divergence). This is the regression oracle. |
| Hand-written idiomatic Stan (e.g. `radon_pp.stan`) | Produces a **semantically-equivalent** alist; constructs with no alist representation are **dropped with a loud warning** to stderr, never silently. |

Scope is **round-trip / idiomatic-McElreath Stan only**. Arbitrary
hand-written Stan (general grammar, multivariate distributions) is out of
v1 scope and must **fail loud** rather than guess.

## 2. What `radon_pp.stan` teaches us

The file:

```stan
data {
  int<lower=1> N;  // observations
  int<lower=1> N_county;
  array[N] int<lower=1, upper=N_county> county;
  vector[N] floor;
  vector[N] log_radon;
}
parameters {
  real mu_alpha;
  real<lower=0> sigma_alpha;
  vector<offset=mu_alpha, multiplier=sigma_alpha>[N_county] alpha;
  real beta;
  real<lower=0> sigma;
}
model {
  log_radon ~ normal(alpha[county] + beta * floor, sigma);
  alpha ~ normal(mu_alpha, sigma_alpha); // partial-pooling
  beta ~ normal(0, 10);
  sigma ~ normal(0, 10);
  mu_alpha ~ normal(0, 10);
  sigma_alpha ~ normal(0, 10);
}
generated quantities {
  array[N] real y_rep = normal_rng(alpha[county] + beta * floor, sigma);
}
```

Target alist:

```r
alist(
  log_radon ~ dnorm( alpha[county] + beta*floor , sigma ),
  alpha[county] ~ dnorm( mu_alpha , sigma_alpha ),
  beta        ~ dnorm( 0 , 10 ),
  sigma       ~ dnorm( 0 , 10 ),
  mu_alpha    ~ dnorm( 0 , 10 ),
  sigma_alpha ~ dnorm( 0 , 10 )
)
```

Per-construct handling (decisions locked in):

| Construct | Handling | Rationale |
|---|---|---|
| Inline comments (`// observations`, `// partial-pooling`) | Strip in the lexer | No alist representation; cosmetic. |
| `generated quantities { y_rep = normal_rng(...) }` | **Parse-and-drop + loud warning** | alist/ulam has no posterior-predictive syntax. |
| `vector<offset=mu_alpha, multiplier=sigma_alpha>[N_county] alpha;` | **Strip affine, emit centered** `alpha[county] ~ dnorm(mu_alpha, sigma_alpha)` | offset/multiplier is a reparameterization semantically identical to the centered model; recoverable from the param's own prior. |
| Linear model inlined in the likelihood | Keep inline via `DistributionArg.expression` | The AST already supports `.expression`; `classify` harvests embedded identifiers. Simplest valid reverse. |
| `real<lower=0> sigma;` + `sigma ~ normal(0,10)` | Drop the `<lower=0>` | `classify` Slice D re-adds it on the forward pass; round-trips for free. |
| Trailing whitespace | Ignored by lexer | — |

Offset/multiplier stripping and generated-quantities drop-with-warning are
therefore **in v1** — they are the first hand-written features encountered,
and without them `radon_pp` would not convert.

## 3. Architecture

Mirror the forward chain in reverse, pivoting through the existing
`UlamModel` / `Statement` AST so `stancode` itself becomes the round-trip
oracle and so `ExpressionLexer` / `ExpressionParser` are reused for RHS
expressions:

```
Results/<name>.stan
   │
   ▼  StanBlockParser        (new)
StanProgram  (data decls, param decls, model lines, dropped blocks)
   │
   ▼  StanToUlamModel        (new)
UlamModel
   │
   ▼  AlistTextEmitter       (new)
Preliminaries/<name>.alist.R
```

### New files

| File | Responsibility |
|---|---|
| `Ulam/Stan2Alist/StanBlockParser.swift` | Strip comments; split into `data` / `parameters` / `model` / `transformed *` / `generated quantities` blocks; parse declarations (`vector[K] x;`, `array[N] int<...> c;`, `real<...> s;`, `vector<offset=,multiplier=>[K] x;`) and model lines (`lhs ~ dist(args) T[..];`, `p = inv_logit(rhs);`). Fail loud on any unrecognized line. |
| `Ulam/Stan2Alist/StanProgram.swift` | Plain value types for the parse result: declarations (type + constraints + affine), sampling statements, assignments, and a list of dropped/opaque blocks for warnings. |
| `Ulam/Stan2Alist/StanToUlamModel.swift` | Reverse of `AlistToUlamModel` + `DataInference`: classify each declared symbol as data vs parameter (the block tells us), re-pair vector params with their index column, invert link wrappers, strip affine offset/multiplier, drop `generated quantities` / `transformed *` with warnings, build `[Statement]` + a stub `UlamData`. |
| `Ulam/Stan2Alist/AlistTextEmitter.swift` | `[Statement]` → McElreath R text: `name ~ dname(args)`, `name[idx] ~ ...`, dist-name reversal, optional `c(...)` regrouping. |
| `Ulam/Generator/DistributionCatalog.swift` (extend) | Add `distribution(fromStanName:args:) throws -> Distribution` and a Stan-name → McElreath-name table, inverting the existing `name(_:)`. |
| `Commands/Stan2Alist.swift` | `stan2alist(model:verbose:force:) throws -> URL` — mirrors `Stancode.swift`; reads `Results/<name>.stan`, writes `Preliminaries/<name>.alist.R`. |
| `SwiftStan.swift` (extend) | New `struct Stan2Alist: ParsableCommand` (`OptionsLimited` + a `--force` flag); register in `subcommands:`. |
| `Tests/SwiftStanTests/Stan2AlistTests.swift` | See §7. |

## 4. Role inference (the only non-mechanical logic)

Stan's block structure supplies most of what `DataInference` / `classify`
had to infer on the forward pass:

- **Data vs parameter** — given directly by which block the declaration is in.
- **Outcome (likelihood)** — the `~` line whose LHS is a `data`-block vector. Emitted first to re-establish McElreath's "first `~`" convention.
- **Varying param ↔ index column** — `vector[N_county] alpha;` is varying; its index column is the `array[N] int<lower=1, upper=N_county> county;` whose `upper` symbol matches the vector size, confirmed by an `alpha[county]` reference in the model. Emit as `alpha[county] ~ ...`.
- **Cardinality symbols** (`N`, `N_county`) — recognized by the `int<lower=1> N_x;` shape and consumed, not emitted as data columns.

## 5. Reverse distribution catalog

Add to `DistributionCatalog` (co-located with `name(_:)`):

```
stanName → mcelreathName:  normal→dnorm, binomial→dbinom, poisson→dpois,
  exponential→dexp, gamma→dgamma, cauchy→dcauchy, lognormal→dlnorm,
  uniform→dunif, student_t→dstudent, beta→dbeta
distribution(fromStanName:args:) → Distribution   // arity-checked, throws on unknown
```

`bernoulli(p)` ↔ `dbinom(1, p)` is the McElreath idiom — canonicalize on
emit. Multivariates (`multi_normal`, `lkj_corr_cholesky`, …) are out of v1
scope → fail loud.

## 6. Implementation order (independently testable slices)

1. **Slice A — reverse catalog.** `distribution(fromStanName:args:)` + name table. Unit-test symmetry against `name(_:)` / `args(_:)`.
2. **Slice B — `StanBlockParser` + `StanProgram`.** Block splitter, comment stripper, declaration & sampling-line parsers; fail-loud on unknowns. Test against `radon_pp.stan` and a generator `.stan`.
3. **Slice C — `StanToUlamModel`.** Role inference (§4), link inversion, varying-param pairing, offset/multiplier stripping, drop-with-warning for `generated quantities` / `transformed *`.
4. **Slice D — `AlistTextEmitter`.** `[Statement]` → alist R text. Exact-text test for `radon_pp` and `chimpanzees`.
5. **Slice E — command + wiring.** `Stan2Alist.swift`, register subcommand, `--force` guard.
6. **Slice F — round-trip oracle test.** For each generator fixture: alist → `stancode` → `stan2alist` → `stancode`, assert byte-identical (modulo `c(...)`).

## 7. Tests (`Stan2AlistTests.swift`, Swift Testing)

- `reverseCatalogIsSymmetric` — every `Distribution` survives `name → distribution(fromStanName:)`.
- `parsesRadonPpStan` — `StanBlockParser` accepts `radon_pp.stan`, drops `generated quantities` with a recorded warning.
- `radonPpReverseProducesExpectedAlist` — full pipeline yields the §2 target alist.
- `rejectsUnknownStanLine` — fail-loud on a line outside the grammar.
- `roundTripsThroughStancode` (`howell`, `multilevel`) — alist → `stancode` → `stan2alist` → `stancode` byte-identical (the oracle). chimpanzees is excluded (loops); covered instead by `roundTripLoopModelFailsLoud`, which asserts a looped model fails loud.
- `radon_pp.stan` is exercised inline (string constant) rather than staged from `Tests/TestDataFiles/`, keeping the Slice B–E unit tests self-contained.

## 8. Locked decisions

1. **v1 coverage:** strip offset/multiplier → centered prior; parse-and-drop `generated quantities` (and `transformed *`) with a loud warning. `radon_pp` is a working example in v1.
2. **Overwrite guard:** refuse to clobber an existing `Preliminaries/<name>.alist.R` unless `--force` is passed.
3. Multivariate distributions and general (non-idiomatic) Stan are out of v1 scope and fail loud.

## 9. Risks

- **Scope creep into general Stan.** Mitigation: fail-loud grammar; multivariates rejected in v1.
- **`c(a,b,c) ~ dnorm(...)` regrouping.** Forward lowering expands a `c(...)` prior into separate scalar priors, so the reverse yields N separate lines unless `AlistTextEmitter` re-groups identical-distribution scalar priors. Cosmetic; the round-trip oracle tolerates it.
- **Affine round-trip is lossy by design.** A non-centered (`offset`/`multiplier`) input reverses to a centered alist; re-running `stancode` produces the centered form, not the original affine declaration. Semantically equivalent, not byte-identical — documented, not a bug.
- **`model`-block `for` loops are out of v1 scope.** `StanBlockParser` splits model statements on `;`, so a `for (i in 1:N) { ... }` body would split mid-loop; the parser detects `for`/`while`/`{` and **fails loud** (`StanBlockParseError.unsupportedLoop`). The forward emitter produces a loop only for a non-vectorisable indexed RHS. **chimpanzees IS such a case** — its `(bp + bpc*condition)*prosoc_left` term is `vector * vector`, which the generator routes to loop emission — so chimpanzees is excluded from v1. The round-trip oracle uses `howell` (scalar) plus a synthetic radon-style multilevel alist (varying prior + vectorising link + half-Cauchy) that stays on the vectorised path. Brace-aware statement splitting + a `renderLoopBody` inverse (de-subscripting `a[idx[i]]` → `a[idx]`) is the fix if looped models ever need converting.
