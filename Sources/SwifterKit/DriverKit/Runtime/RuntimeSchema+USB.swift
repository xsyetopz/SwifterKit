// USB wire constants: interface, transfer, and bundled-I/O limits and request selectors.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeUSBProtocol.h` and the `SwifterKitRuntimeUSB*.cpp` sources read, so neither
// side spells a value twice.

/// Bounds the USB commands share with the extension.
enum RuntimeUSBLimits {
  /// The most interfaces one interface listing carries.
  static let maximumInterfaces = 256
  /// The slots outstanding asynchronous and isochronous transfers share.
  static let maximumPendingTransfers = 32
  /// The most frames one isochronous transfer describes.
  static let maximumIsochronousFrames = 1_024
  /// The most bulk pipes that hold a descriptor ring at once.
  static let maximumBundleRings = 4
  /// The most entries one descriptor ring holds.
  static let maximumBundleRingEntries = 64
  /// The most bytes all buffers of one descriptor ring hold together.
  static let maximumBundleRingBytes = 4 * 1_024 * 1_024
  /// The most transfers one bundled submission carries, `kIOUSBHostPipeBundlingMax`.
  static let maximumBundledTransfers = 16
  /// The `bcdUSB` values `AdjustPipe` accepts.
  static let supportedReleases: [UInt16] = [0x0110, 0x0200, 0x0210, 0x0300, 0x0310, 0x0320]
}

/// Which configuration descriptor a `usbCopyConfigurationDescriptor` request names, its first
/// byte. See `SwifterKitUSBConfigurationRequest`.
enum RuntimeUSBConfigurationSelector: UInt8, CaseIterable {
  /// The active configuration.
  case current = 0
  /// The configuration at an index.
  case index = 1
  /// The configuration with a `bConfigurationValue`.
  case value = 2
}

/// Which endpoint descriptors a pipe descriptor request reads. The public type carries the wire
/// values.
typealias RuntimeUSBPipeDescriptorPolicy = USBPipeDescriptorPolicy
