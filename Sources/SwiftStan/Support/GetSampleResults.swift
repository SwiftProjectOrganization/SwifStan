//
//  GetSampleResults.swift
//  
//
//  Created by Robert Goedman on 11/14/25.
//

import Foundation

public func getSampleResult(dirUrl: URL,
                            modelName: String) -> (String, String) {
  // 2026-06-02: glob `<name>_output*.csv` so non-default num_chains
  // values (e.g. num_chains=2 or 8 passed via trailing args) and
  // partial-chain runs are merged correctly. The first chain's header
  // row is kept; subsequent chains contribute their data rows only.
  let chains = chainOutputFiles(dirUrl: dirUrl, modelName: modelName)
  if chains.isEmpty {
    let modelPath = "\(dirUrl.path)/\(modelName)"
    return ("", "Error: no \(modelPath)_output*.csv chains found.")
  }

  var theResult: [String] = []
  for (chainIndex, chainURL) in chains.enumerated() {
    do {
      var count = 0
      let data = try String(contentsOfFile: chainURL.path, encoding: .utf8)
      for line in data.components(separatedBy: .newlines) {
        if line.isEmpty { continue }
        if line.first == "#" { continue }
        if chainIndex == 0 || count > 0 {
          theResult.append(line)
        }
        count += 1
      }
    } catch {
      return ("", "Error: \(error.localizedDescription)")
    }
  }

  let result = createDotCsvFile(from: theResult,
                         dirUrl: dirUrl,
                         modelName: modelName,
                         kind: "samples")

  return result
}

