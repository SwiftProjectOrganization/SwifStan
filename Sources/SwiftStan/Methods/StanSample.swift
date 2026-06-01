//
//  StanSample.swift
//  
//
//  Created by Robert Goedman on 10/30/25.
//

import Foundation

public func stanSample(dirUrl: URL,
                   modelName: String,
                   arguments: [String] = ["num_chains=4"],
                   cmdstan: String,
                   verbose: Bool) -> (String, String) {
  
  
  let fileManager = FileManager.default
  let binaryPath = "\(dirUrl.path)/\(modelName)"
  if !fileManager.fileExists(atPath: binaryPath + ".data.json") {
    return ("","Input file \(binaryPath).data.json not found.")
  }

  var args = ["sample"]
  args.append(contentsOf: arguments)
  args.append(contentsOf: ["data", "file=\(binaryPath)" + ".data.json"])
  args.append(contentsOf: ["output", "file=\(binaryPath)" + "_output.csv"])
  
  if verbose {
    print(args)
  }
  
  return swiftSyncFileExec(program: binaryPath,
                           arguments: args,
                           method: "sample")
}
