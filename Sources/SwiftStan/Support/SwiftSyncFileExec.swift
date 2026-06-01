
//
//  SwiftSyncFileExec.swift
//
//
//  Created by Robert Goedman on 10/5/25.
//

import Foundation

func swiftSyncFileExec(program: String,
                       arguments: [String],
                       method: String = "sample") -> (String, String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: program)
  process.arguments = arguments

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = errorPipe

  let label = method.isEmpty ? "`\(program)`" : "`\(program) \(method)`"

  do {
    try process.run()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    _ = String(decoding: outputData, as: UTF8.self)
    let errorText = String(decoding: errorData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // `readDataToEndOfFile` blocks until the pipes close (which the
    // child closes on exit), but `terminationStatus` is only valid
    // once the process has actually been reaped.
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      let detail = errorText.isEmpty
        ? "exit \(process.terminationStatus)"
        : "exit \(process.terminationStatus): \(errorText)"
      return ("", "Command \(label) failed (\(detail)).")
    }
    return ("Command \(label) completed successfully.", "")
  } catch {
    return ("", "Command error: \(error.localizedDescription)")
  }
}
