//
//  Compile.swift
//
//
//  Created by Robert Goedman on 11/17/25.
//

import Foundation

public func compile(model: String = "bernoulli",
                    arguments: [String] = [],
                    cmdstan: String,
                    verbose: Bool = false,
                    install: Bool = false) -> (String, String) {

  let fileManager = FileManager.default
  let paths = casePaths(for: model)
  let dirUrl = paths.results

  do {
    try ensureCaseDirectories(paths, verbose: verbose)
  } catch {
    return ("", "Could not create case directories for \(model): " + error.localizedDescription)
  }

  var result: (String, String) = ("", "")

  if install {
    print("Installing bernoulli.stan demo file as \(model).stan")
    result = createDotStanModelFile(model: model)
    printResult(result)
  } else {
    do {
      let filePath = dirUrl.path + "/" + model + ".stan"
      if fileManager.fileExists(atPath: filePath) {
        do {
          let binaryPath = dirUrl.path + "/" + model
          if !fileManager.fileExists(atPath: binaryPath) {
            result = ("Compilation needed.", "")
          } else {
            if result.0 != "Stan model file has not changed, no compilation needed." {
              return ("Found existing binary. Skipping compilation.", "")
            } else {
              result = ("Compilation needed.", "")
            }
          }
        }
      } else {
        print(("", "File \(filePath) not found."))
        exit(9)
      }
    }
  }

  if result.0 == "Compilation needed." {
    print("Compiling...")
    result = stanCompile(dirUrl: dirUrl,
                         modelName: model,
                         cmdstan: cmdstan,
                         verbose: verbose)
  } else {
    if result.1 != "" {
      printResult(result)
      exit(8) // Check for <model>.stan failed
    }
  }

  if result.1 != "" {
    printResult(result)
    exit(1) // Compilation failed
  } else {
    printResult(result)
  }

  return result
}
