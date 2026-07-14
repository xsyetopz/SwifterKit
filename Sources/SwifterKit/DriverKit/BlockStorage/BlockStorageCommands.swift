import Foundation

extension DriverCommand {
  /// Completes an eject, synchronize, or unmap request.
  public static func completeBlockStorageRequest(
    requestID: UInt32,
    status: BlockStorageCompletionStatus = .success
  ) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(status.rawValue)
    return Self(
      opcode: 0x0700,
      requiredCapabilities: .blockStorage,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  /// Completes a read or write request.
  public static func completeBlockStorageIO(
    requestID: UInt32,
    bytesTransferred: UInt64,
    status: BlockStorageCompletionStatus = .success
  ) -> Self {
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(status.rawValue)
    payload.appendRuntimeInteger(bytesTransferred)
    return Self(
      opcode: 0x0701,
      requiredCapabilities: .blockStorage,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }
}

extension DriverContext {
  /// Completes an eject, synchronize, or unmap request.
  public func completeBlockStorageRequest(
    requestID: UInt32,
    status: BlockStorageCompletionStatus = .success
  ) async throws {
    _ = try await execute(.completeBlockStorageRequest(requestID: requestID, status: status))
  }

  /// Completes a read or write request after programming the hardware DMA operation.
  public func completeBlockStorageIO(
    requestID: UInt32,
    bytesTransferred: UInt64,
    status: BlockStorageCompletionStatus = .success
  ) async throws {
    _ = try await execute(
      .completeBlockStorageIO(
        requestID: requestID,
        bytesTransferred: bytesTransferred,
        status: status
      )
    )
  }
}

extension DriverEvent {
  /// Decodes a BlockStorageDeviceDriverKit request.
  public func blockStorage() throws -> BlockStorageRequest? {
    guard type == 0x0700 else { return nil }
    return try BlockStorageRequest(runtimePayload: Data(payload))
  }
}
