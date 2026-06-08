# TestResults.md

Coverage of the 10 alist test cases in
`Tests/SwiftStanTests/TestAlistFiles/Test.alists.txt` run through
`swiftstan stancode --model alist<N>` (in-process alist → `UlamModel` →
Stan source path; no CSV data attached).

| # | Description | Status (2026-06-07) | Status (2026-06-08, identity-link landed) |
|---|---|---|---|
| 1 | Radon (vectorised likelihood) | ❌ FAIL — lower | ❌ FAIL — lower (unchanged) |
| 2 | Radon (deterministic `mu <-`) | ❌ FAIL — parse | ❌ FAIL — *the alist file is missing a comma after the `mu <-` line; with that fixed, it parses cleanly and hits the next blocker (indexed `alpha[county]` RHS needs a `VaryingPrior`).* |
| 3 | UCB binomial with `snorm` / `half_normal` | ❌ FAIL — lower | ❌ FAIL — lower (unchanged) |
| 4 | Tools / Poisson with grouped prior | ✅ PASS | ✅ PASS (unchanged) |
| 5 | Categorical with `softmax` | ❌ FAIL — parse | ❌ FAIL — parse (unchanged) |
| 6 | Ordered logit with `c(a1..a6)` cutpoints | ❌ FAIL — parse | ❌ FAIL — lower (now: `dordlogit` not in catalog) |
| 7 | Reedfrog varying-intercept binomial | ✅ PASS (caveat) | ✅ PASS (unchanged) |
| 8 | Cafe varying-effects via `dmvnorm2` | ❌ FAIL — parse | ❌ FAIL — generate (now: `Rho` flagged as multivariate-with-truncation) |
| 9 | Crossed chimpanzees via `dmvnorm2` × 2 | ❌ FAIL — parse | ❌ FAIL — generate (same as 8, for `Rho_actor`/`Rho_block`) |
| 10 | Measurement error (Waffle / divorce) | ❌ FAIL — parse | ✅ PASS |

**Score:** 3 / 10 generate Stan source (was 2 / 10); 5 of the 8
failures (alists 2, 6, 8, 9, 10) moved past the parser into the
lowering or generate stage.

Recurring blockers (post-identity-link), ranked by how many test cases
each one trips:

1. **Missing distributions in the alist catalog** — `snorm`,
   `half_normal`, `dcategorical`, `dmvnorm2`, `dordlogit`. Tripped by
   alists 3, 5, 6, 8, 9. (Of these, `dordlogit` was previously masked
   by the parser blocker; identity-link landing now surfaces it.)
2. **Expressions inside distribution-arg slots** — `dnorm(alpha[county]
   + beta*floor, sigma)` (alist 1). The lowering pass requires each
   arg to be a literal or a single identifier; expressions there must
   be extracted into a deterministic line first.
3. **Expression-parser handling of `softmax(0, s2, s3)`** (alist 5).
   The parser rejects the second comma — it treats the multi-arg
   function call as a malformed identifier expression. Same likely
   true for other multi-arg helper functions.
4. **Indexed RHS without a paired VaryingPrior** — alist 2 (corrected
   form). `mu <- alpha[county] + beta*floor` references `alpha[county]`
   but `alpha` is declared as a scalar `dnorm(0,10)` prior. The
   generator's loop emitter triggers but has no `VaryingPrior(...)`
   declaration to bind `alpha` to a vector type. Either auto-promote
   `alpha` to a vector parameter on detecting the indexed reference,
   or require the user to use `a[county] ~ dnorm(...)` form explicitly.
5. **`Rho ~ dlkjcorr(...)` getting flagged as multivariate-with-truncation**
   (alists 8, 9). The classify pass appears to be auto-promoting a
   truncation onto `Rho` (likely from the σ-truncation inference
   heuristic firing on it). Worth investigating — `dlkjcorr` priors
   should be exempt from the σ-truncation pass.

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

In order of payoff per LOC (post-identity-link):

1. **Add `snorm`, `half_normal`, `dordlogit` distribution aliases to
   `AlistLowering`** — `snorm(...)` → `.normal(...)`; `half_normal(s)`
   → `.normal(0, s)` with `Truncation(lower: 0)`; `dordlogit` →
   `.orderedLogistic(eta:, cutpoints:)` paired with auto-synthesised
   `OrderedCutpoints`. Unblocks alists 3, 6 outright.
2. **Lift the literal-or-identifier constraint on distribution args**
   (alist 1) by adding `DistributionArg.expression(String)` and
   threading verbatim emission through `DistributionCatalog.arg(_:)`.
   The pattern already exists for `multivariateNormalCholesky` — same
   shape.
3. **Add `dmvnorm2` lowering shortcut** that synthesises the
   companion `dlkjcorr` line (alists 8, 9). Mechanical given the
   existing `dmvnormchol` infrastructure. Also investigate the
   spurious truncation on `Rho` (alists 8, 9 generate-stage error).
4. **Auto-promote indexed-but-otherwise-scalar parameters** (alist 2
   after typo fix) — when `alpha[county]` appears in a deterministic
   RHS and `alpha` is declared via a scalar `Prior(...)`, the
   classifier should promote it to `VaryingPrior(..., indexedBy:
   "county", ...)` automatically. Or surface a clearer error message
   pointing at the missing varying declaration.
5. **`dcategorical` + multi-arg-fn-call parser** (alist 5) and
   **measurement-error two-role classification** (alist 10 —
   note: it now passes but produces semantically odd output where
   `div_obs` is treated as a parameter) are bigger architectural lifts
   — defer to a separate planning round.
