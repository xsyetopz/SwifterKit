import Foundation

/// A host-shared data queue: a ring of records the extension and the host exchange without a
/// runtime command per entry.
///
/// The extension allocates the host ring when the fast path starts, and Swift maps it with
/// ``DriverContext/mapDataQueue(_:)``. For a ``FastPathDataQueueDirection/toHost`` queue, fast-path
/// programs produce entries with ``FastPathOp/enqueue(_:slots:)``: the extension stages them in an
/// `IODataQueueDispatchSource` from the interrupt or command that ran the program, publishes them
/// into the host ring on its runtime queue, and queues one ``FastPathDataQueueEvent`` per
/// published batch. Entries are lossy: one that finds the staging queue or the host ring full is
/// dropped and counted in ``DriverDataQueue/droppedEntries()``.
public struct FastPathDataQueue: Sendable, Hashable {
  /// The queue's identifier, unique in its configuration and at most `0xFF_FFFF`; operations and
  /// ``DriverContext/mapDataQueue(_:)`` name the queue by it.
  public let id: UInt32
  /// The bytes of the host ring's records, a power of two from 4096 through 1 MiB.
  public let capacityBytes: UInt32
  /// The most payload bytes one entry holds, a multiple of 8 from 8 through 64.
  public let maximumEntrySize: UInt32
  /// Which side produces entries.
  public let direction: FastPathDataQueueDirection

  /// Creates a data queue declaration.
  public init(
    id: UInt32,
    capacityBytes: UInt32,
    maximumEntrySize: UInt32,
    direction: FastPathDataQueueDirection
  ) {
    self.id = id
    self.capacityBytes = capacityBytes
    self.maximumEntrySize = maximumEntrySize
    self.direction = direction
  }

  /// The bytes of one record: the smallest power of two that holds the record header and the
  /// maximum entry.
  public var recordStride: UInt32 {
    let bytes = UInt32(FastPathDataQueueLayout.recordHeaderSize) &+ maximumEntrySize
    var stride: UInt32 = 1
    while stride < bytes, stride <= UInt32.max / 2 { stride <<= 1 }
    return stride
  }

  /// The records the host ring holds.
  public var entryCount: UInt32 { capacityBytes / max(recordStride, 1) }

  /// The bytes the host ring occupies: its header and every record.
  public var byteCount: UInt64 {
    UInt64(FastPathDataQueueLayout.headerSize) + UInt64(capacityBytes)
  }
}

/// Which side of a ``FastPathDataQueue`` produces entries.
public enum FastPathDataQueueDirection: Sendable, Hashable, CaseIterable {
  /// Fast-path programs produce entries with ``FastPathOp/enqueue(_:slots:)``; the host reads
  /// them.
  case toHost
  /// The host produces entries; the extension consumes them.
  case toExtension
}

/// The byte layout of a data queue host ring, shared by the extension and ``DriverDataQueue``.
///
/// The header holds little-endian fields; the rest of it is zero. Records follow the header at
/// ``FastPathDataQueue/recordStride`` intervals. The producer and consumer fields are free-running
/// `UInt32` record counts: record `n` lives at slot `n & (entryCount - 1)`, the ring is empty when
/// they are equal, and the producer is never more than `entryCount` ahead. A record starts with its
/// payload byte count as a `UInt32` and four zero bytes, followed by the payload. The producer
/// writes a record before it stores its count with release ordering, and the consumer loads the
/// producer count with acquire ordering before it reads records, and stores its own count after it
/// is done with them.
public enum FastPathDataQueueLayout {
  /// The header bytes before record 0.
  public static let headerSize = RuntimeFastPathLimits.dataQueueHeaderSize
  /// The offset of the producer's record count.
  public static let producerOffset = RuntimeFastPathLimits.dataQueueProducerOffset
  /// The offset of the consumer's record count.
  public static let consumerOffset = RuntimeFastPathLimits.dataQueueConsumerOffset
  /// The offset of the record count, a power of two.
  public static let entryCountOffset = RuntimeFastPathLimits.dataQueueEntryCountOffset
  /// The offset of the record stride in bytes, a power of two.
  public static let strideOffset = RuntimeFastPathLimits.dataQueueStrideOffset
  /// The offset of the maximum entry payload size.
  public static let maximumEntrySizeOffset = RuntimeFastPathLimits.dataQueueMaximumEntrySizeOffset
  /// The offset of the direction: 0 for ``FastPathDataQueueDirection/toHost``, 1 for
  /// ``FastPathDataQueueDirection/toExtension``.
  public static let directionOffset = RuntimeFastPathLimits.dataQueueDirectionOffset
  /// The offset of the `UInt64` count of entries the extension dropped.
  public static let droppedEntriesOffset = RuntimeFastPathLimits.dataQueueDropsOffset
  /// The bytes before a record's payload.
  public static let recordHeaderSize = RuntimeFastPathLimits.dataQueueRecordHeaderSize
}

