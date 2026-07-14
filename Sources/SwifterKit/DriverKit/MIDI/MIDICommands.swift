import Foundation

extension DriverCommand {
  /// Sends Universal MIDI Packet words through a generated source endpoint.
  public static func midiSend(sourceIndex: UInt32, words: [UInt32]) throws -> Self {
    guard !words.isEmpty else { throw MIDIRuntimeError.emptyPacketData }
    guard words.count <= 16_372 else { throw MIDIRuntimeError.packetDataTooLarge }
    var payload = Data(capacity: 8 + words.count * 4)
    payload.appendRuntimeInteger(sourceIndex)
    payload.appendRuntimeInteger(UInt32(words.count))
    for word in words { payload.appendRuntimeInteger(word) }
    return Self(
      opcode: 0x0800,
      requiredCapabilities: .midi,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Sends raw Universal MIDI Packet words through a generated source endpoint.
  public func midiSend(sourceIndex: UInt32, words: [UInt32]) async throws {
    _ = try await execute(.midiSend(sourceIndex: sourceIndex, words: words))
  }
}

extension DriverEvent {
  /// Decodes a MIDIDriverKit lifecycle or destination event.
  public func midi() throws -> MIDIEvent? {
    guard type == 0x0800 else { return nil }
    return try MIDIEvent(runtimePayload: Data(payload))
  }
}
