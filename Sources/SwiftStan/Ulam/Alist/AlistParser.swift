//
//  AlistParser.swift
//  Stan
//
//  Slice A of the alist parser. Consumes an `AlistToken` stream
//  (`AlistLexer`) and produces `[AlistStatement]`. Semantic
//  interpretation lives in slices B–D.
//
//  The parser strips the outer wrap (e.g. `m12.5 <- map2stan(...)`):
//  it scans for the literal `alist(`, parses comma-separated
//  statements until the matching `)`, then ignores everything after.
//  Each statement is one of:
//
//    <lhs> ~ <dist>(args)         — likelihood / prior / varying prior / group prior
//    <link>(<target>) <- <expr>   — link / deterministic
//
//  Expression sub-trees (link RHS, distribution arguments) reuse
//  `ExpressionParser` by extracting the source span between tokens
//  and re-parsing.
//

import Foundation

internal enum AlistParserError: Error, CustomStringConvertible {
  case alistKeywordNotFound
  case unterminatedAlist
  case unexpectedToken(AlistToken, expected: String)
  case unknownLinkFunction(String, position: Int)
  case emptyStatement(position: Int)
  case lexer(AlistLexerError)
  case expression(Error, in: String)

  internal var description: String {
    switch self {
    case .alistKeywordNotFound:
      return "AlistParser: did not find an `alist(...)` block in the source"
    case .unterminatedAlist:
      return "AlistParser: `alist(...)` block is not closed"
    case .unexpectedToken(let tok, let expected):
      return "AlistParser: unexpected token \(tok.lexeme.isEmpty ? String(describing: tok.kind) : tok.lexeme) at position \(tok.position) (expected \(expected))"
    case .unknownLinkFunction(let name, let pos):
      return "AlistParser: unknown link function `\(name)` at position \(pos) (supported: logit, log, cloglog)"
    case .emptyStatement(let pos):
      return "AlistParser: empty statement at position \(pos)"
    case .lexer(let e):
      return e.description
    case .expression(let e, let src):
      return "AlistParser: failed to parse expression `\(src)`: \(e)"
    }
  }
}

internal enum AlistParser {
  internal static func parse(_ source: String) throws -> [AlistStatement] {
    let tokens: [AlistToken]
    do {
      tokens = try AlistLexer.tokenize(source)
    } catch let e as AlistLexerError {
      throw AlistParserError.lexer(e)
    }

    // 1. Scan for the literal `alist(`.
    var i = 0
    while i + 1 < tokens.count {
      if tokens[i].kind == .identifier, tokens[i].lexeme == "alist",
         tokens[i + 1].kind == .leftParen {
        i += 2
        break
      }
      i += 1
    }
    guard i > 0, i <= tokens.count else {
      throw AlistParserError.alistKeywordNotFound
    }
    if i == tokens.count {
      throw AlistParserError.alistKeywordNotFound
    }

    // 2. Slice tokens until the matching `)` of `alist(`.
    var depth = 1
    var bodyEnd = i
    while bodyEnd < tokens.count {
      switch tokens[bodyEnd].kind {
      case .leftParen, .leftBracket: depth += 1
      case .rightParen, .rightBracket:
        depth -= 1
        if depth == 0 { break }
      default: break
      }
      if depth == 0 { break }
      bodyEnd += 1
    }
    guard bodyEnd < tokens.count, tokens[bodyEnd].kind == .rightParen else {
      throw AlistParserError.unterminatedAlist
    }

    // 3. Split the body into statements on top-level commas.
    let bodyTokens = Array(tokens[i..<bodyEnd])
    let groups = splitOnTopLevelCommas(bodyTokens)

    var out: [AlistStatement] = []
    for group in groups {
      // Skip purely empty groups (trailing commas, etc.).
      if group.isEmpty { continue }
      let stmt = try parseStatement(group, in: source)
      out.append(stmt)
    }
    return out
  }

  // MARK: - Statement parsing

  private static func parseStatement(_ tokens: [AlistToken],
                                     in source: String) throws -> AlistStatement {
    guard !tokens.isEmpty else {
      throw AlistParserError.emptyStatement(position: 0)
    }
    // Find the top-level `~` or `<-` operator that splits LHS from RHS.
    var depth = 0
    var splitIdx: Int? = nil
    var splitKind: AlistToken.Kind? = nil
    for (idx, t) in tokens.enumerated() {
      switch t.kind {
      case .leftParen, .leftBracket: depth += 1
      case .rightParen, .rightBracket: depth -= 1
      case .tilde, .assign:
        if depth == 0 {
          splitIdx = idx
          splitKind = t.kind
        }
      default: break
      }
      if splitIdx != nil { break }
    }
    guard let split = splitIdx, let kind = splitKind else {
      throw AlistParserError.unexpectedToken(
        tokens.first!, expected: "`~` or `<-`")
    }
    let lhs = Array(tokens[0..<split])
    let rhs = Array(tokens[(split + 1)..<tokens.count])

    switch kind {
    case .assign:
      return try parseLink(lhs: lhs, rhs: rhs, in: source)
    case .tilde:
      return try parseSample(lhs: lhs, rhs: rhs, in: source)
    default:
      throw AlistParserError.unexpectedToken(tokens[split], expected: "`~` or `<-`")
    }
  }

