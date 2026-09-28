import Foundation

/// A serial port on a USB interface, generated as an `IOUserUSBSerial` service.
///
/// USBSerialDriverKit owns the data path:
/// - It opens the matched `IOUSBHostInterface`.
/// - It moves bytes between the terminal queues and the interface's bulk pipes.
/// - It polls its interrupt pipe.
///
/// Swift programs the hardware in response to ``SerialEvent`` requests, typically with
/// ``DriverContext/usbControlTransfer(_:data:timeout:)``. Swift also reports modem-input changes
/// with ``DriverContext/serialSetModemStatus(_:)`` and can observe every received and interrupt
/// packet through ``DriverEvent/usbSerial()``.
///
/// Because the superclass fills and drains the terminal queues,
/// ``DriverContext/serialEnqueueReceive(_:)`` and
/// ``DriverContext/serialDequeueTransmit(maximumLength:)`` fail with `kIOReturnUnsupported`, and
/// ``SerialEvent/receiveSpaceAvailable`` and ``SerialEvent/transmitDataAvailable`` never arrive.
public struct USBSerialPortConfiguration: Sendable, Hashable {
  /// The BSD device base name, or nil for USBSerialDriverKit's `usbserial-` default.
  public let baseName: String?
  /// The BSD device suffix, or nil for USBSerialDriverKit's default, which is derived from the
  /// device serial number or USB location.
  public let suffix: String?
  /// Modem-input state returned until Swift reports a hardware change.
  public let initialModemStatus: SerialModemStatus
  /// Whether each bulk IN packet is copied to Swift as ``USBSerialEvent/receivedPacket(_:)``.
  public let deliversReceivedPackets: Bool
  /// Whether each interrupt IN packet is copied to Swift as ``USBSerialEvent/interruptPacket(_:)``.
  public let deliversInterruptPackets: Bool

  /// Creates USB serial-port metadata for a generated extension.
  ///
  /// `baseName` and `suffix` are set together or not at all. Received packets reach the terminal
  /// unchanged whether or not they are also delivered to Swift.
  public init(
    baseName: String? = nil,
    suffix: String? = nil,
    initialModemStatus: SerialModemStatus = SerialModemStatus(),
    deliversReceivedPackets: Bool = false,
    deliversInterruptPackets: Bool = true
  ) {
    self.baseName = baseName
    self.suffix = suffix
    self.initialModemStatus = initialModemStatus
    self.deliversReceivedPackets = deliversReceivedPackets
    self.deliversInterruptPackets = deliversInterruptPackets
  }
}

/// A packet USBSerialDriverKit handed to the generated `IOUserUSBSerial` service.
///
/// Packet events are lossy notifications: a stalled host loses packets rather than blocking the
/// USB pipes. A packet larger than one runtime message arrives as several consecutive events.
public enum USBSerialEvent: Sendable, Hashable {
  /// Bytes from the bulk IN pipe, from `handleRxPacket`, before they reach the terminal.
  case receivedPacket([UInt8])
  /// Bytes from the interrupt IN pipe, from `handleInterruptPacket`.
  case interruptPacket([UInt8])

  /// The most bytes one packet event carries.
  public static let maximumPacketLength =
    RuntimeMessage.maximumSize - RuntimeMessage.headerSize - 12

  init(runtimePayload: Data) throws {
    guard runtimePayload.count > 8 else { throw SerialRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let length: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let bytes = Array(runtimePayload.dropFirst(8))
    guard Int(length) == bytes.count else { throw SerialRuntimeError.invalidPayload }
    switch RuntimeUSBSerialPacketKind(rawValue: kind) {
    case .received?: self = .receivedPacket(bytes)
    case .interrupt?: self = .interruptPacket(bytes)
    case nil: throw SerialRuntimeError.invalidEventKind(kind)
    }
  }
}

extension DriverEvent {
  /// Decodes a packet from a generated `IOUserUSBSerial` service.
  ///
  /// Returns nil when the event belongs to another capability family.
  public func usbSerial() throws -> USBSerialEvent? {
    guard type == RuntimeEventType.usbSerialPacket.rawValue else { return nil }
    return try USBSerialEvent(runtimePayload: Data(payload))
  }
}
