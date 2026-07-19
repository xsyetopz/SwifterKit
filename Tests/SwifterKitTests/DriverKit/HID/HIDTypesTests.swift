import Foundation
import Testing

@testable import SwifterKit

@Suite struct HIDTypesTests {
  @Test func configuresAcceptedHostReportTypes() {
    #expect(HIDHostReportTypes.all == [.output, .feature])
    #expect(HIDHostReportTypes.output.rawValue == 1)
    #expect(HIDHostReportTypes.feature.rawValue == 2)
    #expect(hidConfiguration.acceptedHostReportTypes == .all)

    let outputOnly = HIDDeviceConfiguration(
      reportDescriptor: [0xC0],
      vendorID: 1,
      productID: 2,
      manufacturer: "Example",
      product: "Output-only HID",
      serialNumber: "1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1,
      acceptedHostReportTypes: .output
    )
    #expect(outputOnly.acceptedHostReportTypes == .output)
  }

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

  @Test func decodesRuntimeStatisticsAndConfiguresCommand() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt64(12))
    payload.appendRuntimeInteger(UInt64(10))
    payload.appendRuntimeInteger(UInt64(2))

    #expect(
      try HIDRuntimeStatistics(runtimePayload: payload)
        == HIDRuntimeStatistics(
          inputReportAttempts: 12,
          inputReportSuccesses: 10,
          inputReportFailures: 2
        )
    )
    #expect(DriverCommand.hidRuntimeStatistics.opcode == 0x0301)
    #expect(DriverCommand.hidRuntimeStatistics.requiredCapabilities == .hid)
  }

  @Test func rejectsMalformedRuntimeStatistics() {
    #expect(throws: HIDRuntimeError.invalidStatisticsPayload) {
      try HIDRuntimeStatistics(runtimePayload: Data([1]))
    }
  }

  @Test func decodesOnlyHIDEvents() throws {
    let report = HIDReport(bytes: [5], type: .output)
    let event = DriverEvent(type: 0x0300, payload: Array(try report.encodedRuntimePayload()))

    #expect(try event.hidReport() == report)
    #expect(try DriverEvent(type: 99).hidReport() == nil)
  }

  private var hidConfiguration: HIDDeviceConfiguration {
    HIDDeviceConfiguration(
      reportDescriptor: [0xC0],
      vendorID: 1,
      productID: 2,
      manufacturer: "Example",
      product: "Default HID",
      serialNumber: "1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1
    )
  }
}
