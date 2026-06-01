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

  let result = swiftSyncFileExec(program: cmdstan + "/bin/stansummary",
                                 arguments: [ dirUrl.path + "/" + modelName + "_output_1.csv",
                                              dirUrl.path + "/" + modelName + "_output_2.csv",
                                              dirUrl.path + "/" + modelName + "_output_3.csv",
                                              dirUrl.path + "/" + modelName + "_output_4.csv",
                                              "--csv_filename", filePath],
                                 method: "")
  return result
}
