/// Metadata for one driver extension with several IOKit personalities.
///
/// Each personality is a ``DriverConfiguration`` that matches its own provider and runs its own
/// native classes, named after the personality, which compile only that personality's
/// capabilities. Personalities may use any role, and roles may differ between personalities.
public struct DriverExtensionConfiguration: Sendable, Hashable {
  /// The driver extension bundle identifier every personality shares.
  public let bundleIdentifier: String
  /// The personalities keyed by their `IOKitPersonalities` name.
  public let personalities: [String: DriverConfiguration]

  /// Creates multi-personality extension metadata.
  ///
  /// Personality names become part of native class and file names, so each must be an ASCII
  /// letter followed by ASCII letters and digits, and no name may start another, ignoring case.
  /// ``DriverExtensionGenerator/generate(extension:options:at:)`` rejects other names, an empty
  /// personality set, personalities whose bundle identifier differs from `bundleIdentifier`, and
  /// personalities that fail single-configuration validation.
  public init(bundleIdentifier: String, personalities: [String: DriverConfiguration]) {
    self.bundleIdentifier = bundleIdentifier
    self.personalities = personalities
  }

  /// Returns the named personality with ``DriverConfiguration/personalityName`` set, so its
  /// ``DriverConfiguration/serviceClass`` and ``DriverConfiguration/serviceMatch`` name only that
  /// personality's service.
  public func personality(_ name: String) -> DriverConfiguration? {
    guard var configuration = personalities[name] else { return nil }
    configuration.personalityName = name
    return configuration
  }
}
