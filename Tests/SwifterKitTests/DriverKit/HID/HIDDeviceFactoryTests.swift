import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDDeviceFactoryTests {
  private static let configuration = HIDDeviceConfiguration(
    reportDescriptor: [0x05, 0x01, 0x09, 0x05],
    transport: "Bluetooth",
    vendorID: 0x045E,
    productID: 0x02FD,
    versionNumber: 0x0408,
    countryCode: 3,
    locationID: 0x1234,
    manufacturer: "M",
    product: "Pad",
    serialNumber: "S1",
    primaryUsagePage: 1,
    primaryUsage: 5,
    acceptedHostReportTypes: .output,
    answeredReportTypes: .feature
  )

  private func event(_ type: RuntimeEventType, _ payload: Data) -> DriverEvent {
    DriverEvent(type: type.rawValue, payload: [UInt8](payload))
  }

  private func handle(_ value: UInt32) throws -> HIDDeviceHandle {
    try HIDDeviceHandle(rawValue: value)
  }

  @Test
  func encodesCreateDevice() throws {
    let command = try DriverCommand.createHIDDevice(Self.configuration)
    #expect(command.opcode == 0x0340)
    #expect(command.requiredCapabilities == .hid)
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 8)
    let header = HIDLimits.words([
      0x045E, 0x02FD, 0x0408, 3, 0x1234, 1, 5, 1, 4, 9, 1, 3, 2, 4, 0, 0,
    ])
    #expect(header.count == RuntimeHIDLimits.factoryDeviceHeaderSize)
    let strings = Data("BluetoothMPadS1".utf8)
    #expect(command.payload == header + strings + Data([0x05, 0x01, 0x09, 0x05]))
  }

  @Test
  func rejectsInvalidDeviceConfigurations() {
    let base = Self.configuration
    let invalid = [
      HIDDeviceConfiguration(
        reportDescriptor: [],
        vendorID: 1,
        productID: 2,
        manufacturer: "M",
        product: "P",
        serialNumber: "S",
        primaryUsagePage: 1,
        primaryUsage: 5
      ),
      HIDDeviceConfiguration(
        reportDescriptor: base.reportDescriptor,
        transport: "",
        vendorID: 1,
        productID: 2,
        manufacturer: "M",
        product: "P",
        serialNumber: "S",
        primaryUsagePage: 1,
        primaryUsage: 5
      ),
      HIDDeviceConfiguration(
        reportDescriptor: base.reportDescriptor,
        vendorID: 1,
        productID: 2,
        manufacturer: "M\0",
        product: "P",
        serialNumber: "S",
        primaryUsagePage: 1,
        primaryUsage: 5
      ),
      HIDDeviceConfiguration(
        reportDescriptor: base.reportDescriptor,
        vendorID: 1,
        productID: 2,
        manufacturer: "M",
        product: "P",
        serialNumber: "S",
        primaryUsagePage: 1,
        primaryUsage: 5,
        answeredReportTypes: HIDGetReportTypes(rawValue: 8)
      ),
      HIDDeviceConfiguration(
        reportDescriptor: [UInt8](repeating: 1, count: HIDLimits.maximumPayload),
        vendorID: 1,
        productID: 2,
        manufacturer: "M",
        product: "P",
        serialNumber: "S",
        primaryUsagePage: 1,
        primaryUsage: 5
      ),
    ]
    for configuration in invalid {
      #expect(throws: HIDRuntimeError.invalidDeviceConfiguration) {
        try DriverCommand.createHIDDevice(configuration)
      }
    }
  }

  @Test
  func acceptsDescriptorThatFillsOneMessage() throws {
    let fixed = RuntimeHIDLimits.factoryDeviceHeaderSize + "VirtualMPS".utf8.count
    let configuration = HIDDeviceConfiguration(
      reportDescriptor: [UInt8](repeating: 1, count: HIDLimits.maximumPayload - fixed),
      vendorID: 1,
      productID: 2,
      manufacturer: "M",
      product: "P",
      serialNumber: "S",
      primaryUsagePage: 1,
      primaryUsage: 5
    )
    #expect(
      try DriverCommand.createHIDDevice(configuration).payload.count == HIDLimits.maximumPayload
    )
  }

  @Test
  func decodesCreateReply() throws {
    #expect(try HIDDeviceHandle(runtimeReply: HIDLimits.words([7, 0])).rawValue == 7)
    for reply in [HIDLimits.words([0, 0]), HIDLimits.words([7, 1]), HIDLimits.words([7])] {
      #expect(throws: HIDRuntimeError.invalidEventPayload) {
        try HIDDeviceHandle(runtimeReply: reply)
      }
    }
  }

  @Test
  func encodesPerDeviceCommands() throws {
    let device = try handle(3)
    let terminate = DriverCommand.terminateHIDDevice(device)
    #expect(terminate.opcode == 0x0341)
    #expect(terminate.payload == HIDLimits.words([3, 0]))
    #expect(terminate.maximumResponseSize == RuntimeMessage.headerSize)

    let report = HIDReport(bytes: [1, 2], type: .input, options: 1, timestamp: 9)
    let submit = try DriverCommand.submitHIDInputReport(report, to: device)
    #expect(submit.opcode == 0x0342)
    #expect(submit.payload == HIDLimits.words([3, 0]) + (try report.encodedRuntimePayload()))
    #expect(throws: HIDRuntimeError.emptyReport) {
      try DriverCommand.submitHIDInputReport(HIDReport(bytes: [], type: .input), to: device)
    }
    #expect(throws: HIDRuntimeError.invalidReportType) {
      try DriverCommand.submitHIDInputReport(HIDReport(bytes: [1], type: .output), to: device)
    }

    let statistics = DriverCommand.hidRuntimeStatistics(for: device)
    #expect(statistics.opcode == 0x0344)
    #expect(statistics.payload == HIDLimits.words([3, 0]))
    #expect(statistics.maximumResponseSize == RuntimeMessage.headerSize + 24)
    for command in [terminate, submit, statistics] { #expect(command.requiredCapabilities == .hid) }
  }

  @Test
  func completesPerDeviceGetReports() throws {
    let request = try #require(
      try event(.hidFactoryGetReportRequest, HIDLimits.words([4, 0, 9, 2, 0x0105, 2, 100, 0]))
        .hidFactoryGetReportRequest()
    )
    #expect(request.device == (try handle(4)))
    #expect(request.request.requestID == 9)
    #expect(request.request.reportID == 5)

    let completion = try DriverCommand.completeHIDGetReport(request, bytes: [1, 2])
    #expect(completion.opcode == 0x0343)
    #expect(completion.payload == HIDLimits.words([4, 0, 9, 0, 2, 0]) + Data([1, 2]))
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.completeHIDGetReport(request, bytes: [1, 2, 3])
    }
    #expect(throws: HIDRuntimeError.invalidReportLength) {
      try DriverCommand.completeHIDGetReport(request, bytes: [1], status: -1)
    }
  }

  @Test
  func decodesHandleTaggedEvents() throws {
    let report = HIDReport(bytes: [0x0F, 1], type: .output, options: 3)
    let tagged = HIDLimits.words([2, 0]) + (try report.encodedRuntimePayload())
    let decoded = try #require(try event(.hidFactoryReport, tagged).hidFactoryReport())
    #expect(decoded.device == (try handle(2)))
    #expect(decoded.report == report)
    #expect(try event(.hidFactoryReport, tagged).hidReport() == nil)
    #expect(try event(.hidReport, try report.encodedRuntimePayload()).hidFactoryReport() == nil)

    let terminated = event(.hidFactoryDeviceTerminated, HIDLimits.words([6, 0]))
    #expect(try terminated.hidFactoryDeviceTerminated() == (try handle(6)))
    #expect(try terminated.hidFactoryReport() == nil)
  }

  @Test
  func rejectsMalformedHandleTaggedEvents() {
    let malformed: [(RuntimeEventType, Data)] = [
      (.hidFactoryDeviceTerminated, HIDLimits.words([0, 0])),
      (.hidFactoryDeviceTerminated, HIDLimits.words([1, 1])),
      (.hidFactoryDeviceTerminated, HIDLimits.words([1, 0, 0])),
      (.hidFactoryDeviceTerminated, HIDLimits.words([1])),
      (.hidFactoryGetReportRequest, HIDLimits.words([1, 0, 0, 2, 0, 2, 0, 0])),
      (.hidFactoryReport, HIDLimits.words([1, 0])),
    ]
    for (type, payload) in malformed {
      let event = event(type, payload)
      #expect(throws: (any Error).self) {
        _ = try event.hidFactoryDeviceTerminated()
        _ = try event.hidFactoryGetReportRequest()
        _ = try event.hidFactoryReport()
      }
    }
  }
}
