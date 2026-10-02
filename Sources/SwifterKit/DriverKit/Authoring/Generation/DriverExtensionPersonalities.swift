import Foundation

extension DriverExtensionGenerator {
  /// Generates a new extension directory with one IOKit personality per configuration in
  /// `extension`, without overwriting existing data.
  ///
  /// Each personality runs its own native classes, named after the personality, that compile
  /// only that personality's capabilities. The entitlements are the union of the personalities'
  /// entitlements.
  public static func generate(
    extension driverExtension: DriverExtensionConfiguration,
    options: DriverExtensionGenerationOptions = DriverExtensionGenerationOptions(),
    at outputDirectory: URL
  ) throws {
    let personalities = try validate(extension: driverExtension, options: options)
    var entries: [String: [String: Any]] = [:]
    var entitlements: [String: Any] = [:]
    var frameworks: Set<String> = []
    for (name, configuration) in personalities {
      entries[name] = renamingClasses(in: personality(configuration), personality: name)
      merge(entitlements: Self.entitlements(configuration), into: &entitlements)
      frameworks.formUnion(DriverExtensionProject.frameworkNames(for: configuration))
    }
    try stage(at: outputDirectory) { staging in
      try writeInfo(
        personalities: entries,
        options: options,
        to: staging.appendingPathComponent("Info.plist")
      )
      try writePropertyList(
        entitlements,
        to: staging.appendingPathComponent("SwifterKitRuntime.entitlements")
      )
      try renameSources(in: staging, personalities: personalities)
      try renderProject(in: staging) { template in
        try DriverExtensionProject.render(
          frameworks: frameworks,
          bundleIdentifier: driverExtension.bundleIdentifier,
          personalities: personalities.map(\.0),
          options: options,
          template: template
        )
      }
    }
  }

  /// Validates every personality on its own and their names, then returns the personalities
  /// sorted by name.
  static func validate(
    extension driverExtension: DriverExtensionConfiguration,
    options: DriverExtensionGenerationOptions
  ) throws -> [(String, DriverConfiguration)] {
    let personalities = driverExtension.personalities.sorted { $0.key < $1.key }.map { ($0, $1) }
    guard !personalities.isEmpty else { throw DriverExtensionGenerationError.noPersonalities }
    for (name, configuration) in personalities {
      guard isPersonalityName(name), configuration.personalityName ?? name == name,
        !personalities.contains(where: { other in other.0 != name && overlaps(other.0, name) })
      else { throw DriverExtensionGenerationError.invalidPersonalityName(name) }
      guard configuration.bundleIdentifier == driverExtension.bundleIdentifier else {
        throw DriverExtensionGenerationError.invalidBundleIdentifier(configuration.bundleIdentifier)
      }
      try validate(configuration: configuration, options: options)
    }
    return personalities
  }

  /// Whether `name` is an ASCII letter followed by ASCII letters and digits.
  private static func isPersonalityName(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic else {
      return false
    }
    return name.unicodeScalars.allSatisfy { scalar in
      scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))
    }
  }

  /// Whether one name starts the other, ignoring case. Renamed classes and files of such names
  /// could collide, and file names on a case-insensitive volume would.
  private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
    let lhs = lhs.lowercased()
    let rhs = rhs.lowercased()
    return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
  }

  /// Replaces the staged runtime sources with each personality's configured, renamed copy.
  private static func renameSources(
    in staging: URL,
    personalities: [(String, DriverConfiguration)]
  ) throws {
    let fileManager = FileManager.default
    let sources = staging.appendingPathComponent("Sources")
    let renamed = staging.appendingPathComponent(".Sources-personalities")
    try fileManager.createDirectory(at: renamed, withIntermediateDirectories: false)
    for (name, configuration) in personalities {
      let copy = staging.appendingPathComponent(".Sources-\(name)")
      try fileManager.copyItem(at: sources, to: copy)
      try configureSources(configuration, in: copy)
      try DriverExtensionPersonalityRenaming.renameSources(
        at: copy,
        into: renamed,
        personality: name
      )
      try fileManager.removeItem(at: copy)
    }
    try fileManager.removeItem(at: sources)
    try fileManager.moveItem(at: renamed, to: sources)
  }

  /// `entry` with every SwifterKit `IOUserClass`, including nested user-client and device
  /// properties, renamed for `personality`.
  private static func renamingClasses(in entry: [String: Any], personality: String) -> [String: Any]
  {
    entry.reduce(into: [:]) { result, element in
      switch element.value {
      case let name as String where element.key == "IOUserClass":
        result[element.key] = DriverExtensionPersonalityRenaming.renamed(
          name,
          personality: personality
        )
      case let nested as [String: Any]:
        result[element.key] = renamingClasses(in: nested, personality: personality)
      default: result[element.key] = element.value
      }
    }
  }

  /// Adds `entitlements` to `union`: booleans are OR'd and arrays keep each distinct entry.
  private static func merge(entitlements: [String: Any], into union: inout [String: Any]) {
    for (key, value) in entitlements {
      switch (union[key], value) {
      case (let existing as Bool, let added as Bool): union[key] = existing || added
      case (let existing as [Any], let added as [Any]):
        var merged = existing
        for entry in added where !merged.contains(where: { isEqual($0, entry) }) {
          merged.append(entry)
        }
        union[key] = merged
      default: union[key] = value
      }
    }
  }

  private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    (lhs as AnyObject).isEqual(rhs as AnyObject)
  }
}
