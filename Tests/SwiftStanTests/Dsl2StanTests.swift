//
//  Dsl2StanTests.swift
//  StanTests
//
//  V2.1 Slice D: coverage for the `dsl2stan` command.
//
//  Uses a dedicated synthetic fixture (`dsl2stan_fixture`) rather than
//  the bernoulli case directory — `UlamArtifactEmissionTests` overwrites
//  bernoulli's Preliminaries smoke driver in parallel, which races
//  swiftc's "input file was modified during the build" check.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("dsl2stan command tests")
struct Dsl2StanTests {

  static let fixtureModel = "dsl2stan_fixture"

  static let fixtureSmokeDriver = """
    // dsl2stan_fixture.ulam.swift — minimal smoke driver for the
    // dsl2stan round-trip test. Mirrors the Bernoulli demo's shape.

    @main
    struct DSL2StanFixtureSmoke {
      static func main() {
        let data: UlamData = [
          "y": .integer([0, 1, 0, 1, 1, 0, 1, 1, 1, 0]),
          "x": .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]),
        ]

        let model = UlamModel(data: data) {
          Likelihood("y", .bernoulli(p: "p"))
          Link(.logit, lhs: "p", rhs: "a + b*x")
          Prior("a", .normal(0, 1.5))
          Prior("b", .normal(0, 0.5))
        }

        do {
          print(try stancode(model))
        } catch {
          print("ERROR: \\(error)")
        }
      }
    }
    """

  @Test func smokeDriverRoundTripsToGolden() throws {
    let paths = casePaths(for: Self.fixtureModel)
    try ensureCaseDirectories(paths)
    let smokeURL = paths.preliminaries.appendingPathComponent("Fixture.ulam.swift")
    try Self.fixtureSmokeDriver.write(to: smokeURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(
        at: caseRoot().appendingPathComponent(Self.fixtureModel))
    }

    let writtenURL = try dsl2stan(model: Self.fixtureModel)
    let emitted = try String(contentsOf: writtenURL, encoding: .utf8)

    // The fixture builds the same model as `SwiftStan.Ulam.bernoulliDemo()`,
    // so the emitted Stan should equal what the in-process generator
    // produces for that model.
    let golden = try stancode(SwiftStan.Ulam.bernoulliDemo())
    #expect(emitted == golden,
            "dsl2stan emission diverged from in-process stancode golden")
  }

  @Test func missingSmokeDriverThrows() throws {
    #expect(throws: Dsl2StanError.self) {
      _ = try dsl2stan(model: "nonexistent_model_for_test")
    }
  }
}