/// A ``FastPathDataQueue`` batch the extension published into its host ring.
public struct FastPathDataQueueEvent: Sendable, Hashable {
  /// The queue's identifier.
  public let queue: UInt32
  /// The entries the batch published.
  public let publishedEntries: UInt32
  /// Every entry the queue dropped so far.
  public let droppedEntries: UInt64

  /// Creates a data queue event.
  public init(queue: UInt32, publishedEntries: UInt32, droppedEntries: UInt64) {
    self.queue = queue
    self.publishedEntries = publishedEntries
    self.droppedEntries = droppedEntries
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == RuntimeFastPathRow.dataQueueEvent.size else {
      throw FastPathRuntimeError.invalidPayload
    }
    let queue: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let published: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let dropped: UInt64 = try runtimePayload.readRuntimeInteger(at: 8)
    guard queue <= RuntimeClientMemoryType.identifierMask, published != 0 else {
      throw FastPathRuntimeError.invalidPayload
    }
    self.init(queue: queue, publishedEntries: published, droppedEntries: dropped)
  }
}

extension DriverEvent {
  /// Decodes a data queue batch notification.
  ///
  /// The notification travels on the lossy event queue, so it is a hint: read the host ring with
  /// ``DriverDataQueue/dequeue(_:)`` until it is empty rather than counting on one event per
  /// batch. Returns nil when the event belongs to another family.
  public func fastPathDataQueue() throws -> FastPathDataQueueEvent? {
    guard type == RuntimeEventType.fastPathDataQueue.rawValue else { return nil }
    return try FastPathDataQueueEvent(runtimePayload: Data(payload))
  }
}

extension FastPathConfiguration {
  /// Checks the data queue declarations and returns them keyed by identifier.
  func validatedDataQueues() throws(FastPathError) -> [UInt32: FastPathDataQueue] {
    guard dataQueues.count <= FastPathLimits.maximumDataQueues else {
      throw .tooManyDataQueues(count: dataQueues.count)
    }
    var byID: [UInt32: FastPathDataQueue] = [:]
    var bytes: UInt64 = 0
    for queue in dataQueues {
      guard queue.id <= RuntimeClientMemoryType.identifierMask,
        FastPathLimits.dataQueueCapacities.contains(Int(queue.capacityBytes)),
        queue.capacityBytes.nonzeroBitCount == 1,
        FastPathLimits.dataQueueEntrySizes.contains(Int(queue.maximumEntrySize)),
        queue.maximumEntrySize.isMultiple(of: 8), queue.entryCount >= 2
      else { throw .invalidDataQueue(queue: queue.id) }
      guard byID.updateValue(queue, forKey: queue.id) == nil else {
        throw .duplicateDataQueue(queue: queue.id)
      }
      bytes += queue.byteCount
    }
    guard bytes <= UInt64(FastPathLimits.maximumDataQueueBytes) else {
      throw .dataQueueBytesExceeded(bytes: bytes)
    }
    return byID
  }
}
