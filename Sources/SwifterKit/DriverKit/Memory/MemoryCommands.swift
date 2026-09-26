import Foundation

extension DriverCommand {
  static let maximumMemoryTransferLength = 65_472

  /// Allocates and maps a native DriverKit buffer.
  public static func allocateMemory(
    capacity: UInt64,
    length: UInt64? = nil,
    direction: DriverMemoryDirection = .bidirectional,
    alignment: UInt32 = 0
  ) throws -> Self {
    let validLength = length ?? capacity
    guard capacity > 0, validLength <= capacity else { throw DriverMemoryError.invalidSize }
    guard alignment == 0 || alignment.nonzeroBitCount == 1 else {
      throw DriverMemoryError.invalidAlignment
    }

    var payload = Data(capacity: 32)
    payload.appendRuntimeInteger(capacity)
    payload.appendRuntimeInteger(validLength)
    payload.appendRuntimeInteger(UInt64(alignment))
    payload.appendRuntimeInteger(direction.rawValue)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .memoryAllocate,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  /// Releases a native buffer and any prepared DMA mapping.
  public static func releaseMemory(_ handle: DriverMemoryHandle) throws -> Self {
    try handleCommand(opcode: .memoryRelease, handle: handle)
  }

  /// Changes the valid-data length without reallocating the buffer.
  public static func setMemoryLength(_ handle: DriverMemoryHandle, length: UInt64) throws -> Self {
    try validate(handle: handle)
    var payload = Data(capacity: 16)
    payload.appendRuntimeInteger(handle.rawValue)
    payload.appendRuntimeInteger(length)
    return Self(opcode: .memorySetLength, requiredCapabilities: .memory, payload: payload)
  }

  /// Reads bytes from a mapped native buffer.
  public static func readMemory(
    _ handle: DriverMemoryHandle,
    offset: UInt64,
    length: UInt32
  ) throws -> Self {
    guard length > 0 else { throw DriverMemoryError.invalidSize }
    guard length <= maximumMemoryTransferLength else { throw DriverMemoryError.transferTooLarge }
    return try accessCommand(
      opcode: .memoryRead,
      handle: handle,
      offset: offset,
      length: length,
      maximumResponseSize: RuntimeMessage.headerSize + Int(length)
    )
  }

  /// Writes bytes into a mapped native buffer.
  public static func writeMemory(
    _ handle: DriverMemoryHandle,
    offset: UInt64,
    bytes: [UInt8]
  ) throws -> Self {
    guard !bytes.isEmpty else { throw DriverMemoryError.invalidSize }
    guard bytes.count <= maximumMemoryTransferLength else {
      throw DriverMemoryError.transferTooLarge
    }
    var command = try accessCommand(
      opcode: .memoryWrite,
      handle: handle,
      offset: offset,
      length: UInt32(bytes.count),
      maximumResponseSize: RuntimeMessage.headerSize
    )
    var payload = command.payload
    payload.append(contentsOf: bytes)
    command = Self(
      opcode: command.opcode,
      requiredCapabilities: command.requiredCapabilities,
      payload: payload,
      maximumResponseSize: command.maximumResponseSize
    )
    return command
  }

  /// Queries current native buffer metadata.
  public static func memoryInfo(_ handle: DriverMemoryHandle) throws -> Self {
    try handleCommand(
      opcode: .memoryGetInfo,
      handle: handle,
      maximumResponseSize: RuntimeMessage.headerSize + 32
    )
  }

  /// Prepares a buffer range for device DMA and returns its address segments.
  public static func prepareMemoryForDMA(
    _ handle: DriverMemoryHandle,
    offset: UInt64 = 0,
    length: UInt64 = 0,
    maximumAddressBits: UInt32 = 64
  ) throws -> Self {
    try validate(handle: handle)
    guard (1...64).contains(maximumAddressBits) else { throw DriverMemoryError.invalidAddressBits }
    var payload = Data(capacity: 32)
    payload.appendRuntimeInteger(handle.rawValue)
    payload.appendRuntimeInteger(offset)
    payload.appendRuntimeInteger(length)
    payload.appendRuntimeInteger(maximumAddressBits)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .memoryPrepareDMA,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 16 + 32 * 16
    )
  }

