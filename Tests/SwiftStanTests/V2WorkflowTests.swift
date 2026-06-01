//
//  V2WorkflowTests.swift
//  StanTests
//
//  V2.1 Slice G: end-to-end coverage for the file-based ulamPipeline.
//  Exercises `dsl2stan → csv2json → compile → sample` chained together
//  against the chimpanzees fixtures. The individual command suites
//  (`Dsl2StanTests`, `Csv2JsonTests`) cover each step in isolation —
//  this suite proves they compose into a working workflow.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("V2.1 pipeline workflow tests")
struct V2WorkflowTests {

  static let cmdstan: String = {
    if let env = ProcessInfo.processInfo.environment["CMDSTAN"], !env.isEmpty {
      return env
    }
    return "/Users/rob/Projects/StanSupport/cmdstan"
  }()

  /// Drives the four-step file pipeline against chimpanzees. Both inputs
  /// (Preliminaries/Chimpanzees.ulam.swift + chimpanzees.csv) exist from
  /// Slice B's migration; the pipeline should produce a fresh .stan,
  /// .data.json, cmdstan binary, and chain CSVs in Results/.
  @Test func chimpanzeesPipelineEndToEnd() throws {
    let paths = casePaths(for: "chimpanzees")
    let fm = FileManager.default
    try #require(fm.fileExists(atPath: paths.preliminaries
      .appendingPathComponent("Chimpanzees.ulam.swift").path))
    try #require(fm.fileExists(atPath: paths.preliminaries
      .appendingPathComponent("chimpanzees.csv").path))

    let result = ulamPipeline(model: "chimpanzees",
                              cmdstan: Self.cmdstan)
    try #require(result.1.isEmpty,
                 "ulamPipeline returned an error: \(result.1)")

    let stan = paths.results.appendingPathComponent("chimpanzees.stan")
    let data = paths.results.appendingPathComponent("chimpanzees.data.json")
    let summary = paths.results.appendingPathComponent("chimpanzees.stansummary.csv")
    #expect(fm.fileExists(atPath: stan.path))
    #expect(fm.fileExists(atPath: data.path))
    #expect(fm.fileExists(atPath: summary.path),
            "stansummary missing — sample step didn't complete")
  }

  /// Howell adult-heights model (McElreath m4.1): a single Gaussian
  /// likelihood with `mu ~ Normal(178, 20)` and `sigma ~ Uniform(0, 50)`
  /// over Howell1.csv pre-filtered to adults. The smallest non-trivial
  /// pipeline case — exercises dsl2stan ← Howell.ulam.swift OR stancode
  /// ← howell.alist.R, csv2json, compile, sample, and the post-sample
  /// stansummary cleanup. Asserts only artifact emission (matching the
  /// chimpanzees pattern); convergence is *not* asserted because
  /// cmdstan's default unconstrained init range U(-2, 2) for `mu`
  /// can't climb to the actual posterior at `mu ≈ 155 cm` without
  /// explicit init values, and the DSL has no `init:` knob yet. Add
  /// the R-hat assertion once DSL-level inits land.
  @Test func howellPipelineEndToEnd() throws {
    let paths = casePaths(for: "howell")
    let fm = FileManager.default
    let csvURL = paths.preliminaries.appendingPathComponent("howell.csv")
    try #require(fm.fileExists(atPath: csvURL.path),
                 "howell.csv fixture missing at \(csvURL.path)")
    // Either an alist.R or a *.ulam.swift driver is sufficient for the
    // pipeline to pick a path.
    let alistURL = paths.preliminaries.appendingPathComponent("howell.alist.R")
    let driverURL = paths.preliminaries.appendingPathComponent("Howell.ulam.swift")
    try #require(fm.fileExists(atPath: alistURL.path)
                 || fm.fileExists(atPath: driverURL.path),
                 "howell driver missing — need howell.alist.R or Howell.ulam.swift")

    let result = ulamPipeline(model: "howell", cmdstan: Self.cmdstan)
    try #require(result.1.isEmpty,
                 "ulamPipeline returned an error: \(result.1)")

    let stan = paths.results.appendingPathComponent("howell.stan")
    let data = paths.results.appendingPathComponent("howell.data.json")
    let summary = paths.results.appendingPathComponent("howell.stansummary.csv")
    #expect(fm.fileExists(atPath: stan.path))
    #expect(fm.fileExists(atPath: data.path))
    #expect(fm.fileExists(atPath: summary.path),
            "stansummary missing — sample step didn't complete")
  }
}
