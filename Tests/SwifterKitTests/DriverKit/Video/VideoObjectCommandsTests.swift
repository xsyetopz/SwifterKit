import Foundation
import Testing

@testable import SwifterKit

@Suite
struct VideoObjectCommandsTests {
  @Test
  func encodesObjectTargetsAndNames() throws {
    let info = try DriverCommand.videoObjectInfo(.clockDevice(2))
    #expect(info.opcode == 0x0C10)
    #expect(info.requiredCapabilities == .video)
    #expect(info.payload == Data([3, 0, 0, 0, 2, 0, 0, 0]))
    #expect(try DriverCommand.videoObjectInfo(.object(77)).payload.prefix(4) == Data([4, 0, 0, 0]))

    let rename = try DriverCommand.videoSetObjectName(.box(1), name: "Rack")
    #expect(rename.opcode == 0x0C11)
    #expect(
      rename.payload == Data([2, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0]) + Data("Rack".utf8)
    )

    let element = try DriverCommand.videoSetElementName(
      .device,
      kind: .category,
      element: 3,
      scope: .output,
      name: "Main"
    )
    #expect(element.opcode == 0x0C13)
    #expect(element.payload.count == 28)
    #expect(try element.payload.readRuntimeInteger(at: 8) as UInt32 == 1)
    #expect(try element.payload.readRuntimeInteger(at: 16) as UInt32 == 0x6F75_7470)
    #expect(try element.payload.readRuntimeInteger(at: 20) as UInt32 == 4)
    #expect(
      try DriverCommand.videoElementName(.box(0), kind: .number, element: 1, scope: .global).opcode
        == 0x0C12
    )

    let changed = try DriverCommand.videoPropertiesChanged(.device, selectors: [0x6E61_6D65])
    #expect(changed.opcode == 0x0C14)
    #expect(changed.payload.count == 20)
  }

  @Test
  func rejectsInvalidTargetsNamesAndSelectors() {
    #expect(throws: VideoRuntimeError.invalidObjectTarget) {
      try DriverCommand.videoObjectInfo(.box(4))
    }
    #expect(throws: VideoRuntimeError.invalidObjectTarget) {
      try DriverCommand.videoObjectInfo(.object(0))
    }
    #expect(throws: VideoRuntimeError.invalidName) {
      try DriverCommand.videoSetObjectName(.device, name: "")
    }
    #expect(throws: VideoRuntimeError.invalidName) {
      try DriverCommand.videoSetObjectName(.device, name: "a\0b")
    }
    #expect(throws: VideoRuntimeError.invalidName) {
      try DriverCommand.videoSetObjectName(.device, name: String(repeating: "x", count: 256))
    }
    #expect(throws: VideoRuntimeError.invalidObjectTarget) {
      try DriverCommand.videoElementName(.driver, kind: .name, element: 0, scope: .global)
    }
    #expect(throws: VideoRuntimeError.invalidPropertySelectors) {
      try DriverCommand.videoPropertiesChanged(.driver, selectors: [1])
    }
    #expect(throws: VideoRuntimeError.invalidPropertySelectors) {
      try DriverCommand.videoPropertiesChanged(.device, selectors: [0])
    }
    #expect(throws: VideoRuntimeError.invalidPropertySelectors) {
      try DriverCommand.videoPropertiesChanged(.device, selectors: Array(repeating: 1, count: 33))
    }
    #expect(throws: VideoRuntimeError.invalidObjectTarget) {
      try DriverCommand.videoSetBoxOwnership(0, target: .box(1), owned: true)
    }
    #expect(throws: VideoRuntimeError.invalidObjectTarget) {
      try DriverCommand.videoClockDeviceState(.box(0))
    }
  }

  @Test
  func encodesBoxAndClockDeviceCommands() throws {
    let property = try DriverCommand.videoSetBoxProperty(1, .acquisitionFailure(-536_870_212))
    #expect(property.opcode == 0x0C16)
    #expect(property.payload.count == 24)
    #expect(try property.payload.readRuntimeInteger(at: 8) as UInt32 == 8)
    #expect(try property.payload.readRuntimeInteger(at: 16) as UInt64 == 0xE000_02BC)

    let ownership = try DriverCommand.videoSetBoxOwnership(0, target: .clockDevice(3), owned: true)
    #expect(ownership.opcode == 0x0C17)
    #expect(
      [UInt8](ownership.payload)
        == bytes(
          le(UInt32(2)),
          le(UInt32(0)),
          le(UInt32(3)),
          le(UInt32(3)),
          le(UInt32(1)),
          le(UInt32(0))
        )
    )

    let state = try DriverCommand.videoClockDeviceState(.device)
    #expect(state.opcode == 0x0C18)
    #expect(state.maximumResponseSize == RuntimeMessage.headerSize + 80 + 16 * 8)
    #expect(try DriverCommand.videoBoxState(2).opcode == 0x0C15)

    let clock = try DriverCommand.videoSetClockDeviceProperty(1, .clockAlgorithm(.raw))
    #expect(clock.opcode == 0x0C19)
    #expect(try clock.payload.readRuntimeInteger(at: 8) as UInt32 == 2)
    #expect(try clock.payload.readRuntimeInteger(at: 16) as UInt64 == 0x7261_7777)

    let rates = try DriverCommand.videoSetClockSampleRates(0, [30, 59.94, 60])
    #expect(rates.opcode == 0x0C1A)
    #expect(rates.payload.count == 16 + 24)
    let timestamp = try DriverCommand.videoUpdateClockTimestamp(2, sampleTime: 9, hostTime: 10)
    #expect(timestamp.opcode == 0x0C1B)
    #expect(
      [UInt8](timestamp.payload)
        == bytes(le(UInt32(3)), le(UInt32(2)), le(9 as UInt64), le(10 as UInt64))
    )
    let request = try DriverCommand.videoRequestClockSampleRate(1, 30)
    #expect(request.opcode == 0x0C1C)
    #expect(try request.payload.readRuntimeInteger(at: 16) as UInt64 == (30.0).bitPattern)

    #expect(throws: VideoRuntimeError.invalidSampleRates) {
      try DriverCommand.videoSetClockSampleRates(0, [])
    }
    #expect(throws: VideoRuntimeError.invalidSampleRates) {
      try DriverCommand.videoSetClockSampleRates(0, [60, 60])
    }
    #expect(throws: VideoRuntimeError.invalidSampleRates) {
      try DriverCommand.videoSetClockSampleRates(0, Array(stride(from: 1.0, through: 17, by: 1)))
    }
    #expect(throws: VideoRuntimeError.invalidSampleRates) {
      try DriverCommand.videoRequestClockSampleRate(0, .infinity)
    }
    #expect(throws: VideoRuntimeError.invalidSampleRates) {
      try DriverCommand.videoRequestClockSampleRate(0, 0)
    }
  }

  @Test
  func encodesRequestAnswersQueueNotificationsAndPropertyOwners() throws {
    let answer = try DriverCommand.videoCompleteRequest(requestID: 5, accept: false, failure: -1)
    #expect(answer.opcode == 0x0C1D)
    #expect(
      [UInt8](answer.payload) == bytes(le(UInt32(5)), le(UInt32(0)), le(Int32(-1)), le(UInt32(0)))
    )
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoCompleteRequest(requestID: 0, accept: true)
    }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try DriverCommand.videoCompleteRequest(requestID: 1, accept: true, failure: 3)
    }

    let notify = try DriverCommand.videoNotifyBufferQueue(
      .outputBufferNotification,
      streamIndex: 1,
      changeAction: 0x1234
    )
    #expect(notify.opcode == 0x0C1E)
    #expect([UInt8](notify.payload) == bytes(le(UInt32(2)), le(UInt32(1)), le(0x1234 as UInt64)))
    #expect(throws: VideoRuntimeError.invalidStreamIndex) {
      try DriverCommand.videoNotifyBufferQueue(.bufferQueueChange, streamIndex: 8, changeAction: 0)
    }

    let owner = try DriverCommand.videoSetCustomPropertyOwner(3, owner: .driver)
    #expect(owner.opcode == 0x0C1F)
    #expect([UInt8](owner.payload) == bytes(le(UInt32(3)), le(UInt32(2)), le(0 as UInt64)))
    #expect(throws: VideoRuntimeError.invalidCustomPropertyValue) {
      try DriverCommand.videoSetCustomPropertyOwner(0, owner: .device)
    }
  }

  @Test
  func decodesObjectInfoAndStates() throws {
    let info = try VideoObjectInfo(
      runtimePayload: Data(
        bytes(
          le(UInt32(9)),
          le(UInt32(0)),
          le(UInt32(0x6162_6F78)),
          le(UInt32(0x616F_626A)),
          le(UInt32(0x7573_6220)),
          le(UInt32(4)),
          le(UInt32(3)),
          le(UInt32(0)),
          Array("Rackuid".utf8)
        )
      )
    )
    #expect(info.objectID == 9)
    #expect(info.classID == .box)
    #expect(info.baseClassID == .object)
    #expect(info.transport == .usb)
    #expect(info.name == "Rack")
    #expect(info.uid == "uid")
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoObjectInfo(
        runtimePayload: Data(bytes(le(UInt32(1)), le(UInt32(1)), [UInt8](repeating: 0, count: 24)))
      )
    }

    let box = try VideoBoxState(
      runtimePayload: Data(bytes(le(UInt32(4)), le(UInt32(0)), le(UInt32(0x14)), le(Int32(-2))))
    )
    #expect(box.hasVideo && box.isAcquired && !box.hasAudio)
    #expect(box.acquisitionFailure == -2)
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoBoxState(
        runtimePayload: Data(bytes(le(UInt32(4)), le(UInt32(0)), le(UInt32(0x40)), le(Int32(0))))
      )
    }

    let header = bytes(
      le((60.0).bitPattern),
      le(1 as UInt64),
      le(2 as UInt64),
      le(3 as UInt64),
      le(4 as UInt64),
      le(UInt32(7)),
      le(UInt32(1)),
      le(UInt32(0x6D61_7667)),
      le(UInt32(0)),
      le(UInt32(2)),
      le(UInt32(0x5)),
      le(UInt32(10)),
      le(UInt32(11))
    )
    let clock = try VideoClockDeviceState(
      runtimePayload: Data(bytes(header, le(UInt32(0)), le(UInt32(1)), le((60.0).bitPattern)))
    )
    #expect(clock.sampleRate == 60)
    #expect(clock.availableSampleRates == [60])
    #expect(clock.clockAlgorithm == .twelvePointMovingWindowAverage)
    #expect(clock.transportState == .running)
    #expect(clock.clockIsStable && clock.isRunning && !clock.isAlive && !clock.isHidden)
    #expect(clock.outputLatency == 11)
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoClockDeviceState(runtimePayload: Data(bytes(header, le(UInt32(1)), le(UInt32(0)))))
    }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoClockDeviceState(runtimePayload: Data(bytes(header, le(UInt32(0)), le(UInt32(17)))))
    }
  }

  @Test
  func decodesObjectEvents() throws {
    func event(_ kind: UInt32, _ index: UInt32, _ request: UInt32, _ value: UInt64) -> DriverEvent {
      DriverEvent(
        type: 0x0C01,
        payload: bytes(le(kind), le(index), le(request), le(UInt32(0)), le(value))
      )
    }
    #expect(try event(1, 12, 0, 1).videoObject() == .deviceStarted(objectID: 12, flags: 1))
    #expect(try event(4, 1, 0, 0).videoObject() == .clockDeviceStopped(index: 1, flags: 0))
    #expect(
      try event(5, 2, 0, (30.0).bitPattern).videoObject()
        == .clockDeviceSampleRateChanged(index: 2, sampleRate: 30)
    )
    #expect(
      try event(6, 0, 9, 1).videoObject()
        == .boxAcquisitionRequested(requestID: 9, box: 0, acquire: true)
    )
    #expect(
      try event(7, 3, 4, (60.0).bitPattern).videoObject()
        == .clockDeviceSampleRateRequested(requestID: 4, index: 3, sampleRate: 60)
    )
    #expect(
      try event(8, 1, 0, 44).videoObject()
        == .clockDeviceStreamFormatChanged(index: 1, streamObjectID: 44)
    )
    #expect(throws: VideoRuntimeError.invalidPayload) { try event(6, 0, 0, 1).videoObject() }
    #expect(throws: VideoRuntimeError.invalidPayload) { try event(1, 0, 3, 1).videoObject() }
    #expect(throws: VideoRuntimeError.invalidPayload) { try event(6, 0, 1, 2).videoObject() }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try event(8, 0, 0, 0x1_0000_0000).videoObject()
    }
    #expect(throws: VideoRuntimeError.invalidEventKind(9)) { try event(9, 0, 0, 0).videoObject() }
    #expect(try DriverEvent(type: 0x0C00, payload: []).videoObject() == nil)
  }

  private func bytes(_ chunks: [UInt8]...) -> [UInt8] { chunks.flatMap { $0 } }

  private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    var data = Data()
    data.appendRuntimeInteger(value)
    return [UInt8](data)
  }
}