  // MARK: - Link

  private static func parseLink(lhs: [AlistToken],
                                rhs: [AlistToken],
                                in source: String) throws -> AlistStatement {
    // Expected shape: <ident> ( <ident> )
    guard lhs.count == 4,
          lhs[0].kind == .identifier,
          lhs[1].kind == .leftParen,
          lhs[2].kind == .identifier,
          lhs[3].kind == .rightParen else {
      throw AlistParserError.unexpectedToken(
        lhs.first ?? AlistToken(kind: .eof, lexeme: "", position: 0),
        expected: "<link>(<target>)")
    }
    let fnName = lhs[0].lexeme
    let target = lhs[2].lexeme
    let function: AlistLink
    switch fnName {
    case "logit":   function = .logit
    case "log":     function = .log
    case "cloglog": function = .cloglog
    default:
      throw AlistParserError.unknownLinkFunction(fnName, position: lhs[0].position)
    }
    let rhsNode = try parseExpression(tokens: rhs, in: source)
    return .link(function: function, target: target, rhs: rhsNode)
  }

  // MARK: - Sample (likelihood / prior / varying / group)

  private static func parseSample(lhs lhsTokens: [AlistToken],
                                  rhs rhsTokens: [AlistToken],
                                  in source: String) throws -> AlistStatement {
    let lhs = try parseSampleLhs(lhsTokens)
    let dist = try parseDistribution(rhsTokens, in: source)
    // TODO: parse trailing `T[lo, hi]` truncation suffix when McElreath
    // alists start using it. For now sigma → lower:0 inference happens
    // in Slice D, not here.
    return .sample(lhs: lhs, dist: dist, truncation: .none)
  }

  private static func parseSampleLhs(_ tokens: [AlistToken]) throws -> AlistSampleLhs {
    guard !tokens.isEmpty else {
      throw AlistParserError.emptyStatement(position: 0)
    }
    // Shape A: c(a, b, c)
    if tokens.count >= 3,
       tokens[0].kind == .identifier, tokens[0].lexeme == "c",
       tokens[1].kind == .leftParen,
       tokens.last?.kind == .rightParen {
      let inner = Array(tokens[2..<(tokens.count - 1)])
      let names = try splitOnTopLevelCommas(inner).map { group -> String in
        guard group.count == 1, group[0].kind == .identifier else {
          throw AlistParserError.unexpectedToken(
            group.first ?? tokens[0],
            expected: "identifier inside c(...)")
        }
        return group[0].lexeme
      }
      return .group(names)
    }
    // Shape B: <ident>[<ident>]
    if tokens.count == 4,
       tokens[0].kind == .identifier,
       tokens[1].kind == .leftBracket,
       tokens[2].kind == .identifier,
       tokens[3].kind == .rightBracket {
      return .indexed(name: tokens[0].lexeme,
                      indexColumn: tokens[2].lexeme)
    }
    // Shape C: <ident>
    if tokens.count == 1, tokens[0].kind == .identifier {
      return .scalar(tokens[0].lexeme)
    }
    throw AlistParserError.unexpectedToken(
      tokens[0], expected: "scalar name, c(...) group, or name[index]")
  }

  private static func parseDistribution(_ tokens: [AlistToken],
                                        in source: String) throws -> AlistDistribution {
    guard tokens.count >= 3,
          tokens[0].kind == .identifier,
          tokens[1].kind == .leftParen,
          tokens.last?.kind == .rightParen else {
      throw AlistParserError.unexpectedToken(
        tokens.first ?? AlistToken(kind: .eof, lexeme: "", position: 0),
        expected: "<dist>(args, …)")
    }
    let name = tokens[0].lexeme
    let inner = Array(tokens[2..<(tokens.count - 1)])
    let argGroups = splitOnTopLevelCommas(inner)
    var args: [ExpressionNode] = []
    for group in argGroups {
      args.append(try parseExpression(tokens: group, in: source))
    }
    return AlistDistribution(name: name, args: args)
  }

  // MARK: - Expression sub-parsing via source-span extraction

  private static func parseExpression(tokens: [AlistToken],
                                      in source: String) throws -> ExpressionNode {
    guard let first = tokens.first, let last = tokens.last else {
      throw AlistParserError.emptyStatement(position: 0)
    }
    let chars = Array(source)
    let start = first.position
    // Take the end as one past the last lexeme.
    let end = min(chars.count, last.position + last.lexeme.count)
    let fragment = String(chars[start..<end])
    do {
      return try ExpressionParser.parse(fragment)
    } catch {
      throw AlistParserError.expression(error, in: fragment)
    }
  }

  // MARK: - Token-stream splitting

  private static func splitOnTopLevelCommas(_ tokens: [AlistToken]) -> [[AlistToken]] {
    var groups: [[AlistToken]] = []
    var current: [AlistToken] = []
    var depth = 0
    for t in tokens {
      switch t.kind {
      case .leftParen, .leftBracket:
        depth += 1
        current.append(t)
      case .rightParen, .rightBracket:
        depth -= 1
        current.append(t)
      case .comma where depth == 0:
        groups.append(current)
        current = []
      default:
        current.append(t)
      }
    }
    if !current.isEmpty { groups.append(current) }
    return groups
  }
}
