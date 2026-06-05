# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For exhaustive per-component notes see [`Docs/CLAUDE.md`](Docs/CLAUDE.md).

## Project

A macOS Swift CLI (`swift-argument-parser`) that wraps Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) toolchain, plus a Swift port of McElreath's R `ulam()` DSL. macOS only; Swift 6.2; single dependency (`swift-argument-parser ≥ 1.2.0`).

## Build & test commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test by name
swift test --filter "bernoulliMatchesGolden"

# Run a specific suite
swift test --filter "UlamGeneratorTests"
```

Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`). All test targets are in `Tests/SwiftStanTests/`.

The CLI binary is accessed via an alias to the Xcode DerivedData build product or `swift run SwiftStan <subcommand>`.

Required environment variable: `CMDSTAN` pointing to the cmdstan directory. `STAN_CASES` defaults to `StanCases` (under `~/Documents/`).

## Architecture

### Three-layer call structure

1. **`Sources/SwiftStan/Stan.swift`** — `@main struct Stan: ParsableCommand` with all subcommand definitions and three shared `ParsableArguments` groups (`OptionsCompile`, `OptionsSample`, `OptionsLimited`). Each `run()` resolves `CMDSTAN` and calls into the Commands layer.
2. **`Sources/SwiftStan/Commands/*.swift`** — orchestration: resolve `casePaths(for: model)`, optionally install bootstrap files (`-I`), call the Methods layer, post-process via Support.
3. **`Sources/SwiftStan/Methods/*.swift`** — thin wrappers that build an argv and shell out via `swiftSyncFileExec`. Note: `stanSummary` lives in `RunStanSummary.swift` (not `StanSummary.swift`) to avoid an APFS case-collision with `Commands/Stansummary.swift`.

### `(String, String)` return convention

Almost every helper returns `(String, String)` — `.0` is a human-readable status line, `.1` is an error message (empty on success). Callers branch on `.1 == ""`. Do not replace with `throws` piecemeal.

### Process execution

All shelling-out goes through `Support/SwiftSyncFileExec.swift` (`Foundation.Process`, synchronous, separate stdout/stderr pipes). Exit codes are distinct per failure stage — see `Sample.swift` (exits 5–9) as the canonical pattern.

### Filesystem layout

All commands read/write under `~/Documents/<STAN_CASES>/<name>/`:
- `Preliminaries/` — input: `<name>.csv`, `<name>.alist.R`, `<Name>.ulam.swift`
- `Results/` — output: `.stan`, `.data.json`, cmdstan binaries, chain CSVs, clean post-processed CSVs

### Output post-processing (raw vs clean)

cmdstan emits raw CSV (comment headers, one file per chain). The Support layer cleans it up:

| Method | Raw (from cmdstan) | Clean (post-processed) |
|---|---|---|
| sample | `<name>_output_[1..4].csv` | `<name>.samples.csv` |
| stansummary | `<name>_stansummary.csv` | `<name>.stansummary.csv` |
| optimize | `<name>_optimize.csv` | `<name>.optimize.csv` |
| pathfinder | `<name>_pathfinder.csv` | `<name>.pathfinder.csv` |
| laplace | `<name>_laplace.csv` | `<name>.laplace.csv` |

The raw/clean split is load-bearing for `laplace`: cmdstan needs `<name>_optimize.csv` to carry the `# method = optimize` header as its `mode=` input. Overwriting it in place (as the old code did) destroyed that header. `ReplaceNanByNil.swift` handles cmdstan's literal `nan` tokens during CSV→JSON conversion.

### Subcommands

