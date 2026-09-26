import Foundation

// @unchecked Sendable: `lock` guards `isMappedState`, `accessDepth`, and `unmapRequested`, and
// every access to the memory at `baseAddress` runs while holding it, so instances can be shared
// across tasks. `NSRecursiveLock` lets an access closure use this instance again.
/// Extension memory mapped into this process without copying, such as a runtime buffer from
/// ``DriverContext/mapMemory(_:)`` or a packet pool from ``DriverContext/mapPacketPool(_:)``.
///
/// Every access checks its byte range against ``length`` and throws
/// ``DriverSharedMemoryError`` rather than truncating. Integers are little-endian, the byte
/// order of DriverKit's hardware, and need no alignment. Raw memory is reachable only inside
/// ``withUnsafeBytes(_:)`` and ``withUnsafeMutableBytes(_:)``, whose buffer must not escape the
/// closure.
///
/// The mapping ends exactly once: at the first ``unmap()``, when the connection that created it
/// closes, or when the last reference goes away. Accesses after that throw
/// ``DriverSharedMemoryError/unmapped``. Accesses and the unmap are serialized, so an unmap
/// requested from another task waits for a running access, and one requested inside an access
/// closure takes effect when the outermost access returns.
///
/// The extension and the device may change the bytes at any time; coordinate through the
/// protocol that owns the memory, such as a DMA completion or runtime command.
public final class DriverSharedMemory: @unchecked Sendable {
  /// The mapped byte count.
  public let length: Int
  /// Whether the extension shares the memory read-only; stores then throw
  /// ``DriverSharedMemoryError/readOnly``.
  public let isReadOnly: Bool

  private let baseAddress: UnsafeMutableRawPointer
  private let release: @Sendable () -> Void
  private let lock = NSRecursiveLock()
  private var isMappedState = true
  private var accessDepth = 0
  private var unmapRequested = false

  /// Wraps an established mapping; `unmap` runs exactly once to remove it.
  ///
  /// ``DriverConnection`` implementations create instances from
  /// ``DriverConnection/mapMemory(type:readOnly:)``.
  @preconcurrency
  public init(
    baseAddress: UnsafeMutableRawPointer,
    length: Int,
    isReadOnly: Bool,
    unmap: @escaping @Sendable () -> Void
  ) {
    self.baseAddress = baseAddress
    self.length = max(0, length)
    self.isReadOnly = isReadOnly
    self.release = unmap
  }

  deinit { if isMappedState { release() } }

  /// Whether the memory is still mapped.
  public var isMapped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isMappedState && !unmapRequested
  }

  /// Removes the mapping; later calls do nothing.
  public func unmap() {
    lock.lock()
    defer { lock.unlock() }
    guard isMappedState else { return }
    if accessDepth > 0 {
      unmapRequested = true
      return
    }
    isMappedState = false
    release()
  }

  /// Reads a little-endian integer at `offset`.
  public func load<Value: FixedWidthInteger>(
    _ type: Value.Type = Value.self,
    fromByteOffset offset: Int
  ) throws -> Value {
    try access(offset: offset, count: MemoryLayout<Value>.size, writes: false) { pointer in
      Value(littleEndian: pointer.loadUnaligned(as: Value.self))
    }
  }

  /// Writes `value` as a little-endian integer at `offset`.
  public func store<Value: FixedWidthInteger>(_ value: Value, toByteOffset offset: Int) throws {
    try access(offset: offset, count: MemoryLayout<Value>.size, writes: true) { pointer in
      pointer.storeBytes(of: value.littleEndian, as: Value.self)
    }
  }

  /// Copies `count` bytes starting at `offset`.
  public func copyBytes(fromByteOffset offset: Int, count: Int) throws -> [UInt8] {
    try access(offset: offset, count: count, writes: false) { pointer in
      Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
  }

  /// Copies `bytes` into the memory starting at `offset`.
  public func write(_ bytes: [UInt8], toByteOffset offset: Int) throws {
    try access(offset: offset, count: bytes.count, writes: true) { pointer in
      bytes.withUnsafeBytes { source in
        if let start = source.baseAddress {
          pointer.copyMemory(from: start, byteCount: source.count)
        }
      }
    }
  }

  /// Calls `body` with the whole mapping; the buffer must not escape the closure.
  public func withUnsafeBytes<Result>(
    _ body: (UnsafeRawBufferPointer) throws -> Result
  ) throws -> Result {
    try access(offset: 0, count: length, writes: false) { pointer in
      try body(UnsafeRawBufferPointer(start: pointer, count: length))
    }
  }

  /// Calls `body` with the whole writable mapping; the buffer must not escape the closure.
  public func withUnsafeMutableBytes<Result>(
    _ body: (UnsafeMutableRawBufferPointer) throws -> Result
  ) throws -> Result {
    try access(offset: 0, count: length, writes: true) { pointer in
      try body(UnsafeMutableRawBufferPointer(start: pointer, count: length))
    }
  }

  private func access<Result>(
    offset: Int,
    count: Int,
    writes: Bool,
    _ body: (UnsafeMutableRawPointer) throws -> Result
  ) throws -> Result {
    lock.lock()
    defer { lock.unlock() }
    guard isMappedState, !unmapRequested else { throw DriverSharedMemoryError.unmapped }
    guard !writes || !isReadOnly else { throw DriverSharedMemoryError.readOnly }
    guard offset >= 0, count >= 0, offset <= length, count <= length - offset else {
      throw DriverSharedMemoryError.outOfBounds(offset: offset, count: count, length: length)
    }
    accessDepth += 1
    defer {
      accessDepth -= 1
      if accessDepth == 0, unmapRequested {
        unmapRequested = false
        isMappedState = false
        release()
      }
    }
    return try body(baseAddress + offset)
  }
}

/// A ``DriverSharedMemory`` access that cannot proceed.
public enum DriverSharedMemoryError: Error, Sendable, Equatable {
  /// The memory has been unmapped.
  case unmapped
  /// The byte range `offset..<offset + count` is not inside the `length`-byte mapping.
  case outOfBounds(offset: Int, count: Int, length: Int)
  /// The extension shares this memory read-only.
  case readOnly
}
