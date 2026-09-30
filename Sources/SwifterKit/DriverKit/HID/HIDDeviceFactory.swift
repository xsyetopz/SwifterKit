import Foundation

/// A generated root service that creates virtual HID devices at run time.
///
/// The root is an `IOService`, usually on `IOUserResources`. Each device it creates is an
/// `AppleUserHIDDevice` child with its own ``HIDDeviceConfiguration``. Every device belongs to
/// the client that receives events and terminates when that client detaches.
public struct HIDDeviceFactoryConfiguration: Sendable, Hashable {
  /// The valid range of ``maximumDevices``.
  public static let deviceLimit = 1...RuntimeHIDLimits.maximumFactoryDevices

  /// The number of devices that may exist at once. Creating one more fails.
  public let maximumDevices: Int

  /// Creates a factory configuration.
  public init(maximumDevices: Int) { self.maximumDevices = maximumDevices }
}

/// A virtual HID device that a generated HID device factory created at run time.
///
/// The runtime assigns handles. A handle is never reused while the extension's service runs.
public struct HIDDeviceHandle: Sendable, Hashable {
  /// The runtime's identifier for the device.
  public let rawValue: UInt32

  init(rawValue: UInt32) throws {
    guard rawValue != 0 else { throw HIDRuntimeError.invalidEventPayload }
    self.rawValue = rawValue
  }

  /// Decodes a `hidFactoryCreateDevice` reply: the handle and a reserved zero word.
  init(runtimeReply data: Data) throws {
    guard data.count == RuntimeHIDLimits.factoryHandleSize,
      try data.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw HIDRuntimeError.invalidEventPayload }
    try self.init(rawValue: data.readRuntimeInteger(at: 0))
  }
}

/// An output or feature report the host set on a device a factory created.
public struct HIDDeviceReport: Sendable, Hashable {
  /// The device the host addressed.
  public let device: HIDDeviceHandle
  /// The report the host set.
  public let report: HIDReport
}

/// A host get-report request for a device a factory created.
///
/// Answer every request exactly once with the `DriverContext.completeHIDGetReport(_:bytes:status:)`
/// overload that takes this type.
/// Requests still pending when the device terminates complete with `kIOReturnAborted`.
public struct HIDDeviceGetReportRequest: Sendable, Hashable {
  /// The device the host addressed.
  public let device: HIDDeviceHandle
  /// The request, with an identifier unique within ``device``.
  public let request: HIDGetReportRequest
}

extension HIDDeviceConfiguration {
  /// The `hidFactoryCreateDevice` payload: a 64-byte header, the UTF-8 transport,
  /// manufacturer, product, and serial number, then the report descriptor.
  func encodedFactoryPayload() throws -> Data {
    let strings = [transport, manufacturer, product, serialNumber].map { Array($0.utf8) }
    let size =
      RuntimeHIDLimits.factoryDeviceHeaderSize + strings.reduce(0) { $0 + $1.count }
      + reportDescriptor.count
    guard hasValidFields, size <= HIDLimits.maximumPayload else {
      throw HIDRuntimeError.invalidDeviceConfiguration
    }
    let fields = [
      vendorID, productID, versionNumber, countryCode, locationID, primaryUsagePage, primaryUsage,
      acceptedHostReportTypes.rawValue, answeredReportTypes.rawValue,
    ]
    var payload = Data(capacity: size)
    payload.append(HIDLimits.words(fields + strings.map { UInt32($0.count) }))
    payload.append(HIDLimits.words([UInt32(reportDescriptor.count), 0, 0]))
    for string in strings { payload.append(contentsOf: string) }
    payload.append(contentsOf: reportDescriptor)
    return payload
  }
}

extension DriverCommand {
  /// Creates a virtual HID device through the generated HID device factory.
  public static func createHIDDevice(_ configuration: HIDDeviceConfiguration) throws -> Self {
    Self(
      opcode: .hidFactoryCreateDevice,
      requiredCapabilities: .hid,
      payload: try configuration.encodedFactoryPayload(),
      maximumResponseSize: RuntimeMessage.headerSize + RuntimeHIDLimits.factoryHandleSize
    )
  }

