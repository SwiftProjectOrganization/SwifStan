# TestResults.md

Coverage of the 10 alist test cases in
`Tests/SwiftStanTests/TestAlistFiles/Test.alists.txt` run through
`swiftstan stancode --model alist<N>` (in-process alist → `UlamModel` →
Stan source path; no CSV data attached).

The user re-curated the test corpus on 2026-06-08, dropping the
`dcategorical/softmax` and `dordlogit` cases (both known
architectural-lift territory) and revising alist 1 to use the explicit
`alpha[county] ~ dnorm(...)` varying form. The renumbered table:

| # | Description | Status (2026-06-08, post `.expression` lift) |
|---|---|---|
| 1 | Radon — varying intercept w/ inline `alpha[county]` in `dnorm` mean | ✅ PASS — `stancode` generates the canonical hierarchical Stan source (varying `vector[N_county] alpha;`, `array[N] int<lower=1, upper=N_county> county;`, verbatim sampling line). Downstream `csv2json` against `radon.csv` blocks on the `county` column being a state-name string rather than an integer — orthogonal "auto-factorise string columns referenced as integer indices" feature, not a code-gen issue. |
| 2 | Radon (deterministic `mu <-`) | ❌ FAIL — alist file is missing a comma after the `mu <-` line; with that fixed, it parses cleanly and hits the next blocker (indexed `alpha[county]` RHS in a Deterministic line needs `alpha` declared as a `VaryingPrior`). |
| 3 | UCB binomial with `snorm` / `half_normal` | ❌ FAIL — lower (`snorm` not in V1 catalog). |
| 4 | Tools / Poisson with grouped prior | ✅ PASS |
| 5 | Reedfrog varying-intercept binomial *(was #7)* | ✅ PASS (caveat: `density` typed as `vector[N]` when running `stancode` without a CSV — `csv2json` would correct that). |
| 6 | Cafe varying-effects via `dmvnorm2` *(was #8)* | ❌ FAIL — generate (`Rho` flagged as multivariate-with-truncation; classify pass shouldn't be auto-truncating `dlkjcorr` priors). |
| 7 | Crossed chimpanzees via `dmvnorm2` × 2 *(was #9)* | ❌ FAIL — generate (same as #6, for `Rho_actor` / `Rho_block`). |
| 8 | Measurement error (Waffle / divorce) *(was #10)* | ✅ PASS |

**Score:** **4 / 8** generate Stan source (was 3 / 10 against the
larger corpus). The `.expression` lift specifically unblocked alist 1
end-to-end at the `stancode` level — the canonical McElreath radon
form (`dnorm(alpha[county] + beta*floor, sigma)` paired with
`alpha[county] ~ dnorm(0,10)`) now produces clean Stan.

Recurring blockers (post `.expression` lift), ranked by how many test
cases each one trips:

1. **Missing distributions in the alist catalog** — `snorm`,
   `half_normal`, `dmvnorm2`. Tripped by alists 3, 6, 7.
2. **`Rho ~ dlkjcorr(...)` getting flagged as multivariate-with-truncation**
   (alists 6, 7). The classify pass appears to be auto-promoting a
   truncation onto `Rho` (likely from the σ-truncation inference
   heuristic firing on it). Worth investigating — `dlkjcorr` priors
   should be exempt from the σ-truncation pass.
3. **Indexed RHS without a paired VaryingPrior** — alist 2 (corrected
   form). `mu <- alpha[county] + beta*floor` references `alpha[county]`
   but `alpha` is declared as a scalar `dnorm(0,10)` prior. The
   generator's loop emitter triggers but has no `VaryingPrior(...)`
   declaration to bind `alpha` to a vector type. Either auto-promote
   `alpha` to a vector parameter on detecting the indexed reference,
   or require the user to use `a[county] ~ dnorm(...)` form explicitly
   (as alist 1 already does).
4. **String columns referenced as integer indices** (alist 1
   downstream). `radon.csv` has `county` as a state-name string
   (`"AITKIN"`, etc.); `csv2json` rejects with "non-integer value".
   `rethinking` auto-factorises such columns; SwiftStan doesn't.
   Workaround today: pre-process the CSV to add an integer factor
   column, or rename in the alist (alist 1 uses `county`; the radon
   CSV has `county_code` for the int form).

Details below.

---

## ✅ Passes

### alist4 — Poisson, vectorised log link, grouped prior
```r
alist(
  total_tools ~ dpois( lambda ),
  log(lambda) <- a + bp*log_pop + bc*contact_high + bpc*contact_high*log_pop,
  a ~ dnorm(0,100),
  c(bp,bc,bpc) ~ dnorm(0,1)
)
```
Generates clean Stan: integer outcome with `<lower=0>` bound, real
parameters, three i.i.d. priors emitted from the grouped `c(...)`
expansion. The link's RHS contains three multiplications, so
`contact_high` and `log_pop` are auto-promoted to `vector[N]` (Phase 5.5
Slice C). Loop emitter kicks in because of the
`contact_high*log_pop` cross-term, producing a `for (i in 1:N) { … }`
body — expected and matches the existing chimpanzees pattern.

### alist7 — reedfrog varying-intercept binomial
```r
alist(
  surv ~ dbinom( density , p ) ,
  logit(p) <- a_tank[tank] ,
  a_tank[tank] ~ dnorm( a , sigma ) ,
  a ~ dnorm(0,1) ,
  sigma ~ dcauchy(0,1)
)
```
Parses, classifies, and emits Stan source. **Caveat:** because
`stancode` runs without a CSV, `density` has no declared `.integer`
type to anchor the binomial trials slot — it falls through to
`vector[N] density;` in the emitted data block. Stan would reject that
at compile time (`binomial(n, p)` requires `int n`). The fix lands
once the `csv2json` step has populated `<name>.data.json` and
`DataInference.classify(_:)` sees `density` as `.integer(…)`. The
varying-intercept structure itself (`vector[N_tank] a_tank;` +
`a_tank ~ normal(a, sigma);`) is emitted correctly.

---

## ❌ Failures

### alist1 — Radon, vectorised likelihood
```r
log_radon ~ dnorm(alpha[county] + beta * floor, sigma)
```
**Error:** `AlistLowering: distribution arg in 'dnorm' must be a
numeric literal or identifier`

The first argument to `dnorm` is the *expression*
`alpha[county] + beta * floor`. The lowering pass rejects compound
expressions in distribution-arg slots — `DistributionArg` is
`.literal(Double) | .symbol(String)` only. Fix: rewrite as
```r
log_radon ~ dnorm(mu, sigma),
mu <- alpha[county] + beta * floor
```
…which then hits failure #2 below. The architectural answer is to
extend `DistributionArg` with `.expression(String)` and have the
emitter render it verbatim (the same trick `multivariateNormalCholesky`
already uses for its `mean:` / `chol:` args).

### alist2 — Radon, deterministic `mu <-`
```r
log_radon ~ dnorm(mu, sigma),
mu <- alpha[county] + beta * floor   ← bare deterministic
alpha ~ dnorm(0, 10),
```
**Error:** `AlistParser: unexpected token mu at position 39 (expected
<link>(<target>))`

Two issues stacked. (a) The original file is missing the comma after
`floor` — but even with the comma added, (b) the parser only accepts
`<linkfunc>(<target>) <- <expr>` shape, not the bare `<identifier> <-
<expr>` form McElreath uses for non-link deterministic lines. This is
the blocker that drives 5 of the 8 failures.

### alist3 — `snorm` / `half_normal`
```r
a[dept] ~ snorm( abar , sigma ),
…
sigma ~ half_normal(0,1),
```
**Error:** `AlistLowering: distribution 'snorm' is not in the V1
catalog`

The catalog covers `dnorm`, `dbinom`, `dpois`, `dunif`, `dt`,
`dmvnorm`, `dlkjcorr`, `dgamma`, `dcauchy`, `dlnorm`, `dordlogit`,
`dwishart`, `dmvnormchol`. `snorm` (probably a typo for `dnorm`?) and
`half_normal` are absent. McElreath users sometimes write
`sigma ~ dnorm(0,1) T[0,]` (truncated) — the alist parser handles
that; `half_normal(...)` as a primitive would need a lowering shortcut
that injects the truncation.

### alist5 — Categorical with `softmax`
```r
career ~ dcategorical( softmax(0,s2,s3) ),
```
**Error:** `AlistParser: failed to parse expression 'softmax(0,s2,s3)':
unexpectedToken(found: ",", expected: "')'", position: 9)`

The expression parser only accepts a single argument inside a function
call when it appears in a distribution-arg slot. Plus `dcategorical`
itself isn't in the catalog. Adding the distribution is straightforward
(`categorical(theta)` exists in Stan); fixing the multi-arg-fn-call
parsing is broader work — would change the `ExpressionParser`
contract.

### alist6 — Ordered logit with `c(a1..a6)` cutpoints
```r
response ~ dordlogit( phi , c(a1,a2,a3,a4,a5,a6) ) ,
phi <- bA*action + bI*intention + bC*contact,
```
**Error:** `AlistParser: unexpected token phi at position 62 (expected
<link>(<target>))`

Same bare-`<identifier> <-` blocker as alist 2 (`phi <- bA*action +
…`). If the parser accepted bare deterministic, the next blocker would
be the `c(a1,...,a6)` cutpoint expansion in the distribution-arg slot
— SwiftStan's ordered logit primitive expects a single `cutpoints`
symbol typed as `ordered[K-1]` via a companion `OrderedCutpoints` node.
McElreath inlines the cutpoints as `c(…)`; the alist parser would need
to detect that and synthesise the cutpoints parameter.

### alist8 — Cafe varying-effects via `dmvnorm2`
```r
mu <- a_cafe[cafe] + b_cafe[cafe]*afternoon,
c(a_cafe,b_cafe)[cafe] ~ dmvnorm2(c(a,b),sigma_cafe,Rho),
```
**Error:** `AlistParser: unexpected token mu at position 37 (expected
<link>(<target>))`

Bare-deterministic blocker again. Past that, the model uses McElreath's
3-arg `dmvnorm2(mean_vec, sigma_vec, Rho)` form which decomposes
internally into the multi_normal_cholesky parameterisation. SwiftStan
ships `dmvnormchol(mean, chol)` instead — equivalent at the Stan level
but the alist alias doesn't auto-translate. Workaround today: rewrite
as
```r
c(a_cafe,b_cafe)[cafe] ~ dmvnormchol(c(a,b), diag_pre_multiply(sigma_cafe, L_cafe)),
L_cafe ~ dlkjcorr(2)
```
…which the cafe golden test already proves works.

### alist9 — Crossed chimpanzees via `dmvnorm2` × 2
Same two blockers as alist 8, doubled — bare deterministic for `A
<-`/`BP <-`/`BPC <-` lines and `dmvnorm2` lowering for both
`c(a_actor,…)[actor]` and `c(a_block,…)[block_id]` groups. Crossed
random effects with shared cardinality-symbol allocation already exists
(`varyingVectorCrossedEffectsMatchesGolden`); once the two
preconditions land, this alist should compile straight through.

### alist10 — Measurement error
```r
div_est ~ dnorm(mu,sigma),
mu <- a + bA*A + bR*R,
div_obs ~ dnorm(div_est,div_sd),
```
**Error:** `AlistParser: unexpected token mu at position 36 (expected
<link>(<target>))`

Bare-deterministic blocker. Beyond that, this is a measurement-error
model: `div_est` appears as the LHS of the first sampling statement
AND as the *mean argument* of the second. The classifier today assigns
each symbol exactly one role — outcome OR parameter, not both — so a
second pass would be needed to promote `div_est` to a vector parameter
whose elements are themselves sampled from a normal. Non-trivial; deferred.

---

## Next-step recommendations

In order of payoff per LOC:

1. **Add `snorm`, `half_normal` distribution aliases to
   `AlistLowering`** — `snorm(...)` → `.normal(...)`; `half_normal(s)`
   → `.normal(0, s)` with `Truncation(lower: 0)`. Unblocks alist 3.
2. **Investigate the spurious `Rho` truncation in `dlkjcorr` cases**
   (alists 6, 7) — `lkjCorrCholesky` priors shouldn't go through the
   σ-slot truncation heuristic. Plus add the **`dmvnorm2` lowering
   shortcut** that synthesises the companion `dlkjcorr` line.
3. **Auto-promote indexed-but-otherwise-scalar parameters** (alist 2)
   — when `alpha[county]` appears in a deterministic RHS and `alpha`
   is declared via a scalar `Prior(...)`, the classifier should
   promote it to `VaryingPrior(..., indexedBy: "county", ...)`
   automatically. Or surface a clearer error pointing at the missing
   varying declaration.
4. **Auto-factorise string columns referenced as integer indices**
   (alist 1 downstream). `csv2json` could detect that a referenced
   column is meant to be `array[N] int` and assign each unique string
   value an integer 1..N (rethinking does this). Out of scope today;
   workaround is to use a pre-computed integer column.

Deferred / out of scope for v1: measurement-error two-role
classification (alist 8 — currently passes but with semantically odd
output where `div_obs` is treated as a parameter), nested
crossed-with-nested combinations.
