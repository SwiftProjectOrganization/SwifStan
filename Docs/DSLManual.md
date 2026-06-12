# DSL Manual

## 1. Purpose

This manual walks through a set of currently supported R-style `alist()` models,
showing each step — but, unlike [`UlamManual.md`](UlamManual.md), it routes the model
through the **Swift DSL** rather than generating Stan source in-process.

The workflow shown here is the **DSL pipeline**:

```
alist2dsl  →  dsl2stan  →  csv2json  →  compile  →  sample
```

Where `UlamManual.md` uses a single `stancode` step (alist → Stan source, entirely
in-process), this manual splits that step in two:

- `alist2dsl` lowers the `alist()` into a runnable `@main` Swift program — the DSL
  *smoke driver* `Preliminaries/<Name>.ulam.swift`.
- `dsl2stan` compiles that driver with `swiftc` and runs it to capture the Stan
  source into `Results/<name>.stan`.

The DSL driver is the artifact of interest: it shows, in Swift, exactly which DSL
nodes (`Likelihood`, `Prior`, `Link`, …) the `alist()` lowers to. The two paths
produce **identical** Stan source — this manual is the DSL counterpart to the
in-process `stancode` path documented in `UlamManual.md`.

Each example starts from a model description in `Preliminaries/<name>.alist.R` and
uses the `swiftstan` subcommands to generate the DSL, build it, and sample from it.

Requirements:

- macOS only; Swift 6.2+.
- `$CMDSTAN` must point at a cmdstan installation.
- `$STAN_CASES` selects the case-root directory; it defaults to
  `~/Documents/StanCases/`.
- `dsl2stan` additionally needs `$SWIFTSTAN_PROJECT_ROOT` pointing at the SwiftStan
  source checkout, so it can compile the smoke driver against the project's `Ulam/`
  sources. When unset, it uses the default
  `/Users/rob/Projects/Swift/SwiftStan` and prints a notice that the default is in use.

---

## 2. Introduction

Every model lives in its own directory under `~/Documents/<STAN_CASES>/<name>/`,
split into inputs and outputs:

```
~/Documents/StanCases/<name>/
├── Preliminaries/         inputs you provide (plus the generated DSL driver)
│   ├── <name>.alist.r     the model, in McElreath alist() form
│   ├── <name>.csv         the data
└── Results/               everything the rest of the pipeline generates
    ├── <name>.stan        generated Stan source
    ├── <name>             compiled cmdstan binary
    └── <name>.<method>.log / .error.log
```

The model description borrows McElreath's `alist()` notation from the `rethinking`
R package. By convention **the first `~` line is the likelihood**; the remaining
`~` lines are often priors, but can also result in other types of DSL statements. This
convention drives how the parser assigns roles when it lowers the `alist()` into the DSL.

The two source-generation subcommands used in this chapter (the rest — `compile`,
`csv2json`, `sample` — are shared with `UlamManual.md`):

| Command | Reads | Writes |
|---|---|---|
| `swiftstan alist2dsl --model <name>` | `Preliminaries/<name>.alist.r` | `Preliminaries/<Name>.ulam.swift` |
| `swiftstan dsl2stan --model <name>` | `Preliminaries/<Name>.ulam.swift` | `Results/<name>.stan` (+ optional `.init.json`) |
| `swiftstan compile --model <name>` | `Results/<name>.stan` | `Results/<name>` (binary) + compile logs |

`alist2dsl` runs entirely in-process (lex → parse → lower → classify → emit) and
writes a self-contained `@main` Swift driver. Note the **capitalised stem**: model
`radon_dsl` produces `Radon_dsl.ulam.swift`. `dsl2stan` then shells out to `swiftc`
to compile that driver alongside the project's Ulam sources, runs the resulting
binary, and captures its `stancode(model)` stdout into `Results/<name>.stan`.

---

## 3. Simple examples

### 3.1 Radon complete-pooling example

#### 3.1.1 About the radon example

