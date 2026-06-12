//
//  Stan2AlistTests.swift
//  StanTests
//
//  Slice A of Docs/Stan2AlistCommandPlan.md — the reverse distribution
//  catalog. Locks in that `distribution(fromStanName:args:)` is the
//  exact inverse of `name(_:)` + `args(_:)` for every univariate
//  distribution in v1 scope, and that unsupported / mis-arity inputs
//  fail loud.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("stan2alist tests")
struct Stan2AlistTests {

  /// Representative univariate distributions with a mix of literal,
  /// symbol, and compound-expression arguments. Every one must survive
  /// the `Distribution → render → reverse` round trip unchanged.
  static let roundTripCases: [Distribution] = [
    .normal(0, 10),
    .normal("mu_alpha", "sigma_alpha"),
    .normal(.expression("a + b*x"), "sigma"),
    .bernoulli(p: "p"),
    .binomial(n: 1, p: "p"),
    .beta(2, 2),
    .exponential(1),
    .poisson("lambda"),
    .gamma(2, "rate"),
    .cauchy(0, 1),
    .lognormal(0, "sigma"),
    .uniform(lower: 0, upper: 50),
    .studentT(nu: 3, mu: 0, sigma: "sigma"),
  ]

  @Test("reverse catalog is the inverse of the forward catalog")
  func reverseCatalogIsSymmetric() throws {
    for distribution in Self.roundTripCases {
      let stanName = DistributionCatalog.name(distribution)
      let argStrings = DistributionCatalog.args(distribution)
        .components(separatedBy: ", ")
      let rebuilt = try DistributionCatalog.distribution(fromStanName: stanName,
                                                         args: argStrings)
      #expect(rebuilt == distribution,
              "round trip drifted for \(distribution): got \(rebuilt)")
    }
  }

  @Test("unsupported (multivariate) distribution fails loud")
  func unsupportedDistributionThrows() {
    #expect(throws: DistributionCatalog.ReverseError.self) {
      _ = try DistributionCatalog.distribution(fromStanName: "multi_normal",
                                               args: ["mu", "Sigma"])
    }
  }

  @Test("argument-count mismatch fails loud")
  func arityMismatchThrows() {
    #expect(throws: DistributionCatalog.ReverseError.self) {
      _ = try DistributionCatalog.distribution(fromStanName: "normal",
                                               args: ["0"])
    }
  }

  @Test("argument classification splits literal / symbol / expression")
  func argClassification() {
    #expect(DistributionCatalog.distributionArg(from: "10") == .literal(10))
    #expect(DistributionCatalog.distributionArg(from: " 0.5 ") == .literal(0.5))
    #expect(DistributionCatalog.distributionArg(from: "sigma") == .symbol("sigma"))
    #expect(DistributionCatalog.distributionArg(from: "mu_alpha") == .symbol("mu_alpha"))
    #expect(DistributionCatalog.distributionArg(from: "alpha[county] + beta*floor")
            == .expression("alpha[county] + beta*floor"))
  }

  // MARK: - Slice B: StanBlockParser

  /// The hand-written radon_pp.stan from ~/Documents/StanCases/radon_pp —
  /// exercises comments, an inline linear model, an `offset/multiplier`
  /// affine parameter, and a `generated quantities` block.
  static let radonPpStan = """
  data {
    int<lower=1> N;  // observations
    int<lower=1> N_county;
    array[N] int<lower=1, upper=N_county> county;
    vector[N] floor;
    vector[N] log_radon;
  }
  parameters {
    real mu_alpha;
    real<lower=0> sigma_alpha;
    vector<offset=mu_alpha, multiplier=sigma_alpha>[N_county] alpha;
    real beta;
    real<lower=0> sigma;
  }
  model {
    log_radon ~ normal(alpha[county] + beta * floor, sigma);
    alpha ~ normal(mu_alpha, sigma_alpha); // partial-pooling
    beta ~ normal(0, 10);
    sigma ~ normal(0, 10);
    mu_alpha ~ normal(0, 10);
    sigma_alpha ~ normal(0, 10);
  }
  generated quantities {
    array[N] real y_rep = normal_rng(alpha[county] + beta * floor, sigma);
  }
  """

  @Test("parses radon_pp.stan into a structured StanProgram")
  func parsesRadonPpStan() throws {
    let program = try StanBlockParser.parse(Self.radonPpStan)

    // Data block: N, N_county, county, floor, log_radon.
    #expect(program.dataDecls.map(\.name) == ["N", "N_county", "county", "floor", "log_radon"])
    let county = try #require(program.dataDecls.first { $0.name == "county" })
    #expect(county.type == .arrayInt(size: "N"))
    #expect(county.constraints.lower == "1")
    #expect(county.constraints.upper == "N_county")
    let logRadon = try #require(program.dataDecls.first { $0.name == "log_radon" })
    #expect(logRadon.type == .vector(size: "N"))

    // Parameters: the affine `alpha` is the interesting one.
    #expect(program.parameterDecls.map(\.name)
            == ["mu_alpha", "sigma_alpha", "alpha", "beta", "sigma"])
    let alpha = try #require(program.parameterDecls.first { $0.name == "alpha" })
    #expect(alpha.type == .vector(size: "N_county"))
    #expect(alpha.constraints.offset == "mu_alpha")
    #expect(alpha.constraints.multiplier == "sigma_alpha")
    let sigma = try #require(program.parameterDecls.first { $0.name == "sigma" })
    #expect(sigma.type == .real)
    #expect(sigma.constraints.lower == "0")

    // Model block: 6 sampling statements, the first with an inline
    // linear-model expression that must survive bracket-aware splitting.
    #expect(program.modelStatements.count == 6)
    guard case let .sampling(lhs, distName, args, trunc) = program.modelStatements[0] else {
      Issue.record("expected first model statement to be a sampling line")
      return
    }
    #expect(lhs == "log_radon")
    #expect(distName == "normal")
    #expect(args == ["alpha[county] + beta * floor", "sigma"])
    #expect(trunc == nil)

    // generated quantities is recognised and dropped, not translated.
    #expect(program.droppedBlocks == ["generated quantities"])
  }

  @Test("a model line that is neither sampling nor assignment fails loud")
  func rejectsUnknownModelStatement() {
    let src = """
    model {
      this is not valid stan;
    }
    """
    #expect(throws: StanBlockParseError.self) {
      _ = try StanBlockParser.parse(src)
    }
  }

  @Test("an unrecognized top-level block fails loud")
  func rejectsUnknownTopLevel() {
    let src = "banana { real x; }"
    #expect(throws: StanBlockParseError.self) {
      _ = try StanBlockParser.parse(src)
    }
  }

  @Test("parses a truncated sampling statement")
  func parsesTruncation() throws {
    let program = try StanBlockParser.parse("model { sigma ~ normal(0, 10) T[0, ]; }")
    guard case let .sampling(_, _, _, trunc) = program.modelStatements[0] else {
      Issue.record("expected a sampling statement")
      return
    }
    #expect(trunc == StanTruncation(lower: "0", upper: nil))
  }

  // MARK: - Slice C: StanToUlamModel

  @Test("reconstructs radon_pp statements from the parsed program")
  func reconstructsRadonPpStatements() throws {
    let program = try StanBlockParser.parse(Self.radonPpStan)
    let result = try StanToUlamModel.build(program)

    let expected: [Statement] = [
      .likelihood(lhs: "log_radon",
                  distribution: .normal(.expression("alpha[county] + beta * floor"), "sigma"),
                  truncation: .none,
                  useLpdf: false),
      .varyingPrior(name: "alpha",
                    indexedBy: "county",
                    countSymbol: nil,
                    distribution: .normal("mu_alpha", "sigma_alpha"),
                    truncation: .none,
                    constraints: .none,
                    start: nil,
                    useLpdf: false,
                    nonCentered: false),
      .prior(name: "beta", distribution: .normal(0, 10),
             truncation: .none, constraints: .none, start: nil, useLpdf: false),
      .prior(name: "sigma", distribution: .normal(0, 10),
             truncation: .none, constraints: .none, start: nil, useLpdf: false),
      .prior(name: "mu_alpha", distribution: .normal(0, 10),
             truncation: .none, constraints: .none, start: nil, useLpdf: false),
      .prior(name: "sigma_alpha", distribution: .normal(0, 10),
             truncation: .none, constraints: .none, start: nil, useLpdf: false),
    ]

    #expect(result.statements == expected)
    // The dropped `generated quantities` block is surfaced as a warning.
    #expect(result.warnings.contains { $0.contains("generated quantities") })
  }

  @Test("inv_logit assignment becomes a logit link")
  func reconstructsLogitLink() throws {
    let src = """
    data { int<lower=1> N; array[N] int<lower=0, upper=1> y; vector[N] x; }
    parameters { real a; real b; }
    model {
      p = inv_logit(a + b*x);
      y ~ bernoulli(p);
      a ~ normal(0, 1);
      b ~ normal(0, 1);
    }
    """
    let program = try StanBlockParser.parse(src)
    let result = try StanToUlamModel.build(program)

    // Likelihood first, then the link, then the priors.
    #expect(result.statements.first == .likelihood(
      lhs: "y", distribution: .bernoulli(p: "p"), truncation: .none, useLpdf: false))
    #expect(result.statements.contains(
      .link(function: .logit, lhs: "p", rhs: Expression("a + b*x"))))
  }

  @Test("a model with no data-outcome sampling line fails loud")
  func reconstructNoLikelihoodThrows() throws {
    let src = """
    parameters { real a; }
    model { a ~ normal(0, 1); }
    """
    let program = try StanBlockParser.parse(src)
    #expect(throws: StanToUlamError.self) {
      _ = try StanToUlamModel.build(program)
    }
  }

  // MARK: - Slice D: AlistTextEmitter

  @Test("emits radon_pp statements as McElreath alist text")
  func emitsRadonPpAlist() throws {
    let program = try StanBlockParser.parse(Self.radonPpStan)
    let statements = try StanToUlamModel.build(program).statements
    let text = try AlistTextEmitter.emit(statements)

    let expected = """
    alist(
      log_radon ~ dnorm(alpha[county] + beta * floor, sigma),
      alpha[county] ~ dnorm(mu_alpha, sigma_alpha),
      beta ~ dnorm(0, 10),
      sigma ~ dnorm(0, 10),
      mu_alpha ~ dnorm(0, 10),
      sigma_alpha ~ dnorm(0, 10)
    )

    """
    #expect(text == expected)
  }

  @Test("emitted alist re-parses through AlistParser")
  func emittedAlistReparses() throws {
    let program = try StanBlockParser.parse(Self.radonPpStan)
    let statements = try StanToUlamModel.build(program).statements
    let text = try AlistTextEmitter.emit(statements)

    let parsed = try AlistParser.parse(text)
    #expect(parsed.count == 6)
    // First statement is the likelihood over the scalar outcome.
    guard case let .sample(lhs, dist, _) = parsed.first else {
      Issue.record("expected first parsed statement to be a sample")
      return
    }
    #expect(lhs == .scalar("log_radon"))
    #expect(dist.name == "dnorm")
    // The varying prior keeps its `[county]` index.
    #expect(parsed.contains { stmt in
      if case let .sample(lhs, _, _) = stmt {
        return lhs == .indexed(name: "alpha", indexColumn: "county")
      }
      return false
    })
  }

  @Test("bernoulli renders as dbinom(1, p) and inv_logit as a logit link")
  func emitsBernoulliAndLink() throws {
    let statements: [Statement] = [
      .likelihood(lhs: "y", distribution: .bernoulli(p: "p"),
                  truncation: .none, useLpdf: false),
      .link(function: .logit, lhs: "p", rhs: Expression("a + b*x")),
      .prior(name: "a", distribution: .normal(0, 1.5),
             truncation: .none, constraints: .none, start: nil, useLpdf: false),
    ]
    let text = try AlistTextEmitter.emit(statements)
    #expect(text.contains("y ~ dbinom(1, p)"))
    #expect(text.contains("logit(p) <- a + b*x"))
    #expect(text.contains("a ~ dnorm(0, 1.5)"))
  }

  // MARK: - Slice E: stan2alist command

  @Suite("stan2alist command tests")
  struct CommandTests {
    init() { _ = TestCaseRootBootstrap.install }

    @Test("writes Preliminaries/<name>.alist.R from Results/<name>.stan")
    func writesAlistFromStan() throws {
      let model = "stan2alist_radon_fixture"
      let paths = casePaths(for: model)
      try ensureCaseDirectories(paths)
      defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

      try Stan2AlistTests.radonPpStan.write(
        to: paths.results.appendingPathComponent("\(model).stan"),
        atomically: true, encoding: .utf8)

      let outURL = try stan2alist(model: model)
      #expect(outURL == paths.preliminaries.appendingPathComponent("\(model).alist.R"))

      let written = try String(contentsOf: outURL, encoding: .utf8)
      #expect(written.contains("log_radon ~ dnorm(alpha[county] + beta * floor, sigma)"))
      #expect(written.contains("alpha[county] ~ dnorm(mu_alpha, sigma_alpha)"))
    }

    @Test("refuses to overwrite an existing alist without --force")
    func overwriteGuard() throws {
      let model = "stan2alist_force_fixture"
      let paths = casePaths(for: model)
      try ensureCaseDirectories(paths)
      defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

      try Stan2AlistTests.radonPpStan.write(
        to: paths.results.appendingPathComponent("\(model).stan"),
        atomically: true, encoding: .utf8)
      // Pre-existing hand-authored alist that must not be clobbered.
      let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
      try "# hand-authored — keep me\n".write(to: alistURL, atomically: true, encoding: .utf8)

      #expect(throws: Stan2AlistError.self) {
        _ = try stan2alist(model: model)
      }
      // The original file is untouched.
      let preserved = try String(contentsOf: alistURL, encoding: .utf8)
      #expect(preserved.contains("hand-authored"))

      // With --force it overwrites.
      _ = try stan2alist(model: model, force: true)
      let overwritten = try String(contentsOf: alistURL, encoding: .utf8)
      #expect(overwritten.contains("log_radon ~ dnorm"))
    }

    @Test("missing Results/<name>.stan fails loud")
    func missingStanFile() throws {
      let model = "stan2alist_missing_fixture"
      let paths = casePaths(for: model)
      try ensureCaseDirectories(paths)
      defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

      #expect(throws: Stan2AlistError.self) {
        _ = try stan2alist(model: model)
      }
    }

    // MARK: - Slice F: round-trip oracle

    /// `howell` (scalar baseline) and a multilevel radon-style alist that
    /// exercises a varying prior (`alpha[county]`), a vectorising
    /// deterministic link (`mu <- alpha[county] + beta*floor`), and
    /// half-Cauchy scales (the `T[0, ]` / `<lower=0>` round-trip). Both
    /// vectorise — chimpanzees is deliberately excluded because its
    /// `vector * vector` term forces the generator into loop emission,
    /// which is out of v1 scope (see `roundTripLoopModelFailsLoud`).
    static let multilevelAlist = """
    alist(
      log_radon ~ dnorm( mu , sigma ),
      mu <- alpha[county] + beta*floor,
      alpha[county] ~ dnorm( a_bar , sigma_alpha ),
      a_bar ~ dnorm( 0 , 10 ),
      beta ~ dnorm( 0 , 10 ),
      sigma ~ dcauchy( 0 , 1 ),
      sigma_alpha ~ dcauchy( 0 , 1 )
    )
    """

    /// For a generator-produced `.stan`, `stan2alist` followed by
    /// `stancode` must reproduce the original Stan byte-for-byte. The
    /// flow: stage the alist → stancode (original) → stan2alist
    /// (force-overwrites the alist) → stancode (round-trip) → compare.
    @Test("alist → stancode → stan2alist → stancode round-trips byte-identically",
          arguments: ["howell", "multilevel"])
    func roundTripsThroughStancode(_ fixture: String) throws {
      let model = "stan2alist_roundtrip_\(fixture)"
      let paths = casePaths(for: model)
      try ensureCaseDirectories(paths)
      defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

      let alistURL = paths.preliminaries.appendingPathComponent("\(model).alist.R")
      if fixture == "multilevel" {
        try Self.multilevelAlist.write(to: alistURL, atomically: true, encoding: .utf8)
      } else {
        try stageBundledFixture(named: "\(fixture).alist.R", to: alistURL)
      }

      // Forward: alist → original Stan.
      let original = try String(contentsOf: stancode(model: model), encoding: .utf8)

      // Reverse: Stan → alist (force-overwrites the staged alist).
      _ = try stan2alist(model: model, force: true)

      // Forward again: reconstructed alist → Stan.
      let roundtrip = try String(contentsOf: stancode(model: model), encoding: .utf8)

      #expect(roundtrip == original,
              "round-trip diverged for \(fixture):\n--- original ---\n\(original)\n--- roundtrip ---\n\(roundtrip)")
    }

    /// A model whose generated Stan contains a `for` loop (chimpanzees'
    /// `vector * vector` term) is out of v1 scope and must fail loud
    /// rather than mis-parse the loop body.
    @Test("a looped (non-vectorising) model fails loud")
    func roundTripLoopModelFailsLoud() throws {
      let model = "stan2alist_loop_fixture"
      let paths = casePaths(for: model)
      try ensureCaseDirectories(paths)
      defer { try? FileManager.default.removeItem(at: caseRoot().appendingPathComponent(model)) }

      try stageBundledFixture(
        named: "chimpanzees.alist.R",
        to: paths.preliminaries.appendingPathComponent("\(model).alist.R"))
      _ = try stancode(model: model)   // emits a `for` loop

      #expect(throws: Stan2AlistError.self) {
        _ = try stan2alist(model: model, force: true)
      }
    }
  }
}
