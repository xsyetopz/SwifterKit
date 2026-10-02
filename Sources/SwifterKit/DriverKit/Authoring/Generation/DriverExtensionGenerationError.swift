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
  /// USB metadata is absent or malformed, the provider class is neither `IOUSBHostInterface` nor
  /// `IOUSBHostDevice`, or a device provider sets configuration or interface matching fields.
  case invalidUSBConfiguration
  /// PCI metadata is absent, malformed, or conflicts with another physical transport.
  case invalidPCIConfiguration
  /// One of these is true:
  /// - Serial metadata is absent, malformed, or conflicts with HID subclassing.
  /// - Both serial and USB serial metadata are set.
  /// - USB serial metadata lacks the USB capability or an `IOUSBHostInterface` provider.
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
  /// Interrupt sources are absent, duplicated, out of range, or exceed the runtime limit, or
  /// PCI interrupt allocation is invalid or cannot deliver a configured source.
  case invalidInterruptConfiguration
  /// Native memory-pool limits are absent or invalid.
  case invalidMemoryConfiguration
  /// One of these is true:
  /// - Reporters are absent or exceed ``ReportingLimits``.
  /// - A name is empty, too long, or contains NUL.
  /// - Channel IDs are zero or repeat.
  /// - A state or histogram layout is invalid.
  case invalidReportingConfiguration
  /// Fast-path programs break a rule of ``FastPathConfiguration/validate(for:)``.
  case invalidFastPathConfiguration(FastPathError)
  /// Capability metadata was supplied without enabling its capability.
  case capabilityConfigurationMismatch(RuntimeCapabilities)
  /// Matching properties attempted to replace generator-owned metadata.
  case reservedMatchingProperty(String)
  /// The destination already exists.
  case destinationExists(String)
  /// Packaged native runtime templates are unavailable.
  case templateUnavailable
  /// A ``DriverExtensionConfiguration`` has no personalities.
  case noPersonalities
  /// A personality name is not an ASCII letter followed by ASCII letters and digits, starts or
  /// is started by another personality's name ignoring case, or differs from the
  /// ``DriverConfiguration/personalityName`` of its configuration.
  case invalidPersonalityName(String)
  /// A packaged template no longer contains an expected token.
  case templateInvariant(String)
  /// A file-system operation failed.
  case fileSystem(String)
}
