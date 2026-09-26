import Foundation
import Testing

enum PropertyListTestError: Error { case expectedDictionary }

func loadPropertyList(at url: URL) throws -> [String: Any] {
  let data = try Data(contentsOf: url)
  let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
  guard let dictionary = value as? [String: Any] else {
    throw PropertyListTestError.expectedDictionary
  }
  return dictionary
}

/// Returns the `SwiftDriver` personality from the Info.plist of the extension at `output`.
func loadDriverPersonality(
  in output: URL,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
  let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
  let personalities = try #require(
    info["IOKitPersonalities"] as? [String: Any],
    sourceLocation: sourceLocation
  )
  return try #require(
    personalities["SwiftDriver"] as? [String: Any],
    sourceLocation: sourceLocation
  )
}
