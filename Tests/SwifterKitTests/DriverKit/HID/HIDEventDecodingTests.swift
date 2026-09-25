import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDEventDecodingTests {
  private func event(_ type: RuntimeEventType, _ payload: Data) -> DriverEvent {
    DriverEvent(type: type.rawValue, payload: [UInt8](payload))
  }

  @Test
  func decodesInputReportsAndElementValues() throws {
    let report = HIDReport(bytes: [1, 2, 3], type: .input, options: 4, timestamp: 8)
    let input = event(.hidInputReport, try report.encodedRuntimePayload())
    #expect(try input.hidInputReport() == report)
    #expect(try input.hidReport() == nil)
    #expect(try input.hidElementValues() == nil)

    var values = Data()
    values.appendRuntimeInteger(UInt64(77))
    values.append(HIDLimits.words([2, 2, 10, 1, 11, 0]))
    let decoded = try #require(try event(.hidElementValues, values).hidElementValues())
    #expect(decoded.timestamp == 77)
    #expect(decoded.reportID == 2)
    #expect(decoded.values == [10: 1, 11: 0])

    var duplicate = Data()
    duplicate.appendRuntimeInteger(UInt64(1))
    duplicate.append(HIDLimits.words([0, 2, 10, 1, 10, 0]))
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidElementValues, duplicate).hidElementValues()
    }
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidElementValues, values.prefix(20)).hidElementValues()
    }
  }

  @Test
  func decodesRequestsLEDsAndProperties() throws {
    let request = try #require(
      try event(.hidGetReportRequest, HIDLimits.words([9, 2, 0x0105, 64, 100, 0]))
        .hidGetReportRequest()
    )
    #expect(request.requestID == 9)
    #expect(request.type == .feature)
    #expect(request.reportID == 5)
    #expect(request.capacity == 64)
    #expect(request.timeout == 100)
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidGetReportRequest, HIDLimits.words([0, 2, 0, 64, 0, 0])).hidGetReportRequest()
    }
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidGetReportRequest, HIDLimits.words([1, 3, 0, 64, 0, 0])).hidGetReportRequest()
    }

    let led = try #require(try event(.hidLEDState, HIDLimits.words([8, 2, 1, 0])).hidLEDState())
    #expect(led.usagePage == 8)
    #expect(led.usage == 2)
    #expect(led.isOn)
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidLEDState, HIDLimits.words([8, 2, 2, 0])).hidLEDState()
    }

    let properties = try ServicePropertyCoding.encode(.dictionary(["HIDKeyRepeat": .boolean(true)]))
    #expect(
      try event(.hidProperties, properties).hidProperties() == ["HIDKeyRepeat": .boolean(true)]
    )
    #expect(throws: HIDRuntimeError.invalidEventPayload) {
      try event(.hidProperties, try ServicePropertyCoding.encode(.boolean(true))).hidProperties()
    }
  }

  @Test
  func encodesDeviceCommands() throws {
    let request = try HIDGetReportRequest(runtimePayload: HIDLimits.words([3, 2, 1, 4, 0, 0]))
    let completion = try DriverCommand.completeHIDGetReport(request, bytes: [1, 2])
    #expect(completion.opcode == RuntimeOpcode.hidCompleteGetReport.rawValue)
    #expect(completion.payload == HIDLimits.words([3, 0, 2, 0]) + Data([1, 2]))
    let failure = try DriverCommand.completeHIDGetReport(request, bytes: [], status: -1)
    #expect(try failure.payload.readRuntimeInteger(at: 4) as Int32 == -1)
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.completeHIDGetReport(request, bytes: [1, 2, 3, 4, 5])
    }
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.completeHIDGetReport(request, bytes: [1], status: -1)
    }

    let get = try DriverCommand.hidDeviceReport(type: .input, reportID: 1, length: 8, timeout: 50)
    #expect(get.requiredCapabilities == [.hid, .usb])
    #expect(get.payload.count == 32)
    #expect(try get.payload.readRuntimeInteger(at: 24) as UInt32 == 50)
    #expect(throws: HIDRuntimeError.invalidReportID) {
      try DriverCommand.hidDeviceReport(type: .input, length: 8, options: 0x01)
    }

    #expect(DriverCommand.setHIDDeviceProtocol(.boot).payload == HIDLimits.words([0, 0]))
    #expect(DriverCommand.setHIDDeviceIdle(milliseconds: 500).payload == HIDLimits.words([0, 500]))
    #expect(
      DriverCommand.setHIDDeviceIdlePolicy(.pipe, milliseconds: 20).payload
        == HIDLimits.words([1, 20])
    )
    #expect(DriverCommand.resetHIDDevice.payload.isEmpty)
    #expect(DriverCommand.resetHIDDevice.opcode == RuntimeOpcode.hidDeviceReset.rawValue)
  }
}
