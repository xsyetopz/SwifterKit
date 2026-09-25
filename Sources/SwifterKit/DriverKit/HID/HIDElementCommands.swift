import Foundation

/// Limits shared by the HID command encoders; the native runtime enforces the same bounds.
enum HIDLimits {
  /// The most element descriptors one page carries.
  static let maximumElementPage: UInt32 = 512
  /// The most cookies one commit names.
  static let maximumCommitCookies = 1_024
  /// The most elements one digitizer collection names.
  static let maximumCollectionElements = 64
  /// The most touches one dispatch carries.
  static let maximumTouches = 64
  /// Command payload bytes that fit one runtime message.
  static let maximumPayload =
    RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize - RuntimeSchema.commandHeaderSize
  /// Report bytes that fit after a 32-byte report request.
  static let maximumReportLength = maximumPayload - 32
  /// Report bytes Swift can return for a host get-report request.
  static let maximumAnsweredReport = maximumPayload - 16

  static func reportRequest(
    type: HIDReportType,
    reportID: UInt32,
    options: UInt32,
    length: Int,
    timestamp: UInt64 = 0,
    timeout: UInt32 = 0
  ) throws -> Data {
    guard reportID <= 0xFF else { throw HIDRuntimeError.invalidReportID }
    guard length > 0, length <= maximumReportLength else {
      throw HIDRuntimeError.invalidReportLength
    }
    var payload = Data(capacity: 32 + length)
    payload.appendRuntimeInteger(timestamp)
    payload.appendRuntimeInteger(type.rawValue)
    payload.appendRuntimeInteger(reportID)
    payload.appendRuntimeInteger(options)
    payload.appendRuntimeInteger(UInt32(length))
    payload.appendRuntimeInteger(timeout)
    payload.appendRuntimeInteger(UInt32(0))
    return payload
  }

  static func words(_ values: [UInt32]) -> Data {
    var payload = Data(capacity: values.count * 4)
    for value in values { payload.appendRuntimeInteger(value) }
    return payload
  }

  static func flag(from reply: Data) throws -> Bool {
    guard reply.count == 4 else { throw HIDRuntimeError.invalidElementPayload }
    let value: UInt32 = try reply.readRuntimeInteger(at: 0)
    guard value <= 1 else { throw HIDRuntimeError.invalidElementPayload }
    return value == 1
  }

  static func validCookie(_ cookie: UInt32) throws -> UInt32 {
    guard cookie != 0 else { throw HIDRuntimeError.invalidCookie }
    return cookie
  }
}

extension DriverCommand {
  /// Reads one page of the provider interface's element tree.
  public static func hidElements(firstIndex: UInt32, maximumCount: UInt32) throws -> Self {
    guard (1...HIDLimits.maximumElementPage).contains(maximumCount) else {
      throw HIDRuntimeError.invalidItemCount
    }
    return Self(
      opcode: .hidCopyElements,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([firstIndex, maximumCount]),
      maximumResponseSize: RuntimeMessage.headerSize + 8 + Int(maximumCount)
        * HIDElement.encodedSize
    )
  }

  /// Reads one element's value and its scaled forms.
  public static func hidElementValue(
    cookie: UInt32,
    options: UInt32 = 0,
    scale: HIDValueScaleType = .calibrated
  ) throws -> Self {
    Self(
      opcode: .hidGetElementValue,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([try HIDLimits.validCookie(cookie), options, scale.rawValue, 0]),
      maximumResponseSize: RuntimeMessage.headerSize + 24
    )
  }