  /// Completes and releases a buffer's prepared DMA mapping.
  public static func completeMemoryDMA(_ handle: DriverMemoryHandle) throws -> Self {
    try handleCommand(opcode: .memoryCompleteDMA, handle: handle)
  }

  /// Creates a memory entry for `length` bytes of `handle`'s valid data starting at `offset`.
  ///
  /// The extension answers with a new handle. `direction` may narrow, never widen, the source's
  /// device access.
  public static func memorySubrange(
    _ handle: DriverMemoryHandle,
    offset: UInt64,
    length: UInt64,
    direction: DriverMemoryDirection
  ) throws -> Self {
    try validate(handle: handle)
    guard length > 0 else { throw DriverMemoryError.invalidSize }
    guard offset <= UInt64.max - length else { throw DriverMemoryError.invalidRange }
    var payload = Data(capacity: RuntimeMemoryLimits.subrangeHeaderSize)
    payload.appendRuntimeInteger(handle.rawValue)
    payload.appendRuntimeInteger(offset)
    payload.appendRuntimeInteger(length)
    payload.appendRuntimeInteger(direction.rawValue)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: .memorySubrange,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  /// Creates a memory entry that concatenates the valid data of 1...32 entries in order.
  ///
  /// The extension answers with a new handle. `direction` may narrow, never widen, the device
  /// access of every source.
  public static func memoryChain(
    _ handles: [DriverMemoryHandle],
    direction: DriverMemoryDirection
  ) throws -> Self {
    guard (1...RuntimeMemoryLimits.maximumChainLength).contains(handles.count) else {
      throw DriverMemoryError.invalidChainLength
    }
    for handle in handles { try validate(handle: handle) }
    var payload = Data(capacity: RuntimeMemoryLimits.chainHeaderSize + handles.count * 8)
    payload.appendRuntimeInteger(UInt32(handles.count))
    payload.appendRuntimeInteger(direction.rawValue)
    for handle in handles { payload.appendRuntimeInteger(handle.rawValue) }
    return Self(
      opcode: .memoryChain,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + 8
    )
  }

  private static func handleCommand(
    opcode: RuntimeOpcode,
    handle: DriverMemoryHandle,
    maximumResponseSize: Int = RuntimeMessage.headerSize
  ) throws -> Self {
    try validate(handle: handle)
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(handle.rawValue)
    return Self(
      opcode: opcode,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: maximumResponseSize
    )
  }

  private static func accessCommand(
    opcode: RuntimeOpcode,
    handle: DriverMemoryHandle,
    offset: UInt64,
    length: UInt32,
    maximumResponseSize: Int
  ) throws -> Self {
    try validate(handle: handle)
    guard offset <= UInt64.max - UInt64(length) else { throw DriverMemoryError.invalidRange }
    var payload = Data(capacity: 24)
    payload.appendRuntimeInteger(handle.rawValue)
    payload.appendRuntimeInteger(offset)
    payload.appendRuntimeInteger(length)
    payload.appendRuntimeInteger(UInt32(0))
    return Self(
      opcode: opcode,
      requiredCapabilities: .memory,
      payload: payload,
      maximumResponseSize: maximumResponseSize
    )
  }

  private static func validate(handle: DriverMemoryHandle) throws {
    guard handle.rawValue != 0 else { throw DriverMemoryError.invalidHandle }
  }
}

extension DriverContext {
  /// Allocates and maps a native DriverKit buffer.
  public func allocateMemory(
    capacity: UInt64,
    length: UInt64? = nil,
    direction: DriverMemoryDirection = .bidirectional,
    alignment: UInt32 = 0
  ) async throws -> DriverMemoryHandle {
    let payload = try await execute(
      .allocateMemory(
        capacity: capacity,
        length: length,
        direction: direction,
        alignment: alignment
      )
    )
    return try DriverMemoryHandle(runtimePayload: payload)
  }

