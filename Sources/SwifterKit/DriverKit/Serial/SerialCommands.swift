import Foundation

extension DriverCommand {
  /// Enqueues bytes received from serial hardware for terminal clients.
  public static func serialEnqueueReceive(_ bytes: [UInt8]) throws -> Self {
    guard !bytes.isEmpty else { throw SerialRuntimeError.emptyReceiveData }
    guard bytes.count <= 65_496 else { throw SerialRuntimeError.transferTooLarge }
    return Self(
      opcode: 0x0600,
      requiredCapabilities: .serial,
      payload: Data(bytes),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Requests up to `maximumLength` bytes waiting for hardware transmission.
  public static func serialDequeueTransmit(maximumLength: Int) throws -> Self {
    guard maximumLength > 0 else { throw SerialRuntimeError.invalidTransferLength }
    guard maximumLength <= 65_512 else { throw SerialRuntimeError.transferTooLarge }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(UInt32(maximumLength))
    return Self(
      opcode: 0x0601,
      requiredCapabilities: .serial,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + maximumLength
    )
  }

  /// Updates hardware modem-input signals reported to SerialDriverKit.
  public static func serialSetModemStatus(_ status: SerialModemStatus) -> Self {
    Self(
      opcode: 0x0602,
      requiredCapabilities: .serial,
      payload: status.runtimePayload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Reports receive errors to SerialDriverKit.
  public static func serialReportReceiveErrors(_ errors: SerialReceiveErrors) -> Self {
    Self(
      opcode: 0x0603,
      requiredCapabilities: .serial,
      payload: Data([errors.rawValue, 0, 0, 0]),
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Enqueues bytes received from serial hardware for terminal clients.
  public func serialEnqueueReceive(_ bytes: [UInt8]) async throws {
    _ = try await execute(.serialEnqueueReceive(bytes))
  }

  /// Removes bytes waiting for transmission to serial hardware.
  public func serialDequeueTransmit(maximumLength: Int) async throws -> [UInt8] {
    Array(try await execute(.serialDequeueTransmit(maximumLength: maximumLength)))
  }

  /// Updates hardware modem-input signals reported to SerialDriverKit.
  public func serialSetModemStatus(_ status: SerialModemStatus) async throws {
    _ = try await execute(.serialSetModemStatus(status))
  }

  /// Reports receive errors to SerialDriverKit.
  public func serialReportReceiveErrors(_ errors: SerialReceiveErrors) async throws {
    _ = try await execute(.serialReportReceiveErrors(errors))
  }
}

extension DriverEvent {
  /// Decodes a SerialDriverKit hardware request.
  ///
  /// Returns nil when the event belongs to another capability family.
  public func serial() throws -> SerialEvent? {
    guard type == 0x0600 else { return nil }
    return try SerialEvent(runtimePayload: Data(payload))
  }
}
