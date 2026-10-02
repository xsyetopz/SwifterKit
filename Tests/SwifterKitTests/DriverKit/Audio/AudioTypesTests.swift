import Foundation
import Testing

@testable import SwifterKit

@Suite
struct AudioTypesTests {
  @Test
  func configuresRawFormatsAndTopology() {
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

  @Test
  func encodesStreamTimestampAndRateCommands() throws {
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

  @Test
  func decodesIOStateAndLifecycleEvents() throws {
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

  @Test
  func decodesStreamFormatAndActiveEvents() throws {
    var format = Data()
    format.appendRuntimeInteger(UInt32(6))
    format.appendRuntimeInteger(UInt32(1))
    format.appendRuntimeInteger(48_000.0.bitPattern)
    for field: UInt32 in [0x6C70_636D, 12, 8, 1, 8, 2, 32, 0] { format.appendRuntimeInteger(field) }
    let expected = AudioStreamFormat(
      sampleRate: 48_000,
      bytesPerPacket: 8,
      bytesPerFrame: 8,
      channelsPerFrame: 2,
      bitsPerChannel: 32
    )
    #expect(
      try DriverEvent(type: 0x0A00, payload: Array(format)).audio()
        == .streamFormatChanged(index: 1, format: expected)
    )
    var reserved = format
    reserved.replaceSubrange(44..<48, with: Data([1, 0, 0, 0]))
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0A00, payload: Array(reserved)).audio()
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0A00, payload: Array(format.dropLast())).audio()
    }

    for (value, isActive) in [(UInt64(1), true), (UInt64(0), false)] {
      var active = Data()
      active.appendRuntimeInteger(UInt32(7))
      active.appendRuntimeInteger(UInt32(3))
      active.appendRuntimeInteger(value)
      #expect(
        try DriverEvent(type: 0x0A00, payload: Array(active)).audio()
          == .streamActiveChanged(index: 3, isActive: isActive)
      )
    }
    var invalid = Data()
    invalid.appendRuntimeInteger(UInt32(7))
    invalid.appendRuntimeInteger(UInt32(0))
    invalid.appendRuntimeInteger(UInt64(2))
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0A00, payload: Array(invalid)).audio()
    }
  }

  @Test
  func rejectsInvalidTransfersAndPayloads() {
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
    for kind: UInt32 in [0, 8] {
      var event = Data()
      event.appendRuntimeInteger(kind)
      event.appendRuntimeInteger(UInt32(0))
      event.appendRuntimeInteger(UInt64(0))
      #expect(throws: AudioRuntimeError.invalidEventKind(kind)) {
        try DriverEvent(type: 0x0A00, payload: Array(event)).audio()
      }
    }
  }

  @Test
  func schemaCarriesTheAudioWireValues() {
    let schema = RuntimeSchemaHeader.render()
    #expect(schema.contains("kSwifterKitAudioMaximumWriteLength = 65472;"))
    #expect(schema.contains("kSwifterKitAudioMaximumReadLength = 65512;"))
    #expect(schema.contains("kSwifterKitAudioEventStreamFormatChanged = 6;"))
    #expect(schema.contains("kSwifterKitAudioEventStreamActiveChanged = 7;"))
    #expect(schema.contains("kSwifterKitAudioValueStereoPan = 6;"))
    #expect(schema.contains("kSwifterKitAudioControlStereoPan = 5;"))
    #expect(schema.contains("kSwifterKitAudioObjectEventClockRequest = 7;"))
    #expect(schema.contains("kSwifterKitAudioClockPropertyWantsControlsRestored = 10;"))
    #expect(schema.contains("kSwifterKitAudioBoxStateAll = 0x3F;"))
    #expect(schema.contains("kSwifterKitAudioClockStateAll = 0x1F;"))
    #expect(schema.contains("kSwifterKitAudioObjectTableCount = 4;"))
  }
}