  /// Creates a memory entry for part of `handle`'s valid data.
  ///
  /// The new entry retains its source's descriptor, and ``releaseMemory(_:)`` refuses `handle`
  /// with ``DriverMemoryError/inUse`` until the subrange is released. The range is fixed at
  /// creation, so a later ``setMemoryLength(_:length:)`` on the source does not change it, and
  /// the subrange's own length cannot be changed. It counts toward
  /// ``MemoryPoolConfiguration/maximumBuffers`` but not toward the pool's total size.
  public func memorySubrange(
    _ handle: DriverMemoryHandle,
    offset: UInt64,
    length: UInt64,
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    try await DriverMemoryHandle(
      runtimePayload: execute(
        .memorySubrange(handle, offset: offset, length: length, direction: direction)
      )
    )
  }

  /// Creates one memory entry that concatenates the valid data of `handles` in order, for a
  /// single DMA preparation or host mapping.
  ///
  /// The chain retains every source descriptor, keeps each source from being released until the
  /// chain is, and follows the same length and limit rules as
  /// ``memorySubrange(_:offset:length:direction:)``. Reading or writing a chain through the
  /// runtime requires DriverKit to map it into the extension; when it cannot, those commands
  /// fail with `kIOReturnUnsupported` while DMA and host mapping still work.
  public func memoryChain(
    _ handles: [DriverMemoryHandle],
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    try await DriverMemoryHandle(
      runtimePayload: execute(.memoryChain(handles, direction: direction))
    )
  }

  /// Releases a native buffer and any prepared DMA mapping.
  ///
  /// Throws ``DriverMemoryError/inUse`` and releases nothing while a subrange or chain built
  /// from `handle` exists; release those first.
  public func releaseMemory(_ handle: DriverMemoryHandle) async throws {
    do { _ = try await execute(.releaseMemory(handle)) } catch let error as DriverKitError {
      guard error.kind == .ioReturn(RuntimeMemoryStatus.inUse.ioReturn) else { throw error }
      throw DriverMemoryError.inUse
    }
  }

  /// Changes a native buffer's valid-data length.
  public func setMemoryLength(_ handle: DriverMemoryHandle, length: UInt64) async throws {
    _ = try await execute(.setMemoryLength(handle, length: length))
  }

  /// Reads bytes from a mapped native buffer.
  public func readMemory(
    _ handle: DriverMemoryHandle,
    offset: UInt64,
    length: UInt32
  ) async throws -> [UInt8] {
    Array(try await execute(.readMemory(handle, offset: offset, length: length)))
  }

  /// Writes bytes into a mapped native buffer.
  public func writeMemory(_ handle: DriverMemoryHandle, offset: UInt64, bytes: [UInt8]) async throws
  { _ = try await execute(.writeMemory(handle, offset: offset, bytes: bytes)) }

  /// Returns current native buffer metadata.
  public func memoryInfo(_ handle: DriverMemoryHandle) async throws -> DriverMemoryInfo {
    try await DriverMemoryInfo(runtimePayload: execute(.memoryInfo(handle)))
  }

  /// Prepares a native buffer range for device DMA.
  public func prepareMemoryForDMA(
    _ handle: DriverMemoryHandle,
    offset: UInt64 = 0,
    length: UInt64 = 0,
    maximumAddressBits: UInt32 = 64
  ) async throws -> DriverDMAMapping {
    try await DriverDMAMapping(
      runtimePayload: execute(
        .prepareMemoryForDMA(
          handle,
          offset: offset,
          length: length,
          maximumAddressBits: maximumAddressBits
        )
      )
    )
  }

  /// Completes a native buffer's prepared DMA mapping.
  public func completeMemoryDMA(_ handle: DriverMemoryHandle) async throws {
    _ = try await execute(.completeMemoryDMA(handle))
  }
}
