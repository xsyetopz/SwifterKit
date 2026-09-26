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

  /// Maps a fast-path ring into this process, header and entries, without copying.
  ///
  /// ``FastPathRingLayout`` describes the bytes. The extension answers `kIOReturnNotReady` while
  /// its fast path is not running. When the context has a ``fastPath`` configuration, a ring it
  /// does not declare is refused before any request. The mapping keeps the ring's memory alive
  /// after the fast path stops, but the device no longer uses it then.
  public func mapRing(_ id: UInt32) async throws -> DriverSharedMemory {
    guard fastPath?.rings.contains(where: { $0.id == id }) ?? true,
      let type = RuntimeClientMemoryType(kind: .ring, identifier: UInt64(id))
    else { throw FastPathRuntimeError.unknownRing(id) }
    return try await mapMemory(type, readOnly: false, requiring: .pci)
  }
}
