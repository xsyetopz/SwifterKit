import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDElementCommandsTests {
  private func words(_ data: Data) throws -> [UInt32] {
    try stride(from: 0, to: data.count, by: 4).map { try data.readRuntimeInteger(at: $0) }
  }

  @Test
  func encodesElementCommands() throws {
    let page = try DriverCommand.hidElements(firstIndex: 10, maximumCount: 2)
    #expect(page.opcode == RuntimeOpcode.hidCopyElements.rawValue)
    #expect(page.requiredCapabilities == .hid)
    #expect(try words(page.payload) == [10, 2])
    #expect(page.maximumResponseSize == RuntimeMessage.headerSize + 8 + 160)

    let value = try DriverCommand.hidElementValue(cookie: 7, options: 1, scale: .physical)
    #expect(try words(value.payload) == [7, 1, 1, 0])
    #expect(try words(DriverCommand.setHIDElementValue(9, cookie: 3).payload) == [3, 0, 9, 0])

    let data = try DriverCommand.setHIDElementData([0xAA, 0xBB], cookie: 4)
    #expect(try words(data.payload.prefix(16)) == [4, 1, 0, 2])
    #expect(Array(data.payload.suffix(2)) == [0xAA, 0xBB])

    let commit = try DriverCommand.commitHIDElement(cookie: 5, direction: .output)
    #expect(try words(commit.payload) == [5, 1])
    let batch = try DriverCommand.commitHIDElements(cookies: [1, 2, 3], direction: .input)
    #expect(try words(batch.payload) == [0, 3, 1, 2, 3])
    let conforms = try DriverCommand.hidElementConforms(cookie: 2, usagePage: 1, usage: 6)
    #expect(try words(conforms.payload) == [2, 1, 6, 0])
  }

  @Test
  func encodesInterfaceReports() throws {
    let get = try DriverCommand.hidInterfaceReport(type: .feature, reportID: 3, length: 8)
    #expect(get.opcode == RuntimeOpcode.hidInterfaceGetReport.rawValue)
    #expect(get.payload.count == 32)
    #expect(try get.payload.readRuntimeInteger(at: 0) as UInt64 == 0)
    #expect(try words(get.payload.suffix(24)) == [2, 3, 0, 8, 0, 0])
    #expect(get.maximumResponseSize == RuntimeMessage.headerSize + 8)

    let set = try DriverCommand.setHIDInterfaceReport([1, 2, 3], type: .output, reportID: 1)
    #expect(set.payload.count == 35)
    #expect(Array(set.payload.suffix(3)) == [1, 2, 3])

    let process = try DriverCommand.processHIDInterfaceReport([9], reportID: 2, timestamp: 42)
    #expect(try process.payload.readRuntimeInteger(at: 0) as UInt64 == 42)
    #expect(try words(process.payload.subdata(in: 8..<32)) == [0, 2, 0, 1, 0, 0])
  }

  @Test
  func rejectsMalformedElementArguments() {
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.hidElements(firstIndex: 0, maximumCount: 0)
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.hidElements(firstIndex: 0, maximumCount: 513)
    }
    #expect(throws: HIDRuntimeError.invalidCookie) { try DriverCommand.hidElementValue(cookie: 0) }
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.setHIDElementData([], cookie: 1)
    }
    #expect(throws: HIDRuntimeError.invalidCookie) {
      try DriverCommand.commitHIDElements(cookies: [1, 1], direction: .input)
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.commitHIDElements(cookies: [], direction: .input)
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.commitHIDElements(cookies: Array(1...1_025), direction: .input)
    }
    #expect(throws: HIDRuntimeError.invalidReportID) {
      try DriverCommand.hidInterfaceReport(type: .input, reportID: 256, length: 1)
    }
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.hidInterfaceReport(type: .input, length: 0)
    }
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.setHIDInterfaceReport(
        [UInt8](repeating: 0, count: HIDLimits.maximumReportLength + 1),
        type: .output
      )
    }
  }

  @Test
  func decodesElementPagesAndValues() throws {
    var data = Data()
    data.append(HIDLimits.words([3, 1]))
    data.append(
      HIDLimits.words([7, 2, 2, 0, 1, 0x30, 0xFFFF_FF81, 127, 0, 0, 0, 0, 1, 8, 1, 2, 5, 0])
    )
    data.appendRuntimeInteger(UInt64(99))
    let page = try HIDElementPage(runtimePayload: data, maximumCount: 4)
    #expect(page.totalCount == 3)
    let element = try #require(page.elements.first)
    #expect(element.cookie == 7)
    #expect(element.parentCookie == 2)
    #expect(element.type == .inputButton)
    #expect(element.type.isInput)
    #expect(element.usagePage == 1)
    #expect(element.usage == 0x30)
    #expect(Int32(bitPattern: element.logicalMinimum) == -127)
    #expect(element.reportID == 1)
    #expect(element.value == 5)
    #expect(element.timestamp == 99)

    #expect(throws: HIDRuntimeError.invalidElementPayload) {
      try HIDElementPage(runtimePayload: data.prefix(80), maximumCount: 4)
    }
    #expect(throws: HIDRuntimeError.invalidElementPayload) {
      try HIDElementPage(runtimePayload: data, maximumCount: 0)
    }

    var value = HIDLimits.words([5, 6])
    value.appendRuntimeInteger(Int32(-32_768))
    value.appendRuntimeInteger(UInt32(0))
    value.appendRuntimeInteger(UInt64(12))
    let decoded = try HIDElementValue(runtimePayload: value)
    #expect(decoded.value == 5)
    #expect(decoded.scaledValue == 6)
    #expect(decoded.scaledFixedValue == -0.5)
    #expect(decoded.timestamp == 12)
    #expect(throws: HIDRuntimeError.invalidElementPayload) {
      try HIDElementValue(runtimePayload: value.prefix(20))
    }
  }

  @Test
  func convertsFixedPoint() throws {
    #expect(try HIDFixed.raw(1) == 65_536)
    #expect(try HIDFixed.raw(-0.5) == -32_768)
    #expect(HIDFixed.double(98_304) == 1.5)
    #expect(throws: HIDRuntimeError.valueOutOfRange) { try HIDFixed.raw(40_000) }
    #expect(throws: HIDRuntimeError.valueOutOfRange) { try HIDFixed.raw(.nan) }
  }

  @Test
  func encodesElementDataValueRead() throws {
    let command = try DriverCommand.hidElementDataValue(cookie: 7, options: 2)
    #expect(command.opcode == 0x0345)
    #expect(command.requiredCapabilities == .hid)
    #expect(command.payload == Data([7, 0, 0, 0, 2, 0, 0, 0]))
    #expect(command.maximumResponseSize == RuntimeMessage.maximumSize)
    #expect(throws: HIDRuntimeError.invalidCookie) {
      try DriverCommand.hidElementDataValue(cookie: 0)
    }
  }
}
