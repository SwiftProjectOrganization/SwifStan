# SwiftStan CLAUDE.md

## Purpose of this file

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SwiftStan is a Swift Package that provides a command-line tool that wraps Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) toolchain on macOS. 

The functionality provided by SwiftStan can be used:

1. In Xcode: edit the scheme's "Arguments passed on launch", press build-and-run, and watch the console. 

2. By creating an alias `swiftstan` to `~/Library/Developer/Xcode/DerivedData/SwiftStan_*/Build/Products/Debug/SwiftStan`, it can be used from a shell. This is the intended way.

## Build & Run Commands

From within Xcode:

1. Product → Scheme → Edit Scheme → set "Arguments passed on launch" (e.g. `compile -V -I --model bernoulli`, `sample --model bernoulli`, `test`). 
2. Build and Run.

From a shell (the primary workflow):

```bash
swiftstan compile --model bernoulli
swiftstan sample -V --model bernoulli num_samples=2000
swiftstan test  # runs the full cycle on Bernoulli
```

The `BuildProject` MCP tool builds the Xcode-resolved package directly.

## Environment & filesystem assumptions

See the [README](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/README.md)

## Architecture

### Layered call structure

Each subcommand has the same three layers; navigate them in this order when changing behaviour:

1. **`Sources/SwiftStan/SwiftStan.swift`** — the `@main struct SwiftStan: ParsableCommand` plus nested `extension SwiftStan { struct <Sub>: ParsableCommand }` types. Three shared `ParsableArguments` groups (`OptionsCompile`, `OptionsSample`, `OptionsLimited`) carry the flags/options. Each subcommand's `run()` reads `CMDSTAN`, resolves the path, and forwards to a top-level Swift function.
2. **`Sources/SwiftStan/Commands/*.swift`** — `compile`, `sample`, `optimize`, `pathfinder`, `laplace`, `stansummary`, `csv2json`, `dsl2stan`, `alist2dsl`, `stancode`. These are the orchestration layer: resolve `casePaths(for: model)`, optionally install bootstrap files (`-I`), call the `Methods/` layer (or shell out via `Process`), then post-process via `Support/`.
3. **`Sources/SwiftStan/Methods/*.swift`** — `stanCompile`, `stanSample`, `stanOptimize`, `stanPathfinder`, `stanSummary`. Thin wrappers that build an argv and shell out via `swiftSyncFileExec`. The `stanSummary` function lives in `Methods/RunStanSummary.swift` (not `StanSummary.swift`) to avoid an APFS case-insensitive `.o` collision with `Commands/Stansummary.swift`.

### Process execution

All shelling-out goes through `Support/SwiftSyncFileExec.swift`. It uses `Foundation.Process` synchronously with separate `stdout`/`stderr` pipes, reads both to EOF, and returns `(stdout-summary, stderr-or-empty)`. The convention across the codebase is that **empty second element = success**; callers branch on `result.1 == ""` and `exit(N)` with distinct codes per failure point (see `Sample.swift` for the canonical example: exits 5–9 each tag a different stage).

Callers that pass the optional `logsDir:` + `logsBase:` parameters (every cmdstan-method wrapper does) get a best-effort per-invocation log written to `<dir>/<base>.log` (stdout) and `<dir>/<base>.error.log` (stderr). Both files are always written (zero-byte = "ran but emitted nothing"), overwrite on each call, and any write failure is swallowed — log capture never breaks the return tuple.

### Bootstrap install (`-I` / `--install`)

`Helpers/CreateDotStanModelFile.swift` and `Helpers/CreateDotJsonDataFile.swift` write a bundled bernoulli example into the target `<name>/Results/` so a fresh checkout has something to compile and sample. `compile -I` installs `<name>.stan`; `sample -I` installs `<name>.data.json`. The `test` subcommand drives the full cycle end-to-end on `~/Documents/StanCases/bernoulli/`.

### Output post-processing

After cmdstan emits its native CSV (with comment lines and one file per chain), the `Support/` layer cleans it up:

All four post-processed methods follow a uniform **`_raw` / `.clean`** filename convention:

| Method | Raw (from cmdstan) | Clean (post-processed) |
|---|---|---|
| sample | `<name>_output_[1..4].csv` | `<name>.samples.csv` |
| stansummary | `<name>_stansummary.csv` | `<name>.stansummary.csv` |
| optimize | `<name>_optimize.csv` | `<name>.optimize.csv` |
| pathfinder | `<name>_pathfinder.csv` | `<name>.pathfinder.csv` |
| laplace | `<name>_laplace.csv` | `<name>.laplace.csv` |

