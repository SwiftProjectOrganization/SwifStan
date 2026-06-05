//
//  Runinfo.swift
//  SwiftStan
//
//  CLI-side wrapper for reading the cmdstan config JSON written by a
//  prior `sample` invocation (with `save_cmdstan_config=true`) and
//  writing a cleaned, portable `<name>.runinfo.json` alongside.
//
//  Pure-Swift — no cmdstan shell-out, no `Methods/` layer entry. Same
//  shape as `csv2json` / `stancode`.
//

import Foundation

/// Top-level entry for the `runinfo` CLI subcommand. Reads
/// `Results/<name>_output_config.json`, writes
/// `Results/<name>.runinfo.json` with absolute paths stripped to
/// basenames. Returns the URL of the cleaned file.
@discardableResult
public func runinfo(model: String, verbose: Bool = false) throws -> URL {
  let paths = casePaths(for: model)
  try ensureCaseDirectories(paths, verbose: verbose)

  let info = try readRunInfo(dirUrl: paths.results, modelName: model)
  if verbose {
    switch info.method {
    case .sample(let s):
      print("runinfo: \(info.modelName) — sample (chains=\(s.numChains), warmup=\(s.numWarmup), samples=\(s.numSamples))")
    case .optimize:
      print("runinfo: \(info.modelName) — optimize")
    case .laplace:
      print("runinfo: \(info.modelName) — laplace")
    case .pathfinder:
      print("runinfo: \(info.modelName) — pathfinder")
    }
  }
  return try writeCleanRunInfo(dirUrl: paths.results, modelName: model)
}
