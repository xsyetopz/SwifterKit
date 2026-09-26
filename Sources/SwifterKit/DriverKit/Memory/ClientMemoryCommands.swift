extension DriverContext {
  /// Maps a runtime buffer, subrange, or chain into this process without copying.
  ///
  /// The mapping reads and writes the same memory the extension and device use; see
  /// ``DriverSharedMemory`` for bounds, byte order, and unmapping. It keeps the memory alive
  /// after ``releaseMemory(_:)`` until it is unmapped, and ends when the runtime connection
  /// closes. Mapping a handle again while its mapping is live returns the same instance.
  public func mapMemory(_ handle: DriverMemoryHandle) async throws -> DriverSharedMemory {
    guard handle.rawValue != 0,
      let type = RuntimeClientMemoryType(kind: .memoryBuffer, identifier: handle.rawValue)
    else { throw DriverMemoryError.invalidHandle }
    return try await mapMemory(type, readOnly: false, requiring: .memory)
  }

  /// Maps a networking packet pool into this process read-only, so Swift can inspect frames in
  /// the buffers the network family owns without copying them.
  public func mapPacketPool(_ pool: EthernetPacketPool) async throws -> DriverSharedMemory {
    guard let type = RuntimeClientMemoryType(kind: .packetPool, identifier: UInt64(pool.rawValue))
    else { throw DriverMemoryError.invalidHandle }
    return try await mapMemory(type, readOnly: true, requiring: .networking)
  }
}