- `GetSampleResults.swift` collapses the four chain files into a single `<name>.samples.csv`.
- `ExtractStanSummary.swift` reads the raw stansummary CSV and writes a lower-cased-header version to `<name>.stansummary.csv` (also normalises cmdstan `nan` tokens via `replaceNanByNil`).
- `GetOptimizeResult.swift`, `GetPathfinderResult.swift`, `GetLaplaceResult.swift` each read raw and write a comment-stripped clean file alongside, leaving the raw intact.

The split is load-bearing for `optimize` specifically — `stan laplace`'s `mode=<file>` argument needs cmdstan to recognise `<name>_optimize.csv` as Stan optimize output via its `# method = optimize` header, which the in-place overwrite used to destroy.
- `ReplaceNanByNil.swift` handles cmdstan's `nan` tokens — Stan emits the literal string `nan` for undefined entries, which doesn't survive a normal CSV → JSON round-trip without intervention.
- `CsvToDict.swift` + `DictToJson.swift` are the building blocks for the `csvtojson` subcommand: parse CSV (header-aware, configurable delimiter) into `[String: [Double]]`, then serialize.


### Subcommands

Defined in `SwiftStan.swift`:

- `compile` — uses `OptionsCompile` (`-V`, `-I`, `--cmdstan`, `--model`, trailing `values`).
- `sample` — uses `OptionsSample` (adds `-S/--nosummary`). Defaults `num_chains=4 num_samples=1000` when no trailing args are passed. Always calls `getSampleResult` to produce the clean samples file, and by default also runs `stanSummary` + `extractStanSummary`.
- `optimize`, `pathfinder`, `laplace`, `stansummary`, `csv2json`, `dsl2stan`, `alist2dsl`, `stancode`, `runinfo` — all use `OptionsLimited` (no `-I` or `-S`).
- `laplace` — runs cmdstan's Laplace approximation. cmdstan requires an explicit `mode=<file>`; the orchestrator runs `stanOptimize` when `<name>_optimize.csv` is missing or doesn't carry the cmdstan `#` header (verified via a one-byte peek in `looksLikeRawOptimizeOutput`), then feeds the raw file via `mode=`. Trailing pass-through args (`stan laplace --model bernoulli draws=2000 mode=my_mode.csv`) work as for any other cmdstan subcommand. The split filename convention — raw `<name>_optimize.csv` vs clean `<name>.optimize.csv` (see Output post-processing above) — is what keeps the raw file stable across repeated invocations.
- `alist2dsl` — reads `Preliminaries/<name>.alist.R`, runs lexer → parser → lowering → classify → emitter (see **Alist module** below), writes a runnable `@main` `<Name>.ulam.swift` to the same `Preliminaries/` directory. McElreath's "first `~` statement is the likelihood" convention drives the role assignment; `dbinom(1, p)` collapses to `.bernoulli(p:)`; `σ` parameters that appear as the scale slot of a normal/cauchy/lognormal/gamma get `truncation: Truncation(lower: 0)` automatically (half-Cauchy / half-normal).
- `stancode` — in-process fast path. Same alist parser chain as `alist2dsl`, but the classified AST flows through `AlistToUlamModel.build(_:)` to a runtime `UlamModel` value, then through the existing public `stancode(_: UlamModel) throws -> String` generator, written directly to `Results/<name>.stan`. No swiftc, no subprocess. Two stancode entry points exist on the Swift API: `stancode(_ model: UlamModel) throws -> String` (pure) and `stancode(model: String, verbose: Bool) throws -> URL` (the file-based command). The label `model:` disambiguates.
- `csv2json` — reads `Preliminaries/<name>.csv` + `Results/<name>.stan`, writes `Results/<name>.data.json`. Validates that every row-data variable declared in the `.stan` schema is present in the CSV; derives `N` and `N_<col>` cardinalities from the data; fails loudly on `NA` (`Csv2JsonError.naValue` with column + row).
- `dsl2stan` — reads `Preliminaries/*.ulam.swift`, shells to `swiftc` to compile + run it, captures stdout into `Results/<name>.stan`. Locates the project source tree via `$STAN_PROJECT_ROOT` (defaults to a developer fallback path).
- `runinfo` — pure-Swift, no shell-out. Reads `Results/<name>_output_config.json` (cmdstan emits this when `save_cmdstan_config=true` — `StanSample.swift` already sets it) into a typed `RunInfo` value, then writes a cleaned `Results/<name>.runinfo.json` alongside (`data.file`/`output.file` reduced to basenames, sorted keys, 2-space indent). Two Swift API entry points: `readRunInfo(dirUrl:modelName:) throws -> RunInfo` (parse only) and `writeCleanRunInfo(dirUrl:modelName:) throws -> URL` (parse + clean + write). `MethodConfig` is a tagged-union enum (`.sample(SampleConfig)`, `.optimize(OptimizeConfig)`, `.laplace(LaplaceConfig)`, `.pathfinder(PathfinderConfig)`) discriminated on the `method.value` string; the `sample` case is fully typed against a real cmdstan emission, the other three currently decode the nested object into a `[String: JSONValue]` placeholder until those wrappers also set `save_cmdstan_config=true`. The hand-rolled `RunInfoMarshaller` (mirrors `Ulam/Data/DataMarshaller.swift`) preserves clean Doubles (`0.05`, not `0.050000000000000003` as `JSONSerialization.data(.prettyPrinted)` would emit). The Support file is `RunInfoIO.swift` (not `RunInfo.swift`) to avoid an APFS case-insensitive `.o` collision with `Commands/Runinfo.swift` — same pattern as `Methods/RunStanSummary.swift` vs `Commands/Stansummary.swift`.
- `ulam` — V2.1: file-based pipeline driven by `ulamPipeline(model:cmdstan:verbose:arguments:)`. Picks the .stan-generation path by input presence: if `Preliminaries/<name>.alist.R` exists, use `stancode` (in-process, fast); otherwise, fall back to `dsl2stan` against `Preliminaries/<Name>.ulam.swift`. Then `csv2json → compile → sample`. Each step skipped when its outputs are newer than its inputs. The CLI lowercases `--model` for case-directory lookup.
- `test` (default subcommand) — drives `compile → sample → optimize → pathfinder` on `~/Documents/StanCases/bernoulli/`.

