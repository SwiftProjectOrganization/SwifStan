//
//  Sample.swift
//
//
//  Created by Robert Goedman on 11/17/25.
//

import Foundation
import ArgumentParser

public func sample(model: String,
                   arguments: [String],
                   cmdstan: String,
                   verbose: Bool = false,
                   nosummary: Bool = false,
                   install: Bool = false) -> (String, String) {

  var args: [String] = arguments
  if args.count == 0 {
    args.append("num_chains=4")
    args.append("num_samples=1000")
  }

  let fileManager = FileManager.default
  let paths = casePaths(for: model)
  let dirUrl = paths.results

  do {
    try ensureCaseDirectories(paths, verbose: verbose)
  } catch {
    print("", "Could not create case directories for \(model): \(error.localizedDescription)")
    exit(5)
  }

  var result = ("", "")

  if install {
    print("Installing bernoulli.data.json demo file as \(model).data.json")
    result = createDotJsonDataFile(model: model)
  }

  if result.1 == "" {
    result = stanSample(dirUrl: dirUrl,
                        modelName: model,
                        arguments: args,
                        cmdstan: cmdstan,
                        verbose: verbose)
    printResult(result)
  } else {
    exit(6) // Creation of .json data file failed
  }

  if result.1 == "" {
    result = getSampleResult(dirUrl: dirUrl,
                             modelName: model)
    if verbose {
      printResult(result)
    }
  } else {
    exit(7) // stanSample failed
  }

  if !nosummary {
    if result.1 == "" {
      let result = stanSummary(dirUrl: dirUrl,
                               modelName: model,
                               cmdstan: cmdstan)
      if verbose {
        printResult(result)
      }
    } else {
      if !verbose {
        printResult(result)
      }
      exit(8) // getSampleResults failed
    }
  }

  if !nosummary {
    if result.1 == "" {
      result = extractStanSummary(dirUrl: dirUrl,
                                  modelName: model)
      if verbose {
        printResult(result)
      }

    } else {
      exit(9) // stanSummary failed
    }
  }

  return result
}
