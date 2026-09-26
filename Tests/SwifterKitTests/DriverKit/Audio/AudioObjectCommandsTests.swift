import Foundation
import Testing

@testable import SwifterKit

@Suite
struct AudioObjectCommandsTests {
  @Test
  func encodesObjectTargetsAndNames() throws {
    let info = try DriverCommand.audioObjectInfo(.clockDevice(2))
    #expect(info.opcode == 0x0A10)
    #expect(info.requiredCapabilities == .audio)
    #expect(info.payload == Data([3, 0, 0, 0, 2, 0, 0, 0]))
    #expect(try DriverCommand.audioObjectInfo(.object(77)).payload.prefix(4) == Data([4, 0, 0, 0]))

    let rename = try DriverCommand.audioSetObjectName(.box(1), name: "Rack")
    #expect(rename.opcode == 0x0A11)
    #expect(
      rename.payload == Data([2, 0, 0, 0, 1, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0]) + Data("Rack".utf8)
    )

    let element = try DriverCommand.audioSetElementName(
      .device,
      kind: .category,
      element: 3,
      scope: .output,
      name: "Main"
    )
    #expect(element.opcode == 0x0A13)
    #expect(element.payload.count == 28)
    #expect(try element.payload.readRuntimeInteger(at: 8) as UInt32 == 1)
    #expect(try element.payload.readRuntimeInteger(at: 16) as UInt32 == 0x6F75_7470)
    #expect(try element.payload.readRuntimeInteger(at: 20) as UInt32 == 4)

