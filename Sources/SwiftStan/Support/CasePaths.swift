//
//  CasePaths.swift
//  Stan
//
//  V2.1: case-root + per-model path resolution. Centralises the
//  `<root>/<name>/{Preliminaries,Results}/` layout introduced in
//  V2.1, replacing the V1 flat-directory convention.
//

import Foundation

public struct CasePaths {
  public let model: String
  public let preliminaries: URL
  public let results: URL
}

/// Case root resolution: `$STAN_CASES` env var if set, otherwise
/// `~/Documents/StanCases/`.
public func caseRoot() -> URL {
  if let env = ProcessInfo.processInfo.environment["STAN_CASES"],
     !env.isEmpty {
    return URL(fileURLWithPath: (env as NSString).expandingTildeInPath,
               isDirectory: true)
  }
  let documents = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
  return documents.appendingPathComponent("StanCases", isDirectory: true)
}

/// `(preliminaries, results)` URLs for `<name>` under the case root.
/// Does not create the directories — use `ensureCaseDirectories(_:)`
/// for that.
public func casePaths(for model: String) -> CasePaths {
  let modelDir = caseRoot().appendingPathComponent(model, isDirectory: true)
  return CasePaths(
    model: model,
    preliminaries: modelDir.appendingPathComponent("Preliminaries", isDirectory: true),
    results: modelDir.appendingPathComponent("Results", isDirectory: true)
  )
}

public func ensureCaseDirectories(_ paths: CasePaths,
                                  verbose: Bool = false) throws {
  let fm = FileManager.default
  for url in [paths.preliminaries, paths.results] {
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
      try fm.createDirectory(at: url,
                             withIntermediateDirectories: true,
                             attributes: nil)
      if verbose { print("Created directory \(url.path)") }
    }
  }
}