`SWiftStan.swift` repeats the CMDSTAN-resolution block in every `run()` rather than centralising it; if the fallback path needs to change, update all of them.

### Ulam module

A Swift port of McElreath's R `ulam()` (from the `rethinking` package). Sits **above** the existing pipeline: emits a `<name>.stan` + `<name>.data.json` from a Swift result-builder DSL and hands off to the existing `compile` + `sample` machinery. alist2dsl ✅, stancode ✅.

Layout under `Sources/SwiftStan/Ulam/`:

- `AST/` — `Statement` (canonical AST node, `likelihood`/`prior` carry `truncation` and `useLpdf`; `varyingPrior` adds `indexedBy` and `countSymbol`; `vectorPrior` adds `length`), `Distribution` (catalog: `normal`, `bernoulli`, `binomial`, `beta`, `exponential`, `poisson`, `gamma`, `cauchy`, `lognormal`, `uniform`, `studentT`, `multivariateNormal`), `LinkFunction`, `Expression` (raw-string wrapper in v1), `Truncation` (optional `lower`/`upper` + `.none` static), `UlamModel` (top-level value).
- `Builder/` — `StanModelBuilder` (`@resultBuilder`) and six DSL nodes: `Likelihood`, `Prior`, `VaryingPrior`, `VectorPrior`, `Link`, `Deterministic`. `Likelihood`/`Prior`/`VaryingPrior`/`VectorPrior` initialisers carry defaulted `truncation:` and `useLpdf:`; `VaryingPrior` adds defaulted `countSymbol:` for overriding the auto-derived `N_<col>` cardinality variable; `VectorPrior` carries a `length:` cardinality symbol (for `vector[K] mu;`-style declarations under a `multi_normal` prior). All conform to `ModelStatement`.
- `Data/` — `UlamColumn` enum (`.real / .integer / .scalarReal / .scalarInt`) + `UlamData` typealias; `DataMarshaller` (hand-rolled JSON writer with clean Double formatting — emits `0.1` not `0.10000000000000001`; also emits `<countSymbol>: max(values)` for each Phase-5 index column).
- `Generator/` — `DistributionCatalog` (R→Stan name + arg-order mapping, `isDiscrete` for the `_lpmf`/`_lpdf` choice, `renderTruncation` for the `T[...]` suffix, `renderConstraint` for the parameter-declaration constraint suffix, `outcomeBounds` for integer-outcome `<lower=0[, upper=1]>`), `DataInference` (classifies symbols as data/parameter/derived, computes `N`, infers parameter constraints from prior truncations, records outcome bounds per LHS; Phase 5: tracks `vectorParameters` and `indexColumns` from `varyingPrior` cases; throws `conflictingParameterConstraints`/`conflictingVaryingPriorCardinality`/`conflictingIndexColumnCardinality`/`parameterIsBothScalarAndVarying`), `BlockEmitter` (writes `data`/`parameters`/`model` blocks; `dataBlock` uses `outcomeBounds` and Phase-5 index column declarations + tightened `<lower=1, upper=<countSymbol>>` bounds; `parametersBlock` uses `parameterConstraints` and emits `vector<constraint>[<countSymbol>] <name>;` for vector-typed parameters; `modelBlock` routes through `vectorisationStrategy(for:knownVectorParameters:knownIndexColumns:)` — canonical `a[group]` over known vector parameters + index columns vectorises, everything else throws `BlockEmitterError.loopEmissionRequired`; emits both the `~ dist(args) T[...];` form and the `target += dist_lp[m]df(lhs | args);` form; throws `BlockEmitterError.truncationWithLpdf` if both are requested together), `StanCodeGenerator` (public `stancode(_:) throws -> String`; `assemble(inferred:statements:)` is the shared helper that prepends the `// Generated by Stan ulam port (DSL → Stan source).` traceability header).
- `Alist/` — V2.1 follow-up. Seven files implementing the R `alist()` parser plus both downstream targets (Swift smoke driver and runtime `UlamModel`). `AlistAST.swift` (`AlistStatement`/`AlistSampleLhs`/`AlistLink`/`AlistDistribution`) + `AlistLexer.swift` (R tokens incl. `~`, `<-`, `#` comments) + `AlistParser.swift` (outer-wrap stripping for `m12.5 <- map2stan(alist(...), ...)`, comma-split statements, reuses `ExpressionParser` via source-span extraction) cover Slice A. `AlistLowering.swift` maps R `d*` names to V1 `Distribution` cases, expands `c(a, b, c) ~ ...` group priors, and collapses `dbinom(1, p)` → `.bernoulli(p:)`. `AlistClassify.swift` assigns identifier roles (outcome / scalar param / varying param / index column / data column) using McElreath's "first `~` is the likelihood" convention, infers `lower: 0` truncation for any scalar parameter that appears as the scale slot of a normal/cauchy/lognormal/gamma elsewhere, and carries the shared `stubKind(for:)` Q1(b) heuristic that both downstream emitters consume. Two emitters: `AlistEmitter.swift` renders the classified AST as a runnable `@main struct <name>Smoke` smoke driver (input for `dsl2stan`); `AlistToUlamModel.swift` builds an in-memory `UlamModel` value (input for `stancode`).
- `Ulam.swift` — two orchestrators side by side. `ulam(_ model: UlamModel, name:cmdstan:verbose:arguments:)` is the V1 in-process path used by the existing demo tests. `ulamPipeline(model: String, cmdstan:verbose:arguments:)` is the V2.1 file-based path the CLI uses — chains `alist2dsl → dsl2stan → csv2json → compile → sample` with make-style staleness checks (`isStale(input:output:)` per step).