- `compile` — `OptionsCompile` flags (`-V`, `-I`, `--cmdstan`, `--model`, trailing `values` passed through to make).
- `sample` — defaults `num_chains=4 num_samples=1000`; always produces a clean samples file; by default also runs stansummary. Uses `OptionsSample` (adds `-S/--nosummary`).
- `optimize`, `pathfinder`, `laplace`, `stansummary`, `csv2json`, `dsl2stan`, `alist2dsl`, `stancode` — all use `OptionsLimited`.
- `laplace` — auto-runs `stanOptimize` when `<name>_optimize.csv` is missing or lacks the cmdstan `#` header (one-byte peek via `looksLikeRawOptimizeOutput`), then feeds that raw file via `mode=`.
- `csv2json` — reads `Preliminaries/<name>.csv` + `Results/<name>.stan`, writes `Results/<name>.data.json`. Validates every row-data variable in the `.stan` schema is present in the CSV; derives `N` and `N_<col>` cardinalities; fails loudly on `NA` (`Csv2JsonError.naValue`).
- `dsl2stan` — reads `Preliminaries/*.ulam.swift`, shells out to `swiftc` to compile and run it, captures stdout into `Results/<name>.stan`. Requires `$STAN_PROJECT_ROOT` (defaults to a developer fallback path).
- `alist2dsl` — reads `Preliminaries/<name>.alist.R`, runs lexer → parser → lowering → classify → emitter, writes a runnable `@main` `<Name>.ulam.swift` to `Preliminaries/`. McElreath's "first `~` is the likelihood" convention drives role assignment.
- `stancode` — in-process fast path: same alist parser chain as `alist2dsl`, but the classified AST flows through `AlistToUlamModel.build(_:)` directly to the `stancode(_:)` generator, writing `Results/<name>.stan` without invoking `swiftc`.
- `ulam` (V2.1) — chains `stancode`-or-`dsl2stan` → `csv2json` → `compile` → `sample` with make-style staleness checks (`isStale(input:output:)`) per step. Prefers `alist2dsl` path when `Preliminaries/<name>.alist.R` exists.
- `test` — drives `compile → sample → optimize → pathfinder` on `~/Documents/StanCases/bernoulli/`.

Trailing positional `<values>` are passed verbatim to cmdstan (`num_chains=4`, `save_iterations=true`, etc.) using cmdstan's `key=value` syntax.

### Bootstrap install (`-I`)

`Helpers/CreateDotStanModelFile.swift` and `Helpers/CreateDotJsonDataFile.swift` write a bundled bernoulli example into `Results/` so a fresh checkout has something to compile. `compile -I` installs `<name>.stan`; `sample -I` installs `<name>.data.json`. (`Helpers/` is distinct from `Support/` — the latter contains post-processing utilities.)

### Ulam module (`Sources/SwiftStan/Ulam/`)

Swift port of McElreath's `ulam()`. Sub-packages:
- `AST/` — canonical AST types (`Statement`, `Distribution`, `UlamModel`, `Truncation`, `LinkFunction`, `ExpressionNode`)
- `Builder/` — `@resultBuilder StanModelBuilder` + DSL nodes (`Likelihood`, `Prior`, `VaryingPrior`, `VectorPrior`, `Link`, `Deterministic`)
- `Generator/` — `StanCodeGenerator` (public `stancode(_:) throws -> String`), `BlockEmitter`, `DataInference`, `DistributionCatalog`, recursive-descent `ExpressionParser`/`ExpressionLexer`
- `Data/` — `DataMarshaller` (hand-rolled JSON writer; emits clean `Double` formatting; also emits `<countSymbol>: max(values)` for Phase-5 index columns)
- `Alist/` — R `alist()` parser → two downstream targets: `AlistEmitter` (Swift smoke driver for `dsl2stan`) and `AlistToUlamModel` (in-process `UlamModel` for `stancode`)
- `Ulam.swift` — two orchestrators: `ulam(_:name:cmdstan:verbose:arguments:)` (V1 in-process) and `ulamPipeline(model:cmdstan:verbose:arguments:)` (V2.1 file-based CLI path with make-style staleness checks)

Two `stancode` entry points exist on the Swift API: `stancode(_ model: UlamModel) throws -> String` (pure) and `stancode(model: String, verbose: Bool) throws -> URL` (file-based). The `model:` label disambiguates.

### Sibling project

[SwiftStats](https://github.com/SwiftProjectOrganization/SwiftStats) consumes the clean `*.samples.csv` / `*.stansummary.csv` files this CLI produces. The `~/Documents/<STAN_CASES>/<name>/Results/` layout is the contract between the two — don't rename output files without updating both.

## Code style

- **2-space indentation** throughout (not 4). Match existing files.
- Force-unwraps on `URL.appendingPathComponent` are deliberate — inputs are always non-empty.
- `CMDSTAN` resolution is duplicated in every `run()` rather than centralised — update all of them if the fallback path changes.

## Ruleset

1. **Think Before Coding**: No silent assumptions. Push back if a simpler approach exists.
2. **Simplicity First**: Minimum code required. No speculative features.
3. **Surgical Changes**: Touch only what you must. Do not "improve" adjacent formatting.
4. **Goal-Driven Execution**: Define success criteria and loop until verified.
5. **Hard Token Budgets**.
6. **Read Before You Write**.
7. **Checkpoint Multi-Step Operations**.
8. **Fail Loud**.