    let changed = try DriverCommand.audioPropertiesChanged(.device, selectors: [0x6E61_6D65])
    #expect(changed.opcode == 0x0A14)
    #expect(changed.payload.count == 20)
  }

  @Test
  func rejectsInvalidTargetsNamesAndSelectors() {
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioObjectInfo(.box(4))
    }
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioObjectInfo(.object(0))
    }
    #expect(throws: AudioRuntimeError.invalidName) {
      try DriverCommand.audioSetObjectName(.device, name: "")
    }
    #expect(throws: AudioRuntimeError.invalidName) {
      try DriverCommand.audioSetObjectName(.device, name: String(repeating: "x", count: 256))
    }
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioElementName(.driver, kind: .name, element: 0, scope: .global)
    }
    #expect(throws: AudioRuntimeError.invalidPropertySelectors) {
      try DriverCommand.audioPropertiesChanged(.device, selectors: [])
    }
    #expect(throws: AudioRuntimeError.invalidPropertySelectors) {
      try DriverCommand.audioPropertiesChanged(.driver, selectors: [1])
    }
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioSetBoxOwnership(0, target: .box(1), owned: true)
    }
    #expect(throws: AudioRuntimeError.invalidObjectTarget) {
      try DriverCommand.audioClockDeviceState(.driver)
    }
  }

  @Test
  func encodesBoxAndClockDeviceCommands() throws {
    let box = try DriverCommand.audioSetBoxProperty(1, .acquisitionFailure(-536_870_212))
    #expect(box.opcode == 0x0A16)
    #expect(box.payload.count == 24)
    #expect(try box.payload.readRuntimeInteger(at: 8) as UInt32 == 8)
    #expect(try box.payload.readRuntimeInteger(at: 16) as UInt64 == 0xE000_02BC)

    let ownership = try DriverCommand.audioSetBoxOwnership(0, target: .clockDevice(3), owned: true)
    #expect(ownership.opcode == 0x0A17)
    #expect(
      ownership.payload
        == Data([2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0])
    )

    let property = try DriverCommand.audioSetClockDeviceProperty(0, .clockAlgorithm(.raw))
    #expect(property.opcode == 0x0A19)
    #expect(try property.payload.readRuntimeInteger(at: 16) as UInt64 == 0x7261_7777)
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioSetClockDeviceProperty(0, .zeroTimestampPeriod(8))
    }

    let rates = try DriverCommand.audioSetClockSampleRates(1, [44_100, 48_000])
    #expect(rates.opcode == 0x0A1A)
    #expect(rates.payload.count == 32)
    #expect(throws: AudioRuntimeError.invalidSampleRates) {
      try DriverCommand.audioSetClockSampleRates(1, [48_000, 48_000])
    }
    #expect(throws: AudioRuntimeError.invalidSampleRates) {
      try DriverCommand.audioRequestClockSampleRate(1, .nan)
    }

    let timestamp = try DriverCommand.audioUpdateClockTimestamp(2, sampleTime: 5, hostTime: 9)
    #expect(timestamp.opcode == 0x0A1B)
    #expect(timestamp.payload.count == 24)
    #expect(try DriverCommand.audioRequestClockSampleRate(0, 96_000).opcode == 0x0A1C)

    let answer = try DriverCommand.audioCompleteRequest(requestID: 7, accept: false, failure: -1)
    #expect(answer.opcode == 0x0A1D)
    #expect(answer.payload == Data([7, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0]))
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioCompleteRequest(requestID: 0, accept: true)
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try DriverCommand.audioCompleteRequest(requestID: 1, accept: true, failure: 3)
    }
  }

  @Test
  func decodesObjectInfoAndStates() throws {
    var info = Data()
    for value: UInt32 in [5, 1, 0x6162_6F78, 0x616F_626A, 0x7573_6220, 4, 3, 0] {
      info.appendRuntimeInteger(value)
    }
    info.append(Data("RackBOX".utf8))
    let decoded = try AudioObjectInfo(runtimePayload: info)
    #expect(decoded.objectID == 5)
    #expect(decoded.classID == .box)
    #expect(decoded.transport == .usb)
    #expect(decoded.name == "Rack")
    #expect(decoded.uid == "BOX")
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioObjectInfo(runtimePayload: info.dropLast())
    }

    var box = Data()
    for value: UInt32 in [5, 0x7573_6220, 0x19, 0] { box.appendRuntimeInteger(value) }
    let state = try AudioBoxState(runtimePayload: box)
    #expect(state.hasAudio && state.isAcquirable && state.isAcquired && !state.hasMIDI)
    box[8] = 0x40
    #expect(throws: AudioRuntimeError.invalidPayload) { try AudioBoxState(runtimePayload: box) }

    var clock = Data()
    clock.appendRuntimeInteger(Double(48_000).bitPattern)
    for value: UInt64 in [10, 20, 30, 40] { clock.appendRuntimeInteger(value) }
    for value: UInt32 in [9, 7, 0x6969_7266, 0, 2, 0x13, 12, 34, 512, 2] {
      clock.appendRuntimeInteger(value)
    }
    clock.appendRuntimeInteger(Double(44_100).bitPattern)
    clock.appendRuntimeInteger(Double(48_000).bitPattern)
    let clockState = try AudioClockDeviceState(runtimePayload: clock)
    #expect(clockState.sampleRate == 48_000)
    #expect(clockState.availableSampleRates == [44_100, 48_000])
    #expect(clockState.transportState == .running)
    #expect(clockState.clockAlgorithm == .simpleIIR)
    #expect(clockState.clockIsStable && clockState.isAlive && clockState.supportsPrewarming)
    #expect(!clockState.isRunning)
    #expect(clockState.zeroTimestampPeriod == 512)
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioClockDeviceState(runtimePayload: clock.dropLast(8))
    }
  }

  @Test
  func decodesObjectEvents() throws {
    func event(_ kind: UInt32, _ index: UInt32, _ request: UInt32, _ value: UInt64) -> DriverEvent {
      var payload = Data()
      for field in [kind, index, request, 0] { payload.appendRuntimeInteger(field) }
      payload.appendRuntimeInteger(value)
      return DriverEvent(type: 0x0A01, payload: Array(payload))
    }
    #expect(try event(1, 42, 0, 3).audioObject() == .deviceStarted(objectID: 42, flags: 3))
    #expect(try event(4, 1, 0, 0).audioObject() == .clockDeviceStopped(index: 1, flags: 0))
    #expect(
      try event(5, 2, 0, Double(96_000).bitPattern).audioObject()
        == .clockDeviceSampleRateChanged(index: 2, sampleRate: 96_000)
    )
    #expect(
      try event(6, 0, 9, 1).audioObject()
        == .boxAcquisitionRequested(requestID: 9, box: 0, acquire: true)
    )
    #expect(
      try event(7, 3, 11, Double(44_100).bitPattern).audioObject()
        == .clockDeviceSampleRateRequested(requestID: 11, index: 3, sampleRate: 44_100)
    )
    #expect(throws: AudioRuntimeError.invalidPayload) { try event(6, 0, 0, 1).audioObject() }
    #expect(throws: AudioRuntimeError.invalidPayload) { try event(1, 0, 5, 1).audioObject() }
    #expect(throws: AudioRuntimeError.invalidPayload) { try event(6, 0, 1, 2).audioObject() }
    for kind: UInt32 in [0, 8] {
      #expect(throws: AudioRuntimeError.invalidEventKind(kind)) {
        try event(kind, 0, 0, 0).audioObject()
      }
    }
    #expect(try DriverEvent(type: 0x0A00, payload: []).audioObject() == nil)
  }
}
