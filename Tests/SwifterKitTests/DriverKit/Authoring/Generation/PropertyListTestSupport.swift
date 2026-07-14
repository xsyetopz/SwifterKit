import Foundation

enum PropertyListTestError: Error { case expectedDictionary }

func loadPropertyList(at url: URL) throws -> [String: Any] {
  let data = try Data(contentsOf: url)
  let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
  guard let dictionary = value as? [String: Any] else {
    throw PropertyListTestError.expectedDictionary
  }
  return dictionary
}
