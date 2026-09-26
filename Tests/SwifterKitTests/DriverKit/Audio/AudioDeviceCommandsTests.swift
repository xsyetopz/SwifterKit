import Foundation
import Testing

@testable import SwifterKit

@Suite
struct AudioDeviceCommandsTests {
  @Test
  func encodesDeviceCommands() throws {
    let state = DriverCommand.audioDeviceState()
    #expect(state.opcode == 0x0A20)
    #expect(state.requiredCapabilities == .audio)
    #expect(state.payload.isEmpty)
    #expect(state.maximumResponseSize == RuntimeMessage.headerSize + 64)

    let offset = try DriverCommand.audioSetDeviceProperty(.outputSafetyOffset(24))
    #expect(offset.opcode == 0x0A21)
    let offsetBytes: [UInt8] = bytes(le(UInt32(5)), le(UInt32(0)), le(UInt64(24)))
    #expect(offset.payload == Data(offsetBytes))

    let stereo = try DriverCommand.audioSetDeviceProperty(
      .preferredStereoChannels(AudioStereoChannels(left: 3, right: 4))
    )
    let stereoBytes: [UInt8] = bytes(le(UInt32(6)), le(UInt32(0)), le(UInt32(3)), le(UInt32(4)))
    #expect(stereo.payload == Data(stereoBytes))
    let restored = try DriverCommand.audioSetDeviceProperty(.wantsStreamFormatsRestored(true))
    #expect(try restored.payload.readRuntimeInteger(at: 0) as UInt32 == 7)
    #expect(try restored.payload.readRuntimeInteger(at: 8) as UInt64 == 1)

    let layout = try DriverCommand.audioSetPreferredChannelLayout(
      direction: .input,
      labels: [.left, .right, .center]
    )
    #expect(layout.opcode == 0x0A22)
    let layoutBytes: [UInt8] = bytes(
      le(UInt32(1)),
      le(UInt32(3)),
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt32(3))
    )
    #expect(layout.payload == Data(layoutBytes))
  }

  @Test
  func encodesStreamControlAndPropertyCommands() throws {
    let stream = try DriverCommand.audioStreamState(index: 1)
    #expect(stream.opcode == 0x0A23)
    #expect(stream.payload == Data([1, 0, 0, 0, 0, 0, 0, 0]))
    #expect(stream.maximumResponseSize == RuntimeMessage.headerSize + 720)

    let terminal = try DriverCommand.audioSetStreamProperty(index: 1, .terminalType(.headphones))
    #expect(terminal.opcode == 0x0A24)
    let terminalBytes: [UInt8] = bytes(le(UInt32(1)), le(UInt32(4)), le(UInt64(0x6864_7068)))
    #expect(terminal.payload == Data(terminalBytes))
    let ring = try DriverCommand.audioSetStreamProperty(index: 0, .ringBufferFrameCapacity(65_536))
    #expect(try ring.payload.readRuntimeInteger(at: 4) as UInt32 == 6)

    let info = DriverCommand.audioControlInfo(identifier: 9)
    #expect(info.opcode == 0x0A25)
    #expect(info.payload == Data([9, 0, 0, 0, 0, 0, 0, 0]))
    #expect(info.maximumResponseSize <= RuntimeMessage.maximumSize)

    let range = try DriverCommand.audioSetControlProperty(identifier: 4, .sliderRange(10...90))
    #expect(range.opcode == 0x0A26)
    let rangeBytes: [UInt8] = bytes(le(UInt32(4)), le(UInt32(1)), le(UInt32(10)), le(UInt32(90)))
    #expect(range.payload == Data(rangeBytes))

    let removal = try DriverCommand.audioRemoveSelectorItems(identifier: 3, values: [2, 5])
    #expect(removal.opcode == 0x0A27)
    let removalBytes: [UInt8] = bytes(le(UInt32(3)), le(UInt32(2)), le(UInt32(2)), le(UInt32(5)))
    #expect(removal.payload == Data(removalBytes))

    #expect(DriverCommand.audioCustomPropertyInfo(identifier: 20).opcode == 0x0A28)

    let move = try DriverCommand.audioSetMemberAttachment(.customProperty(20), owner: .driver)
    #expect(move.opcode == 0x0A29)
    let moveBytes: [UInt8] = bytes(le(UInt32(3)), le(UInt32(20)), le(UInt32(2)), le(UInt32(0)))
    #expect(move.payload == Data(moveBytes))
    let detach = try DriverCommand.audioSetMemberAttachment(.stream(2), owner: .detached)
    #expect(detach.payload.prefix(12) == Data([1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test
  func rejectsInvalidMembersAndValues() {
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetDeviceProperty(
        .preferredStereoChannels(AudioStereoChannels(left: 1, right: 1))
      )
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetPreferredChannelLayout(direction: .output, labels: [])
    }
    #expect(throws: AudioRuntimeError.invalidStreamIndex) {
      try DriverCommand.audioStreamState(index: 8)
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetStreamProperty(index: 0, .startingChannel(0))
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetStreamProperty(index: 0, .currentFormat(index: 16))
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetStreamProperty(index: 0, .ringBufferFrameCapacity(8))
    }
    #expect(throws: AudioRuntimeError.invalidControlValue) {
      try DriverCommand.audioSetControlProperty(
        identifier: 5,
        .panningChannels(AudioStereoChannels(left: 2, right: 2))
      )
    }
    #expect(throws: AudioRuntimeError.invalidControlValue) {
      try DriverCommand.audioRemoveSelectorItems(identifier: 3, values: [1, 1])
    }
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioSetMemberAttachment(.control(1), owner: .driver)
    }
    #expect(throws: AudioRuntimeError.invalidStreamIndex) {
      try DriverCommand.audioSetMemberAttachment(.stream(8), owner: .device)
    }
  }

  @Test
  func decodesDeviceAndCustomPropertyState() throws {
    let deviceBytes: [UInt8] = bytes(
      le(UInt32(40)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(8)),
      le(UInt32(16)),
      le(UInt32(1)),
      le(UInt32(2)),
      le(UInt64(100)),
      le(UInt64(200)),
      le(UInt64(300)),
      le(UInt64(400))
    )
    let device = try AudioDeviceState(runtimePayload: Data(deviceBytes))
    #expect(device.objectID == 40)
    #expect(device.canBeDefaultInput && !device.canBeDefaultOutput)
    #expect(device.canBeDefaultSystemOutput)
    #expect(device.inputSafetyOffset == 8 && device.outputSafetyOffset == 16)
    #expect(device.preferredStereoChannels == AudioStereoChannels(left: 1, right: 2))
    #expect(device.outputClientTime == AudioClientIOTime(sampleTime: 300, hostTime: 400))
    var badFlag = deviceBytes
    badFlag[4] = 2
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioDeviceState(runtimePayload: Data(badFlag))
    }

    let propertyBytes: [UInt8] = bytes(
      le(UInt32(51)),
      le(UInt32(0x7377_6B70)),
      le(UInt32(0x6366_7374)),
      le(UInt32(0x6366_7374)),
      le(UInt32(2)),
      le(UInt32(0))
    )
    let property = try AudioCustomPropertyInfo(runtimePayload: Data(propertyBytes))
    #expect(property.selector == 0x7377_6B70)
    #expect(property.propertyDataType == .string && property.qualifierDataType == .string)
    #expect(property.owner == .driver)
    var badOwner = propertyBytes
    badOwner[16] = 3
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioCustomPropertyInfo(runtimePayload: Data(badOwner))
    }
  }

  @Test
  func decodesStreamState() throws {
    let format: [UInt8] = bytes(
      le(Double(48_000).bitPattern),
      le(UInt32(0x6C70_636D)),
      le(UInt32(12)),
      le(UInt32(4)),
      le(UInt32(1)),
      le(UInt32(4)),
      le(UInt32(2)),
      le(UInt32(16)),
      le(UInt32(0))
    )
    let header: [UInt8] = bytes(
      le(UInt32(41)),
      le(UInt32(1)),
      le(UInt32(0x6D69_6372)),
      le(UInt32(1)),
      le(UInt32(32)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt64(131_072))
    )
    let payload: [UInt8] = bytes(header, format, format)
    let state = try AudioStreamState(runtimePayload: Data(payload))
    #expect(state.objectID == 41 && state.direction == .input)
    #expect(state.terminalType == .microphone)
    #expect(state.latency == 32 && state.isActive && !state.isAttached)
    #expect(state.memoryLength == 131_072)
    #expect(state.currentFormat == .linearPCM(sampleRate: 48_000, channels: 2))
    #expect(state.availableFormats == [state.currentFormat])
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioStreamState(runtimePayload: Data(bytes(header, format)))
    }
  }

  @Test
  func decodesControlInfo() throws {
    let header: [UInt8] = bytes(
      le(UInt32(60)),
      le(UInt32(3)),
      le(UInt32(0x696E_7074)),
      le(UInt32(0)),
      le(UInt32(1)),
      le(UInt32(1)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(0)),
      le(UInt32(2)),
      le(UInt32(0))
    )
    let items: [UInt8] = bytes(
      le(UInt32(1)),
      le(UInt32(4)),
      Array("Line".utf8),
      le(UInt32(2)),
      le(UInt32(3)),
      Array("Mic".utf8)
    )
    let selector = try AudioControlInfo(runtimePayload: Data(bytes(header, items)))
    #expect(selector.kind == .selector && selector.scope == .input)
    #expect(selector.isSettable && selector.isAttached)
    #expect(selector.sliderRange == nil && selector.panningChannels == nil)
    #expect(
      selector.selectorItems == [
        AudioSelectorValue(value: 1, name: "Line"), AudioSelectorValue(value: 2, name: "Mic"),
      ]
    )
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioControlInfo(runtimePayload: Data(bytes(header, Array(items.dropLast()))))
    }

    var slider = header
    slider.replaceSubrange(4..<8, with: le(UInt32(4)))
    slider.replaceSubrange(24..<32, with: bytes(le(UInt32(10)), le(UInt32(90))))
    slider.replaceSubrange(40..<44, with: le(UInt32(0)))
    let sliderInfo = try AudioControlInfo(runtimePayload: Data(slider))
    #expect(sliderInfo.kind == .slider && sliderInfo.sliderRange == 10...90)
    #expect(sliderInfo.selectorItems.isEmpty)
  }
}
