import Foundation

/// The wire-protocol version shared by the Swift layer and internal extension runtime.
public struct RuntimeProtocolVersion: Sendable, Hashable, RawRepresentable {
  /// The first stable SwifterKit runtime protocol.
  public static let version1 = Self(rawValue: 1)
  /// The newest protocol supported by this package.
  public static let current = version1

  /// The encoded protocol number.
  public let rawValue: UInt16

  /// Creates a protocol version from its encoded number.
  public init(rawValue: UInt16) { self.rawValue = rawValue }
}

/// Message kinds exchanged with the internal extension runtime.
public enum RuntimeMessageKind: UInt16, Sendable, Equatable {
  /// Negotiates protocol versions and capabilities.
  case handshake = 1
  /// Requests one runtime operation.
  case command = 2
  /// Returns a successful operation result.
  case response = 3
  /// Delivers an asynchronous driver event.
  case event = 4
  /// Returns a structured runtime failure.
  case error = 5
}

/// Flags that modify runtime message handling.
public struct RuntimeMessageFlags: OptionSet, Sendable, Hashable {
  /// The encoded flag bits.
  public let rawValue: UInt32

  /// The sender expects a response with the same request identifier.
  public static let expectsResponse = Self(rawValue: 1 << 0)
  /// The payload is the last fragment in a sequence.
  public static let finalFragment = Self(rawValue: 1 << 1)

  /// Creates message flags from encoded bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// Capabilities implemented by an internal extension runtime.
public struct RuntimeCapabilities: OptionSet, Sendable, Hashable {
  /// The encoded capability bits.
  public let rawValue: UInt64

  /// Raw memory descriptors and mappings.
  public static let memory = Self(rawValue: 1 << 0)
  /// Interrupt dispatch, timestamp delivery, and enable-state control.
  public static let interrupts = Self(rawValue: 1 << 1)
  /// USBDriverKit operations.
  public static let usb = Self(rawValue: 1 << 2)
  /// HIDDriverKit operations.
  public static let hid = Self(rawValue: 1 << 3)
  /// PCIDriverKit operations.
  public static let pci = Self(rawValue: 1 << 4)
  /// SerialDriverKit operations.
  public static let serial = Self(rawValue: 1 << 5)
  /// NetworkingDriverKit operations.
  public static let networking = Self(rawValue: 1 << 6)
  /// AudioDriverKit operations.
  public static let audio = Self(rawValue: 1 << 7)
  /// MIDIDriverKit operations.
  public static let midi = Self(rawValue: 1 << 8)
  /// Block-storage operations.
  public static let blockStorage = Self(rawValue: 1 << 9)
  /// SCSI operations.
  public static let scsi = Self(rawValue: 1 << 10)
  /// VideoDriverKit operations.
  public static let video = Self(rawValue: 1 << 11)

  /// Creates capabilities from encoded bits.
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// A versioned message exchanged with the internal DriverKit runtime.
public struct RuntimeMessage: Sendable, Equatable {
  /// The fixed encoded header size.
  public static let headerSize = 24

  static let magic: UInt32 = 0x5357_4B54

  /// The protocol version used to encode the message.
  public let version: RuntimeProtocolVersion
  /// The semantic message kind.
  public let kind: RuntimeMessageKind
  /// The identifier used to correlate requests and responses.
  public let requestID: UInt64
  /// Message handling flags.
  public let flags: RuntimeMessageFlags
  /// Kind-specific bytes.
  public let payload: Data

  /// Creates a runtime message.
  public init(
    version: RuntimeProtocolVersion = .current,
    kind: RuntimeMessageKind,
    requestID: UInt64,
    flags: RuntimeMessageFlags = [],
    payload: Data = Data()
  ) {
    self.version = version
    self.kind = kind
    self.requestID = requestID
    self.flags = flags
    self.payload = payload
  }

  /// Encodes the fixed little-endian wire representation.
  public func encoded() throws -> Data {
    guard payload.count <= Int(UInt32.max) else { throw RuntimeProtocolError.payloadTooLarge }

    var result = Data(capacity: Self.headerSize + payload.count)
    result.appendRuntimeInteger(Self.magic)
    result.appendRuntimeInteger(version.rawValue)
    result.appendRuntimeInteger(kind.rawValue)
    result.appendRuntimeInteger(requestID)
    result.appendRuntimeInteger(UInt32(payload.count))
    result.appendRuntimeInteger(flags.rawValue)
    result.append(payload)
    return result
  }

  /// Decodes and validates one complete wire message.
  public init(decoding data: Data) throws {
    guard data.count >= Self.headerSize else { throw RuntimeProtocolError.truncatedHeader }

    var reader = RuntimeDataReader(data: data)
    guard try reader.readUInt32() == Self.magic else { throw RuntimeProtocolError.invalidMagic }

    let version = RuntimeProtocolVersion(rawValue: try reader.readUInt16())
    guard version == .current else {
      throw RuntimeProtocolError.unsupportedVersion(version.rawValue)
    }
    guard let kind = RuntimeMessageKind(rawValue: try reader.readUInt16()) else {
      throw RuntimeProtocolError.unknownMessageKind
    }

    let requestID = try reader.readUInt64()
    let payloadLength = Int(try reader.readUInt32())
    let flags = RuntimeMessageFlags(rawValue: try reader.readUInt32())
    guard reader.remainingCount == payloadLength else {
      throw RuntimeProtocolError.invalidPayloadLength
    }

    self.init(
      version: version,
      kind: kind,
      requestID: requestID,
      flags: flags,
      payload: Data(data.suffix(payloadLength))
    )
  }
}

/// A malformed or unsupported internal runtime message.
public enum RuntimeProtocolError: Error, Sendable, Equatable {
  /// The fixed header is incomplete.
  case truncatedHeader
  /// The message does not contain the SwifterKit magic value.
  case invalidMagic
  /// The encoded protocol version is unsupported.
  case unsupportedVersion(UInt16)
  /// The encoded message kind is unknown.
  case unknownMessageKind
  /// The payload length does not match the message.
  case invalidPayloadLength
  /// The payload is too large for the wire format.
  case payloadTooLarge
  /// A typed payload value is incomplete.
  case truncatedPayload
}

private struct RuntimeDataReader {
  let data: Data
  var offset = 0

  var remainingCount: Int { data.count - offset }

  mutating func readUInt16() throws -> UInt16 { try readInteger() }

  mutating func readUInt32() throws -> UInt32 { try readInteger() }

  mutating func readUInt64() throws -> UInt64 { try readInteger() }

  private mutating func readInteger<T: FixedWidthInteger>() throws -> T {
    let size = MemoryLayout<T>.size
    guard remainingCount >= size else { throw RuntimeProtocolError.truncatedHeader }

    var value: T = 0
    for index in 0..<size {
      let dataIndex = data.index(data.startIndex, offsetBy: offset + index)
      value |= T(data[dataIndex]) << T(index * 8)
    }
    offset += size
    return value
  }
}
