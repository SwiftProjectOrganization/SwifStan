//
//  AlistLowering.swift
//  Stan
//
//  Slice B of the alist parser. Walks `[AlistStatement]` and:
//
//  1. Maps each R `d*` distribution name to a V1 `Distribution` case
//     (e.g. `dnorm` → `.normal`, `dbinom` → `.binomial`).
//  2. Expands `c(a, b, c) ~ d<dist>(...)` group priors into N
//     individual `.scalarSample` lowered statements.
//  3. Collapses `dbinom(1, p)` to `.bernoulli(p:)` (the canonical
//     McElreath shorthand for binary outcomes).
//  4. Lowers each `ExpressionNode` argument to a V1 `DistributionArg`,
//     rejecting non-literal / non-symbol arguments as out of scope.
//
//  Output is neutral about likelihood-vs-prior — Slice C decides that
//  based on McElreath's "first ~ is the likelihood" convention.
//

import Foundation

internal enum LoweredAlistStatement: Equatable {
  case scalarSample(name: String, dist: Distribution, truncation: Truncation)
  case varyingSample(name: String,
                     indexedBy: String,
                     dist: Distribution,
                     truncation: Truncation)
  case link(function: LinkFunction, target: String, rhs: ExpressionNode)
}

internal enum AlistLoweringError: Error, CustomStringConvertible {
  case unsupportedDistribution(name: String)
  case unsupportedLink(AlistLink)
  case wrongArity(distribution: String, expected: Int, got: Int)
  case unsupportedDistributionArg(ExpressionNode, in: String)

  internal var description: String {
    switch self {
    case .unsupportedDistribution(let name):
      return "AlistLowering: distribution `\(name)` is not in the V1 catalog"
    case .unsupportedLink(let link):
      return "AlistLowering: link function `\(link.rawValue)` is not supported by V1 (logit, log only)"
    case .wrongArity(let dist, let expected, let got):
      return "AlistLowering: `\(dist)` expects \(expected) arguments, got \(got)"
    case .unsupportedDistributionArg(_, let dist):
      return "AlistLowering: distribution arg in `\(dist)` must be a numeric literal or identifier"
    }
  }
}

internal enum AlistLowering {
  internal static func lower(_ statements: [AlistStatement]) throws -> [LoweredAlistStatement] {
    var out: [LoweredAlistStatement] = []
    for stmt in statements {
      switch stmt {
      case .link(let fn, let target, let rhs):
        out.append(.link(function: try lowerLink(fn),
                         target: target,
                         rhs: rhs))
      case .sample(let lhs, let dist, let trunc):
        let lowered = try lowerDistribution(dist)
        switch lhs {
        case .scalar(let name):
          out.append(.scalarSample(name: name, dist: lowered, truncation: trunc))
        case .indexed(let name, let col):
          out.append(.varyingSample(name: name,
                                    indexedBy: col,
                                    dist: lowered,
                                    truncation: trunc))
        case .group(let names):
          for n in names {
            out.append(.scalarSample(name: n, dist: lowered, truncation: trunc))
          }
        }
      }
    }
    return out
  }

  // MARK: - Link function mapping

  private static func lowerLink(_ link: AlistLink) throws -> LinkFunction {
    switch link {
    case .logit: return .logit
    case .log:   return .log
    case .cloglog, .identity:
      throw AlistLoweringError.unsupportedLink(link)
    }
  }

  // MARK: - Distribution mapping

  private static func lowerDistribution(_ dist: AlistDistribution) throws -> Distribution {
    let args = try dist.args.map { try lowerArg($0, in: dist.name) }
    switch dist.name {
    case "dnorm":
      try requireArity(dist, expected: 2, got: args.count)
      return .normal(args[0], args[1])
    case "dbinom":
      try requireArity(dist, expected: 2, got: args.count)
      // dbinom(1, p) ≡ bernoulli(p) — McElreath's canonical binary
      // outcome shorthand.
      if case .literal(let v) = args[0], v == 1.0 {
        return .bernoulli(p: args[1])
      }
      return .binomial(n: args[0], p: args[1])
    case "dbern":
      try requireArity(dist, expected: 1, got: args.count)
      return .bernoulli(p: args[0])
    case "dbeta":
      try requireArity(dist, expected: 2, got: args.count)
      return .beta(args[0], args[1])
    case "dexp":
      try requireArity(dist, expected: 1, got: args.count)
      return .exponential(args[0])
    case "dpois":
      try requireArity(dist, expected: 1, got: args.count)
      return .poisson(args[0])
    case "dgamma":
      try requireArity(dist, expected: 2, got: args.count)
      return .gamma(args[0], args[1])
    case "dcauchy":
      try requireArity(dist, expected: 2, got: args.count)
      return .cauchy(args[0], args[1])
    case "dlnorm":
      try requireArity(dist, expected: 2, got: args.count)
      return .lognormal(args[0], args[1])
    case "dunif":
      try requireArity(dist, expected: 2, got: args.count)
      return .uniform(args[0], args[1])
    case "dt":
      try requireArity(dist, expected: 3, got: args.count)
      return .studentT(args[0], args[1], args[2])
    case "dmvnorm":
      try requireArity(dist, expected: 2, got: args.count)
      return .multivariateNormal(args[0], args[1])
    default:
      throw AlistLoweringError.unsupportedDistribution(name: dist.name)
    }
  }

  private static func requireArity(_ dist: AlistDistribution,
                                   expected: Int,
                                   got: Int) throws {
    if expected != got {
      throw AlistLoweringError.wrongArity(distribution: dist.name,
                                          expected: expected,
                                          got: got)
    }
  }

  /// Curried helper so `dist.args.map(lowerArg(_:in:distName))` works.
  private static func lowerArg(_ node: ExpressionNode,
                               in distName: String) throws -> DistributionArg {
    switch node {
    case .literal(.integer(let n)): return .literal(Double(n))
    case .literal(.float(let d)):   return .literal(d)
    case .identifier(let name):     return .symbol(name)
    default:
      throw AlistLoweringError.unsupportedDistributionArg(node, in: distName)
    }
  }
}

