import Foundation

/// Universal MIDI Packet protocol used by generated endpoints.
public enum MIDIProtocol: UInt32, Sendable, Hashable {
  /// MIDI 1.0 messages transported as Universal MIDI Packets.
  case midi1 = 1
  /// MIDI 2.0 Universal MIDI Packets.
  case midi2 = 2
}

/// Static topology published by a generated MIDIDriverKit extension.
public struct MIDIDeviceConfiguration: Sendable, Hashable {
  /// Driver name presented to the MIDI server.
  public let driverName: String
  /// Stable identifier for the MIDI device.
  public let deviceIdentifier: String
  /// Stable model identifier.
  public let modelIdentifier: String
  /// Stable manufacturer identifier.
  public let manufacturerIdentifier: String
  /// Name of the device entity containing the endpoints.
  public let entityName: String
  /// Protocol used by all generated endpoints.
  public let `protocol`: MIDIProtocol
  /// Number of Swift-to-host source endpoints.
  public let sourceCount: UInt32
  /// Number of host-to-Swift destination endpoints.
  public let destinationCount: UInt32

  /// Creates generated MIDI device metadata.
  public init(
    driverName: String,
    deviceIdentifier: String,
    modelIdentifier: String,
    manufacturerIdentifier: String,
    entityName: String,
    protocol: MIDIProtocol,
    sourceCount: UInt32,
    destinationCount: UInt32
  ) {
    self.driverName = driverName
    self.deviceIdentifier = deviceIdentifier
    self.modelIdentifier = modelIdentifier
    self.manufacturerIdentifier = manufacturerIdentifier
    self.entityName = entityName
    self.protocol = `protocol`
    self.sourceCount = sourceCount
    self.destinationCount = destinationCount
  }
}

/// Universal MIDI Packet words received from or sent to one endpoint.
public struct MIDIUniversalPacketData: Sendable, Hashable {
  /// Zero-based endpoint index in the generated entity.
  public let endpointIndex: UInt32
  /// Raw Universal MIDI Packet words.
  public let words: [UInt32]

  /// Creates endpoint packet data without changing individual UMP words.
  public init(endpointIndex: UInt32, words: [UInt32]) {
    self.endpointIndex = endpointIndex
    self.words = words
  }
}

/// A MIDIDriverKit lifecycle or destination event delivered to Swift behavior.
public enum MIDIEvent: Sendable, Hashable {
  /// The MIDI server requested hardware I/O startup.
  case startIO
  /// The MIDI server requested hardware I/O shutdown.
  case stopIO
  /// A generated destination received Universal MIDI Packet words.
  case received(MIDIUniversalPacketData)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 16 else { throw MIDIRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let endpoint: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let wordCount: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    guard try runtimePayload.readRuntimeInteger(at: 12) as UInt32 == 0,
      Int(wordCount) <= (runtimePayload.count - 16) / 4,
      runtimePayload.count == 16 + Int(wordCount) * 4
    else { throw MIDIRuntimeError.invalidPayload }

    switch kind {
    case 1:
      guard endpoint == 0, wordCount == 0 else { throw MIDIRuntimeError.invalidPayload }
      self = .startIO
    case 2:
      guard endpoint == 0, wordCount == 0 else { throw MIDIRuntimeError.invalidPayload }
      self = .stopIO
    case 3:
      guard wordCount > 0 else { throw MIDIRuntimeError.invalidPayload }
      var words: [UInt32] = []
      words.reserveCapacity(Int(wordCount))
      for index in 0..<Int(wordCount) {
        words.append(try runtimePayload.readRuntimeInteger(at: 16 + index * 4))
      }
      self = .received(MIDIUniversalPacketData(endpointIndex: endpoint, words: words))
    default: throw MIDIRuntimeError.invalidEventKind(kind)
    }
  }
}

/// An invalid MIDI command or runtime event.
public enum MIDIRuntimeError: Error, Sendable, Equatable {
  /// No Universal MIDI Packet words were supplied.
  case emptyPacketData
  /// The words cannot fit in one runtime message.
  case packetDataTooLarge
  /// The native runtime returned malformed MIDI data.
  case invalidPayload
  /// The native runtime returned an unknown MIDI event kind.
  case invalidEventKind(UInt32)
}
