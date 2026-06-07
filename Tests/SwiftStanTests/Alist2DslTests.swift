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

  // MARK: - dmvnormchol + dlkjcorr: correlated varying effects (paired aliases)

  /// Minimal cafe-style alist exercising the paired `dmvnormchol` +
  /// `dlkjcorr` aliases together. `L_Omega` is a proper
  /// `cholesky_factor_corr[J]` parameter via dlkjcorr; J is derived
  /// from the LHS `c(a, b)` arity.
  static let cafeAlistPaired = """
    cafe_demo <- ulam(
      alist(
        wait ~ dnorm(mu, sigma),
        sigma ~ dexp(1),
        sigma_ab ~ dexp(1),
        L_Omega ~ dlkjcorr(2),
        c(a, b)[cafe] ~ dmvnormchol(c(a_bar, b_bar), L_Omega, sigma_ab)
      ),
      data=d )
    """

  @Test func cafeDmvnormcholAlistEmitsExpectedDsl() throws {
    let model = "alist2dsl_cafe_paired_fixture"
    let paths = casePaths(for: model)
    try ensureCaseDirectories(paths)
    defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

    let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
    try Self.cafeAlistPaired.write(to: alistURL, atomically: true, encoding: .utf8)

    let swiftURL = try alist2dsl(model: model)
    let swiftSource = try String(contentsOf: swiftURL, encoding: .utf8)

    // J cardinality is synthesised from the LHS `c(a, b)` arity (= 2).
    #expect(swiftSource.contains("\"J\": .scalarInt(2)"))
    // σ_ab promoted from scalar to vector prior of length J; exponential
    // gets the conventional lower:0 truncation via the σ-truncation pass.
    #expect(swiftSource.contains("VectorPrior(\"sigma_ab\", length: \"J\", .exponential(1), truncation: Truncation(lower: 0))"))
    // dlkjcorr → dedicated LKJCorrCholeskyPrior with dim derived from J.
    #expect(swiftSource.contains("LKJCorrCholeskyPrior(\"L_Omega\", dim: \"J\", eta: 2)"))
    // Packed param name "ab" from `c(a, b)`, length J, chol arg uses
    // `diag_pre_multiply(σ, L_Omega)` order.
    #expect(swiftSource.contains("VaryingVectorPrior(\"ab\", indexedBy: \"cafe\", length: \"J\", .multivariateNormalCholesky(mean: \"[a_bar, b_bar]'\", chol: \"diag_pre_multiply(sigma_ab, L_Omega)\"))"))
    // L_Omega is a parameter, not data — must not appear in the data literal.
    #expect(!swiftSource.contains("\"L_Omega\": .real("))
  }
}
