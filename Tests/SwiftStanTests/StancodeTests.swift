//
//  StancodeTests.swift
//  StanTests
//
//  Slice ε of Docs/StancodeCommandPlan.md. Three checks:
//
//   1. `stancode` command output equals the in-process generator
//      output for the equivalent model — locks in that the fast
//      path's `AlistToUlamModel` translation produces the same Stan
//      as the demo factory.
//   2. `stancode` and `alist2dsl → dsl2stan` outputs are byte-equal —
//      proves the two paths are interchangeable (option 2 of the
//      plan's ulamPipeline integration safely picks either based on
//      which input is present).
//   3. Missing `.alist.R` surfaces `StancodeError.alistNotFound`.
//
//  Synthetic fixtures keep the chimpanzees / bernoulli case dirs
//  untouched (mirrors the pattern in Dsl2StanTests / Alist2DslTests).
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("stancode command tests")
struct StancodeTests {
  init() { _ = TestCaseRootBootstrap.install }


  static let bernoulliAlist = """
    bernoulli_demo <- ulam(
        alist(
            y ~ dbinom( 1 , p ),
            logit(p) <- a + b*x,
            a ~ dnorm( 0 , 1.5 ),
            b ~ dnorm( 0 , 0.5 )
        ),
        data=d )
    """

  @Test func bernoulliMatchesInProcessGenerator() throws {
    let model = "stancode_bernoulli_fixture"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

    let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
    try Self.bernoulliAlist.write(to: alistURL, atomically: true, encoding: .utf8)

    let stanURL = try stancode(model: model)
    let emitted = try String(contentsOf: stanURL, encoding: .utf8)
    let golden = try stancode(SwiftStan.Ulam.bernoulliDemo())
    #expect(emitted == golden,
            "stancode fast-path output diverged from in-process bernoulli golden")
  }

  @Test func matchesDsl2StanByteForByte() throws {
    let fastModel = "stancode_fast_fixture"
    let slowModel = "stancode_slow_fixture"
    let paths = casePaths(for: fastModel)
    let slowPaths = casePaths(for: slowModel)
    try ensureCaseDirectories(paths)
    try ensureCaseDirectories(slowPaths)
    defer {
      try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(fastModel))
      try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(slowModel))
    }

    try Self.bernoulliAlist.write(
      to: paths.preliminaries.appendingPathComponent("\(fastModel).alist.R"),
      atomically: true, encoding: .utf8)
    try Self.bernoulliAlist.write(
      to: slowPaths.preliminaries.appendingPathComponent("\(slowModel).alist.R"),
      atomically: true, encoding: .utf8)

    // Fast path: alist.R → stancode → .stan.
    let fastURL = try stancode(model: fastModel)
    let fastSource = try String(contentsOf: fastURL, encoding: .utf8)

    // Slow path: alist.R → alist2dsl → smoke driver → dsl2stan → .stan.
    _ = try alist2dsl(model: slowModel)
    let slowURL = try dsl2stan(model: slowModel)
    let slowSource = try String(contentsOf: slowURL, encoding: .utf8)

    #expect(fastSource == slowSource,
            "stancode and dsl2stan paths produced different Stan sources")
  }

  @Test func missingAlistThrows() throws {
    let model = "stancode_missing_fixture"
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }
    #expect(throws: StancodeError.self) {
      _ = try stancode(model: model)
    }
  }
}
