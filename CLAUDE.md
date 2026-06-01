# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For full architecture notes see [`Docs/CLAUDE.md`](Docs/CLAUDE.md). This file summarises the essentials.

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

All commands read/write under `~/Documents/<STAN_CASES>/<model>/`:
- `Preliminaries/` — input: `<model>.csv`, `<model>.alist.R`, `<Model>.ulam.swift`
- `Results/` — output: `.stan`, `.data.json`, cmdstan binaries, chain CSVs, clean post-processed CSVs

### Output post-processing (raw vs clean)

cmdstan emits raw CSV (comment headers, one file per chain). The Support layer cleans it up using a `_raw` / `.clean` filename split — e.g. `<model>_optimize.csv` (raw, kept for `laplace mode=`) vs `<model>.optimize.csv` (clean). See `Docs/CLAUDE.md` for the full table.

### Ulam module (`Sources/SwiftStan/Ulam/`)

Swift port of McElreath's `ulam()`. Sub-packages:
- `AST/` — canonical AST types (`Statement`, `Distribution`, `UlamModel`, etc.)
- `Builder/` — `@resultBuilder StanModelBuilder` + DSL nodes (`Likelihood`, `Prior`, `VaryingPrior`, `VectorPrior`, `Link`, `Deterministic`)
- `Generator/` — `StanCodeGenerator` (public `stancode(_:) throws -> String`), `BlockEmitter`, `DataInference`, `DistributionCatalog`, recursive-descent `ExpressionParser`
- `Data/` — `DataMarshaller` (hand-rolled JSON writer; emits clean `Double` formatting)
- `Alist/` — R `alist()` parser → two downstream targets: `AlistEmitter` (Swift smoke driver for `dsl2stan`) and `AlistToUlamModel` (in-process `UlamModel` for `stancode`)
- `Ulam.swift` — two orchestrators: `ulam(_:name:cmdstan:verbose:arguments:)` (V1 in-process) and `ulamPipeline(model:cmdstan:verbose:arguments:)` (V2.1 file-based CLI path with make-style staleness checks)

### `laplace` subcommand note

Requires a raw optimize output file with the `# method = optimize` header intact. The split filename convention (raw `_optimize.csv` vs clean `.optimize.csv`) is what keeps that header stable across repeated runs. See `Docs/CLAUDE.md` for details.

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
