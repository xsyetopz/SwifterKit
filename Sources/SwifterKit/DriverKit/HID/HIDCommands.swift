import Foundation

extension DriverCommand {
  /// Submits an input report through a generated virtual HID device.
  public static func submitHIDInputReport(_ report: HIDReport) throws -> Self {
    guard !report.bytes.isEmpty else { throw HIDRuntimeError.emptyReport }
    guard report.type == .input else { throw HIDRuntimeError.invalidReportType }
    return Self(
      opcode: 0x0300,
      requiredCapabilities: .hid,
      payload: try report.encodedRuntimePayload(),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads extension-side HID input-report delivery counters.
  public static let hidRuntimeStatistics = Self(
    opcode: 0x0301,
    requiredCapabilities: .hid,
    maximumResponseSize: RuntimeMessage.headerSize + 24
  )
}

extension DriverContext {
  /// Submits one input report through HIDDriverKit.
  public func submitHIDInputReport(_ report: HIDReport) async throws {
    _ = try await execute(.submitHIDInputReport(report))
  }

  /// Reads extension-side HID input-report delivery counters.
  public func hidRuntimeStatistics() async throws -> HIDRuntimeStatistics {
    try HIDRuntimeStatistics(runtimePayload: await execute(.hidRuntimeStatistics))
  }
}

extension DriverEvent {
  /// Decodes a HID output or feature report event.
  ///
  /// Returns nil when the event belongs to another capability family.
  public func hidReport() throws -> HIDReport? {
    guard type == 0x0300 else { return nil }
    return try HIDReport(runtimePayload: Data(payload))
  }
}
