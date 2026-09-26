import Foundation

// @unchecked Sendable: the pointer and length never change, `lock` guards `wrapped`, and the
// bytes are shared memory whose ordering the caller owns, as for `DriverSharedMemory`.
/// Page-aligned memory this process allocates for ``DriverContext/wrapClientMemory(_:direction:)``.
///
/// The allocation is zeroed. Until ``wrap(in:direction:)`` succeeds it is freed with this object;
/// once wrapped, it is never freed, because a subrange or chain built from the handle can keep
/// the extension's descriptor, and so the device's access, alive after the handle is released,
/// and the host has no point at which reusing the pages is safe. Accesses through
/// ``withUnsafeMutableBytes(_:)`` race with the device like any shared DMA memory, so order them
/// with the device's own protocol.
public final class DriverHostMemory: @unchecked Sendable {
  /// The allocation's first byte, on a page boundary.
  private let base: UnsafeMutableRawPointer
  /// The allocation's size in bytes, a whole number of pages.
  public let length: Int
  private let lock = NSLock()
  private var wrapped = false

  /// Allocates at least `minimumLength` zeroed bytes, rounded up to whole pages.
  ///
  /// Returns nil when `minimumLength` is not positive or the rounded size overflows.
  public init?(minimumLength: Int) {
    let page = Self.pageSize
    guard minimumLength > 0, minimumLength <= Int.max - (page - 1) else { return nil }
    length = (minimumLength + page - 1) / page * page
    base = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: page)
    base.initializeMemory(as: UInt8.self, repeating: 0, count: length)
  }

  deinit {
    // Wrapped pages stay allocated for the life of the process; see the type's discussion.
    if !wrapped { base.deallocate() }
  }

  /// Wraps the whole allocation as a runtime memory entry with
  /// ``DriverContext/wrapClientMemory(_:direction:)`` and keeps the pages allocated from then on.
  public func wrap(
    in context: DriverContext,
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    let handle = try await context.wrapClientMemory([segment], direction: direction)
    markWrapped()
    return handle
  }

  private func markWrapped() {
    lock.lock()
    wrapped = true
    lock.unlock()
  }

  /// Whether a wrap succeeded, so the pages outlive this object.
  public var isWrapped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return wrapped
  }

  /// The segment covering the whole allocation.
  public var segment: DriverClientMemorySegment {
    DriverClientMemorySegment(address: UInt64(UInt(bitPattern: base)), length: UInt64(length))
  }

  /// Runs `body` with the allocation's bytes.
  public func withUnsafeMutableBytes<Result>(
    _ body: (UnsafeMutableRawBufferPointer) throws -> Result
  ) rethrows -> Result { try body(UnsafeMutableRawBufferPointer(start: base, count: length)) }

  /// This process's virtual-memory page size.
  public static var pageSize: Int {
    #if canImport(Darwin)
      Int(getpagesize())
    #else
      Int(sysconf(Int32(_SC_PAGESIZE)))
    #endif
  }
}
