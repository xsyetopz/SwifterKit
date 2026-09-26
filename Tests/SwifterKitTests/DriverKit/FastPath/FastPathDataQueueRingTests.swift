import Foundation
import Testing

@testable import SwifterKit

/// The portable data queue host ring: geometry checks, wrap, empty and full rings, and indices or
/// sizes a corrupt producer wrote.
@Suite
struct FastPathDataQueueRingTests {
  /// 4096 bytes of 16-byte records (8-byte entries), so 256 records.
  private static let queue = FastPathDataQueue(
    id: 3,
    capacityBytes: 4096,
    maximumEntrySize: 8,
    direction: .toHost
  )

  /// A zeroed host ring with the header the extension writes at start.
  private final class Ring: @unchecked Sendable {
    let pointer: UnsafeMutableRawBufferPointer
    let memory: DriverSharedMemory

    init(_ queue: FastPathDataQueue = FastPathDataQueueRingTests.queue) {
      let count = Int(queue.byteCount)
      pointer = .allocate(byteCount: count, alignment: 16)
      pointer.initializeMemory(as: UInt8.self, repeating: 0)
      memory = DriverSharedMemory(
        baseAddress: pointer.baseAddress!,
        length: count,
        isReadOnly: false
      ) {}
      set(FastPathDataQueueLayout.entryCountOffset, queue.entryCount)
      set(FastPathDataQueueLayout.strideOffset, queue.recordStride)
      set(FastPathDataQueueLayout.maximumEntrySizeOffset, queue.maximumEntrySize)
    }

    deinit { pointer.deallocate() }

    func set(_ offset: Int, _ value: UInt32) {
      pointer.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self)
    }

