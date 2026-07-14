import Foundation

extension DriverCommand {
  /// Injects one hardware-received Ethernet frame into the networking stack.
  public static func ethernetReceive(frame: Data, linkHeaderLength: UInt8 = 14) throws -> Self {
    guard !frame.isEmpty else { throw EthernetRuntimeError.emptyFrame }
    guard frame.count <= 65_480 else { throw EthernetRuntimeError.frameTooLarge }
    var payload = Data(capacity: 8 + frame.count)
    payload.appendRuntimeInteger(UInt32(frame.count))
    payload.append(linkHeaderLength)
    payload.append(contentsOf: [0, 0, 0])
    payload.append(frame)
    return Self(opcode: 0x0900, requiredCapabilities: .networking, payload: payload)
  }

  /// Completes an outgoing frame after the hardware transport finishes.
  public static func completeEthernetTransmit(requestID: UInt32, status: Int32 = 0) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(status)
    return Self(opcode: 0x0901, requiredCapabilities: .networking, payload: payload)
  }

  /// Reports the physical link state and active media word.
  public static func reportEthernetLink(active: Bool, media: EthernetMedia) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(active ? UInt32(3) : UInt32(1))
    payload.appendRuntimeInteger(media.rawValue)
    return Self(opcode: 0x0902, requiredCapabilities: .networking, payload: payload)
  }
}

extension DriverContext {
  /// Injects one hardware-received Ethernet frame into the networking stack.
  public func ethernetReceive(frame: Data, linkHeaderLength: UInt8 = 14) async throws {
    _ = try await execute(.ethernetReceive(frame: frame, linkHeaderLength: linkHeaderLength))
  }

  /// Completes an outgoing frame after the hardware transport finishes.
  public func completeEthernetTransmit(requestID: UInt32, status: Int32 = 0) async throws {
    _ = try await execute(.completeEthernetTransmit(requestID: requestID, status: status))
  }

  /// Reports the physical link state and active media word.
  public func reportEthernetLink(active: Bool, media: EthernetMedia) async throws {
    _ = try await execute(.reportEthernetLink(active: active, media: media))
  }
}

extension DriverEvent {
  /// Decodes a NetworkingDriverKit request, or returns nil for another event family.
  public func ethernet() throws -> EthernetEvent? {
    guard type == 0x0900 else { return nil }
    return try EthernetEvent(runtimePayload: Data(payload))
  }
}