  /// Sets one element's integer value; commit it to reach the device.
  public static func setHIDElementValue(_ value: UInt32, cookie: UInt32) throws -> Self {
    Self(
      opcode: .hidSetElementValue,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([try HIDLimits.validCookie(cookie), 0, value, 0]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Sets one element's data value; commit it to reach the device.
  public static func setHIDElementData(_ bytes: [UInt8], cookie: UInt32) throws -> Self {
    guard !bytes.isEmpty, bytes.count <= HIDLimits.maximumPayload - 16 else {
      throw HIDRuntimeError.invalidReportLength
    }
    var payload = HIDLimits.words([try HIDLimits.validCookie(cookie), 1, 0, UInt32(bytes.count)])
    payload.append(contentsOf: bytes)
    return Self(
      opcode: .hidSetElementValue,
      requiredCapabilities: .hid,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Commits one element through `IOHIDElement::commit`.
  public static func commitHIDElement(
    cookie: UInt32,
    direction: HIDElementCommitDirection
  ) throws -> Self {
    Self(
      opcode: .hidCommitElement,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([try HIDLimits.validCookie(cookie), direction.rawValue]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Commits several elements at once through `IOHIDInterface::commitElements`.
  public static func commitHIDElements(
    cookies: [UInt32],
    direction: HIDElementCommitDirection
  ) throws -> Self {
    guard !cookies.isEmpty, cookies.count <= HIDLimits.maximumCommitCookies else {
      throw HIDRuntimeError.invalidItemCount
    }
    guard !cookies.contains(0), Set(cookies).count == cookies.count else {
      throw HIDRuntimeError.invalidCookie
    }
    return Self(
      opcode: .hidCommitElements,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([direction.rawValue, UInt32(cookies.count)] + cookies),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Asks `IOHIDElement::conformsTo` whether an element matches a usage.
  public static func hidElementConforms(
    cookie: UInt32,
    usagePage: UInt32,
    usage: UInt32 = 0
  ) throws -> Self {
    Self(
      opcode: .hidElementConformsTo,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([try HIDLimits.validCookie(cookie), usagePage, usage, 0]),
      maximumResponseSize: RuntimeMessage.headerSize + 4
    )
  }

  /// Reads a report from the provider interface through `IOHIDInterface::GetReport`.
  public static func hidInterfaceReport(
    type: HIDReportType,
    reportID: UInt32 = 0,
    length: Int,
    options: UInt32 = 0
  ) throws -> Self {
    Self(
      opcode: .hidInterfaceGetReport,
      requiredCapabilities: .hid,
      payload: try HIDLimits.reportRequest(
        type: type,
        reportID: reportID,
        options: options,
        length: length
      ),
      maximumResponseSize: RuntimeMessage.headerSize + length
    )
  }

  /// Sends a report to the provider interface through `IOHIDInterface::SetReport`.
  public static func setHIDInterfaceReport(
    _ bytes: [UInt8],
    type: HIDReportType,
    reportID: UInt32 = 0,
    options: UInt32 = 0
  ) throws -> Self {
    var payload = try HIDLimits.reportRequest(
      type: type,
      reportID: reportID,
      options: options,
      length: bytes.count
    )
    payload.append(contentsOf: bytes)
    return Self(
      opcode: .hidInterfaceSetReport,
      requiredCapabilities: .hid,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Parses a report into the interface's element values through
  /// `IOHIDInterface::processReport`, without dispatching events.
  public static func processHIDInterfaceReport(
    _ bytes: [UInt8],
    type: HIDReportType = .input,
    reportID: UInt32 = 0,
    timestamp: UInt64 = 0
  ) throws -> Self {
    var payload = try HIDLimits.reportRequest(
      type: type,
      reportID: reportID,
      options: 0,
      length: bytes.count,
      timestamp: timestamp
    )
    payload.append(contentsOf: bytes)
    return Self(
      opcode: .hidInterfaceProcessReport,
      requiredCapabilities: .hid,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Reads one page of the provider interface's element tree.
  public func hidElements(
    firstIndex: UInt32,
    maximumCount: UInt32 = 512
  ) async throws -> HIDElementPage {
    try HIDElementPage(
      runtimePayload: await execute(
        .hidElements(firstIndex: firstIndex, maximumCount: maximumCount)
      ),
      maximumCount: maximumCount
    )
  }

  /// Reads the provider interface's whole element tree, one page per runtime message.
  public func hidElements() async throws -> [HIDElement] {
    var elements: [HIDElement] = []
    while true {
      let page = try await hidElements(firstIndex: UInt32(elements.count))
      elements += page.elements
      if elements.count >= Int(page.totalCount) { return elements }
      guard !page.elements.isEmpty else { throw HIDRuntimeError.invalidElementPayload }
    }
  }

  /// Reads one element's value and its scaled forms.
  public func hidElementValue(
    cookie: UInt32,
    options: UInt32 = 0,
    scale: HIDValueScaleType = .calibrated
  ) async throws -> HIDElementValue {
    try HIDElementValue(
      runtimePayload: await execute(
        .hidElementValue(cookie: cookie, options: options, scale: scale)
      )
    )
  }

  /// Sets one element's integer value; commit it to reach the device.
  public func setHIDElementValue(_ value: UInt32, cookie: UInt32) async throws {
    _ = try await execute(.setHIDElementValue(value, cookie: cookie))
  }

  /// Sets one element's data value; commit it to reach the device.
  public func setHIDElementData(_ bytes: [UInt8], cookie: UInt32) async throws {
    _ = try await execute(.setHIDElementData(bytes, cookie: cookie))
  }

  /// Commits one element through `IOHIDElement::commit`.
  public func commitHIDElement(cookie: UInt32, direction: HIDElementCommitDirection) async throws {
    _ = try await execute(.commitHIDElement(cookie: cookie, direction: direction))
  }

  /// Commits several elements at once through `IOHIDInterface::commitElements`.
  public func commitHIDElements(
    cookies: [UInt32],
    direction: HIDElementCommitDirection
  ) async throws {
    _ = try await execute(.commitHIDElements(cookies: cookies, direction: direction))
  }

  /// Asks `IOHIDElement::conformsTo` whether an element matches a usage.
  public func hidElementConforms(
    cookie: UInt32,
    usagePage: UInt32,
    usage: UInt32 = 0
  ) async throws -> Bool {
    try HIDLimits.flag(
      from: await execute(.hidElementConforms(cookie: cookie, usagePage: usagePage, usage: usage))
    )
  }

  /// Reads a report from the provider interface through `IOHIDInterface::GetReport`.
  public func hidInterfaceReport(
    type: HIDReportType,
    reportID: UInt32 = 0,
    length: Int,
    options: UInt32 = 0
  ) async throws -> [UInt8] {
    let reply = try await execute(
      .hidInterfaceReport(type: type, reportID: reportID, length: length, options: options)
    )
    guard reply.count == length else { throw HIDRuntimeError.invalidReportPayload }
    return [UInt8](reply)
  }

  /// Sends a report to the provider interface through `IOHIDInterface::SetReport`.
  public func setHIDInterfaceReport(
    _ bytes: [UInt8],
    type: HIDReportType,
    reportID: UInt32 = 0,
    options: UInt32 = 0
  ) async throws {
    _ = try await execute(
      .setHIDInterfaceReport(bytes, type: type, reportID: reportID, options: options)
    )
  }

  /// Parses a report into the interface's element values through
  /// `IOHIDInterface::processReport`, without dispatching events.
  public func processHIDInterfaceReport(
    _ bytes: [UInt8],
    type: HIDReportType = .input,
    reportID: UInt32 = 0,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .processHIDInterfaceReport(bytes, type: type, reportID: reportID, timestamp: timestamp)
    )
  }
}
