//
//  StanSummary.swift
//
//
//  Created by Robert Goedman on 10/30/25.
//
//  V2.1 follow-up (2026-05-29): the raw cmdstan stansummary output
//  now lands at `<model>_stansummary.csv` (was `<model>_summary.csv`)
//  so the `_raw` / `.clean` split convention is uniform with
//  optimize/laplace/pathfinder. The post-processor in
//  `ExtractStanSummary.swift` reads it and writes the cleaned
//  `<model>.stansummary.csv` alongside.
//

import Foundation

public func stanSummary(dirUrl: URL,
                        modelName: String,
                        cmdstan: String) -> (String, String) {
  let fileManager = FileManager.default
  let filePath = dirUrl.path + "/" + modelName + "_stansummary.csv"

  do {
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory) {
      try fileManager.removeItem(atPath: filePath)
    }
  } catch {
    print("Error deleting file \(modelName)_stansummary.csv: \(error)")
  }

  // 2026-06-02: glob the chain files actually written by cmdstan rather
  // than hard-coding `_output_1..4.csv`. Handles arbitrary `num_chains`
  // values supplied via trailing args, plus partial runs where some
  // chains diverged — summarise whatever is on disk.
  let chains = chainOutputFiles(dirUrl: dirUrl, modelName: modelName)
  if chains.isEmpty {
    return ("", "stansummary: no `\(modelName)_output*.csv` files found in \(dirUrl.path)")
  }
  let result = swiftSyncFileExec(program: cmdstan + "/bin/stansummary",
                                 arguments: chains.map(\.path)
                                   + ["--csv_filename", filePath],
                                 method: "")
  return result
}

/// Enumerate cmdstan's per-chain output files for a model, in chain-id
/// order. cmdstan writes `<model>_output.csv` for `num_chains=1` and
/// `<model>_output_<N>.csv` for `num_chains>1`. Globbing both patterns
/// means downstream stansummary / samples-cleanup don't need to know
/// the chain count up front. Sort is numeric on the trailing chain id
/// so 10+ chains don't reorder ahead of single-digits.
///
/// Matching is **case-insensitive** because the default macOS APFS
/// volume is case-preserving but case-insensitive: a file originally
/// created as `bernoulli_output_1.csv` keeps that display name even
/// when the binary now writes through `Bernoulli_output_1.csv`. A
/// case-sensitive `hasPrefix` would miss the stale-cased entries and
/// the post-sample glob would return empty.
func chainOutputFiles(dirUrl: URL, modelName: String) -> [URL] {
  let fm = FileManager.default
  guard let entries = try? fm.contentsOfDirectory(atPath: dirUrl.path) else {
    return []
  }
  let singleLower = "\(modelName)_output.csv".lowercased()
  let multiPrefixLower = "\(modelName)_output_".lowercased()
  let candidates = entries.filter { name in
    let lower = name.lowercased()
    return lower == singleLower
        || (lower.hasPrefix(multiPrefixLower) && lower.hasSuffix(".csv"))
  }
  return candidates
    .sorted { lhs, rhs in chainId(lhs, multiPrefix: multiPrefixLower)
                       < chainId(rhs, multiPrefix: multiPrefixLower) }
    .map { dirUrl.appendingPathComponent($0) }
}

/// Extract the chain id from a chain-output filename. `_output.csv` →
/// 0; `_output_<N>.csv` → N. Unparseable trailing components return
/// `Int.max` so they sort to the end and don't shift earlier files.
/// `multiPrefix` is the lowercased multi-chain prefix; the filename is
/// lowercased for comparison so case-mixed inputs sort correctly.
private func chainId(_ filename: String, multiPrefix: String) -> Int {
  let lower = filename.lowercased()
  guard lower.hasPrefix(multiPrefix) else { return 0 }
  let middle = lower
    .dropFirst(multiPrefix.count)
    .dropLast(".csv".count)
  return Int(middle) ?? .max
}
