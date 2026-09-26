import Foundation
import Testing

@testable import SwifterKit

/// The checked-in native sources, located relative to this file: the six parents are
/// Generation, Authoring, DriverKit, SwifterKitTests, Tests, and the package root.
let checkedInNativeSources = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
  url.deletingLastPathComponent()
}.appendingPathComponent("Sources/SwifterKit/Resources/DriverKitExtension/Sources")

/// Generates `configuration` into a fresh temporary directory, then runs `body` with the
/// extension directory named `name` and the temporary root, which is removed afterwards.
func withTemporaryExtension<Result>(
  named name: String,
  configuration: DriverConfiguration,
  options: DriverExtensionGenerationOptions = DriverExtensionGenerationOptions(),
  _ body: (_ output: URL, _ root: URL) throws -> Result
) throws -> Result {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let output = root.appendingPathComponent(name, isDirectory: true)
  try DriverExtensionGenerator.generate(configuration: configuration, options: options, at: output)
  return try body(output, root)
}

/// Reads the generated native source `name` from the extension at `output`.
func source(_ name: String, in output: URL) throws -> String {
  try String(
    contentsOf: output.appendingPathComponent("Sources").appendingPathComponent(name),
    encoding: .utf8
  )
}

/// Returns `text` from the first `start` up to the next `end` after it.
func section(
  of text: String,
  from start: String,
  to end: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Substring {
  let lower = try #require(text.range(of: start)?.lowerBound, sourceLocation: sourceLocation)
  let upper = try #require(
    text.range(of: end, range: lower..<text.endIndex)?.lowerBound,
    sourceLocation: sourceLocation
  )
  return text[lower..<upper]
}

/// Requires each fragment to appear, in order, within `text`.
func expectOrder(
  in text: Substring,
  _ fragments: String...,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  var cursor = text.startIndex
  for fragment in fragments {
    let range = try #require(
      text.range(of: fragment, range: cursor..<text.endIndex),
      "\(fragment) is missing or out of order",
      sourceLocation: sourceLocation
    )
    cursor = range.upperBound
  }
}
