import Foundation

/// A supported PCI transport-entitlement and personality matching key.
public enum PCIMatchKey: String, Sendable, Hashable {
  /// Vendor/device IDs, including subsystem IDs.
  case general = "IOPCIMatch"
  /// Primary vendor/device IDs.
  case primary = "IOPCIPrimaryMatch"
  /// Subsystem vendor/device IDs.
  case secondary = "IOPCISecondaryMatch"
  /// PCI class-code matching.
  case deviceClass = "IOPCIClassMatch"
}

/// PCI hardware matching shared by the generated personality and entitlement.
public struct PCIDeviceConfiguration: Sendable, Hashable {
  /// Raw PCI match expressions keyed by their DriverKit matching property.
  public let matches: [PCIMatchKey: String]

  /// Creates PCI matching from explicit DriverKit match expressions.
  public init(matches: [PCIMatchKey: String]) { self.matches = matches }

  /// Creates primary vendor/device matching.
  public init(vendorID: UInt16, deviceIDs: [UInt16]) {
    let expressions = deviceIDs.map { String(format: "0x%04X%04X", $0, vendorID) }
    self.init(matches: [.primary: expressions.joined(separator: " ")])
  }

  var matchingProperties: [String: DriverProperty] {
    Dictionary(uniqueKeysWithValues: matches.map { ($0.key.rawValue, .string($0.value)) })
  }
}

/// The width of one PCI configuration-space or aperture access.
public enum PCIAccessWidth: UInt8, Sendable, Hashable {
  /// An 8-bit access.
  case byte = 1
  /// A 16-bit access.
  case word = 2
  /// A 32-bit access.
  case doubleWord = 4
  /// A 64-bit aperture access.
  case quadWord = 8
}

/// A PCI register address.
public enum PCIRegisterSpace: Sendable, Hashable {
  /// PCI configuration space.
  case configuration
  /// A device memory range resolved from a BAR.
  case memory(index: UInt8)
}

/// Information about one PCI base-address register.
public struct PCIBaseAddressInfo: Sendable, Hashable {
  /// The memory-array index used for aperture accesses.
  public let memoryIndex: UInt8
  /// The raw `IOPCIBARType` value.
  public let type: UInt8
  /// The aperture size in bytes.
  public let size: UInt64

  /// Creates PCI BAR information.
  public init(memoryIndex: UInt8, type: UInt8, size: UInt64) {
    self.memoryIndex = memoryIndex
    self.type = type
    self.size = size
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 12, runtimePayload[2] == 0, runtimePayload[3] == 0 else {
      throw PCIRuntimeError.invalidResponse
    }
    let size: UInt64 = try runtimePayload.readRuntimeInteger(at: 4)
    self.init(memoryIndex: runtimePayload[0], type: runtimePayload[1], size: size)
  }
}

/// The PCI bus, device, and function address.
public struct PCILocation: Sendable, Hashable {
  /// PCI bus number.
  public let bus: UInt8
  /// PCI device number.
  public let device: UInt8
  /// PCI function number.
  public let function: UInt8

  /// Creates a PCI location.
  public init(bus: UInt8, device: UInt8, function: UInt8) {
    self.bus = bus
    self.device = device
    self.function = function
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 4, runtimePayload[3] == 0 else {
      throw PCIRuntimeError.invalidResponse
    }
    self.init(bus: runtimePayload[0], device: runtimePayload[1], function: runtimePayload[2])
  }
}

/// An invalid PCI configuration or runtime payload.
public enum PCIRuntimeError: Error, Sendable, Equatable {
  /// No valid transport matching expression was supplied.
  case invalidMatching
  /// A BAR index must identify BAR0...BAR5 or the expansion ROM.
  case invalidBARIndex
  /// Configuration space does not support the requested access width.
  case invalidConfigurationWidth
  /// A configuration-space access exceeds the 4 KiB extended configuration area.
  case configurationOffsetOutOfRange
  /// A write value does not fit the selected width.
  case valueOutOfRange
  /// The offset is not aligned to the access width.
  case misalignedOffset
  /// The native runtime returned a malformed response.
  case invalidResponse
}
