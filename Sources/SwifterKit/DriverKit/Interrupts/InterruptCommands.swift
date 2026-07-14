import Foundation

extension DriverCommand {
  /// Enables or disables delivery from a configured interrupt source.
  public static func setInterruptEnabled(index: UInt32, enabled: Bool) throws -> Self {
    try interruptCommand(
      opcode: 0x0100,
      index: index,
      enabled: enabled,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Queries the DriverKit interrupt type flags for a configured source.
  public static func interruptType(index: UInt32) throws -> Self {
    try interruptCommand(
      opcode: 0x0101,
      index: index,
      enabled: false,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  /// Queries the most recently observed count and timestamp.
  public static func lastInterrupt(index: UInt32) throws -> Self {
    try interruptCommand(
      opcode: 0x0102,
      index: index,
      enabled: false,
      maximumResponseSize: RuntimeMessage.headerSize + 16
    )
  }

  private static func interruptCommand(
    opcode: UInt32,
    index: UInt32,
    enabled: Bool,
    maximumResponseSize: Int
  ) throws -> Self {
    guard index <= UInt16.max else { throw InterruptRuntimeError.invalidSourceIndex }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(index)
    payload.append(enabled ? 1 : 0)
    payload.append(contentsOf: [0, 0, 0])
    return Self(
      opcode: opcode,
      requiredCapabilities: .interrupts,
      payload: payload,
      maximumResponseSize: maximumResponseSize
    )
  }
}

extension DriverContext {
  /// Enables or disables delivery from a configured hardware interrupt source.
  public func setInterruptEnabled(index: UInt32, enabled: Bool) async throws {
    _ = try await execute(.setInterruptEnabled(index: index, enabled: enabled))
  }

  /// Returns DriverKit's interrupt type flags for a configured source.
  public func interruptType(index: UInt32) async throws -> UInt64 {
    let payload = try await execute(.interruptType(index: index))
    guard payload.count == 8 else { throw InterruptRuntimeError.invalidPayload }
    return try payload.readRuntimeInteger(at: 0)
  }

  /// Returns the latest count and timestamp reported by DriverKit.
  public func lastInterrupt(index: UInt32) async throws -> InterruptSnapshot {
    try await InterruptSnapshot(runtimePayload: execute(.lastInterrupt(index: index)))
  }
}

extension DriverEvent {
  /// Decodes a hardware-interrupt event.
  ///
  /// Returns nil when the event belongs to another capability family.
  public func interrupt() throws -> InterruptEvent? {
    guard type == 0x0100 else { return nil }
    return try InterruptEvent(runtimePayload: Data(payload))
  }
}
