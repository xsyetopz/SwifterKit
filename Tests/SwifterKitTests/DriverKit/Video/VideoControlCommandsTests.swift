import Foundation
import Testing

@testable import SwifterKit

@Suite struct VideoControlCommandsTests {
  @Test func encodesTypedControlCommands() throws {
    let get = DriverCommand.videoGetControl(identifier: 9, as: .scalar)
    #expect(get.opcode == 0x0C07)
    #expect(get.payload == Data([9, 0, 0, 0, 3, 0, 0, 0]))

    let set = try DriverCommand.videoSetControl(identifier: 9, value: .selector([4, 7]))
    #expect(set.opcode == 0x0C08)
    #expect(set.requiredCapabilities == .video)
    #expect(set.payload.count == 24)
    #expect(set.payload.prefix(16) == Data([9, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test func decodesEveryControlValueRepresentation() throws {
    #expect(try decode(kind: 1, values: [1]) == .boolean(true))
    #expect(try decode(kind: 7, values: [1]) == .direction(true))
    #expect(try decode(kind: 2, values: [Float(-6).bitPattern]) == .decibels(-6))
    #expect(try decode(kind: 3, values: [Float(0.5).bitPattern]) == .scalar(0.5))
    #expect(try decode(kind: 4, values: [2, 3]) == .selector([2, 3]))
    #expect(try decode(kind: 5, values: [42]) == .slider(42))
    #expect(try decode(kind: 6, values: [Float(-0.25).bitPattern]) == .stereoPan(-0.25))
  }

  @Test func encodesBoundedStringCustomProperties() throws {
    let get = try DriverCommand.videoGetCustomProperty(identifier: 2, qualifier: "Mode")
    #expect(get.opcode == 0x0C09)
    #expect(get.payload.count == 20)

    let set = try DriverCommand.videoSetCustomProperty(
      identifier: 2,
      qualifier: "Mode",
      value: "Studio"
    )
    #expect(set.opcode == 0x0C0A)
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
      try DriverEvent(type: 0x0C00, payload: Array(control)).video()
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
      try DriverEvent(type: 0x0C00, payload: Array(property)).video()
        == .customPropertyChanged(identifier: 7, qualifier: "Mode", value: "Studio")
    )
  }

  @Test func rejectsMalformedControlAndPropertyValues() {
    #expect(throws: VideoRuntimeError.invalidControlValue) {
      try DriverCommand.videoSetControl(identifier: 1, value: .selector([]))
    }
    #expect(throws: VideoRuntimeError.invalidCustomPropertyValue) {
      try DriverCommand.videoGetCustomProperty(identifier: 1, qualifier: "")
    }
    #expect(throws: VideoRuntimeError.invalidPayload) {
      try VideoControlValue(runtimePayload: Data(repeating: 0, count: 15))
    }
  }

  private func decode(kind: UInt32, values: [UInt32]) throws -> VideoControlValue {
    var data = Data()
    data.appendRuntimeInteger(UInt32(9))
    data.appendRuntimeInteger(kind)
    data.appendRuntimeInteger(UInt32(values.count))
    data.appendRuntimeInteger(UInt32(0))
    for value in values { data.appendRuntimeInteger(value) }
    return try VideoControlValue(runtimePayload: data)
  }
}
