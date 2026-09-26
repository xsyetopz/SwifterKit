import Foundation
import Testing

@testable import SwifterKit

@Suite
struct MIDIObjectCommandsTests {
  @Test
  func encodesObjectTargetsAndNames() throws {
    let info = try DriverCommand.midiObjectInfo(.destination(3))
    #expect(info.opcode == 0x0810)
    #expect(info.requiredCapabilities == .midi)
    #expect(info.payload == bytes(u32(4), u32(3)))
    #expect(info.maximumResponseSize == RuntimeMessage.headerSize + 24 + 255)

    let rename = try DriverCommand.midiSetObjectName(.driver, name: "Keys")
    #expect(rename.opcode == 0x0811)
    #expect(rename.payload == bytes(u32(0), u32(0), u32(4), u32(0), Data("Keys".utf8)))
    #expect(try DriverCommand.midiObjectInfo(.object(9)).payload == bytes(u32(5), u32(9)))
    #expect(try DriverCommand.midiObjectInfo(.entity).payload == bytes(u32(2), u32(0)))
  }

  @Test
  func rejectsInvalidTargetsAndNames() {
    #expect(throws: MIDIRuntimeError.invalidObjectTarget) {
      try DriverCommand.midiObjectInfo(.source(32))
    }
    #expect(throws: MIDIRuntimeError.invalidObjectTarget) {
      try DriverCommand.midiObjectInfo(.object(0))
    }
    #expect(throws: MIDIRuntimeError.invalidObjectTarget) {
      try DriverCommand.midiProperties(.driver)
    }
    #expect(throws: MIDIRuntimeError.invalidName) {
      try DriverCommand.midiSetObjectName(.device, name: "")
    }
    #expect(throws: MIDIRuntimeError.invalidName) {
      try DriverCommand.midiSetObjectName(.device, name: String(repeating: "a", count: 256))
    }
    #expect(throws: MIDIRuntimeError.invalidPropertyKey) {
      try DriverCommand.midiCopyProperty(.device, key: .custom("a\u{0}b"))
    }
    #expect(throws: MIDIRuntimeError.invalidPropertyKey) {
      try DriverCommand.midiPropertyType(.device, property: MIDIProperty(rawValue: 0))
    }
  }

  @Test
  func encodesPropertyKeysAndValues() throws {
    #expect(MIDIProperty.name.rawValue == 0x6D6E_616D)
    #expect(MIDIProperty.associatedEndpoint.rawValue == 0x6165_7074)

    let type = try DriverCommand.midiPropertyType(.source(1), property: .uniqueID)
    #expect(type.opcode == 0x0812)
    #expect(type.payload == bytes(u32(3), u32(1), u32(0), u32(0x6D75_6964)))

    let copy = try DriverCommand.midiCopyProperty(.entity, key: .custom("Owner"))
    #expect(copy.opcode == 0x0813)
    #expect(copy.payload == bytes(u32(2), u32(0), u32(1), u32(5), Data("Owner".utf8)))
    #expect(copy.maximumResponseSize == RuntimeMessage.maximumSize)

    let set = try DriverCommand.midiSetProperty(
      .device,
      key: .property(.uniqueID),
      value: .int32(-2)
    )
    #expect(set.opcode == 0x0814)
    #expect(set.payload == bytes(u32(1), u32(0), u32(0), u32(0x6D75_6964), number(-2, bits: 32)))
  }

  @Test
  func encodesNestedDictionariesWithSortedKeys() throws {
    let command = try DriverCommand.midiSetProperties(
      .device,
      ["b": .data(Data([7])), "a": .array([.string("x")])]
    )
    #expect(command.opcode == 0x0816)
    let array = bytes(u32(4), u32(17), u32(1), u32(0), u32(0), u32(1), Data("x".utf8))
    let data = bytes(u32(3), u32(1), Data([7]))
    let body = bytes(u32(2), u32(0), u32(1), u32(0), Data("a".utf8), array)
    let entries = bytes(body, u32(1), u32(0), Data("b".utf8), data)
    #expect(command.payload == bytes(u32(1), u32(0), u32(2), u32(UInt32(entries.count)), entries))
  }

  @Test
  func rejectsInvalidValues() {
    #expect(throws: MIDIRuntimeError.invalidPropertyValue) {
      try DriverCommand.midiSetProperty(.device, key: .property(.name), value: .number(1, bits: 12))
    }
    #expect(throws: MIDIRuntimeError.invalidPropertyValue) {
      try DriverCommand.midiSetProperty(
        .device,
        key: .property(.name),
        value: .number(128, bits: 8)
      )
    }
    #expect(throws: MIDIRuntimeError.invalidPropertyValue) {
      try DriverCommand.midiSetProperty(.device, key: .property(.name), value: .string("a\u{0}"))
    }
    var nested = MIDIPropertyValue.string("leaf")
    for _ in 0..<4 { nested = .array([nested]) }
    #expect(throws: MIDIRuntimeError.invalidPropertyValue) {
      try DriverCommand.midiSetProperties(.device, ["deep": nested])
    }
    #expect(throws: MIDIRuntimeError.propertyValueTooLarge) {
      try DriverCommand.midiSetProperty(
        .device,
        key: .property(.image),
        value: .data(Data(count: RuntimeMessage.maximumSize))
      )
    }
  }

  @Test
  func roundTripsPropertyValues() throws {
    let value = MIDIPropertyValue.dictionary([
      "name": .string("Pad"), "id": .number(-5, bits: 64), "small": .number(-1, bits: 8),
      "blob": .data(Data([1, 2])), "entities": .array([.dictionary(["x": .int32(Int32.min)])]),
    ])
    #expect(try MIDIPropertyValue(runtimePayload: value.runtimePayload()) == value)
  }

  @Test
  func rejectsMalformedPropertyValues() {
    let malformed: [Data] = [
      bytes(u32(9), u32(0)), bytes(u32(0), u32(4), Data("ab".utf8)),
      bytes(u32(1), u32(16), u32(32), u32(0), u64(0x1_0000_0000)),
      bytes(u32(1), u32(16), u32(12), u32(0), u64(0)), bytes(u32(2), u32(8), u32(1), u32(0)),
      bytes(u32(3), u32(1), Data([1, 2])), bytes(u32(2), u32(8), u32(0), u32(1)),
    ]
    for payload in malformed {
      #expect(throws: MIDIRuntimeError.self) { try MIDIPropertyValue(runtimePayload: payload) }
    }
    // Two entries with the same key.
    let entry = bytes(u32(1), u32(0), Data("k".utf8), u32(3), u32(0))
    let body = bytes(u32(2), u32(0), entry, entry)
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try MIDIPropertyValue(runtimePayload: bytes(u32(2), u32(UInt32(body.count)), body))
    }
  }

  @Test
  func encodesDeviceAndMembershipCommands() throws {
    #expect(DriverCommand.midiDeviceState().opcode == 0x0817)
    #expect(DriverCommand.midiDeviceState().payload.isEmpty)
    #expect(DriverCommand.midiEntityMembers().opcode == 0x0818)
    let detach = try DriverCommand.midiSetMemberAttachment(.source(2), attached: false)
    #expect(detach.opcode == 0x0819)
    #expect(detach.payload == bytes(u32(3), u32(2), u32(0), u32(0)))
    let attach = try DriverCommand.midiSetMemberAttachment(.entity, attached: true)
    #expect(attach.payload == bytes(u32(2), u32(0), u32(1), u32(0)))
    #expect(throws: MIDIRuntimeError.invalidObjectTarget) {
      try DriverCommand.midiSetMemberAttachment(.destination(40), attached: true)
    }
  }

  @Test
  func decodesObjectInfo() throws {
    let source = try MIDIObjectInfo(
      runtimePayload: bytes(u32(7), u32(4), u32(1), u32(3), u32(3), u32(0), Data("Out".utf8))
    )
    #expect(source.objectID == 7)
    #expect(source.ownerObjectID == 4)
    #expect(source.classID == .source)
    #expect(source.baseClassID == .endpoint)
    #expect(source.name == "Out")

    let driver = try MIDIObjectInfo(
      runtimePayload: bytes(u32(1), u32(0), u32(.max), u32(.max), u32(0), u32(0))
    )
    #expect(driver.classID == nil)
    #expect(driver.name.isEmpty)

    let malformed: [Data] = [
      bytes(u32(7), u32(4), u32(9), u32(3), u32(0), u32(0)),
      bytes(u32(7), u32(4), u32(1), u32(.max), u32(0), u32(0)),
      bytes(u32(2), u32(0), u32(.max), u32(.max), u32(0), u32(0)),
      bytes(u32(7), u32(4), u32(1), u32(3), u32(4), u32(0), Data("Out".utf8)),
      bytes(u32(0), u32(4), u32(1), u32(3), u32(0), u32(0)),
      bytes(u32(7), u32(4), u32(1), u32(3), u32(0), u32(1)),
    ]
    for payload in malformed {
      #expect(throws: MIDIRuntimeError.invalidPayload) {
        try MIDIObjectInfo(runtimePayload: payload)
      }
    }
  }

  @Test
  func decodesDeviceStateAndEntityMembers() throws {
    let state = try MIDIDeviceState(runtimePayload: bytes(u32(1), u32(2), u32(4), u32(9)))
    #expect(state.isRunning)
    #expect(state.entityObjectIDs == [4, 9])
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try MIDIDeviceState(runtimePayload: bytes(u32(2), u32(0)))
    }
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try MIDIDeviceState(runtimePayload: bytes(u32(0), u32(1), u32(0)))
    }
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try MIDIDeviceState(runtimePayload: bytes(u32(0), u32(65)))
    }

    let members = try MIDIEntityMembers(
      runtimePayload: bytes(u32(1), u32(3), u32(5), u32(6), u32(7))
    )
    #expect(members.sourceObjectIDs == [5])
    #expect(members.destinationObjectIDs == [6, 7])
    #expect(throws: MIDIRuntimeError.invalidPayload) {
      try MIDIEntityMembers(runtimePayload: bytes(u32(2), u32(1), u32(5)))
    }
  }

  private func number(_ value: Int64, bits: UInt32) -> Data {
    bytes(
      u32(1),
      u32(16),
      u32(bits),
      u32(0),
      u64(UInt64(bitPattern: value) & (bits == 64 ? .max : (1 << UInt64(bits)) - 1))
    )
  }

  private func u32(_ value: UInt32) -> Data {
    var data = Data()
    data.appendRuntimeInteger(value)
    return data
  }

  private func u64(_ value: UInt64) -> Data {
    var data = Data()
    data.appendRuntimeInteger(value)
    return data
  }

  private func bytes(_ parts: Data...) -> Data { parts.reduce(into: Data()) { $0.append($1) } }
}
