import Foundation

extension DriverCommand {
  /// Reads raw bytes from an AudioDriverKit stream ring buffer.
  public static func audioReadStream(index: UInt32, byteOffset: UInt64, length: Int) throws -> Self
  {
    guard index < 8 else { throw AudioRuntimeError.invalidStreamIndex }
    guard length > 0 else { throw AudioRuntimeError.invalidTransferRange }
    guard length <= 65_472 else { throw AudioRuntimeError.transferTooLarge }
    return Self(
      opcode: 0x0A00,
      requiredCapabilities: .audio,
      payload: audioTransferPayload(index: index, byteOffset: byteOffset, length: UInt32(length)),
      maximumResponseSize: RuntimeMessage.headerSize + length
    )
  }

  /// Writes raw bytes into an AudioDriverKit stream ring buffer.
  public static func audioWriteStream(index: UInt32, byteOffset: UInt64, bytes: Data) throws -> Self
  {
    guard index < 8 else { throw AudioRuntimeError.invalidStreamIndex }
    guard !bytes.isEmpty else { throw AudioRuntimeError.invalidTransferRange }
    guard bytes.count <= 65_472 else { throw AudioRuntimeError.transferTooLarge }
    var payload = audioTransferPayload(
      index: index,
      byteOffset: byteOffset,
      length: UInt32(bytes.count)
    )
    payload.append(bytes)
    return Self(
      opcode: 0x0A01,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Requests the latest lock-free real-time I/O snapshot.
  public static func audioGetIOState() -> Self {
    Self(
      opcode: 0x0A02,
      requiredCapabilities: .audio,
      maximumResponseSize: RuntimeMessage.headerSize + 32
    )
  }

  /// Updates the device zero timestamp from the hardware clock.
  public static func audioUpdateTimestamp(sampleTime: UInt64, hostTime: UInt64) -> Self {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(sampleTime)
    payload.appendRuntimeInteger(hostTime)
    return Self(
      opcode: 0x0A03,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Requests a host-coordinated device sample-rate change.
  public static func audioRequestSampleRate(_ sampleRate: Double) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(sampleRate.bitPattern)
    return Self(
      opcode: 0x0A04,
      requiredCapabilities: .audio,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  private static func audioTransferPayload(index: UInt32, byteOffset: UInt64, length: UInt32)
    -> Data
  {
    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(index)
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(byteOffset)
    payload.appendRuntimeInteger(length)
    payload.appendRuntimeInteger(UInt32(0))
    return payload
  }
}

extension DriverContext {
  /// Reads raw bytes from a stream ring buffer.
  public func audioReadStream(index: UInt32, byteOffset: UInt64, length: Int) async throws -> Data {
    try await execute(.audioReadStream(index: index, byteOffset: byteOffset, length: length))
  }

  /// Writes raw bytes into a stream ring buffer.
  public func audioWriteStream(index: UInt32, byteOffset: UInt64, bytes: Data) async throws {
    _ = try await execute(.audioWriteStream(index: index, byteOffset: byteOffset, bytes: bytes))
  }

  /// Returns the latest real-time I/O operation snapshot.
  public func audioIOState() async throws -> AudioIOState {
    try AudioIOState(runtimePayload: await execute(.audioGetIOState()))
  }

  /// Reports a hardware-derived zero timestamp.
  public func audioUpdateTimestamp(sampleTime: UInt64, hostTime: UInt64) async throws {
    _ = try await execute(.audioUpdateTimestamp(sampleTime: sampleTime, hostTime: hostTime))
  }

  /// Requests a host-coordinated sample-rate change.
  public func audioRequestSampleRate(_ sampleRate: Double) async throws {
    _ = try await execute(.audioRequestSampleRate(sampleRate))
  }
}

extension DriverEvent {
  /// Decodes an AudioDriverKit lifecycle or format event.
  public func audio() throws -> AudioEvent? {
    guard type == 0x0A00 else { return nil }
    return try AudioEvent(runtimePayload: Data(payload))
  }
}
