import Foundation
import Testing

@testable import SwifterKit

@Suite
struct VideoMemberCommandsTests {
  @Test
  func encodesDeviceCommands() throws {
    let state = DriverCommand.videoDeviceState()
    #expect(state.opcode == 0x0C20)
    #expect(state.requiredCapabilities == .video)
    #expect(state.payload.isEmpty)
    #expect(state.maximumResponseSize == RuntimeMessage.headerSize + 64)

    let offset = try DriverCommand.videoSetDeviceProperty(.outputSafetyOffset(24))
    #expect(offset.opcode == 0x0C21)
    let offsetBytes: [UInt8] = bytes(le(UInt32(5)), le(UInt32(0)), le(UInt64(24)))
    #expect(offset.payload == Data(offsetBytes))
    let stereo = try DriverCommand.videoSetDeviceProperty(
      .preferredStereoChannels(VideoStereoChannels(left: 3, right: 4))
    )
    let stereoBytes: [UInt8] = bytes(le(UInt32(6)), le(UInt32(0)), le(UInt32(3)), le(UInt32(4)))
    #expect(stereo.payload == Data(stereoBytes))
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoSetDeviceProperty(
        .preferredStereoChannels(VideoStereoChannels(left: 2, right: 2))
      )
    }

    let layout = try DriverCommand.videoSetPreferredChannelLayout(
      direction: .input,
      labels: [.left, .right]
    )
    #expect(layout.opcode == 0x0C22)
    let layoutBytes: [UInt8] = bytes(le(UInt32(1)), le(UInt32(2)), le(UInt32(1)), le(UInt32(2)))
    #expect(layout.payload == Data(layoutBytes))
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoSetPreferredChannelLayout(direction: .output, labels: [])
    }
  }

  @Test
  func encodesStreamAndBufferCommands() throws {
    let stream = try DriverCommand.videoStreamState(index: 1)
    #expect(stream.opcode == 0x0C23)
    #expect(stream.payload == Data([1, 0, 0, 0, 0, 0, 0, 0]))
    #expect(stream.maximumResponseSize == RuntimeMessage.headerSize + 896)
    #expect(throws: VideoRuntimeError.invalidStreamIndex) {
      try DriverCommand.videoStreamState(index: 8)
    }

    let capacity = try DriverCommand.videoSetStreamProperty(
      index: 2,
      .bufferCapacity(data: 4096, control: 64)
    )
    #expect(capacity.opcode == 0x0C24)
    let capacityBytes: [UInt8] = bytes(
      le(UInt32(2)),
      le(UInt32(5)),
      le(UInt32(4096)),
      le(UInt32(64))
    )
    #expect(capacity.payload == Data(capacityBytes))
    let queue = try DriverCommand.videoSetStreamProperty(index: 0, .queueEntryCount(16))
    #expect(try queue.payload.readRuntimeInteger(at: 4) as UInt32 == 6)
    let terminal = try DriverCommand.videoSetStreamProperty(index: 0, .terminalType(.line))
    #expect(try terminal.payload.readRuntimeInteger(at: 8) as UInt64 == 0x6C69_6E65)
    let invalid: [VideoStreamProperty] = [
      .startingChannel(0), .currentFormat(index: 16), .bufferCapacity(data: 0, control: 1),
      .bufferCapacity(data: 1, control: 1_048_577), .queueEntryCount(0), .queueEntryCount(257),
    ]
    for property in invalid {
      #expect(throws: VideoRuntimeError.invalidPayload) {
        try DriverCommand.videoSetStreamProperty(index: 0, property)
      }
    }

    let info = try DriverCommand.videoBufferInfo(streamIndex: 1, bufferIndex: 3)
    #expect(info.opcode == 0x0C25)
    #expect(info.payload == Data(bytes(le(UInt32(1)), le(UInt32(3)))))
    #expect(info.maximumResponseSize == RuntimeMessage.headerSize + 64)
    #expect(throws: VideoRuntimeError.invalidBufferIndex) {
      try DriverCommand.videoBufferInfo(streamIndex: 0, bufferIndex: 32)
    }

    let identifier = try DriverCommand.videoSetBufferProperty(
      streamIndex: 1,
      bufferIndex: 2,
      .bufferID(40)
    )
    #expect(identifier.opcode == 0x0C26)
    let identifierBytes: [UInt8] = bytes(
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt64(40))
    )
    #expect(identifier.payload == Data(identifierBytes))
    let detach = try DriverCommand.videoSetBufferProperty(
      streamIndex: 0,
      bufferIndex: 0,
      .isAttached(false)
    )
    #expect(try detach.payload.readRuntimeInteger(at: 8) as UInt32 == 2)
    #expect(try detach.payload.readRuntimeInteger(at: 16) as UInt64 == 0)
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoSetBufferProperty(streamIndex: 0, bufferIndex: 0, .bufferID(.max))
    }

    let enqueue = try DriverCommand.videoEnqueueOutputBuffer(
      streamIndex: 1,
      entry: VideoBufferQueueEntry(bufferIndex: 2, dataLength: 100)
    )
    #expect(enqueue.opcode == 0x0C2C)
    #expect(enqueue.payload.count == 36)
    #expect(try enqueue.payload.readRuntimeInteger(at: 4) as UInt32 == 2)
    #expect(try enqueue.payload.readRuntimeInteger(at: 12) as UInt32 == 100)

    let memory = try DriverCommand.videoStreamMemoryObjectID(streamIndex: 3, memoryType: 0x1_0002)
    #expect(memory.opcode == 0x0C2D)
    #expect(memory.payload == Data(bytes(le(UInt32(3)), le(UInt32(0x1_0002)))))
  }

  @Test
  func encodesControlAndMemberCommands() throws {
    let info = DriverCommand.videoControlInfo(identifier: 7)
    #expect(info.opcode == 0x0C27)
    #expect(info.maximumResponseSize == RuntimeMessage.headerSize + 48 + 32 * 263)
    let range = try DriverCommand.videoSetControlProperty(identifier: 7, .sliderRange(2...9))
    #expect(range.opcode == 0x0C28)
    let rangeBytes: [UInt8] = bytes(le(UInt32(7)), le(UInt32(1)), le(UInt32(2)), le(UInt32(9)))
    #expect(range.payload == Data(rangeBytes))
    #expect(throws: VideoRuntimeError.invalidControlValue) {
      try DriverCommand.videoSetControlProperty(
        identifier: 7,
        .panningChannels(VideoStereoChannels(left: 1, right: 1))
      )
    }
    let removal = try DriverCommand.videoRemoveSelectorItems(identifier: 7, values: [1, 3])
    #expect(removal.opcode == 0x0C29)
    let removalBytes: [UInt8] = bytes(le(UInt32(7)), le(UInt32(2)), le(UInt32(1)), le(UInt32(3)))
    #expect(removal.payload == Data(removalBytes))
    #expect(throws: VideoRuntimeError.invalidControlValue) {
      try DriverCommand.videoRemoveSelectorItems(identifier: 7, values: [1, 1])
    }
    #expect(DriverCommand.videoCustomPropertyInfo(identifier: 5).opcode == 0x0C2A)

    let attach = try DriverCommand.videoSetMemberAttachment(.control(9), attached: true)
    #expect(attach.opcode == 0x0C2B)
    let attachBytes: [UInt8] = bytes(le(UInt32(2)), le(UInt32(9)), le(UInt32(1)), le(UInt32(0)))
    #expect(attach.payload == Data(attachBytes))
    #expect(throws: VideoRuntimeError.invalidStreamIndex) {
      try DriverCommand.videoSetMemberAttachment(.stream(8), attached: false)
    }

    let notify = try DriverCommand.videoNotifyBufferQueue(
      .streamBufferQueueChange,
      streamIndex: 1,
      changeAction: 0
    )
    #expect(try notify.payload.readRuntimeInteger(at: 0) as UInt32 == 3)
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoNotifyBufferQueue(
        .streamBufferQueueChange,
        streamIndex: 1,
        changeAction: 1
      )
    }
  }

  @Test
  func decodesDeviceStreamAndBufferState() throws {
    let device: [UInt8] = bytes(
      le(UInt32(40)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(8)),
      le(UInt32(9)),
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt64(100)),
      le(UInt64(200)),
      le(UInt64(300)),
      le(UInt64(400))
    )
    let state = try VideoDeviceState(runtimePayload: Data(device))
    #expect(state.canBeDefaultInput && !state.canBeDefaultOutput && state.canBeDefaultSystemOutput)
    #expect(state.outputSafetyOffset == 9)
    #expect(state.preferredStereoChannels == VideoStereoChannels(left: 1, right: 2))
    #expect(state.outputClientTime == VideoClientIOTime(sampleTime: 300, hostTime: 400))
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoDeviceState(runtimePayload: Data(bytes(le(UInt32(1)), le(UInt32(2)), device)))
    }

    let format: [UInt8] = bytes(
      le((30.0).bitPattern),
      le(UInt64(1)),
      le(UInt32(30)),
      le(UInt32(0x3432_3076)),
      le(UInt32(0)),
      le(UInt32(1920)),
      le(UInt32(1080)),
      le(UInt32(0))
    )
    let queues: [UInt8] = bytes(
      le(UInt32(8)),
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt32(0)),
      le(UInt64(4096)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt64(0))
    )
    let header: [UInt8] = bytes(
      le(UInt32(50)),
      le(UInt32(1)),
      le(UInt32(0x6C69_6E65)),
      le(UInt32(1)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt32(8_294_400)),
      le(UInt32(256)),
      queues
    )
    let stream = try VideoStreamState(
      runtimePayload: Data(bytes(header, format, format, le(UInt32(0)), le(UInt32(7))))
    )
    #expect(stream.direction == .input)
    #expect(stream.terminalType == .line)
    #expect(stream.isActive && !stream.isAttached)
    #expect(stream.dataBufferCapacity == 8_294_400)
    #expect(stream.inputQueue.entryCount == 8 && stream.inputQueue.memoryLength == 4096)
    #expect(stream.currentFormat.width == 1920 && stream.availableFormats.count == 1)
    #expect(stream.bufferIDs == [0, 7])
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoStreamState(runtimePayload: Data(bytes(header, format, format)))
    }

    let buffer: [UInt8] = bytes(
      le(UInt32(60)),
      le(UInt32(0x6275_6666)),
      le(UInt32(0x6F62_6A20)),
      le(UInt32(7)),
      le(UInt32(1)),
      le(UInt32(61)),
      le(UInt32(62)),
      le(UInt32(0)),
      le(UInt64(4096)),
      le(UInt64(64)),
      le(UInt64(4096)),
      le(UInt64(0))
    )
    let info = try VideoBufferInfo(runtimePayload: Data(buffer))
    #expect(info.bufferID == 7 && info.isAttached)
    #expect(info.dataMemoryObjectID == 61 && info.controlLength == 64)
    #expect(info.classID == VideoClassID(rawValue: 0x6275_6666))
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoBufferInfo(runtimePayload: Data(bytes(buffer, le(UInt32(0)))))
    }
  }

  @Test
  func decodesControlPropertyAndEventPayloads() throws {
    let control: [UInt8] = bytes(
      le(UInt32(70)),
      le(UInt32(3)),
      le(UInt32(0x676C_6F62)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(40)),
      le(UInt32(2)),
      le(UInt32(3)),
      Array("HDR".utf8)
    )
    let info = try VideoControlInfo(runtimePayload: Data(control))
    #expect(info.kind == .selector && info.owningDeviceID == 40)
    #expect(info.selectorItems == [VideoSelectorValue(value: 2, name: "HDR")])
    #expect(info.sliderRange == nil)
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoControlInfo(runtimePayload: Data(bytes(control, [0])))
    }

    let property: [UInt8] = bytes(
      le(UInt32(80)),
      le(UInt32(0x6162_6364)),
      le(UInt32(0x6366_7374)),
      le(UInt32(0)),
      le(UInt32(2)),
      le(UInt32(0))
    )
    let custom = try VideoCustomPropertyInfo(runtimePayload: Data(property))
    #expect(custom.propertyDataType == .string && custom.owner == .driver)

    func event(_ kind: UInt32, _ index: UInt32, _ value: UInt64) -> DriverEvent {
      DriverEvent(
        type: 0x0C01,
        payload: bytes(le(kind), le(index), le(UInt32(0)), le(UInt32(0)), le(value))
      )
    }
    #expect(try event(9, 0, 55).videoObject() == .deviceStreamFormatChanged(streamObjectID: 55))
    #expect(throws: VideoRuntimeError.invalidPayload) { try event(9, 1, 55).videoObject() }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try event(9, 0, UInt64(UInt32.max) + 1).videoObject()
    }
  }
}
