import Foundation

extension DriverContext {
  /// Maps a runtime buffer, subrange, or chain into this process without copying.
  ///
  /// The mapping reads and writes the same memory the extension and device use; see
  /// ``DriverSharedMemory`` for bounds, byte order, and unmapping. It keeps the memory alive
  /// after ``releaseMemory(_:)`` until it is unmapped, and ends when the runtime connection
  /// closes. Mapping a handle again while its mapping is live returns the same instance. The
  /// extension refuses memory another connection wrapped; `IOConnectMapMemory64` reports every
  /// refused mapping as `kIOReturnBadArgument`.
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

  /// Maps a fast-path data queue's host ring into this process, header and records, without
  /// copying.
  ///
  /// ``FastPathDataQueueLayout`` describes the bytes, and the returned reader checks them on
  /// every access. The extension answers `kIOReturnNotReady` while its fast path is not running.
  /// When the context has a ``fastPath`` configuration, a queue it does not declare is refused
  /// before any request, and the ring's geometry must match the declaration.
  public func mapDataQueue(_ id: UInt32) async throws -> DriverDataQueue {
    let queue = fastPath?.dataQueues.first { $0.id == id }
    guard fastPath == nil || queue != nil,
      let type = RuntimeClientMemoryType(kind: .dataQueue, identifier: UInt64(id))
    else { throw FastPathRuntimeError.unknownDataQueue(id) }
    return DriverDataQueue(
      memory: try await mapMemory(type, readOnly: false, requiring: []),
      queue: queue
    )
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
  /// ``releaseMemory(_:)`` succeeds for this handle, which it refuses with
  /// ``DriverMemoryError/inUse`` while a subrange or chain built from it exists. A
  /// ``mapMemory(_:)`` mapping of the handle outlives its release, so unmap it first.
  ///
  /// The entry belongs to this runtime connection: a command from any other connection that
  /// names it, or a subrange or chain built from it, throws ``DriverMemoryError/notOwner``, the
  /// extension refuses such a connection's ``mapMemory(_:)`` of it, and such a subrange or chain
  /// belongs to this connection too.
  /// When the connection closes or the process exits, the extension releases these entries,
  /// compositions first, and completes any DMA prepared on them. It does so when DriverKit stops
  /// the connection's user client, after the close returns, and this process cannot observe
  /// that, so memory wrapped on a connection that closed with the handle unreleased must still
  /// never be freed or reused; ``DriverHostMemory/wrap(in:direction:)`` keeps it allocated.
  public func wrapClientMemory(
    _ segments: [DriverClientMemorySegment],
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    try await DriverMemoryHandle(
      runtimePayload: execute(.wrapClientMemory(segments, direction: direction))
    )
  }
}
