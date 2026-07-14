import Foundation
import Testing

@testable import SwifterKit

@Suite struct MIDITypesTests {
  @Test func encodesSourceSendCommand() throws {
    let command = try DriverCommand.midiSend(sourceIndex: 2, words: [0x2090_3C7F, 0x4080_3C00])

    #expect(command.opcode == 0x0800)
    #expect(command.requiredCapabilities == .midi)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 4) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt32 == 0x2090_3C7F)
  }

  @Test func rejectsEmptyAndOversizedSends() {
    #expect(throws: MIDIRuntimeError.emptyPacketData) {
      try DriverCommand.midiSend(sourceIndex: 0, words: [])
    }
    #expect(throws: MIDIRuntimeError.packetDataTooLarge) {
      try DriverCommand.midiSend(sourceIndex: 0, words: Array(repeating: 0, count: 16_373))
    }
  }

  @Test func decodesLifecycleAndDestinationEvents() throws {
    #expect(try event(kind: 1).midi() == .startIO)
    #expect(try event(kind: 2).midi() == .stopIO)

    var payload = Data(event(kind: 3, endpoint: 4, count: 2).payload)
    payload.appendRuntimeInteger(UInt32(0x2090_3C7F))
    payload.appendRuntimeInteger(UInt32(0x4090_3D7F))
    #expect(
      try DriverEvent(type: 0x0800, payload: Array(payload)).midi()
        == .received(MIDIUniversalPacketData(endpointIndex: 4, words: [0x2090_3C7F, 0x4090_3D7F]))
    )
  }

  @Test func rejectsMalformedAndForeignEvents() throws {
    #expect(try DriverEvent(type: 0x0100).midi() == nil)
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0800, payload: [1]).midi()
    }
    #expect(throws: MIDIRuntimeError.invalidEventKind(9)) { try event(kind: 9).midi() }
  }

  private func event(kind: UInt32, endpoint: UInt32 = 0, count: UInt32 = 0) -> DriverEvent {
    var payload = Data()
    payload.appendRuntimeInteger(kind)
    payload.appendRuntimeInteger(endpoint)
    payload.appendRuntimeInteger(count)
    payload.appendRuntimeInteger(UInt32(0))
    return DriverEvent(type: 0x0800, payload: Array(payload))
  }
}
