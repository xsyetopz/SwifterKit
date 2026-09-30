import Foundation

/// A host request for a report that the generated HID device answers from Swift.
///
/// Answer every request exactly once with
/// ``DriverContext/completeHIDGetReport(_:bytes:status:)-(HIDGetReportRequest,_,_)``.
/// Requests still pending when the host detaches or the service stops complete with
/// `kIOReturnAborted`.
public struct HIDGetReportRequest: Sendable, Hashable {
  /// The runtime's identifier for this request.
  public let requestID: UInt32
  /// The requested report type.
  public let type: HIDReportType
  /// The requested report identifier, from the low byte of ``options``.
  public var reportID: UInt32 { options & 0xFF }
  /// HIDDriverKit option bits, with the report identifier in the low byte.
  public let options: UInt32
  /// The most report bytes the host accepts.
  public let capacity: UInt32
  /// The host's completion timeout in milliseconds.
  public let timeout: UInt32

  init(runtimePayload data: Data) throws {
    guard data.count == 24, try data.readRuntimeInteger(at: 20) as UInt32 == 0 else {
      throw HIDRuntimeError.invalidEventPayload
    }
    requestID = try data.readRuntimeInteger(at: 0)
    guard requestID != 0, let type = HIDReportType(rawValue: try data.readRuntimeInteger(at: 4))
    else { throw HIDRuntimeError.invalidEventPayload }
    self.type = type
    options = try data.readRuntimeInteger(at: 8)
    capacity = try data.readRuntimeInteger(at: 12)
    timeout = try data.readRuntimeInteger(at: 16)
    guard capacity > 0 else { throw HIDRuntimeError.invalidEventPayload }
  }
}

/// An LED change the host requested through `SetLEDState`.
public struct HIDLEDState: Sendable, Hashable {
  /// The LED's usage page.
  public let usagePage: UInt32
  /// The LED's usage.
  public let usage: UInt32
  /// Whether the LED is on.
  public let isOn: Bool

  init(runtimePayload data: Data) throws {
    guard data.count == 16, try data.readRuntimeInteger(at: 12) as UInt32 == 0 else {
      throw HIDRuntimeError.invalidEventPayload
    }
    let on: UInt32 = try data.readRuntimeInteger(at: 8)
    guard on <= 1 else { throw HIDRuntimeError.invalidEventPayload }
    usagePage = try data.readRuntimeInteger(at: 0)
    usage = try data.readRuntimeInteger(at: 4)
    isOn = on == 1
  }
}

/// The USB HID protocol an `IOUserUSBHostHIDDevice` selects with `setProtocol`.
public enum HIDDeviceProtocol: UInt32, Sendable, Hashable {
  /// The boot protocol.
  case boot = 0
  /// The report protocol.
  case report = 1
}

/// What an `IOUserUSBHostHIDDevice` idle policy applies to.
public enum HIDIdlePolicyTarget: UInt32, Sendable, Hashable {
  /// The USB interface.
  case interface = 0
  /// The input pipe.
  case pipe = 1
}

