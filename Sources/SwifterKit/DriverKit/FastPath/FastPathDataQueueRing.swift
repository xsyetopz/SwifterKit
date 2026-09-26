import Foundation

#if canImport(Synchronization)
  import Synchronization
#endif

/// Why a data queue host ring's bytes were refused.
///
/// The extension and a buggy or malicious peer can write any bytes into a mapped ring, so the
/// reader checks every field it uses before it touches a record.
public enum FastPathDataQueueError: Error, Sendable, Hashable {
  /// The header's geometry does not fit the mapping, is not a power of two, or differs from the
  /// queue's declaration.
  case invalidGeometry
  /// The producer is more than the record count ahead of the consumer.
  case invalidIndices(producer: UInt32, consumer: UInt32)
  /// A record's payload byte count is above the queue's maximum entry size.
  case invalidEntrySize(UInt32)
  /// The ring has no free record.
  case full
  /// The entry is empty or larger than the queue's maximum entry size.
  case invalidEntry(byteCount: Int)
  /// The host wrote to a ring whose header does not name
  /// ``FastPathDataQueueDirection/toExtension``; the extension produces that ring's entries.
  case notProducer
}

/// The portable single-producer, single-consumer logic over a data queue host ring's bytes,
/// described by ``FastPathDataQueueLayout``.
///
/// It has no platform dependency, so the layout checks run everywhere Swift does.
struct FastPathDataQueueRing {
  let entryCount: UInt32
  let stride: UInt32
  let maximumEntrySize: UInt32

  /// Reads and checks the geometry in the header of `bytes`, against `queue` when it is known.
  init(
    header bytes: UnsafeRawBufferPointer,
    expecting queue: FastPathDataQueue?
  ) throws(FastPathDataQueueError) {
    guard bytes.count >= FastPathDataQueueLayout.headerSize else { throw .invalidGeometry }
    let count = Self.load(bytes, FastPathDataQueueLayout.entryCountOffset)
    let stride = Self.load(bytes, FastPathDataQueueLayout.strideOffset)
    let maximum = Self.load(bytes, FastPathDataQueueLayout.maximumEntrySizeOffset)
    let records = UInt64(count) * UInt64(stride)
    guard count.nonzeroBitCount == 1, stride.nonzeroBitCount == 1, maximum != 0,
      UInt64(maximum) + UInt64(FastPathDataQueueLayout.recordHeaderSize) <= UInt64(stride),
      UInt64(FastPathDataQueueLayout.headerSize) + records <= UInt64(bytes.count)
    else { throw .invalidGeometry }
    if let queue {
      guard count == queue.entryCount, stride == queue.recordStride,
        maximum == queue.maximumEntrySize
      else { throw .invalidGeometry }
    }
    entryCount = count
    self.stride = stride
    maximumEntrySize = maximum
  }

  /// Takes the oldest record and passes its payload to `body` in place; returns nil when the
  /// ring is empty. The record is released only after `body` returns without throwing.
  func dequeue<Result>(
    _ bytes: UnsafeMutableRawBufferPointer,
    _ body: (UnsafeRawBufferPointer) throws -> Result
  ) throws -> Result? {
    let producer = Self.acquire(
      UnsafeRawBufferPointer(bytes),
      FastPathDataQueueLayout.producerOffset
    )
    let consumer = Self.load(UnsafeRawBufferPointer(bytes), FastPathDataQueueLayout.consumerOffset)
    let used = producer &- consumer
    guard used <= entryCount else {
      throw FastPathDataQueueError.invalidIndices(producer: producer, consumer: consumer)
    }
    guard used != 0 else { return nil }
    let record = recordOffset(consumer)
    let size = Self.load(UnsafeRawBufferPointer(bytes), record)
    guard size <= maximumEntrySize else { throw FastPathDataQueueError.invalidEntrySize(size) }
    let start = record + FastPathDataQueueLayout.recordHeaderSize
    let result = try body(UnsafeRawBufferPointer(rebasing: bytes[start..<start + Int(size)]))
    Self.release(bytes, FastPathDataQueueLayout.consumerOffset, consumer &+ 1)
    return result
  }

  /// Appends one record holding `payload`.
  func enqueue(
    _ bytes: UnsafeMutableRawBufferPointer,
    _ payload: UnsafeRawBufferPointer
  ) throws(FastPathDataQueueError) {
    guard !payload.isEmpty, payload.count <= Int(maximumEntrySize) else {
      throw .invalidEntry(byteCount: payload.count)
    }
    let producer = Self.load(UnsafeRawBufferPointer(bytes), FastPathDataQueueLayout.producerOffset)
    let consumer = Self.acquire(
      UnsafeRawBufferPointer(bytes),
      FastPathDataQueueLayout.consumerOffset
    )
    let used = producer &- consumer
    guard used <= entryCount else { throw .invalidIndices(producer: producer, consumer: consumer) }
    guard used < entryCount else { throw .full }
    let record = recordOffset(producer)
    Self.store(bytes, record, UInt32(payload.count))
    Self.store(bytes, record + 4, 0)
    let start = record + FastPathDataQueueLayout.recordHeaderSize
    UnsafeMutableRawBufferPointer(rebasing: bytes[start..<start + payload.count]).copyMemory(
      from: payload
    )
    Self.release(bytes, FastPathDataQueueLayout.producerOffset, producer &+ 1)
  }

