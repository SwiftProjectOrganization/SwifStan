//
//  Alist2DslTests.swift
//  StanTests
//
//  Slice F + G coverage for the alist2dsl orchestrator. Drives a
//  synthetic minimal alist through the lex → parse → lower → classify
//  → emit chain and asserts the output is a runnable @main Swift smoke
//  driver. Then runs dsl2stan on the produced smoke driver to confirm
//  the round-trip: R alist → Swift DSL → Stan source.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("alist2dsl command tests")
struct Alist2DslTests {

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

  @Test func bernoulliAlistRoundTripsThroughDsl2Stan() throws {
    let model = "alist2dsl_bernoulli_fixture"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

    let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
    try Self.bernoulliAlist.write(to: alistURL, atomically: true, encoding: .utf8)

    // Slice F: alist → Swift smoke driver
    let swiftURL = try alist2dsl(model: model)
    let swiftSource = try String(contentsOf: swiftURL, encoding: .utf8)

    #expect(swiftSource.contains("@main"))
    #expect(swiftSource.contains("Likelihood(\"y\", .bernoulli(p: \"p\"))"))
    #expect(swiftSource.contains("Link(.logit, lhs: \"p\", rhs: \"a + b*x\")"))
    #expect(swiftSource.contains("Prior(\"a\", .normal(0, 1.5))"))
    #expect(swiftSource.contains("Prior(\"b\", .normal(0, 0.5))"))
    // Outcome is binary → integer; x is data → real; no index columns.
    #expect(swiftSource.contains("\"y\": .integer("))
    #expect(swiftSource.contains("\"x\": .real("))

    // Slice G round-trip: dsl2stan should successfully compile + run
    // the produced smoke driver and write a .stan file that matches
    // the in-process generator's output for the same model.
    let stanURL = try dsl2stan(model: model)
    let emitted = try String(contentsOf: stanURL, encoding: .utf8)
    let golden = try stancode(SwiftStan.Ulam.bernoulliDemo())
    #expect(emitted == golden,
            "alist2dsl → dsl2stan output diverged from in-process bernoulli golden")
  }

  @Test func chimpanzeesM125Probe() throws {
    let model = "alist2dsl_chimpanzees_fixture"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

    let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
    try Self.chimpanzeesAlist.write(to: alistURL, atomically: true, encoding: .utf8)

    let swiftURL = try alist2dsl(model: model)
    let swiftSource = try String(contentsOf: swiftURL, encoding: .utf8)

    // Key shape checks. Half-Cauchy gets inferred lower:0 via the σ-slot
    // heuristic (Slice D).
    #expect(swiftSource.contains("Likelihood(\"pulled_left\", .bernoulli(p: \"p\"))"))
    #expect(swiftSource.contains("VaryingPrior(\"a_actor\", indexedBy: \"actor\","))
    #expect(swiftSource.contains("VaryingPrior(\"a_block\", indexedBy: \"block_id\","))
    #expect(swiftSource.contains("Prior(\"a\", .normal(0, 10))"))
    #expect(swiftSource.contains("Prior(\"bp\", .normal(0, 10))"))
    #expect(swiftSource.contains("Prior(\"bpc\", .normal(0, 10))"))
    #expect(swiftSource.contains("Prior(\"sigma_actor\", .cauchy(0, 1), truncation: Truncation(lower: 0))"))
    #expect(swiftSource.contains("Prior(\"sigma_block\", .cauchy(0, 1), truncation: Truncation(lower: 0))"))
  }

  static let chimpanzeesAlist = """
    m12.5 <- map2stan(
        alist(
            pulled_left ~ dbinom( 1 , p ),
            logit(p) <- a + a_actor[actor] + a_block[block_id] +
                        (bp + bpc*condition)*prosoc_left,
            a_actor[actor] ~ dnorm( 0 , sigma_actor ),
            a_block[block_id] ~ dnorm( 0 , sigma_block ),
            c(a,bp,bpc) ~ dnorm(0,10),
            sigma_actor ~ dcauchy(0,1),
            sigma_block ~ dcauchy(0,1)
        ),
        data=d, warmup=1000 , iter=6000 , chains=4 , cores=3 )
    """

  @Test func missingAlistFileThrows() throws {
    let model = "alist2dsl_missing_fixture"
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }
    #expect(throws: Alist2DslError.self) {
      _ = try alist2dsl(model: model)
    }
  }
}