extension DriverCommand {
  /// Answers a host get-report request. A failure status carries no bytes.
  public static func completeHIDGetReport(
    _ request: HIDGetReportRequest,
    bytes: [UInt8],
    status: Int32 = 0
  ) throws -> Self {
    guard bytes.count <= min(Int(request.capacity), HIDLimits.maximumAnsweredReport),
      status == 0 || bytes.isEmpty
    else { throw HIDRuntimeError.invalidReportLength }
    var payload = Data(capacity: 16 + bytes.count)
    payload.appendRuntimeInteger(request.requestID)
    payload.appendRuntimeInteger(status)
    payload.append(HIDLimits.words([UInt32(bytes.count), 0]))
    payload.append(contentsOf: bytes)
    return Self(
      opcode: .hidCompleteGetReport,
      requiredCapabilities: .hid,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reads a report from a USB HID device through `IOUserUSBHostHIDDevice::getReport`.
  public static func hidDeviceReport(
    type: HIDReportType,
    reportID: UInt32 = 0,
    length: Int,
    options: UInt32 = 0,
    timeout: UInt32 = 0
  ) throws -> Self {
    guard options & 0xFF == 0 else { throw HIDRuntimeError.invalidReportID }
    return Self(
      opcode: .hidDeviceGetReport,
      requiredCapabilities: [.hid, .usb],
      payload: try HIDLimits.reportRequest(
        type: type,
        reportID: reportID,
        options: options,
        length: length,
        timeout: timeout
      ),
      maximumResponseSize: RuntimeMessage.headerSize + length
    )
  }

  /// Selects a USB HID device's protocol through `setProtocol`.
  public static func setHIDDeviceProtocol(_ deviceProtocol: HIDDeviceProtocol) -> Self {
    deviceSetting(.hidDeviceSetProtocol, 0, deviceProtocol.rawValue)
  }

  /// Sets a USB HID device's idle rate through `setIdle`.
  public static func setHIDDeviceIdle(milliseconds: UInt16) -> Self {
    deviceSetting(.hidDeviceSetIdle, 0, UInt32(milliseconds))
  }

  /// Sets a USB HID device's idle policy through `setIdlePolicy`.
  public static func setHIDDeviceIdlePolicy(
    _ target: HIDIdlePolicyTarget,
    milliseconds: UInt16
  ) -> Self { deviceSetting(.hidDeviceSetIdlePolicy, target.rawValue, UInt32(milliseconds)) }

  /// Resets a USB HID device through `reset`.
  public static let resetHIDDevice = Self(
    opcode: .hidDeviceReset,
    requiredCapabilities: [.hid, .usb],
    maximumResponseSize: RuntimeMessage.headerSize
  )

  private static func deviceSetting(
    _ opcode: RuntimeOpcode,
    _ kind: UInt32,
    _ value: UInt32
  ) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: [.hid, .usb],
      payload: HIDLimits.words([kind, value]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Answers a host get-report request. A failure status carries no bytes.
  public func completeHIDGetReport(
    _ request: HIDGetReportRequest,
    bytes: [UInt8],
    status: Int32 = 0
  ) async throws {
    _ = try await execute(.completeHIDGetReport(request, bytes: bytes, status: status))
  }

  /// Reads a report from a USB HID device through `IOUserUSBHostHIDDevice::getReport`.
  public func hidDeviceReport(
    type: HIDReportType,
    reportID: UInt32 = 0,
    length: Int,
    options: UInt32 = 0,
    timeout: UInt32 = 0
  ) async throws -> [UInt8] {
    let reply = try await execute(
      .hidDeviceReport(
        type: type,
        reportID: reportID,
        length: length,
        options: options,
        timeout: timeout
      )
    )
    guard reply.count <= length else { throw HIDRuntimeError.invalidReportPayload }
    return [UInt8](reply)
  }

  /// Selects a USB HID device's protocol through `setProtocol`.
  public func setHIDDeviceProtocol(_ deviceProtocol: HIDDeviceProtocol) async throws {
    _ = try await execute(.setHIDDeviceProtocol(deviceProtocol))
  }

  /// Sets a USB HID device's idle rate through `setIdle`.
  public func setHIDDeviceIdle(milliseconds: UInt16) async throws {
    _ = try await execute(.setHIDDeviceIdle(milliseconds: milliseconds))
  }

  /// Sets a USB HID device's idle policy through `setIdlePolicy`.
  public func setHIDDeviceIdlePolicy(
    _ target: HIDIdlePolicyTarget,
    milliseconds: UInt16
  ) async throws {
    _ = try await execute(.setHIDDeviceIdlePolicy(target, milliseconds: milliseconds))
  }

  /// Resets a USB HID device through `reset`.
  public func resetHIDDevice() async throws { _ = try await execute(.resetHIDDevice) }
}

extension DriverEvent {
  /// Decodes an input report a HID event service or USB HID device delivered.
  ///
  /// An event service puts the report identifier in ``HIDReport/options``. Returns nil when the
  /// event belongs to another capability family.
  public func hidInputReport() throws -> HIDReport? {
    guard type == RuntimeEventType.hidInputReport.rawValue else { return nil }
    return try HIDReport(runtimePayload: Data(payload))
  }

  /// Decodes the input element values one report updated.
  public func hidElementValues() throws -> HIDElementValues? {
    guard type == RuntimeEventType.hidElementValues.rawValue else { return nil }
    return try HIDElementValues(runtimePayload: Data(payload))
  }

  /// Decodes a host get-report request Swift must answer.
  public func hidGetReportRequest() throws -> HIDGetReportRequest? {
    guard type == RuntimeEventType.hidGetReportRequest.rawValue else { return nil }
    return try HIDGetReportRequest(runtimePayload: Data(payload))
  }

  /// Decodes an LED change the host requested.
  public func hidLEDState() throws -> HIDLEDState? {
    guard type == RuntimeEventType.hidLEDState.rawValue else { return nil }
    return try HIDLEDState(runtimePayload: Data(payload))
  }

  /// Decodes properties the host set through `SetProperties` or `setProperty`.
  public func hidProperties() throws -> [String: DriverProperty]? {
    guard type == RuntimeEventType.hidProperties.rawValue else { return nil }
    guard case .dictionary(let properties) = try ServicePropertyCoding.decode(Data(payload)) else {
      throw HIDRuntimeError.invalidEventPayload
    }
    return properties
  }
}
