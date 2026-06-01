// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import Foundation
import ArgumentParser

@main
struct SwiftStan: ParsableCommand {
  // Customize your command's help and subcommands by implementing the
  // `configuration` property.
  static let configuration = CommandConfiguration(
    // Optional abstracts and discussions are used for help output.
    abstract: "A wrapper for running cmdstan.",
    
    // Commands can define a version for automatic '--version' support.
    version: "1.0.0",
    
    // Pass an array to `subcommands` to set up a nested tree of subcommands.
    // With language support for type-level introspection, this could be
    // provided by automatically finding nested `ParsableCommand` types.
    subcommands: [Compile.self, Sample.self, Optimize.self, Pathfinder.self, Laplace.self, Stansummary.self, Csv2Json.self, Dsl2Stan.self, Alist2Dsl.self, Stancode.self, Ulam.self, Test.self],
    
    // A default subcommand, when provided, is automatically selected if a
    // subcommand is not given on the command line.
    defaultSubcommand: Test.self)
}

struct OptionsCompile: ParsableArguments {
  
  @Flag(
    name: [.customLong("verbose"), .customShort("V")],
    help: "Show more information."
  )
  var verbose: Bool = false
  
  @Flag(
    name: [.customLong("install"), .customShort("I")],
    help: "Install a `<model>.stan` file before compiling."
  )
  var install: Bool = false
  
  @Option(
    help: "Location of cmdstan.")
  var cmdstan: String?

  @Option(
    help: "Model name.")
  var model: String?
  
  @Argument(
    help: "Arguments for method."
  )
  var values: [String] = []
}

struct OptionsSample: ParsableArguments {
  
  @Flag(
    name: [.customLong("verbose"), .customShort("V")],
    help: "Show more information."
  )
  var verbose: Bool = false
  
  @Flag(
    name: [.customLong("install"), .customShort("I")],
    help: "Install a `<model>.data.json` before sampling."
  )
  var install: Bool = false
  
  @Flag(
    name: [.customLong("nosummary"), .customShort("S")],
    help: "Don't run stansummary."
  )
  var nosummary: Bool = false
  
  @Option(
    help: "Location of cmdstan.")
  var cmdstan: String?

  @Option(
    help: "Model name.")
  var model: String?
  
  @Argument(
    help: "Arguments for method."
  )
  var values: [String] = []
}

struct OptionsLimited: ParsableArguments {
  
  @Flag(
    name: [.customLong("verbose"), .customShort("V")],
    help: "Show more information."
  )
  var verbose: Bool = false
  
  @Option(
    help: "Location of cmdstan.")
  var cmdstan: String?

  @Option(
    help: "Model name.")
  var model: String?
  
  @Argument(
    help: "Arguments for method."
  )
  var values: [String] = []
}

extension SwiftStan {
  struct Compile: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "compile",
      abstract: "Compile the Stan model.",
    )
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsCompile
    
    mutating func run() {
      
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String
      
      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          //print(path)
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }
      
      let result = compile(model: options.model ?? "bernoulli",
                           arguments: options.values,
                           cmdstan: cmdstan,
                           verbose: options.verbose,
                           install: options.install)
      printFinalResult(result)
    }
  }
}

extension SwiftStan {
  struct Sample: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "sample",
      abstract: "Sample the Stan model."
    )
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsSample
    
    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String
      
      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }
      
      let result = sample(model: options.model ?? "bernoulli",
                          arguments: options.values,
                          cmdstan: cmdstan,
                          verbose: options.verbose,
                          nosummary: options.nosummary,
                          install: options.install)
      printFinalResult(result)

    }
  }
}

extension SwiftStan {
  struct Optimize: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "optimize",
      abstract: "Optimize the Stan model."
    )
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsLimited
    
    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String
      
      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }
      
      let result = optimize(model: options.model ?? "bernoulli",
                            arguments: options.values,
                            cmdstan: cmdstan,
                            verbose: options.verbose
      )
      printFinalResult(result)
    }
  }
}

