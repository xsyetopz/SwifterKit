import Foundation

/// The operating speed of a USB device, from `tIOUSBHostConnectionSpeed`.
public struct USBDeviceSpeed: RawRepresentable, Sendable, Hashable {
  /// No device is connected.
  public static let none = Self(rawValue: 0)
  /// Full speed, 12 Mb/s.
  public static let full = Self(rawValue: 1)
  /// Low speed, 1.5 Mb/s.
  public static let low = Self(rawValue: 2)
  /// High speed, 480 Mb/s.
  public static let high = Self(rawValue: 3)
  /// SuperSpeed, 5 Gb/s.
  public static let superSpeed = Self(rawValue: 4)
  /// SuperSpeedPlus, 10 Gb/s.
  public static let superSpeedPlus = Self(rawValue: 5)
  /// SuperSpeedPlus by 2, 20 Gb/s.
  public static let superSpeedPlusBy2 = Self(rawValue: 6)

  /// The USBDriverKit speed value.
  public let rawValue: UInt8

  /// Creates a speed from its USBDriverKit value.
  public init(rawValue: UInt8) { self.rawValue = rawValue }
}

/// The status of the port a USB device is attached to, from `tIOUSBHostPortStatus`.
public struct USBPortStatus: RawRepresentable, Sendable, Hashable {
  /// The USBDriverKit status bits.
  public let rawValue: UInt32

  /// Creates a status from its USBDriverKit bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The port type: standard, captive, internal, accessory, or ExpressCard (0 through 4).
  public var portType: UInt8 { UInt8(rawValue & 0xF) }
  /// The speed of the connected device, or ``USBDeviceSpeed/none``.
  public var connectedSpeed: USBDeviceSpeed { USBDeviceSpeed(rawValue: UInt8(rawValue >> 8 & 0x7)) }
  /// The port is resetting its link.
  public var isResetting: Bool { rawValue & 1 << 11 != 0 }
  /// The port is enabled and packets can reach the device.
  public var isEnabled: Bool { rawValue & 1 << 12 != 0 }
  /// The port is suspended.
  public var isSuspended: Bool { rawValue & 1 << 13 != 0 }
  /// The port is in an overcurrent condition.
  public var isOvercurrent: Bool { rawValue & 1 << 14 != 0 }
  /// The port is in test mode.
  public var isTestMode: Bool { rawValue & 1 << 15 != 0 }
}

/// A USB controller frame or microframe number and the system time associated with it.
public struct USBFrameTime: Sendable, Hashable {
  /// The frame or microframe number.
  public let frame: UInt64
  /// The system time, in mach absolute time units, associated with the frame.
  public let time: UInt64

  /// Creates a frame time.
  public init(frame: UInt64, time: UInt64) {
    self.frame = frame
    self.time = time
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 16 else { throw USBRuntimeError.invalidResponse }
    self.init(
      frame: try runtimePayload.readRuntimeInteger(at: 0),
      time: try runtimePayload.readRuntimeInteger(at: 8)
    )
  }
}

/// Which configuration descriptor to copy.
public enum USBConfigurationSelector: Sendable, Hashable {
  /// The active configuration. For an interface driver, the configuration of its interface.
  case current
  /// The configuration at a zero-based descriptor index.
  case index(UInt8)
  /// The configuration whose `bConfigurationValue` matches.
  case value(UInt8)
}

/// The `tDeviceRequestType` used to fetch a descriptor.
public enum USBDescriptorRequestType: UInt8, Sendable, Hashable {
  /// A standard request.
  case standard = 0
  /// A class-specific request.
  case `class` = 1
  /// A vendor-specific request.
  case vendor = 2
}

/// The `tDeviceRequestRecipient` used to fetch a descriptor.
public enum USBDescriptorRecipient: UInt8, Sendable, Hashable {
  /// The device.
  case device = 0
  /// An interface.
  case interface = 1
  /// An endpoint.
  case endpoint = 2
  /// Another recipient.
  case other = 3
}

/// Which endpoint descriptors a pipe reports.
public enum USBPipeDescriptorPolicy: UInt8, Sendable, Hashable {
  /// The descriptors used when the pipe was created.
  case original = 0
  /// The descriptors that control the pipe's current policy.
  case currentPolicy = 1
}

/// A SuperSpeed endpoint companion descriptor.
public struct USBSuperSpeedEndpointCompanion: Sendable, Hashable {
  /// The `bMaxBurst` value.
  public let maxBurst: UInt8
  /// The `bmAttributes` value.
  public let attributes: UInt8
  /// The `wBytesPerInterval` value.
  public let bytesPerInterval: UInt16
}

/// The descriptors that describe one pipe's endpoint.
public struct USBPipeDescriptors: Sendable, Hashable {
  /// The `bcdUSB` value of the device.
  public let usbRelease: UInt16
  /// The endpoint descriptor.
  public let endpoint: USBEndpointDescriptor
  /// The SuperSpeed companion descriptor, when the endpoint has one.
  public let superSpeedCompanion: USBSuperSpeedEndpointCompanion?
  /// The `dwBytesPerInterval` of the SuperSpeedPlus isochronous companion, when present.
  public let superSpeedPlusIsochronousBytesPerInterval: UInt32?

  init(runtimePayload: Data) throws {
    let bytes = [UInt8](runtimePayload)
    guard bytes.count == 23, let endpoint = USBEndpointDescriptor(descriptor: bytes[2..<9]) else {
      throw USBRuntimeError.invalidResponse
    }
    usbRelease = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
    self.endpoint = endpoint
    superSpeedCompanion =
      bytes[9] >= 6 && bytes[10] == 0x30
      ? USBSuperSpeedEndpointCompanion(
        maxBurst: bytes[11],
        attributes: bytes[12],
        bytesPerInterval: UInt16(bytes[13]) | UInt16(bytes[14]) << 8
      ) : nil
    superSpeedPlusIsochronousBytesPerInterval =
      bytes[15] >= 8 && bytes[16] == 0x31
      ? (19..<23).reduce(UInt32(0)) { $0 | UInt32(bytes[$1]) << UInt32(($1 - 19) * 8) } : nil
  }
}