The radon dataset is a multilevel example: measurements
of indoor radon gas concentration in homes, recorded together with the floor on
which the measurement was taken (basement vs. first floor). In its full form it is
the textbook varying-intercept-by-county model, see [ARM](https://sites.stat.columbia.edu/gelman/arm/).

The version used here is the **simplest** form — a complete-pooling linear regression of
log-radon on the floor indicator, with no grouping:

```
log_radon ~ Normal(alpha + beta * floor, sigma)
```

This makes it an ideal first end-to-end example: one likelihood, three priors, no
indexing.

> This manual uses the model name `radon_dsl` (a copy of the `radon` inputs) so its
> generated files sit in their own `~/Documents/StanCases/radon_dsl/` directory and
> never collide with the `radon` case used by `UlamManual.md`. The two `.stan` outputs
> are identical apart from the filename.

#### 3.1.2 The `Preliminaries` directory and `alist2dsl`

The radon_dsl case starts with these inputs:

```
~/Documents/StanCases/radon_dsl/Preliminaries/
├── radon_dsl.alist.R
└── radon_dsl.csv
```

The model description, `radon_dsl.alist.R`, is a direct transcription of McElreath's
`alist()` format of the complete-pooling model:

```r
alist(
	log_radon ~ dnorm(alpha + beta * floor, sigma),
	alpha ~ dnorm(0, 10),
	beta ~ dnorm(0, 10),
	sigma ~ dnorm(0, 10)
)
```

The first line is the likelihood (`log_radon`), and the three following lines are
priors on `alpha`, `beta`, and `sigma`.

Lower the `alist()` into the Swift DSL:

```bash
swiftstan alist2dsl --model radon_dsl
```

This reads `Preliminaries/radon_dsl.alist.R`, runs the alist parser → lowering →
classify → emit chain in-process, and writes a runnable `@main` Swift driver to
`Preliminaries/Radon_dsl.ulam.swift`. On success it prints:

```
→ Wrote /Users/rob/Documents/StanCases/radon_dsl/Preliminaries/Radon_dsl.ulam.swift
```

The generated `Preliminaries/Radon_dsl.ulam.swift`:

```swift
// Radon_dsl.ulam.swift
//
// Generated by `stan alist2dsl` from `radon_dsl.alist.R`.
// Edit `radon_dsl.alist.R` and re-run `stan alist2dsl` to regenerate.
// The `data` literal carries one stub row per column — actual values
// come from `Preliminaries/radon_dsl.csv` via `csv2json`.

@main
struct Radon_dslSmoke {
  static func main() {
    let data: UlamData = [
      "log_radon": .real([0.0]),
      "floor": .real([0.0]),
    ]

    let model = UlamModel(data: data) {
      Likelihood("log_radon", .normal(.expression("alpha + beta*floor"), "sigma"))
      Prior("alpha", .normal(0, 10))
      Prior("beta", .normal(0, 10))
      Prior("sigma", .normal(0, 10), truncation: Truncation(lower: 0))
    }

    do {
      print(try stancode(model))
      let inits = try stanInits(model)
      if !inits.isEmpty {
        print("// === SWIFTSTAN_INITS ===")
        print(inits)
      }
    } catch {
      print("ERROR: \(error)")
    }
  }
}
```

This is where the DSL pipeline differs from `UlamManual.md`. Each `alist()` line maps
to a DSL node:

- The likelihood line becomes `Likelihood("log_radon", .normal(...))`, with its mean
  argument carried as an `.expression("alpha + beta*floor")`.
- Each prior line becomes a `Prior(...)`.
- The `sigma` prior gains `truncation: Truncation(lower: 0)` — the classifier
  recognises `sigma` as a standard deviation and truncates its prior at zero (the same
  inference that gives `sigma` a `<lower=0>` constraint downstream).
- The `data` literal carries **one stub row per referenced column** (`log_radon`,
  `floor`). These stubs only let the driver type-check and infer the data schema; the
  real values come from `radon_dsl.csv` via `csv2json` later.

#### 3.1.3 Generating Stan source with `dsl2stan`

Compile and run the smoke driver to capture its Stan source:

```bash
swiftstan dsl2stan --model radon_dsl
```

This shells out to `swiftc` to compile `Preliminaries/Radon_dsl.ulam.swift` alongside
the project's Ulam sources (resolved via `$SWIFTSTAN_PROJECT_ROOT`), runs the resulting
binary, and writes its stdout to `Results/radon_dsl.stan`. On success it prints:

```
→ Wrote /Users/rob/Documents/StanCases/radon_dsl/Results/radon_dsl.stan
```

The generated `Results/radon_dsl.stan`:

```stan
// Generated by SwiftStan ulam port.
data {
  int<lower=1> N;
  vector[N] floor;
  vector[N] log_radon;
}
parameters {
  real alpha;
  real beta;
  real<lower=0> sigma;
}
model {
  alpha ~ normal(0, 10);
  beta ~ normal(0, 10);
  sigma ~ normal(0, 10) T[0, ];
  log_radon ~ normal(alpha + beta*floor, sigma);
}
```

A few things the generator inferred automatically:

- `N` and the `vector[N]` data columns (`floor`, `log_radon`) were derived from the
  variables referenced in the model.
- `sigma` was given a `<lower=0>` constraint and its prior was truncated at zero
  (`T[0, ]`), matching the `Truncation(lower: 0)` in the DSL driver.
- `dnorm` was mapped to Stan's `normal`.

This file is **byte-for-byte identical** to the `Results/radon.stan` that
`UlamManual.md` produces with `stancode` — the in-process and DSL paths converge on
the same Stan source. (If the smoke driver had emitted initial values, `dsl2stan`
would also write `Results/radon_dsl.init.json`; this model has none.)

#### 3.1.4 Running `compile` and the updated `Results` directory

Compile the generated Stan program into a native cmdstan binary:

```bash
swiftstan compile --model radon_dsl
```

This reads `Results/radon_dsl.stan` and invokes `/usr/bin/make` inside the cmdstan
directory, which runs three stages: translate Stan → C++ (`stanc`), compile the C++
(`clang++`), and link the model. On success it prints:

```
Compiling...
Command `/usr/bin/make (radon_dsl executable)` completed successfully.

→ Command `/usr/bin/make (radon_dsl executable)` completed successfully.
```

After compilation, `Results/` contains the binary and the captured build logs
(`radon_dsl`, `radon_dsl.compile.log`, `radon_dsl.compile.error.log`), exactly as in
`UlamManual.md` §3.1.3. The intermediate `radon_dsl.hpp` and `radon_dsl.o` files are
removed by cmdstan's Makefile once linking succeeds; on a clean build the
`radon_dsl.compile.error.log` is empty. The logs overwrite on each run — copy them
aside if you want a historical record.

#### 3.1.5 Preparing the data with `csv2json`

cmdstan reads its input data as JSON, not CSV. The `csv2json` subcommand reads the
raw `Preliminaries/<name>.csv`, validates it against the data block of the generated
`Results/<name>.stan`, and writes a cmdstan-ready `Results/<name>.data.json`.

The first five lines of `radon_dsl.csv` (a header row plus four data rows):

```
,idnum,state,zip,region,typebldg,floor,room,basement,county,Uppm,log_radon
0,5081.0,MN,55735,5.0,1.0,1.0,3.0,N,AITKIN,0.502054,0.8329091229351040
1,5082.0,MN,55748,5.0,1.0,0.0,4.0,Y,AITKIN,0.502054,0.8329091229351040
2,5083.0,MN,55748,5.0,1.0,0.0,4.0,Y,AITKIN,0.502054,1.0986122886681100
3,5084.0,MN,56469,5.0,1.0,0.0,4.0,Y,AITKIN,0.502054,0.09531017980432490
```

The CSV has many columns, but the model only references `floor` and `log_radon`.
`csv2json` pulls exactly the columns named in the `.stan` data block, derives the row
count `N`, and ignores the rest.

```bash
swiftstan csv2json --model radon_dsl
```

On success it prints:

```
→ Wrote /Users/rob/Documents/StanCases/radon_dsl/Results/radon_dsl.data.json
```

An abbreviated view of the resulting `Results/radon_dsl.data.json` (the two data
vectors are 919 elements each — elided here with `…`):

```json
{
  "floor" : [
    1,
    0,
    0,
    …
  ],
  "log_radon" : [
    0.832909122935104,
    0.832909122935104,
    1.09861228866811,
    …
    1.09861228866811
  ],
  "N" : 919
}
```

Notes:

- Only `floor` and `log_radon` appear — the columns referenced by the model — plus
  the derived `N` (919 rows). Unreferenced CSV columns (`state`, `zip`, `county`, …)
  are dropped.
- `csv2json` fails loudly on `NA` values in any required column rather than emitting
  silent gaps.

With the binary and `radon_dsl.data.json` in place, the model is ready for sampling.

#### 3.1.6 Sampling with `sample` (and `stansummary`)

The `sample` subcommand runs the compiled binary's NUTS sampler against
`Results/radon_dsl.data.json`. By default it runs **four chains of 1000 post-warmup
draws**, cleans the per-chain output into a single samples file, and then **also runs
`stansummary`** to produce convergence diagnostics — all in one invocation.

```bash
swiftstan sample --model radon_dsl
```

Output:

```
Command `/Users/rob/Documents/StanCases/radon_dsl/Results/radon_dsl sample` completed successfully.

→ Wrote cleaned radon_dsl.stansummary.csv (raw radon_dsl_stansummary.csv preserved)
```

The bundled `stansummary` step writes a human-readable table to
`Results/radon_dsl.stansummary.log`:

```
Inference for Stan model: radon_dsl_model
4 chains: each with iter=1000; warmup=1000; thin=1; 1000 iterations saved.

Warmup took (0.091, 0.090, 0.088, 0.083) seconds, 0.35 seconds total
Sampling took (0.14, 0.13, 0.13, 0.11) seconds, 0.52 seconds total

                 Mean     MCSE  StdDev    MAD     5%    50%    95%  ESS_bulk  ESS_tail  ESS_bulk/s  R_hat

lp__             -243  3.0e-02     1.3    1.0   -245   -243   -242      2036      2509        3954    1.0
accept_stat__    0.91  1.5e-03    0.11  0.071   0.69   0.95    1.0      5517      4048       10712    1.0
stepsize__       0.74      nan   0.055  0.060   0.66   0.75   0.81       nan       nan         nan    nan
treedepth__       2.2  1.1e-02    0.54   0.00    1.0    2.0    3.0      2695      3099        5234    1.0
n_leapfrog__      4.8  4.1e-02     2.1   0.00    3.0    3.0    7.0      3049      2636        5920    1.0
divergent__      0.00      nan    0.00   0.00   0.00   0.00   0.00       nan       nan         nan    nan
energy__          245  4.5e-02     1.8    1.7    242    244    248      1665      2489        3233    1.0

alpha             1.4  5.2e-04   0.028  0.028    1.3    1.4    1.4      2950      2808        5728    1.0
beta            -0.59  1.3e-03   0.070  0.070  -0.70  -0.59  -0.47      3029      2923        5881    1.0
sigma            0.79  3.5e-04   0.018  0.019   0.76   0.79   0.82      2797      2614        5430    1.0

Samples were drawn using hmc with nuts.
```

The three model parameters have converged cleanly (`R_hat ≈ 1.00`, healthy effective
sample sizes, no divergences): `alpha ≈ 1.36`, `beta ≈ -0.59` (homes measured on the
first floor read lower than basements), and `sigma ≈ 0.79`.

The same statistics, in machine-readable form, are written to the cleaned
`Results/radon_dsl.stansummary.csv`:

```csv
name,mean,mcse,stddev,mad,p05,p50,p95,ess_bulk,ess_tail,ess_bulk_per_s,R_hat
"lp__",-243.041,0.0296753,1.27123,1.02479,-245.49,-242.687,-241.697,2036.46,2509.39,3954.29,1.00016
...
"alpha",1.36182,0.000519688,0.0280947,0.0277913,1.31405,1.36186,1.40836,2950,2807.69,5728.16,1.00141
"beta",-0.585891,0.00128319,0.0701878,0.0699178,-0.702164,-0.586038,-0.470258,3028.74,2923.42,5881.05,1.00087
"sigma",0.791113,0.000349299,0.0184341,0.0186122,0.760819,0.790648,0.821395,2796.57,2614.5,5430.23,1.00285
```

(In the cleaned CSV, cmdstan's `nan` diagnostic entries — e.g. `stepsize__`'s MCSE —
are replaced with the sentinel `-100000`.)

After sampling, `Results/` holds the raw cmdstan output, the cleaned files this CLI
produces, and the per-method logs:

```
~/Documents/StanCases/radon_dsl/Results/
├── radon_dsl                       compiled binary
├── radon_dsl.stan
├── radon_dsl.data.json
├── radon_dsl_output_1.csv          raw per-chain draws (one file per chain)
├── radon_dsl_output_2.csv
├── radon_dsl_output_3.csv
├── radon_dsl_output_4.csv
├── radon_dsl_output_config.json
├── radon_dsl.samples.csv           ← cleaned: all chains merged
├── radon_dsl_stansummary.csv       raw stansummary output
├── radon_dsl.stansummary.csv       ← cleaned stansummary
├── radon_dsl.sample.log / .error.log
├── radon_dsl.stansummary.log / .error.log
└── radon_dsl.compile.log / .error.log
```

The two **cleaned** files — `radon_dsl.samples.csv` and `radon_dsl.stansummary.csv` —
are the contract consumed by downstream tools (such as the
[SwiftStats](https://github.com/SwiftProjectOrganization/SwiftStats) package).

> Pass `-S` / `--nosummary` to skip the bundled `stansummary` step, or run
> `swiftstan stansummary --model radon_dsl` separately. Trailing `key=value` arguments
> (e.g. `num_chains=8 num_samples=2000`) are passed straight through to cmdstan.

---

## 4. Further examples

The §3 model had only scalar parameters, so its DSL driver used nothing but
`Likelihood` and `Prior`. The grouped examples below introduce the DSL nodes that the
richer `alist()` forms lower to — `Deterministic`, `VaryingPrior`, and `Link` — which
is the whole point of reading the generated driver.

### 4.1 Radon no-pooling example

#### 4.1.1 About the no-pooling radon model

§3.1 fit a single intercept `alpha` shared by every home — *complete pooling*. The
**no-pooling** model goes to the opposite extreme: it gives each of the 85 Minnesota
counties its own independent intercept `alpha[county]`, while keeping a single shared
floor slope `beta`:

```
log_radon ~ Normal(mu, sigma)
mu = alpha[county] + beta * floor
alpha[county] ~ Normal(0, 10)   (one per county, estimated independently)
```

"No pooling" because the county intercepts share no common hyper-distribution — each
is estimated only from that county's own homes. This is the first DSL driver with a
**vector-valued (indexed) parameter**.

> As in §3.1, this manual uses the model name `radon_np_dsl` (a copy of the `radon_np`
> inputs) so its generated files sit in their own
> `~/Documents/StanCases/radon_np_dsl/` directory and never collide with the
> `radon_np` case used by `UlamManual.md` §4.1. The two `.stan` outputs are identical
> apart from the filename.

#### 4.1.2 The `Preliminaries` directory and `alist2dsl`

The radon_np_dsl case starts with these inputs:

```
~/Documents/StanCases/radon_np_dsl/Preliminaries/
├── radon_np_dsl.alist.R
└── radon_np_dsl.csv
```

The model description, `radon_np_dsl.alist.R`:

```r
alist(
	log_radon ~ dnorm(mu, sigma),
    mu <- alpha[county] + beta * floor,
	alpha[county] ~ dnorm(0, 10),
	beta ~ dnorm(0, 10),
	sigma ~ dnorm(0, 10)
)
```

The `mu <- ...` line is a deterministic assignment, and the `[county]` subscript on
`alpha` makes it a grouped (indexed) parameter.

Lower the `alist()` into the Swift DSL:

```bash
swiftstan alist2dsl --model radon_np_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/radon_np_dsl/Preliminaries/Radon_np_dsl.ulam.swift
```

The generated `Preliminaries/Radon_np_dsl.ulam.swift`:

```swift
// Radon_np_dsl.ulam.swift
//
// Generated by `stan alist2dsl` from `radon_np_dsl.alist.R`.
// Edit `radon_np_dsl.alist.R` and re-run `stan alist2dsl` to regenerate.
// The `data` literal carries one stub row per column — actual values
// come from `Preliminaries/radon_np_dsl.csv` via `csv2json`.

@main
struct Radon_np_dslSmoke {
  static func main() {
    let data: UlamData = [
      "log_radon": .real([0.0]),
      "county": .integer([1]),
      "floor": .real([0.0]),
      "mu": .real([0.0]),
    ]

    let model = UlamModel(data: data) {
      Likelihood("log_radon", .normal("mu", "sigma"))
      Deterministic("mu", "alpha[county] + beta*floor")
      VaryingPrior("alpha", indexedBy: "county", .normal(0, 10))
      Prior("beta", .normal(0, 10))
      Prior("sigma", .normal(0, 10), truncation: Truncation(lower: 0))
    }

    do {
      print(try stancode(model))
      let inits = try stanInits(model)
      if !inits.isEmpty {
        print("// === SWIFTSTAN_INITS ===")
        print(inits)
      }
    } catch {
      print("ERROR: \(error)")
    }
  }
}
```

Compared with the §3.1 driver, the grouped model lowers to two new DSL nodes:

- The `mu <- ...` line becomes `Deterministic("mu", "alpha[county] + beta*floor")` —
  a named intermediate quantity rather than an inline mean expression.
- The indexed prior `alpha[county] ~ dnorm(0, 10)` becomes
  `VaryingPrior("alpha", indexedBy: "county", .normal(0, 10))`, which tells the
  generator that `alpha` is a vector with one entry per distinct `county` value.
- The `data` stub now also carries `"county": .integer([1])` and a `"mu"` stub, so the
  driver type-checks; the real index values come from `radon_np_dsl.csv` via
  `csv2json`.

#### 4.1.3 Generating Stan source with `dsl2stan`

Compile and run the smoke driver to capture its Stan source:

```bash
swiftstan dsl2stan --model radon_np_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/radon_np_dsl/Results/radon_np_dsl.stan
```

The generated `Results/radon_np_dsl.stan`:

```stan
// Generated by SwiftStan ulam port.
data {
  int<lower=1> N;
  int<lower=1> N_county;
  array[N] int<lower=1, upper=N_county> county;
  vector[N] floor;
  vector[N] log_radon;
}
parameters {
  vector[N_county] alpha;
  real beta;
  real<lower=0> sigma;
}
model {
  vector[N] mu;
  mu = alpha[county] + beta*floor;
  alpha ~ normal(0, 10);
  beta ~ normal(0, 10);
  sigma ~ normal(0, 10) T[0, ];
  log_radon ~ normal(mu, sigma);
}
```

What the `VaryingPrior` / `Deterministic` nodes produced:

- A cardinality `N_county` and an index array `county` declared as
  `array[N] int<lower=1, upper=N_county>` — one 1-based county index per row.
- `alpha` is now a `vector[N_county]`, and the single prior `alpha ~ normal(0, 10)` is
  applied to the whole vector — all 85 intercepts share one prior but are otherwise
  independent.
- `Deterministic("mu", ...)` became a local `vector[N] mu;` assigned in the `model`
  block.

This file is **byte-for-byte identical** to the `Results/radon_np.stan` that
`UlamManual.md` §4.1 produces with `stancode` — the in-process and DSL paths converge
on the same Stan source.

#### 4.1.4 Running `compile`

```bash
swiftstan compile --model radon_np_dsl
```

```
Command `/usr/bin/make (radon_np_dsl executable)` completed successfully.

→ Command `/usr/bin/make (radon_np_dsl executable)` completed successfully.
```

Writes the `radon_np_dsl` binary and the compile logs into `Results/`, exactly as in
§3.1.4.

#### 4.1.5 Preparing the data with `csv2json`

The `radon_np_dsl.csv` is the full 31-column radon dataset. The model references
`county`, `floor`, `log_radon`; note that `county` holds **strings**
(`"AITKIN"`, `"ANOKA"`, …), not integers.

```bash
swiftstan csv2json --model radon_np_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/radon_np_dsl/Results/radon_np_dsl.data.json
```

`csv2json` **factorises** the string `county` column into 1-based integer indices and
emits the matching cardinality `N_county`:

```json
{
  "county" : [ 1, 1, 1, 1, 2, 2, … ],
  "floor" : [ … ],
  "log_radon" : [ … ],
  "N" : 919,
  "N_county" : 85
}
```

The 85 distinct county names map to indices `1…85` (`AITKIN → 1`, `ANOKA → 2`, …), and
`N_county = 85` matches the `int<lower=1> N_county` the `.stan` schema expects.

#### 4.1.6 Sampling with `sample` (and `stansummary`)

```bash
swiftstan sample --model radon_np_dsl
```

```
Command `/Users/rob/Documents/StanCases/radon_np_dsl/Results/radon_np_dsl sample` completed successfully.

→ Wrote cleaned radon_np_dsl.stansummary.csv (raw radon_np_dsl_stansummary.csv preserved)
```

The model has 87 parameters (85 county intercepts, plus `beta` and `sigma`). The head
and the two shared parameters from `Results/radon_np_dsl.stansummary.log`:

```
Inference for Stan model: radon_np_dsl_model
4 chains: each with iter=1000; warmup=1000; thin=1; 1000 iterations saved.

Sampling took (0.14, 0.14, 0.097, 0.089) seconds, 0.47 seconds total

                 Mean     MCSE  StdDev    MAD     5%    50%    95%  ESS_bulk  ESS_tail  R_hat

lp__             -167  1.8e-01     6.9    6.8   -179   -167   -157      1494      2121    1.0
energy__          211  2.6e-01     9.5    9.3    196    211    227      1340      2252    1.0

alpha[1]         0.89  5.0e-03    0.36   0.37   0.29   0.88    1.5      5282      2715    1.0
alpha[2]         0.93  1.3e-03   0.099  0.097   0.77   0.93    1.1      5836      2844    1.0
...
beta            -0.69  1.2e-03   0.070  0.070  -0.80  -0.69  -0.57      3453      2985    1.0
sigma            0.73  2.5e-04   0.018  0.018   0.70   0.73   0.76      5065      2529    1.0
```

Clean convergence across all 87 parameters (`R_hat ≈ 1.00`, no divergences). The
shared slope `beta ≈ -0.69` matches the in-process result in `UlamManual.md` §4.1, and
the per-county intercepts vary in precision with each county's sample size — counties
with few homes (e.g. `alpha[1]`, StdDev ≈ 0.36) are estimated far less sharply than
data-rich ones (e.g. `alpha[2]`, StdDev ≈ 0.10).

The machine-readable `Results/radon_np_dsl.stansummary.csv` (a few representative
rows):

```csv
name,mean,mcse,stddev,mad,p05,p50,p95,ess_bulk,ess_tail,ess_bulk_per_s,R_hat
"alpha[1]",0.885774,0.00499573,0.360439,0.367019,0.290447,0.88255,1.47843,5281.59,2715.34,11237.4,1.00049
"alpha[85]",1.21446,0.00643127,0.528752,0.527829,0.355369,1.21816,2.0885,6834.05,2940.69,14540.5,1.00307
"beta",-0.687037,0.00119771,0.0699528,0.0703334,-0.803527,-0.687717,-0.571356,3452.61,2984.81,7345.97,1.00069
"sigma",0.727653,0.000249142,0.0176543,0.017741,0.700025,0.727205,0.75756,5065.18,2528.91,10777,1.00069
```

After sampling, `Results/` mirrors the §3.1.6 layout, with `radon_np_dsl.*` filenames.

### 4.2 Chimpanzees — cross-classified varying effects

#### 4.2.1 About the chimpanzees model

This is McElreath's prosocial-choice experiment: each row is one lever-pull by one
chimpanzee, and the binary outcome `pulled_left` records which lever it chose. The
model asks whether chimpanzees pull the prosocial option more often, while accounting
for the fact that observations are grouped two ways at once — by the individual
`actor` and by the experimental `block`:

```
pulled_left ~ Binomial(1, p)
logit(p) = a + a_actor[actor] + a_block[block_id] + (bp + bpc·condition)·prosoc_left
a_actor[actor] ~ Normal(0, sigma_actor)
a_block[block_id] ~ Normal(0, sigma_block)
a, bp, bpc       ~ Normal(0, 10)
sigma_actor, sigma_block ~ HalfCauchy(0, 1)
```

It extends §4.1 in three ways: **two** grouping factors instead of one
(*cross-classified*), **partial pooling** (each group's `sigma_*` is a *learned*
hyper-parameter, not a fixed constant), and a non-trivial linear predictor with an
interaction term, expressed through a **link function**. This is the most elaborate
model in the manual so far, and the first DSL driver to use the `Link` node.

> As in §3.1 and §4.1, this manual uses the model name `chimpanzees_dsl` (a copy of the
> `chimpanzees` inputs) so its generated files sit in their own
> `~/Documents/StanCases/chimpanzees_dsl/` directory and never collide with the
> `chimpanzees` case used by `UlamManual.md` §4.2. The two `.stan` outputs are identical
> apart from the filename.

#### 4.2.2 The `Preliminaries` directory and `alist2dsl`

The chimpanzees_dsl case starts with these inputs:

```
~/Documents/StanCases/chimpanzees_dsl/Preliminaries/
├── chimpanzees_dsl.alist.R
└── chimpanzees_dsl.csv
```

The model description, `chimpanzees_dsl.alist.R`:

```r
alist(
    pulled_left ~ dbinom( 1 , p ),
    logit(p) <- a + a_actor[actor] + a_block[block_id] +
                (bp + bpc*condition)*prosoc_left,
    a_actor[actor] ~ dnorm( 0 , sigma_actor ),
    a_block[block_id] ~ dnorm( 0 , sigma_block ),
    c(a,bp,bpc) ~ dnorm(0,10),
    sigma_actor ~ dcauchy(0,1),
    sigma_block ~ dcauchy(0,1)
)
```

Two notational features beyond §4.1: the `c(a,bp,bpc) ~ dnorm(0,10)` shorthand assigns
the **same prior to three parameters** at once, and the two
`a_*[...] ~ dnorm(0, sigma_*)` lines give each varying intercept a prior whose scale is
itself a parameter (`sigma_actor`, `sigma_block`) — the hallmark of partial pooling.

Lower the `alist()` into the Swift DSL:

```bash
swiftstan alist2dsl --model chimpanzees_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/chimpanzees_dsl/Preliminaries/Chimpanzees_dsl.ulam.swift
```

The generated `Preliminaries/Chimpanzees_dsl.ulam.swift`:

```swift
// Chimpanzees_dsl.ulam.swift
//
// Generated by `stan alist2dsl` from `chimpanzees_dsl.alist.R`.
// Edit `chimpanzees_dsl.alist.R` and re-run `stan alist2dsl` to regenerate.
// The `data` literal carries one stub row per column — actual values
// come from `Preliminaries/chimpanzees_dsl.csv` via `csv2json`.

@main
struct Chimpanzees_dslSmoke {
  static func main() {
    let data: UlamData = [
      "pulled_left": .integer([0]),
      "actor": .integer([1]),
      "block_id": .integer([1]),
      "condition": .real([0.0]),
      "p": .real([0.0]),
      "prosoc_left": .real([0.0]),
    ]

    let model = UlamModel(data: data) {
      Likelihood("pulled_left", .bernoulli(p: "p"))
      Link(.logit, lhs: "p", rhs: "a + a_actor[actor] + a_block[block_id] + (bp + bpc*condition)*prosoc_left")
      VaryingPrior("a_actor", indexedBy: "actor", .normal(0, "sigma_actor"))
      VaryingPrior("a_block", indexedBy: "block_id", .normal(0, "sigma_block"))
      Prior("a", .normal(0, 10))
      Prior("bp", .normal(0, 10))
      Prior("bpc", .normal(0, 10))
      Prior("sigma_actor", .cauchy(0, 1), truncation: Truncation(lower: 0))
      Prior("sigma_block", .cauchy(0, 1), truncation: Truncation(lower: 0))
    }

    do {
      print(try stancode(model))
      let inits = try stanInits(model)
      if !inits.isEmpty {
        print("// === SWIFTSTAN_INITS ===")
        print(inits)
      }
    } catch {
      print("ERROR: \(error)")
    }
  }
}
```

How the richer `alist()` lowered to DSL nodes:

- The `logit(p) <- ...` line became a `Link(.logit, lhs: "p", rhs: ...)` — the new node
  this example introduces. The `dbinom(1, p)` likelihood (one trial) lowered to
  `.bernoulli(p: "p")`.
- The two `a_*[...] ~ dnorm(0, sigma_*)` lines each became a `VaryingPrior` whose scale
  is the *symbol* `"sigma_actor"` / `"sigma_block"` rather than a literal — that is what
  makes the pooling partial.
- The `c(a,bp,bpc) ~ dnorm(0,10)` shorthand expanded into three separate `Prior` nodes.
- `sigma_actor` / `sigma_block` are recognised as standard deviations and gain
  `truncation: Truncation(lower: 0)`.
- The `data` stub carries both index columns (`actor`, `block_id` as `.integer`) and a
  `"p"` stub for the linked quantity, so the driver type-checks; the real values come
  from `chimpanzees_dsl.csv` via `csv2json`.

#### 4.2.3 Generating Stan source with `dsl2stan`

Compile and run the smoke driver to capture its Stan source:

```bash
swiftstan dsl2stan --model chimpanzees_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/chimpanzees_dsl/Results/chimpanzees_dsl.stan
```

The generated `Results/chimpanzees_dsl.stan`:

```stan
// Generated by SwiftStan ulam port.
data {
  int<lower=1> N;
  int<lower=1> N_actor;
  int<lower=1> N_block_id;
  array[N] int<lower=1, upper=N_actor> actor;
  array[N] int<lower=1, upper=N_block_id> block_id;
  vector[N] condition;
  vector[N] prosoc_left;
  array[N] int<lower=0, upper=1> pulled_left;
}
parameters {
  vector[N_actor] a_actor;
  vector[N_block_id] a_block;
  real a;
  real bp;
  real bpc;
  real<lower=0> sigma_actor;
  real<lower=0> sigma_block;
}
model {
  vector[N] p;
  for (i in 1:N) {
    p[i] = inv_logit(a + a_actor[actor[i]] + a_block[block_id[i]] + (bp + bpc*condition[i])*prosoc_left[i]);
  }
  a_actor ~ normal(0, sigma_actor);
  a_block ~ normal(0, sigma_block);
  a ~ normal(0, 10);
  bp ~ normal(0, 10);
  bpc ~ normal(0, 10);
  sigma_actor ~ cauchy(0, 1) T[0, ];
  sigma_block ~ cauchy(0, 1) T[0, ];
  pulled_left ~ bernoulli(p);
}
```

What the `Link` / `VaryingPrior` nodes produced:

- **Two** index pairs — `(N_actor, actor)` and `(N_block_id, block_id)` — each with its
  own `vector[N_*]` intercept.
- `sigma_actor` / `sigma_block` appear *as the scale* of the `a_actor` / `a_block`
  priors — the partial-pooling structure.
- Because the linear predictor mixes indexed and per-row terms in an interaction
  (`(bp + bpc*condition)*prosoc_left`), the `Link` is emitted as an explicit
  `for (i in 1:N)` loop computing `p[i] = inv_logit(...)`, rather than a single
  vectorised expression.
- `dbinom(1, p)` with one trial collapses to `bernoulli(p)`, and the `logit` link
  becomes `inv_logit`.

This file is **byte-for-byte identical** to the `Results/chimpanzees.stan` that
`UlamManual.md` §4.2 produces with `stancode` — the in-process and DSL paths converge on
the same Stan source.

#### 4.2.4 Running `compile`

```bash
swiftstan compile --model chimpanzees_dsl
```

```
Compiling...
Command `/usr/bin/make (chimpanzees_dsl executable)` completed successfully.

→ Command `/usr/bin/make (chimpanzees_dsl executable)` completed successfully.
```

Writes the `chimpanzees_dsl` binary and the compile logs into `Results/`, exactly as in
§3.1.4.

#### 4.2.5 Preparing the data with `csv2json`

The first six lines of `chimpanzees_dsl.csv` (header plus five of the 504 rows):

```
"","actor","condition","block_id","trial","prosoc_left","chose_prosoc","pulled_left"
"1",1,0,1,2,0,1,0
"2",1,0,1,4,0,0,1
"3",1,0,1,6,1,0,0
"4",1,0,1,8,0,1,0
"5",1,0,1,10,1,1,1
```

```bash
swiftstan csv2json --model chimpanzees_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/chimpanzees_dsl/Results/chimpanzees_dsl.data.json
```

The two index columns are already integer-coded in the CSV, so `csv2json` simply carries
them through and derives both cardinalities (keys emitted in sorted order):

```json
{
  "actor" : [ 1, 1, 1, … ],
  "block_id" : [ 1, 1, 1, … ],
  "condition" : [ … ],
  "N" : 504,
  "N_actor" : 7,
  "N_block_id" : 6,
  "prosoc_left" : [ … ],
  "pulled_left" : [ … ]
}
```

There are 7 chimpanzees and 6 experimental blocks, so `N_actor = 7` and
`N_block_id = 6` — matching the two `int<lower=1>` cardinalities in the `.stan` schema.
(Unlike the `radon_np_dsl` county column in §4.1, these are already integers, so no
string factorisation is needed.)

#### 4.2.6 Sampling with `sample` (and `stansummary`)

```bash
swiftstan sample --model chimpanzees_dsl
```

```
Command `/Users/rob/Documents/StanCases/chimpanzees_dsl/Results/chimpanzees_dsl sample` completed successfully.

→ Wrote cleaned chimpanzees_dsl.stansummary.csv (raw chimpanzees_dsl_stansummary.csv preserved)
```

This model has 18 parameters. The head and a representative slice from
`Results/chimpanzees_dsl.stansummary.log`:

```
Inference for Stan model: chimpanzees_dsl_model
4 chains: each with iter=1000; warmup=1000; thin=1; 1000 iterations saved.

Sampling took (0.80, 0.84, 0.76, 0.76) seconds, 3.2 seconds total

                    Mean     MCSE   StdDev    MAD     5%       50%    95%  ESS_bulk  ESS_tail  R_hat

lp__            -2.6e+02  3.2e-01      5.3    5.1   -271  -2.6e+02   -253       285       313    1.0

a_actor[1]      -1.2e+00  4.2e-02      1.1   0.89   -2.9  -1.1e+00   0.48       778       487    1.0
a_actor[2]       4.2e+00  6.2e-02      1.8    1.4    2.0   3.9e+00    7.5      1087       478    1.0
a_actor[3]      -1.5e+00  3.9e-02      1.1   0.90   -3.2  -1.4e+00   0.12       826       501    1.0
...
a_actor[7]       1.3e+00  3.8e-02      1.1   0.92  -0.42   1.3e+00    3.0       869       446    1.0
a_block[1]      -1.8e-01  9.4e-03     0.24   0.17  -0.64  -1.1e-01  0.079       765       939    1.0
...
a_block[6]       1.1e-01  6.6e-03     0.21   0.14  -0.14   6.6e-02   0.52      1125      1506    1.0
a                4.6e-01  3.9e-02      1.1   0.87   -1.1   4.2e-01    2.2       797       466    1.0
bp               8.2e-01  5.2e-03     0.26   0.25   0.41   8.2e-01    1.2      2455      2765    1.0
bpc             -1.3e-01  6.1e-03     0.30   0.29  -0.61  -1.3e-01   0.36      2352      2470    1.0
sigma_actor      2.3e+00  3.4e-02      1.0   0.74    1.2   2.1e+00    4.2      1018      1179    1.0
sigma_block      2.3e-01  9.7e-03     0.19   0.16  0.019   1.8e-01   0.58       246       253    1.0
```

Convergence is healthy (`R_hat ≈ 1.00` throughout), with only a couple of divergent
transitions out of the 4000 draws; the effective sample sizes are smaller than in the
simpler models because the hierarchical geometry is harder to sample. The science matches
McElreath's result: the prosocial main effect `bp ≈ 0.82` is clearly positive, while the
interaction `bpc ≈ -0.13` is near zero. Crucially, `sigma_actor ≈ 2.3` is an order of
magnitude larger than `sigma_block ≈ 0.23` — almost all the variation is between
*individuals*, not between *blocks*, and the large `a_actor[2] ≈ 4.2` is the one chimp
that nearly always pulled left.

The machine-readable `Results/chimpanzees_dsl.stansummary.csv` (representative rows):

```csv
name,mean,mcse,stddev,mad,p05,p50,p95,ess_bulk,ess_tail,ess_bulk_per_s,R_hat
"a_actor[2]",4.17541,0.0615018,1.77036,1.40082,1.96074,3.88038,7.46706,1087.33,478.384,344.636,1.00597
"a",0.457678,0.0387435,1.0563,0.865397,-1.13769,0.417652,2.19645,796.951,465.572,252.599,1.00707
"bp",0.819987,0.0052032,0.257437,0.254555,0.405078,0.819342,1.24289,2455.1,2765.44,778.16,1.00302
"bpc",-0.13066,0.00610594,0.29518,0.293138,-0.610849,-0.131488,0.356286,2351.77,2470.31,745.411,1.0024
"sigma_actor",2.33359,0.0341759,1.02128,0.743166,1.24678,2.0977,4.18615,1017.63,1178.82,322.546,1.0042
"sigma_block",0.225027,0.00972454,0.18517,0.162614,0.0194493,0.184242,0.578693,246.317,252.95,78.0718,1.01329
```

After sampling, `Results/` mirrors the §3.1.6 layout, with `chimpanzees_dsl.*` filenames.

---

## 5. Advanced examples

The advanced examples reach the richest DSL nodes — correlated (multivariate) varying
effects and the covariance/LKJ priors they require.

### 5.1 Cafés — correlated varying slopes (multivariate normal + LKJ)

#### 5.1.1 About the café model

This is McElreath's chapter-14 café waiting-time model: each café has a per-café
intercept and afternoon slope drawn **jointly** from a bivariate normal, with an
**LKJ-Cholesky** prior on the intercept–slope correlation.

```
wait ~ Normal(mu, sigma)
mu   = a_cafe[cafe] + b_cafe[cafe] * afternoon
[a_cafe[cafe], b_cafe[cafe]] ~ MVNormal([a, b], S)
S = diag(sigma_cafe) · Rho · diag(sigma_cafe)
Rho  ~ LKJcorr(2)
```

It is the DSL counterpart to `UlamManual.md` §5.1 — and the most demanding lowering in
the manual, exercising three DSL nodes the simpler models never reach:
`VaryingVectorPrior`, `LKJCorrCholeskyPrior`, and a `Deterministic` whose RHS indexes
the packed coefficient vector.

> As elsewhere in this manual, the case is named `cafe_dsl` (a copy of the `cafe`
> inputs) so its generated files never collide with the `cafe` case used by
> `UlamManual.md` §5.1. The two `.stan` outputs are identical apart from the filename.

#### 5.1.2 The `Preliminaries` directory and `alist2dsl`

```
~/Documents/StanCases/cafe_dsl/Preliminaries/
├── cafe_dsl.alist.R
└── cafe_dsl.csv
```

The model description, `cafe_dsl.alist.R`:

```r
alist(
	wait ~ dnorm( mu , sigma ),
	mu <- a_cafe[cafe] + b_cafe[cafe]*afternoon,
	c(a_cafe,b_cafe)[cafe] ~ dmvnorm2(c(a,b),sigma_cafe,Rho),
	a ~ dnorm(0,10),
	b ~ dnorm(0,10),
	sigma_cafe ~ dcauchy(0,2),
	sigma ~ dcauchy(0,2),
	Rho ~ dlkjcorr(2)
)
```

Lower it into the Swift DSL:

```bash
swiftstan alist2dsl --model cafe_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/cafe_dsl/Preliminaries/Cafe_dsl.ulam.swift
```

The model closure of the generated `Preliminaries/Cafe_dsl.ulam.swift`:

```swift
    let model = UlamModel(data: data) {
      Likelihood("wait", .normal("mu", "sigma"))
      Deterministic("mu", "a_cafeb_cafe[cafe][1] + a_cafeb_cafe[cafe][2]*afternoon")
      VaryingVectorPrior("a_cafeb_cafe", indexedBy: "cafe", length: "J", .multivariateNormalCholesky(mean: "[a, b]'", chol: "diag_pre_multiply(sigma_cafe, Rho)"))
      Prior("a", .normal(0, 10))
      Prior("b", .normal(0, 10))
      VectorPrior("sigma_cafe", length: "J", .cauchy(0, 2), truncation: Truncation(lower: 0))
      Prior("sigma", .cauchy(0, 2), truncation: Truncation(lower: 0))
      LKJCorrCholeskyPrior("Rho", dim: "J", eta: 2)
    }
```

This is where the DSL pipeline earns its keep — the single `dmvnorm2` alist line
lowers into several distinct nodes, and the driver shows exactly which:

- `c(a_cafe, b_cafe)[cafe] ~ dmvnorm2(...)` becomes a **`VaryingVectorPrior`** over a
  packed parameter `a_cafeb_cafe` (the two coefficient names joined), length `J`, with
  a `.multivariateNormalCholesky` distribution whose chol arg is
  `diag_pre_multiply(sigma_cafe, Rho)` — scale first, then correlation factor.
- The deterministic `mu <- a_cafe[cafe] + b_cafe[cafe]*afternoon` is **rewritten** to
  index the packed vector: `a_cafeb_cafe[cafe][1]` / `[2]`. The split names `a_cafe` /
  `b_cafe` no longer exist as parameters, so they don't appear here or in the `data`
  stub literal.
- `sigma_cafe` (the `dmvnorm2` scale arg) is promoted to a length-`J` **`VectorPrior`**
  with the conventional `lower: 0` truncation.
- `Rho` (the correlation arg) becomes an **`LKJCorrCholeskyPrior`** — *not* a
  `VectorPrior`, and with no truncation (it's multivariate).

#### 5.1.3 Generating Stan source with `dsl2stan`

```bash
swiftstan dsl2stan --model cafe_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/cafe_dsl/Results/cafe_dsl.stan
```

The generated `Results/cafe_dsl.stan`:

```stan
// Generated by SwiftStan ulam port.
data {
  int<lower=1> N;
  int<lower=1> N_cafe;
  vector[N] afternoon;
  array[N] int<lower=1, upper=N_cafe> cafe;
  vector[N] wait;
  int J;
}
parameters {
  array[N_cafe] vector[J] a_cafeb_cafe;
  real a;
  real b;
  vector<lower=0>[J] sigma_cafe;
  real<lower=0> sigma;
  cholesky_factor_corr[J] Rho;
}
model {
  vector[N] mu;
  for (i in 1:N) {
    mu[i] = a_cafeb_cafe[cafe[i]][1] + a_cafeb_cafe[cafe[i]][2]*afternoon[i];
  }
  a_cafeb_cafe ~ multi_normal_cholesky([a, b]', diag_pre_multiply(sigma_cafe, Rho));
  a ~ normal(0, 10);
  b ~ normal(0, 10);
  sigma_cafe ~ cauchy(0, 2) T[0, ];
  sigma ~ cauchy(0, 2) T[0, ];
  Rho ~ lkj_corr_cholesky(2);
  wait ~ normal(mu, sigma);
}
```

This file is **byte-for-byte identical** to the `Results/cafe.stan` that
`UlamManual.md` §5.1 produces with `stancode`. Because the smoke driver declares the
structural constant `J` as a `.scalarInt(2)`, `dsl2stan` also writes a
`Results/cafe_dsl.scalars.json` sidecar (`{"J":2}`) — see §5.1.5.

#### 5.1.4 Running `compile`

```bash
swiftstan compile --model cafe_dsl
```

```
Command `/usr/bin/make (cafe_dsl executable)` completed successfully.

→ Command `/usr/bin/make (cafe_dsl executable)` completed successfully.
```

#### 5.1.5 Preparing the data with `csv2json`

The first six lines of `cafe_dsl.csv` (header plus five of the 60 rows):

```
"","cafe","afternoon","wait"
"1",1,0,3.81
"2",2,0,4.22
"3",3,0,3.95
"4",4,0,4.14
"5",5,0,4.08
```

```bash
swiftstan csv2json --model cafe_dsl
```

```
→ Wrote /Users/rob/Documents/StanCases/cafe_dsl/Results/cafe_dsl.data.json
```

The resulting data JSON carries the three CSV arrays, the derived cardinalities, **and
the structural constant `J`**:

```json
{
  "afternoon" : [ … ],
  "cafe" : [ 1, 2, 3, … ],
  "wait" : [ … ],
  "J" : 2,
  "N" : 60,
  "N_cafe" : 6
}
```

`J = 2` is the multivariate dimension, not a CSV column. `dsl2stan` recorded it in
`Results/cafe_dsl.scalars.json` (`{"J":2}`) when it ran the smoke driver, and
`csv2json` merges that sidecar into the data JSON so cmdstan finds the `int J;` its
data block declares. (Without it, sampling would fail with "variable J not found in
data.")

#### 5.1.6 Sampling with `sample` (and `stansummary`)

```bash
swiftstan sample --model cafe_dsl
```

```
Command `/Users/rob/Documents/StanCases/cafe_dsl/Results/cafe_dsl sample` completed successfully.

→ Wrote cleaned cafe_dsl.stansummary.csv (raw cafe_dsl_stansummary.csv preserved)
```

An excerpt of `Results/cafe_dsl.stansummary.log`:

```
Inference for Stan model: cafe_dsl_model
4 chains: each with iter=1000; warmup=1000; thin=1; 1000 iterations saved.

                     Mean     MCSE  StdDev      MAD        5%    50%    95%  ESS_bulk  ESS_tail  R_hat

a_cafeb_cafe[1,1]     3.6  3.0e-03   0.081    0.078       3.4    3.6    3.7       747      1235    1.0
a                     3.6  3.1e-03   0.073    0.073       3.5    3.6    3.7       551       909    1.0
b                    -1.1  3.7e-03    0.10    0.099      -1.3   -1.1  -0.93       691      1198    1.0
sigma_cafe[1]       0.073  3.3e-03   0.059    0.048     0.013  0.058   0.19        60      1646    1.1
sigma                0.35  8.4e-04   0.032    0.030      0.30   0.35   0.41      1409      1851    1.0
Rho[2,1]            -0.13  3.5e-02    0.47     0.54     -0.88  -0.14   0.64       156        66    1.0

Samples were drawn using hmc with nuts.
```

The population means match `UlamManual.md` §5.1: a morning baseline `a ≈ 3.6` and a
negative afternoon effect `b ≈ -1.1`, with `Rho[2,1]` the Cholesky-factor entry behind
the intercept–slope correlation.

> **Convergence note.** As in `UlamManual.md` §5.1, this is the *centred*
> parameterisation of a correlated hierarchical model — its funnel geometry samples
> imperfectly (low ESS on `sigma_cafe`, a few divergences). The parameters reach
> `R_hat ≈ 1.0`, but a production fit would use a non-centred reparameterisation or a
> higher `adapt_delta`.

The machine-readable `Results/cafe_dsl.stansummary.csv` (representative rows):

```csv
name,mean,mcse,stddev,mad,p05,p50,p95,ess_bulk,ess_tail,ess_bulk_per_s,R_hat
"a_cafeb_cafe[1,1]",3.562,0.00296222,0.0811679,0.0780603,3.43098,3.56239,3.69664,746.544,1234.93,2085.32,1.00939
"a",3.56944,0.00307964,0.0731355,0.0731752,3.45561,3.56963,3.69316,550.561,909.181,1537.88,1.0088
"b",-1.0829,0.00374287,0.101336,0.0990481,-1.2501,-1.08044,-0.92538,691.156,1197.72,1930.6,1.00942
"sigma",0.352947,0.00083542,0.0322444,0.0296973,0.304912,0.348983,0.412448,1408.85,1851.49,3935.34,1.0028
"Rho[2,1]",-0.130855,0.0347975,0.465984,0.541672,-0.882031,-0.136753,0.63938,156.134,66.2086,436.13,1.02965
```

After sampling, `Results/` mirrors the §3.1.6 layout, with `cafe_dsl.*` filenames plus
the `cafe_dsl.scalars.json` sidecar.

---

## 6. Future work

The DSL pipeline and this manual are still growing. Planned additions:

- **Route the remaining `UlamManual.md` examples through the DSL pipeline** — the
  bernoulli (§3.2), binomial (§3.3), and grouped/indexed (§4) models, showing the
  additional DSL nodes (`Link`, `VectorPrior`, `VaryingPrior`) each lowers to.
- **Non-centred parameterisation** for correlated/hierarchical models. The café model
  (§5.1) is emitted in the centred form, whose funnel geometry samples imperfectly.
- **Crossed random effects with distinct group cardinalities.** The current port
  shares a single vector-length symbol (`J`); independent grouping dimensions need
  per-group symbols.
- **Indexed bare-LHS deterministics** (`mu[i] <- …`). Today only plain-identifier
  deterministic targets are rewritten to the packed-and-indexed form.
- **A non-developer default for `$SWIFTSTAN_PROJECT_ROOT`.** `dsl2stan` falls back to
  a hard-coded checkout path; a relocatable default would make the DSL pipeline
  portable across machines.

---

## 7. References

- McElreath, R. *Statistical Rethinking: A Bayesian Course with Examples in R and
  Stan* (2nd ed.), CRC Press — the source of the `ulam()` DSL and most examples here.
- The `rethinking` R package — <https://github.com/rmcelreath/rethinking>.
- Stan and cmdstan documentation —
  <https://mc-stan.org/docs/2_37/cmdstan-guide/>.
- Gelman, A. & Hill, J. *Data Analysis Using Regression and Multilevel/Hierarchical
  Models* (ARM) — the radon example — <https://sites.stat.columbia.edu/gelman/arm/>.
- [SwiftStats](https://github.com/SwiftProjectOrganization/SwiftStats) — the sibling
  package that consumes the clean `*.samples.csv` / `*.stansummary.csv` outputs.

---

## See also

- [`UlamManual.md`](UlamManual.md) — the same examples via the in-process `stancode`
  path (no `swiftc`); the DSL pipeline here produces identical Stan source.
- [`README.md`](README.md) — project overview, setup, and environment configuration.
