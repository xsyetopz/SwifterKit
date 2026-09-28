import Foundation

/// A descriptor ring the extension allocates when the fast path starts and prepares for DMA.
///
/// The ring is one buffer: a ``FastPathRingLayout/headerSize``-byte header that holds the
/// producer and consumer indices, followed by `entryCount` entries of `entrySize` bytes. Programs
/// read and write entries with ``FastPathOp/ringLoad(_:entry:fieldOffset:width:into:)`` and
/// ``FastPathOp/ringStore(_:entry:fieldOffset:width:_:)``, move the indices with
/// ``FastPathOp/ringAdvance(_:_:by:)``, and hand the device the address of entry 0 through
/// ``FastPathOperand/ringDeviceAddress(_:_:)``. Swift maps the same buffer with
/// ``DriverContext/mapRing(_:)``.
public struct FastPathRing: Sendable, Hashable {
  /// The ring's identifier, unique in its configuration and at most `0xFF_FFFF`. Operations and
  /// ``DriverContext/mapRing(_:)`` name the ring by it.
  public let id: UInt32
  /// The bytes of one entry, a power of two from 8 through 4096.
  public let entrySize: UInt32
  /// The number of entries, a power of two from 2 through 65 536.
  public let entryCount: UInt32
  /// Which way the device moves data through the ring.
  public let direction: DriverMemoryDirection

  /// Creates a ring declaration.
  public init(id: UInt32, entrySize: UInt32, entryCount: UInt32, direction: DriverMemoryDirection) {
    self.id = id
    self.entrySize = entrySize
    self.entryCount = entryCount
    self.direction = direction
  }

  /// The bytes the ring occupies: its header and every entry.
  public var byteCount: UInt64 {
    UInt64(FastPathRingLayout.headerSize) + UInt64(entrySize) * UInt64(entryCount)
  }
}

/// The byte layout of a ring buffer, shared by the extension and a ``DriverSharedMemory`` from
/// ``DriverContext/mapRing(_:)``.
///
/// All fields are little-endian `UInt32` values in the header. The rest of the header is zero.
/// Indices are always below the entry count. The extension masks them by `entryCount - 1`, and a
/// host that writes an index must do the same. The extension stores an index with release
/// ordering after the entries it covers. A host that reads the index and then the entries sees
/// the written entries.
public enum FastPathRingLayout {
  /// The header bytes before entry 0.
  public static let headerSize = RuntimeFastPathLimits.ringHeaderSize
  /// The offset of the producer index.
  public static let producerOffset = RuntimeFastPathLimits.ringProducerOffset
  /// The offset of the consumer index.
  public static let consumerOffset = RuntimeFastPathLimits.ringConsumerOffset
  /// The offset of the entry size.
  public static let entrySizeOffset = RuntimeFastPathLimits.ringEntrySizeOffset
  /// The offset of the entry count.
  public static let entryCountOffset = RuntimeFastPathLimits.ringEntryCountOffset

  /// The offset of entry `index`'s first byte.
  public static func entryOffset(_ index: UInt32, of ring: FastPathRing) -> Int {
    headerSize + Int(index & (ring.entryCount &- 1)) * Int(ring.entrySize)
  }
}

/// The half of a 64-bit ring device address an operand takes.
public enum FastPathRingAddressHalf: Sendable, Hashable, CaseIterable {
  /// Bits 0 through 31.
  case low
  /// Bits 32 through 63.
  case high
}

/// One of a ring's two indices.
public enum FastPathRingIndex: Sendable, Hashable, CaseIterable {
  /// The index of the next entry the producer fills.
  case producer
  /// The index of the next entry the consumer takes.
  case consumer
}
