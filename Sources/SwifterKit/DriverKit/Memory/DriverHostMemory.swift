import Foundation

// @unchecked Sendable: the pointer and length never change; the bytes are shared memory whose
// ordering the caller owns, as for `DriverSharedMemory`.
/// Page-aligned memory this process allocates for ``DriverContext/wrapClientMemory(_:direction:)``.
///
/// The allocation is zeroed and lives as long as this object: keep a reference until
/// ``DriverContext/releaseMemory(_:)`` has returned for every handle that wraps it, because the
/// extension and the device keep using these pages until then. Accesses through
/// ``withUnsafeMutableBytes(_:)`` race with the device like any shared DMA memory, so order them
/// with the device's own protocol.
public final class DriverHostMemory: @unchecked Sendable {
  /// The allocation's first byte, on a page boundary.
  private let base: UnsafeMutableRawPointer
  /// The allocation's size in bytes, a whole number of pages.
  public let length: Int

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

  deinit { base.deallocate() }

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