DSL example:

```swift
let model = UlamModel(data: ["y": .integer(...), "x": .real(...)]) {
  Likelihood("y", .bernoulli(p: "p"))
  Link(.logit, lhs: "p", rhs: "a + b*x")
  Prior("a", .normal(0, 1.5))
  Prior("b", .normal(0, 0.5))
}
```

### Tests & fixture staging

Tests live in `Tests/SwiftStanTests/`; they use Swift Testing (`@Suite` + `@Test` + `#require`/`#expect`), not XCTest. Run a single one with `swift test --filter "<name>"`.

A whole-suite invocation (`swift test`) writes all artifacts into a sibling **`~/Documents/<STAN_CASES>_Test/`** dir, not the production `<STAN_CASES>/`. The redirect is wired by `Tests/SwiftStanTests/TestCaseRootBootstrap.swift`: every `@Suite` struct's `init()` references `TestCaseRootBootstrap.install`, which sets `caseRootOverride` (declared in `Sources/SwiftStan/Support/CasePaths.swift`) exactly once at first access. From that point on, every `casePaths(for:)` call resolves under `<STAN_CASES>_Test/`. Production binaries never touch `caseRootOverride` — it stays nil through the CLI's entire lifetime.

The contract: `swift test` must succeed against an **empty** `~/Documents/<STAN_CASES>_Test/` directory. Pipeline tests that need a hand-authored fixture (e.g. `howell.csv`, `chimpanzees.csv`, `Chimpanzees.ulam.swift`) **must** stage that fixture themselves before any `#require(fileExists:)`. Don't rely on test ordering — Swift Testing parallelises, and the first run from a fresh checkout is the canonical "does this work?" case. `StanCases_Test/` is left populated across runs so cmdstan binaries survive (make-style staleness checks skip the rebuild); wipe with `rm -rf ~/Documents/StanCases_Test` to exercise the empty-state contract.

