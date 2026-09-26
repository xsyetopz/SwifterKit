import Foundation

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

extension DriverCommand {
  /// Creates a request that wraps host memory as a runtime memory entry without copying it.
  ///
  /// The segments are checked here and again in the extension: 1 to 32 of them, each nonzero
  /// and not wrapping past the end of the address space, with a total length that fits 64 bits.
  public static func wrapClientMemory(
    _ segments: [DriverClientMemorySegment],
    direction: DriverMemoryDirection
  ) throws -> Self {
    guard (1...RuntimeMemoryLimits.maximumClientSegments).contains(segments.count) else {
      throw DriverMemoryError.invalidSegmentCount
    }
    var payload = Data(
      capacity: RuntimeMemoryLimits.clientHeaderSize + segments.count
        * RuntimeMemoryLimits.clientSegmentSize
    )
    payload.appendRuntimeInteger(UInt32(segments.count))
    payload.appendRuntimeInteger(direction.rawValue)
    var total: UInt64 = 0
    for segment in segments {
      let sum = total.addingReportingOverflow(segment.length)
      guard segment.length != 0, segment.address <= UInt64.max - segment.length, !sum.overflow
      else { throw DriverMemoryError.invalidSegment }
      total = sum.partialValue
      payload.appendRuntimeInteger(segment.address)
      payload.appendRuntimeInteger(segment.length)
    }
    return Self(
      opcode: .memoryWrapClient,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }
}

extension DriverContext {
  /// Wraps memory this process owns as a runtime memory entry, without copying it.
  ///
  /// The extension describes the segments with `IOUserClient::CreateMemoryDescriptorFromClient`
  /// while it handles this request, so the handle names this process's own pages: the device
  /// reads or writes them after ``prepareMemoryForDMA(_:offset:length:maximumAddressBits:)``, and
  /// ``readMemory(_:offset:length:)``, ``writeMemory(_:offset:bytes:)``,
  /// ``memorySubrange(_:offset:length:direction:)``, and ``memoryChain(_:direction:)`` work as for
  /// an allocated buffer. The entry takes one of ``MemoryPoolConfiguration/maximumBuffers`` slots
  /// but none of the pool's byte budget, and its length cannot change.
  ///
  /// The memory must stay allocated, and must not be unmapped or reused, until
  /// ``releaseMemory(_:)`` returns for this handle and every subrange or chain built from it;
  /// ``DriverHostMemory/wrap(in:direction:)`` keeps its allocation alive for that long.
  public func wrapClientMemory(
    _ segments: [DriverClientMemorySegment],
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    try await DriverMemoryHandle(
      runtimePayload: execute(.wrapClientMemory(segments, direction: direction))
    )
  }
}