extension SwiftStan {
  struct Pathfinder: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "pathfinder",
      abstract: "Use Pathfinder approximation.")
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsLimited
    
    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String
      
      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }
      
      let result = pathfinder(model: options.model ?? "bernoulli",
                              arguments: options.values,
                              cmdstan: cmdstan,
                              verbose: options.verbose
      )
      printFinalResult(result)
    }
  }
}

extension SwiftStan {
  struct Laplace: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "laplace",
      abstract: "Run cmdstan's Laplace approximation on a compiled model.")

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String

      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }

      let result = laplace(model: options.model ?? "bernoulli",
                           arguments: options.values,
                           cmdstan: cmdstan,
                           verbose: options.verbose
      )
      printFinalResult(result)
    }
  }
}

extension SwiftStan {
  struct Stansummary: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "stansummary",
      abstract: "Run the Stan summary program.")
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsLimited
    
    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String
      
      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          //print(path)
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }
      
      let result = stansummary(model: options.model ?? "bernoulli",
                               cmdstan: cmdstan,
                               verbose: options.verbose
      )
      printFinalResult(result)
    }
  }
}

extension SwiftStan {
  struct Csv2Json: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "csv2json",
      abstract: "Read Preliminaries/<model>.csv, validate against Results/<model>.stan, write Results/<model>.data.json.")

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let model = options.model ?? "bernoulli"
      do {
        let url = try csv2json(model: model, verbose: options.verbose)
        printFinalResult(("Wrote \(url.path)", ""))
      } catch {
        printFinalResult(("", "\(error)"))
      }
    }
  }
}

extension SwiftStan {
  struct Stancode: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "stancode",
      abstract: "Translate Preliminaries/<model>.alist.R straight to Results/<model>.stan (in-process, no swiftc).")

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let model = options.model ?? "bernoulli"
      do {
        let url = try stancode(model: model, verbose: options.verbose)
        printFinalResult(("Wrote \(url.path)", ""))
      } catch {
        printFinalResult(("", "\(error)"))
      }
    }
  }
}

extension SwiftStan {
  struct Alist2Dsl: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "alist2dsl",
      abstract: "Translate Preliminaries/<model>.alist.R into Preliminaries/<Model>.ulam.swift.")

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let model = options.model ?? "bernoulli"
      do {
        let url = try alist2dsl(model: model, verbose: options.verbose)
        printFinalResult(("Wrote \(url.path)", ""))
      } catch {
        printFinalResult(("", "\(error)"))
      }
    }
  }
}

extension SwiftStan {
  struct Dsl2Stan: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "dsl2stan",
      abstract: "Compile a Preliminaries/*.ulam.swift smoke driver and write its Stan source to Results/<model>.stan.")

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let model = options.model ?? "bernoulli"
      do {
        let url = try dsl2stan(model: model, verbose: options.verbose)
        printFinalResult(("Wrote \(url.path)", ""))
      } catch {
        printFinalResult(("", "\(error)"))
      }
    }
  }
}

