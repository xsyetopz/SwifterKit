import Foundation

extension DriverCommand {
  /// Creates a synchronous USB control-transfer command.
  public static func usbControlTransfer(
    _ request: USBControlRequest,
    data: [UInt8] = [],
    timeout: UInt32 = 5_000
  ) throws -> Self {
    try validateUSBTransfer(direction: request.direction, length: Int(request.length), data: data)

    var payload = Data(capacity: 16 + data.count)
    payload.append(request.requestType)
    payload.append(request.request)
    payload.appendRuntimeInteger(request.value)
    payload.appendRuntimeInteger(request.index)
    payload.appendRuntimeInteger(request.length)
    payload.appendRuntimeInteger(timeout)
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(contentsOf: data)
    return Self(
      opcode: 0x0200,
      requiredCapabilities: .usb,
      payload: payload,
      maximumResponseSize: usbMaximumResponseSize(
        direction: request.direction,
        length: Int(request.length)
      )
    )
  }

  /// Creates a synchronous device-to-host USB pipe-transfer command.
  public static func usbPipeRead(endpoint: UInt8, length: Int, timeout: UInt32 = 5_000) throws
    -> Self
  {
    guard USBTransferDirection(encodedByte: endpoint) == .in else {
      throw USBRuntimeError.directionMismatch
    }
    return try usbPipeTransfer(endpoint: endpoint, length: length, data: [], timeout: timeout)
  }

  /// Creates a synchronous host-to-device USB pipe-transfer command.
  public static func usbPipeWrite(endpoint: UInt8, data: [UInt8], timeout: UInt32 = 5_000) throws
    -> Self
  {
    guard USBTransferDirection(encodedByte: endpoint) == .out else {
      throw USBRuntimeError.directionMismatch
    }
    return try usbPipeTransfer(endpoint: endpoint, length: data.count, data: data, timeout: timeout)
  }

  /// Creates a command that clears an endpoint halt condition.
  public static func usbClearStall(endpoint: UInt8, withRequest: Bool = true) -> Self {
    Self(
      opcode: 0x0202,
      requiredCapabilities: .usb,
      payload: Data([endpoint, withRequest ? 1 : 0, 0, 0]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Creates a command that selects an interface alternate setting.
  public static func usbSelectAlternateSetting(_ alternateSetting: UInt8) -> Self {
    Self(
      opcode: 0x0203,
      requiredCapabilities: .usb,
      payload: Data([alternateSetting, 0, 0, 0]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  private static func usbPipeTransfer(endpoint: UInt8, length: Int, data: [UInt8], timeout: UInt32)
    throws -> Self
  {
    let direction = USBTransferDirection(encodedByte: endpoint)
    guard length > 0 else { throw USBRuntimeError.emptyTransfer }
    try validateUSBTransfer(direction: direction, length: length, data: data)
    guard length <= Int(UInt32.max) else { throw USBRuntimeError.transferTooLarge }

    var payload = Data(capacity: 16 + data.count)
    payload.append(endpoint)
    payload.append(0)
    payload.appendRuntimeInteger(UInt16(0))
    payload.appendRuntimeInteger(UInt32(length))
    payload.appendRuntimeInteger(timeout)
    payload.appendRuntimeInteger(UInt32(0))
    payload.append(contentsOf: data)
    return Self(
      opcode: 0x0201,
      requiredCapabilities: .usb,
      payload: payload,
      maximumResponseSize: usbMaximumResponseSize(direction: direction, length: length)
    )
  }

  private static func validateUSBTransfer(
    direction: USBTransferDirection,
    length: Int,
    data: [UInt8]
  ) throws {
    let maximumLength = direction == .in ? 65_508 : 65_480
    guard length >= 0, length <= maximumLength else { throw USBRuntimeError.transferTooLarge }
    switch direction {
    case .in: guard data.isEmpty else { throw USBRuntimeError.directionMismatch }
    case .out: guard data.count == length else { throw USBRuntimeError.invalidOutputLength }
    }
  }

  private static func usbMaximumResponseSize(direction: USBTransferDirection, length: Int) -> Int {
    RuntimeMessage.headerSize + 4 + (direction == .in ? length : 0)
  }
}

extension DriverContext {
  /// Performs a synchronous control transfer through USBDriverKit.
  public func usbControlTransfer(
    _ request: USBControlRequest,
    data: [UInt8] = [],
    timeout: UInt32 = 5_000
  ) async throws -> USBTransferResult {
    let response = try await execute(.usbControlTransfer(request, data: data, timeout: timeout))
    return try USBTransferResult(runtimePayload: response)
  }

  /// Reads from a bulk or interrupt IN endpoint.
  public func usbRead(endpoint: UInt8, length: Int, timeout: UInt32 = 5_000) async throws
    -> USBTransferResult
  {
    let response = try await execute(
      .usbPipeRead(endpoint: endpoint, length: length, timeout: timeout)
    )
    return try USBTransferResult(runtimePayload: response)
  }

  /// Writes to a bulk or interrupt OUT endpoint.
  public func usbWrite(endpoint: UInt8, data: [UInt8], timeout: UInt32 = 5_000) async throws
    -> USBTransferResult
  {
    let response = try await execute(
      .usbPipeWrite(endpoint: endpoint, data: data, timeout: timeout)
    )
    return try USBTransferResult(runtimePayload: response)
  }

  /// Clears a USB endpoint halt condition.
  public func usbClearStall(endpoint: UInt8, withRequest: Bool = true) async throws {
    _ = try await execute(.usbClearStall(endpoint: endpoint, withRequest: withRequest))
  }

  /// Selects the active alternate setting for the matched USB interface.
  public func usbSelectAlternateSetting(_ alternateSetting: UInt8) async throws {
    _ = try await execute(.usbSelectAlternateSetting(alternateSetting))
  }
}