    func get(_ offset: Int) -> UInt32 {
      UInt32(littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    /// Produces one entry as the extension does.
    func produce(_ value: UInt64) throws {
      let ring = try FastPathDataQueueRing(
        header: UnsafeRawBufferPointer(pointer),
        expecting: FastPathDataQueueRingTests.queue
      )
      try withUnsafeBytes(of: value.littleEndian) { try ring.enqueue(pointer, $0) }
    }
  }

  @Test
  func geometryFollowsTheDeclaration() {
    #expect(Self.queue.recordStride == 16)
    #expect(Self.queue.entryCount == 256)
    #expect(Self.queue.byteCount == 64 + 4096)
    let widest = FastPathDataQueue(
      id: 1,
      capacityBytes: 4096,
      maximumEntrySize: 64,
      direction: .toHost
    )
    #expect(widest.recordStride == 128)
    #expect(widest.entryCount == 32)
  }

  @Test
  func emptyRingDequeuesNothing() throws {
    let ring = Ring()
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    #expect(try queue.dequeueValues() == nil)
    #expect(try queue.droppedEntries() == 0)
  }

  @Test
  func entriesArriveInOrderAcrossTheWrap() throws {
    let ring = Ring()
    // Start both counts just below the UInt32 wrap and record 255, so records and counts wrap.
    ring.set(FastPathDataQueueLayout.producerOffset, UInt32.max - 1)
    ring.set(FastPathDataQueueLayout.consumerOffset, UInt32.max - 1)
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    for value in UInt64(1)...4 { try ring.produce(value) }
    #expect(ring.get(FastPathDataQueueLayout.producerOffset) == 2)
    var values: [UInt64] = []
    while let entry = try queue.dequeueValues() { values += entry }
    #expect(values == [1, 2, 3, 4])
    #expect(ring.get(FastPathDataQueueLayout.consumerOffset) == 2)
  }

  @Test
  func fullRingRefusesTheProducerAndDrainsCompletely() throws {
    let ring = Ring()
    for value in 0..<UInt64(Self.queue.entryCount) { try ring.produce(value) }
    #expect(throws: FastPathDataQueueError.full) { try ring.produce(99) }
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    var count: UInt64 = 0
    while let entry = try queue.dequeueValues() {
      #expect(entry == [count])
      count += 1
    }
    #expect(count == UInt64(Self.queue.entryCount))
  }

  @Test
  func entryIsReadInPlaceAndReleasedOnlyAfterTheBody() throws {
    let ring = Ring()
    try ring.produce(0xAABB)
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    struct Stop: Error {}
    #expect(throws: Stop.self) { _ = try queue.dequeue { _ in throw Stop() } }
    #expect(ring.get(FastPathDataQueueLayout.consumerOffset) == 0)
    let size = try queue.dequeue { $0.count }
    #expect(size == 8)
    #expect(ring.get(FastPathDataQueueLayout.consumerOffset) == 1)
  }

  @Test
  func corruptProducerIndexIsRejected() throws {
    let ring = Ring()
    ring.set(FastPathDataQueueLayout.producerOffset, 257)
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    #expect(throws: FastPathDataQueueError.invalidIndices(producer: 257, consumer: 0)) {
      try queue.dequeueValues()
    }
    ring.set(FastPathDataQueueLayout.producerOffset, 0)
    ring.set(FastPathDataQueueLayout.consumerOffset, 1)
    #expect(throws: FastPathDataQueueError.invalidIndices(producer: 0, consumer: 1)) {
      try queue.dequeueValues()
    }
  }

  @Test
  func corruptEntrySizeIsRejected() throws {
    let ring = Ring()
    ring.set(FastPathDataQueueLayout.producerOffset, 1)
    ring.set(FastPathDataQueueLayout.headerSize, 9)
    let queue = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    #expect(throws: FastPathDataQueueError.invalidEntrySize(9)) { try queue.dequeueValues() }
  }

  @Test(arguments: [
    (FastPathDataQueueLayout.entryCountOffset, UInt32(3)),
    (FastPathDataQueueLayout.entryCountOffset, UInt32(512)),
    (FastPathDataQueueLayout.strideOffset, UInt32(8)),
    (FastPathDataQueueLayout.strideOffset, UInt32(24)),
    (FastPathDataQueueLayout.maximumEntrySizeOffset, UInt32(0)),
    (FastPathDataQueueLayout.maximumEntrySizeOffset, UInt32(16)),
  ])
  func corruptGeometryIsRejected(offset: Int, value: UInt32) throws {
    let ring = Ring()
    ring.set(offset, value)
    let queue = DriverDataQueue(memory: ring.memory)
    #expect(throws: FastPathDataQueueError.invalidGeometry) { try queue.dequeueValues() }
  }

  @Test
  func geometryMustMatchTheDeclaration() throws {
    let ring = Ring()
    ring.set(FastPathDataQueueLayout.entryCountOffset, 128)
    #expect(try DriverDataQueue(memory: ring.memory).dequeueValues() == nil)
    let declared = DriverDataQueue(memory: ring.memory, queue: Self.queue)
    #expect(throws: FastPathDataQueueError.invalidGeometry) { try declared.dequeueValues() }
  }

  @Test
  func producerRefusesEmptyAndOversizedEntries() throws {
    let ring = Ring()
    let view = try FastPathDataQueueRing(
      header: UnsafeRawBufferPointer(ring.pointer),
      expecting: Self.queue
    )
    #expect(throws: FastPathDataQueueError.invalidEntry(byteCount: 0)) {
      try view.enqueue(ring.pointer, UnsafeRawBufferPointer(start: nil, count: 0))
    }
    let wide = [UInt8](repeating: 1, count: 9)
    #expect(throws: FastPathDataQueueError.invalidEntry(byteCount: 9)) {
      try wide.withUnsafeBytes { try view.enqueue(ring.pointer, $0) }
    }
  }

  @Test
  func eventDecodesAndRejectsMalformedPayloads() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(3))
    payload.appendRuntimeInteger(UInt32(2))
    payload.appendRuntimeInteger(UInt64(7))
    let event = try DriverEvent(
      type: RuntimeEventType.fastPathDataQueue.rawValue,
      payload: [UInt8](payload)
    ).fastPathDataQueue()
    #expect(event == FastPathDataQueueEvent(queue: 3, publishedEntries: 2, droppedEntries: 7))
    #expect(
      try DriverEvent(type: RuntimeEventType.fastPath.rawValue, payload: []).fastPathDataQueue()
        == nil
    )
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try DriverEvent(
        type: RuntimeEventType.fastPathDataQueue.rawValue,
        payload: [UInt8](payload.prefix(12))
      ).fastPathDataQueue()
    }
  }
}
