import Foundation

extension DriverCommand {
  /// Reads bytes from a native video buffer plane.
  public static func videoReadBuffer(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    plane: VideoBufferPlane = .data,
    byteOffset: UInt32 = 0,
    length: Int
  ) throws -> Self {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    guard bufferIndex < 32 else { throw VideoRuntimeError.invalidBufferIndex }
    guard length > 0 else { throw VideoRuntimeError.invalidTransferRange }
    guard length <= 65_464 else { throw VideoRuntimeError.transferTooLarge }
    return Self(
      opcode: 0x0C00,
      requiredCapabilities: .video,
      payload: videoTransferPayload(
        streamIndex: streamIndex,
        bufferIndex: bufferIndex,
        plane: plane,
        byteOffset: byteOffset,
        length: UInt32(length)
      ),
      maximumResponseSize: RuntimeMessage.headerSize + length
    )
  }

  /// Writes bytes into a native video buffer plane.
  public static func videoWriteBuffer(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    plane: VideoBufferPlane = .data,
    byteOffset: UInt32 = 0,
    bytes: Data
  ) throws -> Self {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    guard bufferIndex < 32 else { throw VideoRuntimeError.invalidBufferIndex }
    guard !bytes.isEmpty else { throw VideoRuntimeError.invalidTransferRange }
    guard bytes.count <= 65_432 else { throw VideoRuntimeError.transferTooLarge }
    var payload = videoTransferPayload(
      streamIndex: streamIndex,
      bufferIndex: bufferIndex,
      plane: plane,
      byteOffset: byteOffset,
      length: UInt32(bytes.count)
    )
    payload.append(bytes)
    return Self(opcode: 0x0C01, requiredCapabilities: .video, payload: payload)
  }

  /// Enqueues a completed output entry for the host.
  public static func videoEnqueueOutput(streamIndex: UInt32, entry: VideoBufferQueueEntry) throws
    -> Self
  {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    guard entry.bufferIndex < 32 else { throw VideoRuntimeError.invalidBufferIndex }
    var payload = Data(capacity: 36)
    payload.appendRuntimeInteger(streamIndex)
    payload.append(videoEntryPayload(entry))
    return Self(opcode: 0x0C02, requiredCapabilities: .video, payload: payload)
  }

  /// Dequeues an input entry supplied by the host.
  public static func videoDequeueInput(streamIndex: UInt32) throws -> Self {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(streamIndex)
    return Self(
      opcode: 0x0C03,
      requiredCapabilities: .video,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 32
    )
  }

  /// Notifies the host that output entries are ready.
  public static func videoNotifyOutput(streamIndex: UInt32) throws -> Self {
    guard streamIndex < 8 else { throw VideoRuntimeError.invalidStreamIndex }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(streamIndex)
    return Self(opcode: 0x0C04, requiredCapabilities: .video, payload: payload)
  }

  /// Updates the device timestamp from the hardware clock.
  public static func videoUpdateTimestamp(sampleTime: UInt64, hostTime: UInt64) -> Self {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(sampleTime)
    payload.appendRuntimeInteger(hostTime)
    return Self(opcode: 0x0C05, requiredCapabilities: .video, payload: payload)
  }

  /// Requests a host-coordinated device sample-rate change.
  public static func videoRequestSampleRate(_ sampleRate: Double) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(sampleRate.bitPattern)
    return Self(opcode: 0x0C06, requiredCapabilities: .video, payload: payload)
  }

  private static func videoTransferPayload(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    plane: VideoBufferPlane,
    byteOffset: UInt32,
    length: UInt32
  ) -> Data {
    var payload = Data(capacity: 32)
    for value in [streamIndex, bufferIndex, plane.rawValue, byteOffset, length, 0, 0, 0] {
      payload.appendRuntimeInteger(value)
    }
    return payload
  }

  private static func videoEntryPayload(_ entry: VideoBufferQueueEntry) -> Data {
    var payload = Data(capacity: 32)
    for value in [
      entry.bufferIndex, entry.dataOffset, entry.dataLength, entry.controlOffset,
      entry.controlLength, 0, 0, 0,
    ] { payload.appendRuntimeInteger(value) }
    return payload
  }
}

extension DriverContext {
  /// Reads bytes from a native video buffer plane.
  public func videoReadBuffer(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    plane: VideoBufferPlane = .data,
    byteOffset: UInt32 = 0,
    length: Int
  ) async throws -> Data {
    try await execute(
      .videoReadBuffer(
        streamIndex: streamIndex,
        bufferIndex: bufferIndex,
        plane: plane,
        byteOffset: byteOffset,
        length: length
      )
    )
  }

  /// Writes bytes into a native video buffer plane.
  public func videoWriteBuffer(
    streamIndex: UInt32,
    bufferIndex: UInt32,
    plane: VideoBufferPlane = .data,
    byteOffset: UInt32 = 0,
    bytes: Data
  ) async throws {
    _ = try await execute(
      .videoWriteBuffer(
        streamIndex: streamIndex,
        bufferIndex: bufferIndex,
        plane: plane,
        byteOffset: byteOffset,
        bytes: bytes
      )
    )
  }

  /// Enqueues a completed output entry for the host.
  public func videoEnqueueOutput(streamIndex: UInt32, entry: VideoBufferQueueEntry) async throws {
    _ = try await execute(.videoEnqueueOutput(streamIndex: streamIndex, entry: entry))
  }

  /// Dequeues an input entry supplied by the host.
  public func videoDequeueInput(streamIndex: UInt32) async throws -> VideoBufferQueueEntry {
    try VideoBufferQueueEntry(
      runtimePayload: await execute(.videoDequeueInput(streamIndex: streamIndex))
    )
  }

  /// Notifies the host that output entries are ready.
  public func videoNotifyOutput(streamIndex: UInt32) async throws {
    _ = try await execute(.videoNotifyOutput(streamIndex: streamIndex))
  }

  /// Reports a hardware-derived timestamp.
  public func videoUpdateTimestamp(sampleTime: UInt64, hostTime: UInt64) async throws {
    _ = try await execute(.videoUpdateTimestamp(sampleTime: sampleTime, hostTime: hostTime))
  }

  /// Requests a host-coordinated sample-rate change.
  public func videoRequestSampleRate(_ sampleRate: Double) async throws {
    _ = try await execute(.videoRequestSampleRate(sampleRate))
  }
}

extension DriverEvent {
  /// Decodes a VideoDriverKit lifecycle event.
  public func video() throws -> VideoEvent? {
    guard type == 0x0C00 else { return nil }
    return try VideoEvent(runtimePayload: Data(payload))
  }
}