  /// The records waiting for the consumer, or nil when the indices are corrupt.
  func pending(_ bytes: UnsafeRawBufferPointer) -> UInt32? {
    let used =
      Self.acquire(bytes, FastPathDataQueueLayout.producerOffset)
      &- Self.load(bytes, FastPathDataQueueLayout.consumerOffset)
    return used <= entryCount ? used : nil
  }

  private func recordOffset(_ index: UInt32) -> Int {
    FastPathDataQueueLayout.headerSize + Int(index & (entryCount &- 1)) * Int(stride)
  }

  static func load(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
    UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
  }

  static func store(_ bytes: UnsafeMutableRawBufferPointer, _ offset: Int, _ value: UInt32) {
    bytes.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
  }

  /// Loads the other side's index, ordering later record reads after it.
  private static func acquire(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
    let value = load(bytes, offset)
    fence()
    return value
  }

  /// Stores this side's index, ordering earlier record accesses before it.
  private static func release(
    _ bytes: UnsafeMutableRawBufferPointer,
    _ offset: Int,
    _ value: UInt32
  ) {
    fence()
    store(bytes, offset, value)
  }

  private static func fence() {
    #if canImport(Synchronization)
      if #available(macOS 15.0, *) { atomicMemoryFence(ordering: .sequentiallyConsistent) }
    #endif
  }
}

/// A mapped ``FastPathDataQueue`` host ring from ``DriverContext/mapDataQueue(_:)``.
///
/// Reads check the header's geometry and indices on every call and throw
/// ``FastPathDataQueueError`` for bytes that do not describe a valid ring, so a corrupt or
/// malicious producer index cannot move an access outside the mapping. Use one reader per queue:
/// the ring has a single consumer.
public final class DriverDataQueue: Sendable {
  /// The mapped ring, header and records.
  public let memory: DriverSharedMemory
  /// The queue's declaration, when the context's configuration names it.
  public let queue: FastPathDataQueue?

  /// Wraps a mapped ring; `queue`, when given, must match the header's geometry.
  public init(memory: DriverSharedMemory, queue: FastPathDataQueue? = nil) {
    self.memory = memory
    self.queue = queue
  }

  /// Takes the oldest entry and passes its payload to `body` without copying; returns nil when
  /// the ring is empty. The buffer must not escape `body`; the entry is released when `body`
  /// returns.
  public func dequeue<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) throws -> Result? {
    try memory.withUnsafeMutableBytes { bytes in
      let ring = try FastPathDataQueueRing(header: UnsafeRawBufferPointer(bytes), expecting: queue)
      return try ring.dequeue(bytes, body)
    }
  }

  /// Takes the oldest entry as little-endian 64-bit words; returns nil when the ring is empty.
  /// Trailing bytes that do not fill a word are dropped.
  public func dequeueValues() throws -> [UInt64]? {
    try dequeue { payload in
      stride(from: 0, to: payload.count / 8 * 8, by: 8).map {
        UInt64(littleEndian: payload.loadUnaligned(fromByteOffset: $0, as: UInt64.self))
      }
    }
  }

  /// Appends one entry to a ``FastPathDataQueueDirection/toExtension`` ring; call
  /// ``DriverContext/notifyDataQueue(_:)`` after one or more appends so the extension takes them.
  /// Throws ``FastPathDataQueueError/full`` when the extension has not taken enough entries yet,
  /// and refuses an empty entry or one above the maximum entry size. Use one writer per queue: the
  /// ring has a single producer.
  public func enqueue(_ payload: UnsafeRawBufferPointer) throws {
    try memory.withUnsafeMutableBytes { bytes in
      let ring = try FastPathDataQueueRing(header: UnsafeRawBufferPointer(bytes), expecting: queue)
      guard
        FastPathDataQueueRing.load(
          UnsafeRawBufferPointer(bytes),
          FastPathDataQueueLayout.directionOffset
        ) == RuntimeFastPathDataQueueDirection.toExtension.rawValue
      else { throw FastPathDataQueueError.notProducer }
      try ring.enqueue(bytes, payload)
    }
  }

  /// Appends `values`, eight little-endian bytes each, as one entry; see ``enqueue(_:)``.
  public func enqueueValues(_ values: [UInt64]) throws {
    let bytes = values.flatMap { withUnsafeBytes(of: $0.littleEndian, Array.init) }
    try bytes.withUnsafeBytes { try enqueue($0) }
  }

  /// The entries the extension dropped because the staging queue or this ring was full.
  public func droppedEntries() throws -> UInt64 {
    try memory.load(UInt64.self, fromByteOffset: FastPathDataQueueLayout.droppedEntriesOffset)
  }
}
