import Foundation
import Testing

@testable import SwifterKit

@Suite struct AudioTypesTests {
  @Test func configuresRawFormatsAndTopology() {
    let format = AudioStreamFormat.linearPCM(sampleRate: 48_000, channels: 2)
    let stream = AudioStreamConfiguration(direction: .output, name: "Output", formats: [format])
    let device = AudioDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Audio",
      transport: .usb,
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [stream]
    )

    #expect(format.formatID == .linearPCM)
    #expect(format.formatFlags == [.signedInteger, .packed])
    #expect(format.bytesPerFrame == 4)
    #expect(device.transport == .usb)
    #expect(device.streams[0].direction == .output)
  }

  @Test func encodesStreamTimestampAndRateCommands() throws {
    let read = try DriverCommand.audioReadStream(index: 2, byteOffset: 64, length: 4)
    #expect(read.opcode == 0x0A00)
    #expect(read.requiredCapabilities == .audio)
    #expect(
      read.payload
        == Data([2, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0])
    )

    let write = try DriverCommand.audioWriteStream(index: 1, byteOffset: 9, bytes: Data([7, 8]))
    #expect(write.opcode == 0x0A01)
    #expect(write.payload.suffix(2) == Data([7, 8]))

    #expect(DriverCommand.audioGetIOState().opcode == 0x0A02)
    #expect(DriverCommand.audioUpdateTimestamp(sampleTime: 1, hostTime: 2).opcode == 0x0A03)
    #expect(DriverCommand.audioRequestSampleRate(48_000).opcode == 0x0A04)
  }

  @Test func decodesIOStateAndLifecycleEvents() throws {
    var state = Data()
    state.appendRuntimeInteger(UInt64(7))
    state.appendRuntimeInteger(UInt32(1))
    state.appendRuntimeInteger(UInt32(128))
    state.appendRuntimeInteger(UInt64(2_048))
    state.appendRuntimeInteger(UInt64(9_000))
    let decoded = try AudioIOState(runtimePayload: state)
    #expect(decoded.sequence == 7)
    #expect(decoded.operation == .writeEnd)
    #expect(decoded.frameCount == 128)

    var event = Data()
    event.appendRuntimeInteger(UInt32(3))
    event.appendRuntimeInteger(UInt32(0))
    event.appendRuntimeInteger(48_000.0.bitPattern)
    #expect(
      try DriverEvent(type: 0x0A00, payload: Array(event)).audio() == .sampleRateChanged(48_000)
    )
    #expect(try DriverEvent(type: 1).audio() == nil)
  }

  @Test func rejectsInvalidTransfersAndPayloads() {
    #expect(throws: AudioRuntimeError.invalidStreamIndex) {
      try DriverCommand.audioReadStream(index: 8, byteOffset: 0, length: 1)
    }
    #expect(throws: AudioRuntimeError.invalidTransferRange) {
      try DriverCommand.audioWriteStream(index: 0, byteOffset: 0, bytes: Data())
    }
    #expect(throws: AudioRuntimeError.transferTooLarge) {
      try DriverCommand.audioReadStream(index: 0, byteOffset: 0, length: 65_473)
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0A00, payload: []).audio()
    }
  }
}