  /// Terminates a device the HID device factory created.
  public static func terminateHIDDevice(_ device: HIDDeviceHandle) -> Self {
    Self(
      opcode: .hidFactoryTerminateDevice,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([device.rawValue, 0]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Submits an input report through a device the HID device factory created.
  public static func submitHIDInputReport(
    _ report: HIDReport,
    to device: HIDDeviceHandle
  ) throws -> Self {
    guard !report.bytes.isEmpty else { throw HIDRuntimeError.emptyReport }
    guard report.type == .input else { throw HIDRuntimeError.invalidReportType }
    return Self(
      opcode: .hidFactorySubmitInputReport,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([device.rawValue, 0]) + (try report.encodedRuntimePayload()),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Answers a host get-report request for a device the factory created. A failure status
  /// carries no bytes.
  public static func completeHIDGetReport(
    _ request: HIDDeviceGetReportRequest,
    bytes: [UInt8],
    status: Int32 = 0
  ) throws -> Self {
    let completion = try completeHIDGetReport(request.request, bytes: bytes, status: status)
    guard completion.payload.count + RuntimeHIDLimits.factoryHandleSize <= HIDLimits.maximumPayload
    else { throw HIDRuntimeError.invalidReportLength }
    return Self(
      opcode: .hidFactoryCompleteGetReport,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([request.device.rawValue, 0]) + completion.payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads the input-report delivery counters of a device the factory created.
  public static func hidRuntimeStatistics(for device: HIDDeviceHandle) -> Self {
    Self(
      opcode: .hidFactoryGetRuntimeStatistics,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([device.rawValue, 0]),
      maximumResponseSize: RuntimeMessage.headerSize + 24
    )
  }
}

extension DriverContext {
  /// Creates a virtual HID device and returns its handle.
  ///
  /// Only the client that receives events may create devices. The factory terminates every
  /// device a client created when that client detaches, closes, or crashes.
  public func createHIDDevice(
    _ configuration: HIDDeviceConfiguration
  ) async throws -> HIDDeviceHandle {
    try HIDDeviceHandle(runtimeReply: await execute(.createHIDDevice(configuration)))
  }

  /// Terminates a device the factory created. Its pending get-report requests complete with
  /// `kIOReturnAborted`.
  public func terminateHIDDevice(_ device: HIDDeviceHandle) async throws {
    _ = try await execute(.terminateHIDDevice(device))
  }

  /// Submits one input report through a device the factory created.
  public func submitHIDInputReport(_ report: HIDReport, to device: HIDDeviceHandle) async throws {
    _ = try await execute(.submitHIDInputReport(report, to: device))
  }

  /// Answers a host get-report request for a device the factory created.
  public func completeHIDGetReport(
    _ request: HIDDeviceGetReportRequest,
    bytes: [UInt8],
    status: Int32 = 0
  ) async throws {
    _ = try await execute(.completeHIDGetReport(request, bytes: bytes, status: status))
  }

  /// Reads the input-report delivery counters of a device the factory created.
  public func hidRuntimeStatistics(for device: HIDDeviceHandle) async throws -> HIDRuntimeStatistics
  { try HIDRuntimeStatistics(runtimePayload: await execute(.hidRuntimeStatistics(for: device))) }
}

extension DriverEvent {
  /// Decodes an output or feature report the host set on a device the factory created.
  ///
  /// Returns nil when the event belongs to another capability family.
  public func hidFactoryReport() throws -> HIDDeviceReport? {
    guard type == RuntimeEventType.hidFactoryReport.rawValue else { return nil }
    let (device, body) = try factoryHandle()
    return HIDDeviceReport(device: device, report: try HIDReport(runtimePayload: body))
  }

  /// Decodes a host get-report request for a device the factory created.
  public func hidFactoryGetReportRequest() throws -> HIDDeviceGetReportRequest? {
    guard type == RuntimeEventType.hidFactoryGetReportRequest.rawValue else { return nil }
    let (device, body) = try factoryHandle()
    return HIDDeviceGetReportRequest(
      device: device,
      request: try HIDGetReportRequest(runtimePayload: body)
    )
  }

  /// Decodes the handle of a device the system terminated without a Swift request.
  public func hidFactoryDeviceTerminated() throws -> HIDDeviceHandle? {
    guard type == RuntimeEventType.hidFactoryDeviceTerminated.rawValue else { return nil }
    let (device, body) = try factoryHandle()
    guard body.isEmpty else { throw HIDRuntimeError.invalidEventPayload }
    return device
  }

  private func factoryHandle() throws -> (HIDDeviceHandle, Data) {
    let data = Data(payload)
    guard data.count >= RuntimeHIDLimits.factoryHandleSize,
      try data.readRuntimeInteger(at: 4) as UInt32 == 0
    else { throw HIDRuntimeError.invalidEventPayload }
    let handle = try HIDDeviceHandle(rawValue: data.readRuntimeInteger(at: 0))
    return (handle, Data(data.dropFirst(RuntimeHIDLimits.factoryHandleSize)))
  }
}
