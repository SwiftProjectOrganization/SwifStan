//
//  LaplaceTests.swift
//  StanTests
//
//  Slice δ of Docs/Planning docs/LaplaceCommandPlan.md.
//
//  The cmdstan-guide's canonical Laplace example uses the bernoulli
//  model, which is also the project's canonical fixture (already
//  installed and compiled under `~/Documents/StanCases/bernoulli/`).
//  This test invokes `laplace(model: "bernoulli", ...)` end-to-end
//  and asserts the cleaned `bernoulli_laplace.csv` exists with at
//  least a header + one draw row.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("laplace command tests")
struct LaplaceTests {

  static let cmdstan: String = {
    if let env = ProcessInfo.processInfo.environment["CMDSTAN"], !env.isEmpty {
      return env
    }
    return "/Users/rob/Projects/StanSupport/cmdstan"
  }()

  @Test func bernoulliLaplaceProducesOutputCsv() throws {
    let paths = casePaths(for: "bernoulli")
    let binary = paths.results.appendingPathComponent("bernoulli")
    let dataJSON = paths.results.appendingPathComponent("bernoulli.data.json")
    let fm = FileManager.default
    try #require(fm.fileExists(atPath: binary.path),
                 "bernoulli binary missing; run `stan compile -I --model bernoulli` first")
    try #require(fm.fileExists(atPath: dataJSON.path),
                 "bernoulli.data.json missing; run `stan sample -I --model bernoulli` first")

    let result = laplace(model: "bernoulli",
                         arguments: [],
                         cmdstan: Self.cmdstan,
                         verbose: false)
    try #require(result.1.isEmpty, "laplace returned an error: \(result.1)")

    let cleanURL = paths.results.appendingPathComponent("bernoulli.laplace.csv")
    let rawURL = paths.results.appendingPathComponent("bernoulli_laplace.csv")
    #expect(fm.fileExists(atPath: cleanURL.path),
            "expected clean bernoulli.laplace.csv to exist")
    #expect(fm.fileExists(atPath: rawURL.path),
            "expected raw bernoulli_laplace.csv to be preserved (mode= source for repeat invocations)")

    let clean = try String(contentsOf: cleanURL, encoding: .utf8)
    let cleanLines = clean.split(whereSeparator: \.isNewline)
    #expect(cleanLines.allSatisfy { !$0.hasPrefix("#") },
            "cleaned file must not contain `#` comment lines")
    #expect(cleanLines.count >= 2,
            "expected header + draws; got \(cleanLines.count) line(s)")

    let raw = try String(contentsOf: rawURL, encoding: .utf8)
    #expect(raw.hasPrefix("#"),
            "raw bernoulli_laplace.csv should still begin with cmdstan's `#` header")
  }

  /// Companion to the cmdstan-failure tests for sample / optimize /
  /// pathfinder: laplace against a data JSON that omits a declared
  /// variable should surface cmdstan's stderr as a non-empty error
  /// tuple, not silently report success.
  @Test func stanLaplaceFailsWhenDataMissingDeclaredVariable() throws {
    let model = "laplace_missing_y_test"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)

    let stanSource = """
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
    let stanURL = paths.results.appendingPathComponent("\(model).stan")
    try stanSource.write(to: stanURL, atomically: true, encoding: .utf8)

    let compileResult = stanCompile(dirUrl: paths.results,
                                    modelName: model,
                                    cmdstan: Self.cmdstan,
                                    verbose: false)
    try #require(compileResult.1.isEmpty,
                 "stanCompile error: \(compileResult.1)")

    // Run optimize against good data first so a `mode=` file exists —
    // otherwise cmdstan's laplace stops on the missing-mode error
    // before it reads the data file, and we wouldn't actually exercise
    // the missing-variable code path.
    let dataURL = paths.results.appendingPathComponent("\(model).data.json")
    try #"{"N": 5, "y": [0, 1, 0, 1, 1]}"#.write(to: dataURL,
                                                 atomically: true,
                                                 encoding: .utf8)
    let optResult = stanOptimize(dirUrl: paths.results,
                                 modelName: model,
                                 cmdstan: Self.cmdstan,
                                 verbose: false)
    try #require(optResult.1.isEmpty,
                 "stanOptimize prerequisite failed: \(optResult.1)")

    // Now switch the data JSON to the missing-y form and run laplace
    // with the mode pointing at the optimize output.
    try #"{"N": 5}"#.write(to: dataURL, atomically: true, encoding: .utf8)

    let modePath = paths.results.appendingPathComponent("\(model)_optimize.csv").path
    let result = stanLaplace(dirUrl: paths.results,
                             modelName: model,
                             arguments: ["laplace", "mode=" + modePath],
                             cmdstan: Self.cmdstan,
                             verbose: false)
    #expect(!result.1.isEmpty,
            "stanLaplace should return an error when data is missing a declared variable")
    #expect(result.1.contains("y"),
            "Error should reference the missing variable; got: \(result.1)")
  }
}