extension SwiftStan {
  struct Ulam: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "ulam",
      abstract: "Run one of the built-in ulam DSL demos (--model Bernoulli|Poisson|Binomial|UCB|Dmvnorm)."
    )

    @OptionGroup var options: OptionsLimited

    mutating func run() {
      let environment = ProcessInfo.processInfo.environment
      let cmdstan: String

      if options.cmdstan != nil {
        cmdstan = options.cmdstan!
      } else {
        if let path = environment["CMDSTAN"] {
          cmdstan = path
        } else {
          cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
        }
      }

      // V2.1: the CLI dispatches to the file-based pipeline. The
      // built-in demo dirs (bernoulli, poisson, …) already carry their
      // own Preliminaries/<Name>.ulam.swift, so any of the historical
      // demo names still works — passed in any case, lowercased for the
      // directory lookup.
      let modelName = (options.model ?? "bernoulli").lowercased()
      let result = ulamPipeline(model: modelName,
                                cmdstan: cmdstan,
                                verbose: options.verbose,
                                arguments: options.values)
      printFinalResult(result)
    }

    // MARK: - Built-in demos

    /// Canonical Statistical Rethinking opener: Bernoulli + logit link.
    static func bernoulliDemo() -> UlamModel {
      let data: UlamData = [
        "y": .integer([0, 1, 0, 1, 1, 0, 1, 1, 1, 0]),
        "x": .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]),
      ]
      return UlamModel(data: data) {
        Likelihood("y", .bernoulli(p: "p"))
        Link(.logit, lhs: "p", rhs: "a + b*x")
        Prior("a", .normal(0, 1.5))
        Prior("b", .normal(0, 0.5))
      }
    }

    /// Phase 3 demo: Poisson regression with log link, target += lpmf form,
    /// and a Cauchy prior on the slope.
    static func poissonDemo() -> UlamModel {
      let data: UlamData = [
        "y": .integer([2, 1, 3, 5, 4, 6, 8, 7]),
        "x": .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]),
      ]
      return UlamModel(data: data) {
        Likelihood("y", .poisson("lambda"), useLpdf: true)
        Link(.log, lhs: "lambda", rhs: "a + b*x")
        Prior("a", .normal(0, 1.5))
        Prior("b", .cauchy(0, 1))
      }
    }

    /// Phase 5 demo: McElreath's UCB Berkeley admissions varying-intercept
    /// binomial logistic regression (`~/Documents/StanCases/UCB/`).
    /// Demonstrates `VaryingPrior` over a `dept` index column, plus a
    /// half-normal prior on the group-level scale.
    static func ucbDemo() -> UlamModel {
      let data: UlamData = [
        "admit":        .integer([512, 89, 353, 17, 120, 202, 138, 131, 53, 94, 22, 24]),
        "applications": .integer([825, 108, 560, 25, 325, 593, 417, 375, 191, 393, 373, 341]),
        // `male` is a 0/1 predictor. Phase 5.5 Slice C auto-promotes
        // integer columns referenced in real-typed arithmetic (here:
        // `b*male`), so we declare the raw integer values and let the
        // generator emit `vector[N] male;` with float-shaped data.
        "male":         .integer([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]),
        "dept":         .integer([1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]),
      ]
      return UlamModel(data: data) {
        Likelihood("admit", .binomial(n: "applications", p: "p"))
        Link(.logit, lhs: "p", rhs: "a[dept] + b*male")
        VaryingPrior("a", indexedBy: "dept",
                     .normal("abar", "sigma"))
        Prior("abar", .normal(0, 4))
        Prior("sigma", .normal(0, 1), truncation: Truncation(lower: 0))
        Prior("b", .normal(0, 1))
      }
    }

    /// Phase 6 demo: minimum-viable multivariate-normal — bivariate-mean
    /// estimation with fixed prior and observation covariance matrices.
    /// `mu ~ multi_normal(zero, Sigma_prior)` and
    /// `y ~ multi_normal(mu, Sigma_obs)`. The cardinality symbol `K` is
    /// bound to 2 via the inner length of the matrix-shaped data
    /// columns.
    static func dmvnormDemo() -> UlamModel {
      // 20 synthetic bivariate observations centred near (1.0, 0.5)
      // with a positively-correlated noise structure.
      let observations: [[Double]] = [
        [1.10, 0.42], [0.92, 0.61], [1.05, 0.48], [1.21, 0.34],
        [0.88, 0.55], [1.14, 0.39], [1.02, 0.52], [0.95, 0.58],
        [1.18, 0.36], [1.08, 0.47], [0.97, 0.56], [1.03, 0.50],
        [1.12, 0.41], [0.99, 0.54], [1.16, 0.37], [0.91, 0.60],
        [1.07, 0.46], [1.04, 0.49], [0.96, 0.57], [1.10, 0.43],
      ]
      let data: UlamData = [
        "y":           .realArrayVector(rowCount: observations.count,
                                        colCount: 2,
                                        values: observations),
        "zero":        .realVector(length: 2, values: [0, 0]),
        "Sigma_prior": .realCovMatrix(dim: 2, values: [[1, 0.5], [0.5, 1]]),
        "Sigma_obs":   .realCovMatrix(dim: 2,
                                      values: [[0.02, 0.005], [0.005, 0.02]]),
      ]
      return UlamModel(data: data) {
        Likelihood("y", .multivariateNormal("mu", "Sigma_obs"))
        VectorPrior("mu", length: "K",
                    .multivariateNormal("zero", "Sigma_prior"))
      }
    }

    /// Phase 3 demo: binomial logistic regression with a truncated half-normal
    /// prior on the slope.
    static func binomialDemo() -> UlamModel {
      let data: UlamData = [
        "successes": .integer([2, 3, 1, 4, 5, 6, 7, 8]),
        "trials":    .integer([5, 5, 5, 5, 10, 10, 10, 10]),
        "x":         .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]),
      ]
      return UlamModel(data: data) {
        Likelihood("successes", .binomial(n: "trials", p: "theta"))
        Link(.logit, lhs: "theta", rhs: "a + b*x")
        Prior("a", .normal(0, 1.5))
        Prior("b", .normal(0, 1), truncation: Truncation(lower: 0))
      }
    }

    /// Phase 5.5 Slice F demo: varying *slopes* — the same vector-
    /// parameter machinery Phase 5 introduced for varying intercepts,
    /// but acting as the coefficient of a real-typed predictor
    /// (`b[group]*x`). Slice D's loop-emission body translates the
    /// `vector * vector` shape into a per-row `for (i in 1:N)` body
    /// (`b[group[i]]*x[i]`), so the generated `.stan` is valid even
    /// though Stan rejects the canonical vectorised form.
    ///
    /// `stan ulam --model VaryingSlopes` compiles + samples through
    /// cmdstan. No end-to-end artifact test in the suite — the
    /// synthetic dataset is sparse enough that the default
    /// `num_chains=4 num_samples=1000` would dominate the unit-test
    /// runtime; the source generation is covered by
    /// `varyingSlopesBernoulliMatchesGolden`.
    static func varyingSlopesDemo() -> UlamModel {
      let data: UlamData = [
        "y":     .integer([0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0]),
        "x":     .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.2, 0.5, 0.7, 0.3]),
        "group": .integer([1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2]),
      ]
      return UlamModel(data: data) {
        Likelihood("y", .bernoulli(p: "p"))
        Link(.logit, lhs: "p", rhs: "a + b[group]*x")
        Prior("a", .normal(0, 1.5))
        VaryingPrior("b", indexedBy: "group", .normal("b_bar", "sigma_b"))
        Prior("b_bar", .normal(0, 1))
        Prior("sigma_b", .exponential(1))
      }
    }

    /// Phase 5.5 Slice G demo: a *two-grouping* multilevel model
    /// (Statistical Rethinking chapter 13 reedfrog-style) — survival
    /// modelled with both a per-tank random intercept and a per-size
    /// random offset. Exercises that Phase 5's `vectorParameters` and
    /// `indexColumns` accumulators handle two independent index
    /// columns cleanly. The RHS `a[tank] + s[size]` is
    /// `vector + vector` — Stan element-wise — so it vectorises
    /// without needing Slice D's loop emitter.
    /// Multivariate hierarchical priors demo (2026-05-31): McElreath
    /// chapter-14 cafes model. Per-cafe random intercept α and slope β
    /// drawn from a bivariate normal with LKJ-Cholesky prior on the
    /// correlation factor. Tests Slices A–D end-to-end through `ulam()`.
    ///
    /// Synthetic data: 6 cafes × 10 observations each = 60 rows. Each
    /// cafe has 5 morning visits (afternoon=0) and 5 afternoon visits
    /// (afternoon=1). True α near 3.5, β near -1 with correlation -0.7;
    /// the values below were generated from a fixed-seed Box–Muller
    /// draw against those targets and embedded verbatim so the test is
    /// deterministic without a Swift-side RNG.
    static func cafeDemo() -> UlamModel {
      let cafe: [Int] = (1...6).flatMap { Array(repeating: $0, count: 10) }
      let afternoon: [Int] = Array(repeating: [0,0,0,0,0,1,1,1,1,1],
                                   count: 6).flatMap { $0 }
      let wait: [Double] = [
        // cafe 1 (α≈4.0, β≈-1.5)
        3.81, 4.22, 3.95, 4.14, 4.08, 2.46, 2.74, 2.61, 2.39, 2.55,
        // cafe 2 (α≈3.2, β≈-0.8)
        3.04, 3.34, 3.18, 3.27, 3.11, 2.31, 2.52, 2.40, 2.48, 2.36,
        // cafe 3 (α≈3.7, β≈-1.2)
        3.58, 3.81, 3.62, 3.74, 3.69, 2.40, 2.62, 2.54, 2.45, 2.58,
        // cafe 4 (α≈2.9, β≈-0.5)
        2.81, 2.94, 2.86, 3.01, 2.92, 2.32, 2.50, 2.41, 2.38, 2.45,
        // cafe 5 (α≈4.2, β≈-1.7)
        4.04, 4.31, 4.12, 4.24, 4.18, 2.42, 2.65, 2.51, 2.58, 2.46,
        // cafe 6 (α≈3.4, β≈-0.9)
        3.27, 3.50, 3.38, 3.46, 3.41, 2.44, 2.62, 2.55, 2.49, 2.58,
      ]
      let data: UlamData = [
        "J":         .scalarInt(2),
        "cafe":      .integer(cafe),
        "afternoon": .integer(afternoon),
        "wait":      .real(wait),
      ]
      return UlamModel(data: data) {
        Likelihood("wait", .normal("mu", "sigma"))
        Deterministic("mu", "ab[cafe][1] + ab[cafe][2] * afternoon")
        Prior("a_bar", .normal(0, 5))
        Prior("b_bar", .normal(0, 5))
        Prior("sigma", .exponential(1), truncation: Truncation(lower: 0))
        VectorPrior("sigma_ab", length: "J", .exponential(1),
                    truncation: Truncation(lower: 0))
        LKJCorrCholeskyPrior("L_Omega", dim: "J", eta: 2)
        VaryingVectorPrior("ab", indexedBy: "cafe", length: "J",
                           .multivariateNormalCholesky(
                             "[a_bar, b_bar]'",
                             "diag_pre_multiply(sigma_ab, L_Omega)"))
      }
    }

    static func reedfrogDemo() -> UlamModel {
      let data: UlamData = [
        "y":       .integer([3, 5, 4, 2, 7, 8, 6, 7, 4, 5, 3, 6, 8, 9, 7, 8]),
        "density": .integer([10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]),
        "tank":    .integer([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
        "size":    .integer([1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2]),
      ]
      return UlamModel(data: data) {
        Likelihood("y", .binomial(n: "density", p: "p"))
        Link(.logit, lhs: "p", rhs: "a[tank] + s[size]")
        VaryingPrior("a", indexedBy: "tank", .normal("a_bar", "sigma_a"))
        VaryingPrior("s", indexedBy: "size", .normal(0, "sigma_s"))
        Prior("a_bar", .normal(0, 1.5))
        Prior("sigma_a", .normal(0, 1), truncation: Truncation(lower: 0))
        Prior("sigma_s", .normal(0, 1), truncation: Truncation(lower: 0))
      }
    }
  }
}

