import Foundation

@testable import SwifterKit

// @unchecked Sendable: `lock` guards `value`.
/// Counts how often in-memory mappings were removed.
final class UnmapCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// The number of unmaps so far.
  var total: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func increment() {
    lock.lock()
    value += 1
    lock.unlock()
  }
}

/// The in-memory stand-in for `IOConnectMapMemory64` that mock connections share: zeroed
/// allocations, one live instance per memory type, and every mapping unmapped on close.
struct InMemoryMappings {
  /// Bytes each new mapping gets.
  var length = 64
  let unmaps = UnmapCounter()
  private(set) var types: [UInt32] = []
  private var live: [UInt32: WeakMapping] = [:]

  mutating func map(type: UInt32, readOnly: Bool) -> DriverSharedMemory {
    if let existing = live[type]?.memory, existing.isMapped { return existing }
    types.append(type)
    let base = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
    base.initializeMemory(as: UInt8.self, repeating: 0, count: length)
    let address = UInt(bitPattern: base)
    let unmaps = self.unmaps
    let memory = DriverSharedMemory(baseAddress: base, length: length, isReadOnly: readOnly) {
      UnsafeMutableRawPointer(bitPattern: address)?.deallocate()
      unmaps.increment()
    }
    live[type] = WeakMapping(memory: memory)
    return memory
  }

  mutating func unmapAll() {
    for mapping in live.values { mapping.memory?.unmap() }
    live = [:]
  }

  private struct WeakMapping { weak var memory: DriverSharedMemory? }
}

/// Thrown by mock connections whose tests do not map memory.
struct MappingUnsupported: Error {}
