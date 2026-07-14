import Foundation
import Testing

@testable import SwifterKit

@Suite struct AudioControlCommandsTests {
  @Test func encodesTypedControlCommands() throws {
    let get = DriverCommand.audioGetControl(identifier: 9, as: .scalar)
    #expect(get.opcode == 0x0A05)
    #expect(get.payload == Data([9, 0, 0, 0, 3, 0, 0, 0]))

    let set = try DriverCommand.audioSetControl(identifier: 9, value: .selector([4, 7]))
    #expect(set.opcode == 0x0A06)
    #expect(set.requiredCapabilities == .audio)
    #expect(set.payload.count == 24)
    #expect(set.payload.prefix(16) == Data([9, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test func decodesEveryControlValueRepresentation() throws {
    #expect(try decode(kind: 1, values: [1]) == .boolean(true))
    #expect(try decode(kind: 2, values: [Float(-6).bitPattern]) == .decibels(-6))
    #expect(try decode(kind: 3, values: [Float(0.5).bitPattern]) == .scalar(0.5))
    #expect(try decode(kind: 4, values: [2, 3]) == .selector([2, 3]))
    #expect(try decode(kind: 5, values: [42]) == .slider(42))
    #expect(try decode(kind: 6, values: [Float(-0.25).bitPattern]) == .stereoPan(-0.25))
  }

  @Test func encodesBoundedStringCustomProperties() throws {
    let get = try DriverCommand.audioGetCustomProperty(identifier: 2, qualifier: "Mode")
    #expect(get.opcode == 0x0A07)
    #expect(get.payload.count == 20)

    let set = try DriverCommand.audioSetCustomProperty(
      identifier: 2,
      qualifier: "Mode",
      value: "Studio"
    )
    #expect(set.opcode == 0x0A08)
    #expect(set.payload.suffix(10) == Data("ModeStudio".utf8))
  }

  @Test func decodesHostControlAndCustomPropertyEvents() throws {
    var control = Data()
    control.appendRuntimeInteger(UInt32(4))
    control.appendRuntimeInteger(UInt32(9))
    control.appendRuntimeInteger(UInt32(2))
    control.appendRuntimeInteger(UInt32(1))
    control.appendRuntimeInteger(UInt32(0))
    control.appendRuntimeInteger(Float(-12).bitPattern)
    #expect(
      try DriverEvent(type: 0x0A00, payload: Array(control)).audio()
        == .controlChanged(identifier: 9, value: .decibels(-12))
    )

    var property = Data()
    property.appendRuntimeInteger(UInt32(5))
    property.appendRuntimeInteger(UInt32(7))
    property.appendRuntimeInteger(UInt32(4))
    property.appendRuntimeInteger(UInt32(6))
    property.appendRuntimeInteger(UInt32(0))
    property.append(Data("ModeStudio".utf8))
    #expect(
      try DriverEvent(type: 0x0A00, payload: Array(property)).audio()
        == .customPropertyChanged(identifier: 7, qualifier: "Mode", value: "Studio")
    )
  }

  @Test func rejectsMalformedControlAndPropertyValues() {
    #expect(throws: AudioRuntimeError.invalidControlValue) {
      try DriverCommand.audioSetControl(identifier: 1, value: .selector([]))
    }
    #expect(throws: AudioRuntimeError.invalidCustomPropertyValue) {
      try DriverCommand.audioGetCustomProperty(identifier: 1, qualifier: "")
    }
    #expect(throws: AudioRuntimeError.invalidPayload) {
      try AudioControlValue(runtimePayload: Data(repeating: 0, count: 15))
    }
  }

  private func decode(kind: UInt32, values: [UInt32]) throws -> AudioControlValue {
    var data = Data()
    data.appendRuntimeInteger(UInt32(9))
    data.appendRuntimeInteger(kind)
    data.appendRuntimeInteger(UInt32(values.count))
    data.appendRuntimeInteger(UInt32(0))
    for value in values { data.appendRuntimeInteger(value) }
    return try AudioControlValue(runtimePayload: data)
  }
}
