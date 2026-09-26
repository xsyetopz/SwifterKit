import Foundation
import Testing

@testable import SwifterKit

/// Bounds, byte order, read-only refusal, and exactly-once unmapping of shared memory.
@Suite
struct DriverSharedMemoryTests {
  @Test
  func loadsAndStoresLittleEndianIntegersAtAnyOffset() throws {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 1, readOnly: false)
    try memory.store(UInt32(0x0403_0201), toByteOffset: 1)
    #expect(try memory.copyBytes(fromByteOffset: 0, count: 6) == [0, 1, 2, 3, 4, 0])
    #expect(try memory.load(UInt32.self, fromByteOffset: 1) == 0x0403_0201)
    #expect(try memory.load(UInt16.self, fromByteOffset: 2) == 0x0302)
    try memory.store(UInt64.max, toByteOffset: 56)
    #expect(try memory.load(UInt64.self, fromByteOffset: 56) == .max)
    try memory.write([9, 8, 7], toByteOffset: 61)
    #expect(try memory.load(UInt8.self, fromByteOffset: 63) == 7)
    #expect(try memory.withUnsafeBytes { $0.count } == 64)
    try memory.withUnsafeMutableBytes { $0[0] = 0xAB }
    #expect(try memory.load(UInt8.self, fromByteOffset: 0) == 0xAB)
  }

  @Test
  func refusesRangesOutsideTheMappingWithoutTouchingIt() throws {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 1, readOnly: false)
    #expect(throws: DriverSharedMemoryError.outOfBounds(offset: 57, count: 8, length: 64)) {
      try memory.store(UInt64.max, toByteOffset: 57)
    }
    #expect(throws: DriverSharedMemoryError.outOfBounds(offset: -1, count: 1, length: 64)) {
      try memory.load(UInt8.self, fromByteOffset: -1)
    }
    #expect(throws: DriverSharedMemoryError.outOfBounds(offset: 60, count: 5, length: 64)) {
      try memory.write([1, 2, 3, 4, 5], toByteOffset: 60)
    }
    #expect(throws: DriverSharedMemoryError.outOfBounds(offset: .max, count: 2, length: 64)) {
      try memory.copyBytes(fromByteOffset: .max, count: 2)
    }
    #expect(try memory.copyBytes(fromByteOffset: 56, count: 8) == Array(repeating: 0, count: 8))
    #expect(try memory.copyBytes(fromByteOffset: 64, count: 0).isEmpty)
  }

  @Test
  func readOnlyMemoryRefusesStores() throws {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 2, readOnly: true)
    #expect(memory.isReadOnly)
    #expect(throws: DriverSharedMemoryError.readOnly) {
      try memory.store(UInt8(1), toByteOffset: 0)
    }
    #expect(throws: DriverSharedMemoryError.readOnly) { try memory.write([1], toByteOffset: 0) }
    #expect(throws: DriverSharedMemoryError.readOnly) { try memory.withUnsafeMutableBytes { _ in } }
    #expect(try memory.load(UInt8.self, fromByteOffset: 0) == 0)
  }

  @Test
  func unmapsExactlyOnce() throws {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 1, readOnly: false)
    memory.unmap()
    memory.unmap()
    #expect(!memory.isMapped)
    #expect(mappings.unmaps.total == 1)
    #expect(throws: DriverSharedMemoryError.unmapped) {
      try memory.load(UInt8.self, fromByteOffset: 0)
    }
    #expect(throws: DriverSharedMemoryError.unmapped) { try memory.withUnsafeBytes { _ in } }
  }

  @Test
  func unmapsWhenReleasedAndNotAgain() {
    var mappings = InMemoryMappings()
    do { _ = mappings.map(type: 1, readOnly: false) }
    #expect(mappings.unmaps.total == 1)
    do {
      let memory = mappings.map(type: 3, readOnly: false)
      memory.unmap()
    }
    #expect(mappings.unmaps.total == 2)
  }

  @Test
  func unmapInsideAnAccessWaitsForTheAccessToEnd() throws {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 1, readOnly: false)
    let unmaps = mappings.unmaps
    try memory.withUnsafeMutableBytes { bytes in
      memory.unmap()
      #expect(unmaps.total == 0)
      bytes[0] = 1
      #expect(!memory.isMapped)
    }
    #expect(unmaps.total == 1)
    #expect(throws: DriverSharedMemoryError.unmapped) {
      try memory.load(UInt8.self, fromByteOffset: 0)
    }
  }

  @Test
  func concurrentAccessesAndUnmapAreSerialized() async {
    var mappings = InMemoryMappings()
    let memory = mappings.map(type: 1, readOnly: false)
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<32 {
        group.addTask {
          if index == 16 { memory.unmap() }
          _ = try? memory.store(UInt64(index), toByteOffset: 8 * (index % 8))
        }
      }
    }
    #expect(!memory.isMapped)
    #expect(mappings.unmaps.total == 1)
  }
}
