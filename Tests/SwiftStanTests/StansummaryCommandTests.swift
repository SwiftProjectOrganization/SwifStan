//
//  StansummaryCommandTests.swift
//  StanTests
//
//  Direct tests for `stanSummary(...)` — the wrapper around cmdstan's
//  `stansummary` binary. Reads four `<model>_output_<i>.csv` chain
//  files and writes a `<model>_stansummary.csv` aggregate. Happy
//  path: run a tiny sample then summarise. Failure path: invoke with
//  no chain files present — cmdstan stansummary exits non-zero and
//  the wrapper surfaces it.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("Stan stansummary command tests")
struct StansummaryCommandTests {

  static let cmdstan: String = {
    if let env = ProcessInfo.processInfo.environment["CMDSTAN"], !env.isEmpty {
      return env
    }
    return "/Users/rob/Projects/StanSupport/cmdstan"
  }()

  static let bernoulliStanSource = """
  data {
    int<lower=1> N;
    array[N] int<lower=0, upper=1> y;
  }
  parameters {
    real<lower=0, upper=1> theta;
  }
  model {
    theta ~ beta(1, 1);
    y ~ bernoulli(theta);
  }
  """

  /// Compile + sample so the four chain outputs exist, then summarise.
  /// Asserts the raw `<model>_stansummary.csv` lands.
  @Test func stanSummarySucceedsOnExistingChains() throws {
    let model = "stansummary_ok_test"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)

    let stanURL = paths.results.appendingPathComponent("\(model).stan")
    try Self.bernoulliStanSource.write(to: stanURL,
                                       atomically: true, encoding: .utf8)

    let compileResult = stanCompile(dirUrl: paths.results,
                                    modelName: model,
                                    cmdstan: Self.cmdstan,
                                    verbose: false)
    try #require(compileResult.1.isEmpty,
                 "stanCompile error: \(compileResult.1)")

    let goodJSON = #"{"N": 5, "y": [0, 1, 0, 1, 1]}"#
    let dataURL = paths.results.appendingPathComponent("\(model).data.json")
    try goodJSON.write(to: dataURL, atomically: true, encoding: .utf8)

    let sampleResult = stanSample(dirUrl: paths.results,
                                  modelName: model,
                                  arguments: ["num_chains=4", "num_samples=200"],
                                  cmdstan: Self.cmdstan,
                                  verbose: false)
    try #require(sampleResult.1.isEmpty,
                 "stanSample error: \(sampleResult.1)")

    let result = stanSummary(dirUrl: paths.results,
                             modelName: model,
                             cmdstan: Self.cmdstan)
    #expect(result.1.isEmpty,
            "stanSummary should succeed; got error: \(result.1)")

    let summaryURL = paths.results.appendingPathComponent("\(model)_stansummary.csv")
    #expect(FileManager.default.fileExists(atPath: summaryURL.path),
            "stansummary CSV should exist at \(summaryURL.path)")
  }

  /// With no chain outputs on disk, cmdstan's stansummary exits
  /// non-zero. The wrapper now surfaces that as a non-empty error.
  @Test func stanSummaryFailsWhenChainsMissing() throws {
    let model = "stansummary_no_chains_test"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)

    // Remove any leftover chain outputs from a previous run.
    let fm = FileManager.default
    for i in 1...4 {
      let url = paths.results.appendingPathComponent("\(model)_output_\(i).csv")
      try? fm.removeItem(at: url)
    }

    let result = stanSummary(dirUrl: paths.results,
                             modelName: model,
                             cmdstan: Self.cmdstan)
    #expect(!result.1.isEmpty,
            "stanSummary should return an error when chain outputs are missing")
  }
}