extension SwiftStan {
  struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "test",
      abstract: "Test the CLI functions.",
    )
    
    // The `@OptionGroup` attribute includes the flags, options, and
    // arguments defined by another `ParsableArguments` type.
    @OptionGroup var options: OptionsCompile
    
      mutating func run() {
          
          let environment = ProcessInfo.processInfo.environment
          let cmdstan: String
          
          if options.cmdstan != nil {
              cmdstan = options.cmdstan!
          } else {
              if let path = environment["CMDSTAN"] {
                  //print(path)
                  cmdstan = path
              } else {
                  cmdstan = "/Users/rob/Projects/StanSupport/cmdstan"
              }
          }
          
          let _ = compile(model: "Bernoulli",
                          arguments: options.values,
                          cmdstan: cmdstan,
                          verbose: true,
                          install: true)
          print("\n")
          let _ = sample(model: "Bernoulli",
                         arguments: options.values,
                         cmdstan: cmdstan,
                         verbose: true,
                         install: true)
          print("\n")
          let _ = optimize(model: "Bernoulli",
                           arguments: options.values,
                           cmdstan: cmdstan,
                           verbose: true
          )
          print("\n")
          let _ = pathfinder(model: "Bernoulli",
                             arguments: options.values,
                             cmdstan: cmdstan,
                             verbose: true
          )
          print("\n")
      }
  }
}
