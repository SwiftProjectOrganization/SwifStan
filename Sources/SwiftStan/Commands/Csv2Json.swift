//
//  Csv2Json.swift
//  Stan
//
//  V2.1 Slice C: read `Preliminaries/<name>.csv`, validate column
//  coverage against `Results/<name>.stan`'s data block, derive the
//  cardinality scalars (`N`, `N_<col>`), and write
//  `Results/<name>.data.json`.
//
//  The schema source-of-truth is the generated `.stan`. csv2json
//  therefore runs *after* dsl2stan in the V2.1 orchestrator.
//
//  Any `NA` (or unparseable value) in a column the schema declares as
//  row data fails loudly with the offending column name and row number
//  — no silent drop, no NaN propagation.
//

import Foundation

public enum Csv2JsonError: Error, CustomStringConvertible {
  case csvNotFound(path: String)
  case stanNotFound(path: String)
  case schemaColumnMissing(column: String, csvPath: String)
  case naValue(column: String, row: Int, value: String)
  case nonInteger(column: String, row: Int, value: String)
  case nonReal(column: String, row: Int, value: String)
  case schemaError(StanSchemaParseError)

  public var description: String {
    switch self {
    case .csvNotFound(let path):
      return "csv2json: CSV not found at \(path)"
    case .stanNotFound(let path):
      return "csv2json: Stan source not found at \(path); run `dsl2stan` first"
    case .schemaColumnMissing(let column, let csvPath):
      return "csv2json: schema requires column '\(column)' but it is not present in \(csvPath)"
    case .naValue(let column, let row, let value):
      return "csv2json: NA-like value '\(value)' in column '\(column)' at row \(row); drop or fix the input"
    case .nonInteger(let column, let row, let value):
      return "csv2json: non-integer value '\(value)' in column '\(column)' at row \(row)"
    case .nonReal(let column, let row, let value):
      return "csv2json: non-numeric value '\(value)' in column '\(column)' at row \(row)"
    case .schemaError(let err):
      return "csv2json: \(err.description)"
    }
  }
}

@discardableResult
public func csv2json(model: String, verbose: Bool = false) throws -> URL {
  let paths = casePaths(for: model)
  try ensureCaseDirectories(paths, verbose: verbose)

  let csvURL = paths.preliminaries.appendingPathComponent("\(model).csv")
  let stanURL = paths.results.appendingPathComponent("\(model).stan")
  let fm = FileManager.default
  guard fm.fileExists(atPath: csvURL.path) else {
    throw Csv2JsonError.csvNotFound(path: csvURL.path)
  }
  guard fm.fileExists(atPath: stanURL.path) else {
    throw Csv2JsonError.stanNotFound(path: stanURL.path)
  }

  let stanSource = try String(contentsOf: stanURL, encoding: .utf8)
  let schema: StanDataSchema
  do {
    schema = try parseStanDataSchema(source: stanSource)
  } catch let err as StanSchemaParseError {
    throw Csv2JsonError.schemaError(err)
  }

  let rawCsv = try String(contentsOf: csvURL, encoding: .utf8)
  let parsed = parseCsv(rawCsv)
  if verbose {
    print("csv2json: parsed \(parsed.rowCount) rows × \(parsed.headers.count) columns from \(csvURL.lastPathComponent)")
  }

  var output: [String: Any] = [:]

  // Required row-data columns must exist in the CSV.
  for decl in schema.declarations {
    switch decl.kind {
    case .rowCount:
      output["N"] = parsed.rowCount
    case .cardinality(let col):
      guard let column = parsed.column(named: col) else {
        // Cardinality references a column we don't have — let the user
        // fix the schema or rename.
        throw Csv2JsonError.schemaColumnMissing(column: col, csvPath: csvURL.path)
      }
      let ints = try parseIntColumn(column, columnName: col)
      output[decl.name] = ints.max() ?? 0
    case .rowInt:
      guard let column = parsed.column(named: decl.name) else {
        throw Csv2JsonError.schemaColumnMissing(column: decl.name, csvPath: csvURL.path)
      }
      output[decl.name] = try parseIntColumn(column, columnName: decl.name)
    case .rowReal:
      guard let column = parsed.column(named: decl.name) else {
        throw Csv2JsonError.schemaColumnMissing(column: decl.name, csvPath: csvURL.path)
      }
      output[decl.name] = try parseRealColumn(column, columnName: decl.name)
    case .other:
      continue
    }
  }

  let outURL = paths.results.appendingPathComponent("\(model).data.json")
  let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
  try json.write(to: outURL, options: .atomic)
  if verbose { print("csv2json: wrote \(outURL.path)") }
  return outURL
}

// MARK: - CSV parsing

private struct ParsedCsv {
  let headers: [String]
  let rows: [[String]]
  var rowCount: Int { rows.count }

  func column(named name: String) -> [String]? {
    guard let idx = headers.firstIndex(of: name) else { return nil }
    return rows.map { idx < $0.count ? $0[idx] : "" }
  }
}

private func parseCsv(_ raw: String) -> ParsedCsv {
  let lines = raw
    .split(whereSeparator: \.isNewline)
    .map(String.init)
    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  guard let header = lines.first else { return ParsedCsv(headers: [], rows: []) }
  let delimiter: Character = header.contains(";") ? ";" : ","
  let quotes = CharacterSet(charactersIn: "\"")
  let headers = header.split(separator: delimiter, omittingEmptySubsequences: false).map {
    String($0).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: quotes)
  }
  let rows = lines.dropFirst().map { line in
    line.split(separator: delimiter, omittingEmptySubsequences: false).map {
      String($0).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: quotes)
    }
  }
  return ParsedCsv(headers: headers, rows: rows)
}

// MARK: - Column parsers (with NA detection)

private let naTokens: Set<String> = ["NA", "na", "N/A", "n/a", "NaN", "nan", ""]

private func parseIntColumn(_ values: [String], columnName: String) throws -> [Int] {
  var out: [Int] = []
  out.reserveCapacity(values.count)
  for (i, v) in values.enumerated() {
    if naTokens.contains(v) {
      throw Csv2JsonError.naValue(column: columnName, row: i + 1, value: v)
    }
    guard let parsed = Int(v) else {
      throw Csv2JsonError.nonInteger(column: columnName, row: i + 1, value: v)
    }
    out.append(parsed)
  }
  return out
}

private func parseRealColumn(_ values: [String], columnName: String) throws -> [Double] {
  var out: [Double] = []
  out.reserveCapacity(values.count)
  for (i, v) in values.enumerated() {
    if naTokens.contains(v) {
      throw Csv2JsonError.naValue(column: columnName, row: i + 1, value: v)
    }
    guard let parsed = Double(v) else {
      throw Csv2JsonError.nonReal(column: columnName, row: i + 1, value: v)
    }
    out.append(parsed)
  }
  return out
}
