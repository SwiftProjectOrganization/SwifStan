//
//  UlamExpressionParserTests.swift
//  StanTests
//
//  Phase 5.5 Slice A: golden-parse tests for the new expression lexer,
//  parser, and symbol-reference walker. Purely additive — no shipping
//  generator code reads the parser yet, so these tests cover the
//  parsing surface in isolation. Slice B will route the existing
//  vectorisation strategy through this parser and add the cross-test
//  coverage with `UlamGeneratorTests`.
//

import Foundation
import Testing
@testable import SwiftStan

@Suite("Ulam expression parser tests")
struct UlamExpressionParserTests {

  // MARK: - Lexer

  @Test func lexer_tokenizesIdentifiersAndOperators() throws {
    let tokens = try ExpressionLexer.tokenize("a + b*x")
    let kinds = tokens.map(\.kind)
    #expect(kinds == [.identifier, .plus, .identifier, .star, .identifier, .eof])
  }

  @Test func lexer_handlesWhitespaceInsideBrackets() throws {
    let tokens = try ExpressionLexer.tokenize("a [ dept ]")
    let kinds = tokens.map(\.kind)
    #expect(kinds == [.identifier, .leftBracket, .identifier, .rightBracket, .eof])
  }

  @Test func lexer_tokenizesNumericLiterals() throws {
    let tokens = try ExpressionLexer.tokenize("0 1 1.5 1e-3 0.5")
    let kinds = tokens.map(\.kind)
    #expect(kinds == [.integerLiteral,
                      .integerLiteral,
                      .floatLiteral,
                      .floatLiteral,
                      .floatLiteral,
                      .eof])
  }

  @Test func lexer_rejectsUnexpectedCharacter() throws {
    #expect(throws: ExpressionLexerError.self) {
      _ = try ExpressionLexer.tokenize("a & b")
    }
  }

  // MARK: - Parser (the four canonical RHS shapes from the demos)

  @Test func parser_parsesAdditiveAndMultiplicative() throws {
    let node = try ExpressionParser.parse("a + b*x")
    #expect(node == .binary(
      op: .add,
      lhs: .identifier("a"),
      rhs: .binary(op: .multiply,
                   lhs: .identifier("b"),
                   rhs: .identifier("x"))))
  }

  @Test func parser_parsesIndexedExpression() throws {
    let node = try ExpressionParser.parse("a[dept] + b*male")
    #expect(node == .binary(
      op: .add,
      lhs: .indexed(name: "a", index: .identifier("dept")),
      rhs: .binary(op: .multiply,
                   lhs: .identifier("b"),
                   rhs: .identifier("male"))))
  }

  @Test func parser_parsesNestedIndexing() throws {
    let node = try ExpressionParser.parse("a[group[i]] * b[year[i]]")
    #expect(node == .binary(
      op: .multiply,
      lhs: .indexed(name: "a",
                    index: .indexed(name: "group",
                                    index: .identifier("i"))),
      rhs: .indexed(name: "b",
                    index: .indexed(name: "year",
                                    index: .identifier("i")))))
  }

  @Test func parser_parsesFunctionCall() throws {
    let node = try ExpressionParser.parse("inv_logit(a + b*x)")
    #expect(node == .call(
      name: "inv_logit",
      argument: .binary(
        op: .add,
        lhs: .identifier("a"),
        rhs: .binary(op: .multiply,
                     lhs: .identifier("b"),
                     rhs: .identifier("x")))))
  }

  // MARK: - Precedence + associativity

  @Test func parser_respectsPrecedence() throws {
    // Multiplicative binds tighter than additive, and equal-precedence
    // operators left-associate: ((a + b*x) + c)
    let node = try ExpressionParser.parse("a + b*x + c")
    #expect(node == .binary(
      op: .add,
      lhs: .binary(op: .add,
                   lhs: .identifier("a"),
                   rhs: .binary(op: .multiply,
                                lhs: .identifier("b"),
                                rhs: .identifier("x"))),
      rhs: .identifier("c")))
  }

  @Test func parser_parenthesesOverridePrecedence() throws {
    let node = try ExpressionParser.parse("(a + b) * x")
    #expect(node == .binary(
      op: .multiply,
      lhs: .binary(op: .add,
                   lhs: .identifier("a"),
                   rhs: .identifier("b")),
      rhs: .identifier("x")))
  }

  @Test func parser_parsesUnaryNegation() throws {
    let node = try ExpressionParser.parse("-a + b")
    #expect(node == .binary(
      op: .add,
      lhs: .unary(op: .negate, operand: .identifier("a")),
      rhs: .identifier("b")))
  }

  @Test func parser_parsesNumericLiteralsInArithmetic() throws {
    let node = try ExpressionParser.parse("2 * x + 1.5")
    #expect(node == .binary(
      op: .add,
      lhs: .binary(op: .multiply,
                   lhs: .literal(.integer(2)),
                   rhs: .identifier("x")),
      rhs: .literal(.float(1.5))))
  }

  // MARK: - Symbol-reference walker

  @Test func symbolReferences_capturesIdentifiersInArithmetic() throws {
    let uses = try ExpressionParser.parse("a + b*x").symbolReferences()
    #expect(uses == [
      SymbolUse(name: "a", isIndexed: false, isInsideIndex: false),
      SymbolUse(name: "b", isIndexed: false, isInsideIndex: false),
      SymbolUse(name: "x", isIndexed: false, isInsideIndex: false),
    ])
  }

  @Test func symbolReferences_tagsIndexedSymbols() throws {
    let uses = try ExpressionParser.parse("a[dept] + b*male").symbolReferences()
    #expect(uses == [
      SymbolUse(name: "a",    isIndexed: true,  isInsideIndex: false),
      SymbolUse(name: "dept", isIndexed: false, isInsideIndex: true),
      SymbolUse(name: "b",    isIndexed: false, isInsideIndex: false),
      SymbolUse(name: "male", isIndexed: false, isInsideIndex: false),
    ])
  }

  @Test func symbolReferences_handlesNestedIndexing() throws {
    let uses = try ExpressionParser.parse("a[group[i]]").symbolReferences()
    #expect(uses == [
      SymbolUse(name: "a",     isIndexed: true,  isInsideIndex: false),
      SymbolUse(name: "group", isIndexed: true,  isInsideIndex: true),
      SymbolUse(name: "i",     isIndexed: false, isInsideIndex: true),
    ])
  }

  @Test func symbolReferences_ignoresCalleeName() throws {
    // `inv_logit` is a function — not a symbol reference.
    let uses = try ExpressionParser.parse("inv_logit(a + b*x)").symbolReferences()
    #expect(uses == [
      SymbolUse(name: "a", isIndexed: false, isInsideIndex: false),
      SymbolUse(name: "b", isIndexed: false, isInsideIndex: false),
      SymbolUse(name: "x", isIndexed: false, isInsideIndex: false),
    ])
  }

  @Test func symbolReferences_distinguishesScalarAndIndexedUsesOfSameName() throws {
    // `a + a[i]` should yield two distinct SymbolUse entries for `a`.
    let uses = try ExpressionParser.parse("a + a[i]").symbolReferences()
    #expect(uses.contains(SymbolUse(name: "a", isIndexed: false, isInsideIndex: false)))
    #expect(uses.contains(SymbolUse(name: "a", isIndexed: true,  isInsideIndex: false)))
    #expect(uses.contains(SymbolUse(name: "i", isIndexed: false, isInsideIndex: true)))
  }

  // MARK: - Error paths

  @Test func parser_rejectsUnclosedBracket() throws {
    #expect(throws: ExpressionParseError.self) {
      _ = try ExpressionParser.parse("a[dept")
    }
  }

  @Test func parser_rejectsTrailingOperator() throws {
    #expect(throws: ExpressionParseError.self) {
      _ = try ExpressionParser.parse("a +")
    }
  }

  @Test func parser_rejectsEmptyExpression() throws {
    #expect(throws: ExpressionParseError.self) {
      _ = try ExpressionParser.parse("")
    }
  }

  @Test func parser_rejectsTrailingGarbage() throws {
    // After parsing `a + b`, the trailing `extra` identifier should
    // fail the post-parse EOF check rather than silently truncate.
    #expect(throws: ExpressionParseError.self) {
      _ = try ExpressionParser.parse("a + b extra")
    }
  }

  // Note: the `Expression.parsed()` and `Expression.symbolReferences()`
  // convenience entry points are trivial delegates to the underlying
  // parser tested above. They'd be tested directly here but Foundation
  // on macOS 15+ ships its own `Expression` generic and the test
  // module sees both — Swift can't disambiguate via a `SwiftStan.Expression`
  // path because the `SwiftStan` module name is shadowed by `struct SwiftStan` in
  // `Sources/SwiftStan/SwiftStan.swift`. Slice B will exercise the convenience
  // entry points from inside the module (no collision there).
}