When adding a new `@Suite` struct, add `init() { _ = TestCaseRootBootstrap.install }` as the first member — without it the suite runs against the user's production `<STAN_CASES>/` instead.

Pattern:

1. Bundle the fixture under `Tests/SwiftStanTests/TestDataFiles/` and declare it in `Package.swift` (`resources: [.copy("TestDataFiles")]` is already set).
2. Call `stageBundledFixture(named:to:)` from `Tests/SwiftStanTests/TestFixtureStaging.swift` — it copies via `Bundle.module` and overwrites stale destinations.
3. If the test also needs derived artifacts (a compiled binary, a generated `.stan`), bootstrap them after staging: call `stancode(model:)` / `stanCompile(...)` / `createDotStanModelFile(model:)` / `createDotJsonDataFile(model:)` directly. `LaplaceTests.bernoulliLaplaceProducesOutputCsv` is the canonical example.
4. Keep the `#require(fileExists:)` checks downstream of staging — they then act as belt-and-braces for the staging itself.

Why not just rely on `~/Documents/StanCases/`? Because clean checkouts (and CI) won't have it, and we don't want test pass/fail to depend on which other test ran first.

### `(String, String)` return convention

Almost every helper returns `(String, String)` where `.0` is a human-readable status line and `.1` is an error message (empty on success). This shows up everywhere — `compile`, `sample`, `swiftSyncFileExec`, `csvToDict`, etc. — and the call sites consistently branch on `.1 == ""`. Don't replace it with `throws` piecemeal; either keep it or refactor everything in one pass.

## Argument quirks

- `--directory <directory>` is **relative to `~/Documents`**, not the working directory. There's no way to point at an absolute path without editing the source.
- Trailing positional `<values>` are passed through verbatim to cmdstan (`num_chains=4`, `save_iterations=true`, etc.), so they follow cmdstan's `key=value` syntax, not Swift-argument-parser's.
- `-V/--verbose` is wired everywhere but its semantics are inconsistent — sometimes it prints the make/cmdstan invocation, sometimes a status `(String, String)` tuple.
- `--version` and `-V` collide in spirit (top-level `Stan` declares `version: "1.0.0"`, individual subcommands have `-V` as `--verbose`). The top-level `--version` flag works because subcommands don't reach it.

## Code style

Indentation in the existing sources is **2 spaces**, not the 4 spaces specified in the parent `CLAUDE.md` style note. Match the existing files (2-space) when editing them. Force-unwraps on `URL` from `appendingPathComponent` are common in this codebase — that API returns optional, but the inputs are always non-empty, so the unwrap is safe in context.

## Related / sibling projects

- [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) — the underlying binary that this wrapper calls via `make`.
- McElreath's R package `rethinking` provides `ulam()`.

## Key constraints

- macOS only (`Process`, `/usr/bin/make`, `~/Documents`-rooted paths, `FileManager.urls(for: .documentDirectory, in: .userDomainMask)`).
- Swift 6.2+ toolchain (`Package.swift` declares `swift-tools-version: 6.2`).
- Single dependency: `swift-argument-parser` ≥ 1.2.0. Do not pull in additional packages without a clear reason — the CLI's value proposition is "thin wrapper".
- Prefer `async`/`await` over Combine for any new asynchronous code. The current shell-out path is intentionally synchronous (`Process.run()` + read-to-EOF) because the CLI is short-lived; if you make it async, propagate that everywhere rather than mixing styles.

## Ruleset

Leave this section and these rules in CLAUDE.md and use them as overall guidance.

1. Think Before Coding: No silent assumptions. Push back if a simpler approach exists.
2. Simplicity First: Minimum code required. No speculative features.
3. Surgical Changes: Touch only what you must. Do not “improve” adjacent formatting.
4. Goal-Driven Execution: Define success criteria and loop until verified, rather than blindly following rigid steps.
5. Hard Token Budgets.
6. Read Before You Write.
7. Checkpoint Multi-Step Operations.
8. Fail Loud.

