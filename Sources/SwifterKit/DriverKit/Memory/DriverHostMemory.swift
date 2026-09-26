import Foundation

// @unchecked Sendable: the pointer and length never change, `lock` guards `wraps`, and the
// bytes are shared memory whose ordering the caller owns, as for `DriverSharedMemory`.
/// Page-aligned memory this process allocates for ``DriverContext/wrapClientMemory(_:direction:)``.
///
/// The allocation is zeroed. ``wrap(in:direction:)`` wraps it, and the runtime connection holds
/// this object until ``DriverContext/releaseMemory(_:)`` succeeds for the returned handle, which
/// the extension refuses with ``DriverMemoryError/inUse`` while a subrange or chain built from
/// it exists. The pages are freed when the last reference goes away with no wrap outstanding,
/// so unmap any ``DriverSharedMemory`` from ``DriverContext/mapMemory(_:)`` of the handle, or of
/// a subrange or chain built from it, before releasing it: that mapping outlives the release.
/// A wrap whose handle was never released, including one outstanding when its connection
/// closed, keeps the pages allocated for the life of the process. The extension releases the
/// entry when DriverKit stops the connection's user client, but that stop runs after the close
/// returns and the host has no way to observe it, so freeing the pages at close could hand
/// memory the extension or device still describes back to the allocator. Accesses through
/// ``withUnsafeMutableBytes(_:)`` race with the device like any shared DMA memory, so order them
/// with the device's own protocol.
public final class DriverHostMemory: @unchecked Sendable {
  /// The allocation's first byte, on a page boundary.
  private let base: UnsafeMutableRawPointer
  /// The allocation's size in bytes, a whole number of pages.
  public let length: Int
  private let lock = NSLock()
  /// Wraps whose release the extension has not confirmed.
  private var wraps = 0

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
    // An unreleased wrap may still be described by the extension; see the type's discussion.
    if wraps == 0 { base.deallocate() }
  }

  /// Wraps the whole allocation as a runtime memory entry with
  /// ``DriverContext/wrapClientMemory(_:direction:)``.
  ///
  /// The context's runtime connection keeps this object, and so the pages, alive until a
  /// release of the returned handle succeeds.
  public func wrap(
    in context: DriverContext,
    direction: DriverMemoryDirection
  ) async throws -> DriverMemoryHandle {
    try await context.wrapHostMemory(self, direction: direction)
  }

  /// Records a wrap the extension answered.
  func beginWrap() {
    lock.lock()
    wraps += 1
    lock.unlock()
  }

  /// Records that the extension released a wrap's handle.
  func endWrap() {
    lock.lock()
    wraps -= 1
    lock.unlock()
  }

  /// Whether a wrap's handle is still unreleased, so the pages outlive this object.
  public var isWrapped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return wraps != 0
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
