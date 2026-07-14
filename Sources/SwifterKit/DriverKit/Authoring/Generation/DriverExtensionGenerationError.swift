/// A deterministic extension-generation failure.
public enum DriverExtensionGenerationError: Error, Sendable, Equatable {
  /// The bundle identifier is not reverse-DNS compatible.
  case invalidBundleIdentifier(String)
  /// The provider class is empty.
  case invalidProviderClass
  /// A version string is empty.
  case invalidVersion
  /// The DriverKit deployment target is invalid.
  case invalidDeploymentTarget
  /// The requested runtime capability has no native implementation yet.
  case unsupportedCapabilities(RuntimeCapabilities)
  /// HID metadata is absent or malformed.
  case invalidHIDConfiguration
  /// USB metadata is absent or does not target an interface provider.
  case invalidUSBConfiguration
  /// PCI metadata is absent, malformed, or conflicts with another physical transport.
  case invalidPCIConfiguration
  /// Serial metadata is absent, malformed, or conflicts with HID subclassing.
  case invalidSerialConfiguration
  /// Block-storage metadata is absent, malformed, or conflicts with another superclass.
  case invalidBlockStorageConfiguration
  /// MIDI metadata is absent, malformed, or conflicts with another superclass.
  case invalidMIDIConfiguration
  /// Ethernet metadata is absent, malformed, unavailable at the deployment target, or conflicts.
  case invalidEthernetConfiguration
  /// Audio metadata is absent, malformed, unavailable at the deployment target, or conflicts.
  case invalidAudioConfiguration
  /// SCSI controller or peripheral policy is absent, invalid, ambiguous, or conflicts.
  case invalidSCSIConfiguration
  /// Video metadata is absent, malformed, unavailable at the deployment target, or conflicts.
  case invalidVideoConfiguration
  /// Interrupt sources are absent, duplicated, out of range, or exceed the runtime limit.
  case invalidInterruptConfiguration
  /// Native memory-pool limits are absent or invalid.
  case invalidMemoryConfiguration
  /// Capability metadata was supplied without enabling its capability.
  case capabilityConfigurationMismatch(RuntimeCapabilities)
  /// Matching properties attempted to replace generator-owned metadata.
  case reservedMatchingProperty(String)
  /// The destination already exists.
  case destinationExists(String)
  /// Packaged native runtime templates are unavailable.
  case templateUnavailable
  /// A packaged template no longer contains an expected token.
  case templateInvariant(String)
  /// A file-system operation failed.
  case fileSystem(String)
}
