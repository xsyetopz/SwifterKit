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
    return Self(opcode: .networkReceive, requiredCapabilities: .networking, payload: payload)
  }

  /// Completes an outgoing frame after the hardware transport finishes.
  public static func completeEthernetTransmit(requestID: UInt32, status: Int32 = 0) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(status)
    return Self(
      opcode: .networkCompleteTransmit,
      requiredCapabilities: .networking,
      payload: payload
    )
  }

  /// Creates a BSD interface name read through `IOUserNetworkEthernet::getBSDName`.
  public static let ethernetBSDName = Self(
    opcode: .networkGetBSDName,
    requiredCapabilities: .networking,
    maximumResponseSize: RuntimeMessage.headerSize + ServicePropertyCoding.maximumNameLength
  )

  /// Reports the physical link state and active media word.
  public static func reportEthernetLink(active: Bool, media: EthernetMedia) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(active ? UInt32(3) : UInt32(1))
    payload.appendRuntimeInteger(media.rawValue)
    return Self(opcode: .networkReportLink, requiredCapabilities: .networking, payload: payload)
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

  /// Returns the interface's BSD name, such as `en5`, from `IOUserNetworkEthernet::getBSDName`, or
  /// `nil` while it returns no name, before the interface registers.
  public func ethernetBSDName() async throws -> String? {
    let reply = try await execute(.ethernetBSDName)
    guard !reply.isEmpty else { return nil }
    guard let name = String(data: reply, encoding: .utf8) else {
      throw EthernetRuntimeError.invalidPayload
    }
    return name
  }

  /// Reports the physical link state and active media word.
  public func reportEthernetLink(active: Bool, media: EthernetMedia) async throws {
    _ = try await execute(.reportEthernetLink(active: active, media: media))
  }
}

extension DriverEvent {
  /// Decodes a NetworkingDriverKit request, or returns nil for another event family.
  public func ethernet() throws -> EthernetEvent? {
    guard type == RuntimeEventType.network.rawValue else { return nil }
    return try EthernetEvent(runtimePayload: Data(payload))
  }
}
