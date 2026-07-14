import Foundation
import Testing

@testable import SwifterKit

@Suite struct VideoTypesTests {
  @Test func encodesBufferAndQueueCommands() throws {
    let write = try DriverCommand.videoWriteBuffer(
      streamIndex: 1,
      bufferIndex: 2,
      plane: .control,
      byteOffset: 4,
      bytes: Data([7, 8])
    )
    let entry = VideoBufferQueueEntry(
      bufferIndex: 2,
      dataOffset: 8,
      dataLength: 64,
      controlOffset: 2,
      controlLength: 4
    )
    let enqueue = try DriverCommand.videoEnqueueOutput(streamIndex: 1, entry: entry)

    #expect(write.opcode == 0x0C01)
    #expect(write.requiredCapabilities == .video)
    #expect(write.payload.count == 34)
    #expect(try write.payload.readRuntimeInteger(at: 0) as UInt32 == 1)
    #expect(try write.payload.readRuntimeInteger(at: 4) as UInt32 == 2)
    #expect(try write.payload.readRuntimeInteger(at: 8) as UInt32 == 1)
    #expect(Array(write.payload.suffix(2)) == [7, 8])
    #expect(enqueue.opcode == 0x0C02)
    #expect(enqueue.payload.count == 36)
  }

  @Test func decodesQueueEntryAndLifecycle() throws {
    var entry = Data()
    for value: UInt32 in [3, 4, 100, 8, 12, 0, 0, 0] { entry.appendRuntimeInteger(value) }
    let decoded = try VideoBufferQueueEntry(runtimePayload: entry)
    #expect(decoded.bufferIndex == 3)
    #expect(decoded.dataLength == 100)
    #expect(decoded.controlLength == 12)

    var event = Data()
    event.appendRuntimeInteger(UInt32(3))
    event.appendRuntimeInteger(UInt32(0))
    event.appendRuntimeInteger(60.0.bitPattern)
    #expect(try VideoEvent(runtimePayload: event) == .sampleRateChanged(60))
  }

  @Test func decodesHostStreamEvents() throws {
    var state = Data()
    state.appendRuntimeInteger(UInt32(9))
    state.appendRuntimeInteger(UInt32(2))
    state.appendRuntimeInteger(UInt64(1))
    #expect(try VideoEvent(runtimePayload: state) == .streamActiveChanged(index: 2, isActive: true))

    var format = Data()
    format.appendRuntimeInteger(UInt32(8))
    format.appendRuntimeInteger(UInt32(1))
    format.appendRuntimeInteger(60.0.bitPattern)
    format.appendRuntimeInteger(UInt64(1))
    format.appendRuntimeInteger(UInt32(60))
    format.appendRuntimeInteger(VideoCodec.bgra32.rawValue)
    format.appendRuntimeInteger(UInt32(0))
    format.appendRuntimeInteger(UInt32(1_920))
    format.appendRuntimeInteger(UInt32(1_080))
    format.appendRuntimeInteger(UInt32(0))
    format.appendRuntimeInteger(UInt32(0))
    let expected = VideoStreamFormat(
      frameRate: 60,
      frameTimeScale: 60,
      codec: .bgra32,
      width: 1_920,
      height: 1_080
    )
    #expect(
      try VideoEvent(runtimePayload: format) == .streamFormatChanged(index: 1, format: expected)
    )

    var notification = Data()
    notification.appendRuntimeInteger(UInt32(10))
    notification.appendRuntimeInteger(UInt32(3))
    notification.appendRuntimeInteger(UInt64(0))
    #expect(try VideoEvent(runtimePayload: notification) == .streamInputAvailable(index: 3))
  }

  @Test func rejectsInvalidTransfersAndPayloads() {
    #expect(throws: VideoRuntimeError.invalidStreamIndex) {
      try DriverCommand.videoReadBuffer(streamIndex: 8, bufferIndex: 0, length: 1)
    }
    #expect(throws: VideoRuntimeError.invalidBufferIndex) {
      try DriverCommand.videoReadBuffer(streamIndex: 0, bufferIndex: 32, length: 1)
    }
    #expect(throws: VideoRuntimeError.invalidTransferRange) {
      try DriverCommand.videoReadBuffer(streamIndex: 0, bufferIndex: 0, length: 0)
    }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoBufferQueueEntry(runtimePayload: Data(repeating: 0, count: 31))
    }
  }
}
