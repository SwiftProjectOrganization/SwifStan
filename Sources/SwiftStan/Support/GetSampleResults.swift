//
//  GetSampleResults.swift
//  
//
//  Created by Robert Goedman on 11/14/25.
//

import Foundation

public func getSampleResult(dirUrl: URL,
                            modelName: String) -> (String, String) {
  
  let fileManager = FileManager.default
  let modelPath: String = "\(dirUrl.path)/\(modelName)"
  var theResult: [String] = []
  
  for i in 1...4 {
    do {
      var isDirectory: ObjCBool = false
      let filePath: String? = modelPath + "_output_\(i).csv"
      if fileManager.fileExists(atPath: filePath!, isDirectory: &isDirectory) {
        if let path = filePath {
          do {
            var count = 0
            //print("Reading file \(path).")
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let myStrings = data.components(separatedBy: .newlines)
            for result in myStrings {
              if result.count > 0 {
                let index = result.index(result.startIndex, offsetBy: 0)
                let character = result[index]
                if character != "#" {
                  if (i == 1) || (i > 1 && count > 0) {
                    theResult.append(result)
                  }
                  count += 1
                }
              }
            }
          } catch {
            return ("", "Error: \(error.localizedDescription)")
          }
        }
      } else {
        return ("", "Error: \(modelPath)_output_\(i).csv not found.")
      }
    }
  }
  
  let result = createDotCsvFile(from: theResult,
                         dirUrl: dirUrl,
                         modelName: modelName,
                         kind: "samples")
  
  return result
}

