import Foundation
import Testing

@testable import SwifterKit

@Suite struct HIDTypesTests {
  @Test func roundTripsRuntimeReportPayload() throws {
    let report = HIDReport(bytes: [1, 2, 3], type: .output, options: 7, timestamp: 42)

    #expect(try HIDReport(runtimePayload: report.encodedRuntimePayload()) == report)
  }

  @Test func rejectsMalformedRuntimeReportPayload() throws {
    var payload = try HIDReport(bytes: [1], type: .feature).encodedRuntimePayload()
    payload.removeLast()

    #expect(throws: HIDRuntimeError.invalidReportPayload) { try HIDReport(runtimePayload: payload) }
  }

  @Test func commandRequiresHIDAndInputDirection() throws {
    let command = try DriverCommand.submitHIDInputReport(HIDReport(bytes: [9, 8], type: .input))

    #expect(command.opcode == 0x0300)
    #expect(command.requiredCapabilities == .hid)
    #expect(throws: HIDRuntimeError.emptyReport) {
      try DriverCommand.submitHIDInputReport(HIDReport(bytes: [], type: .input))
    }
    #expect(throws: HIDRuntimeError.invalidReportType) {
      try DriverCommand.submitHIDInputReport(HIDReport(bytes: [1], type: .output))
    }
  }

  @Test func decodesOnlyHIDEvents() throws {
    let report = HIDReport(bytes: [5], type: .output)
    let event = DriverEvent(type: 0x0300, payload: Array(try report.encodedRuntimePayload()))

    #expect(try event.hidReport() == report)
    #expect(try DriverEvent(type: 99).hidReport() == nil)
  }
}
