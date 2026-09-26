import Foundation
import Testing

@testable import SwifterKit

/// Wrapping host memory: the request payload, Swift-side segment checks, and the page-aligned
/// host allocation that keeps wrapped pages alive.
@Suite
struct ClientMemoryWrapTests {
  @Test
  func encodesSegments() throws {
    let command = try DriverCommand.wrapClientMemory(
      [
        DriverClientMemorySegment(address: 0x1_0000, length: 0x4000),
        DriverClientMemorySegment(address: 0x8_0000, length: 1),
      ],
      direction: .deviceWrites
    )
    #expect(command.opcode == 0x050A)
    #expect(command.requiredCapabilities == .memory)
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 8)
    #expect(command.payload.count == 8 + 2 * 16)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 4) as UInt32 == 1)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt64 == 0x1_0000)
    #expect(try command.payload.readRuntimeInteger(at: 16) as UInt64 == 0x4000)
    #expect(try command.payload.readRuntimeInteger(at: 24) as UInt64 == 0x8_0000)
    #expect(try command.payload.readRuntimeInteger(at: 32) as UInt64 == 1)
  }

  @Test
  func refusesSegmentCountsAndRangesBeforeSending() throws {
    let segment = DriverClientMemorySegment(address: 0x1000, length: 0x1000)
    #expect(throws: DriverMemoryError.invalidSegmentCount) {
      try DriverCommand.wrapClientMemory([], direction: .bidirectional)
    }
    #expect(throws: DriverMemoryError.invalidSegmentCount) {
      try DriverCommand.wrapClientMemory(
        Array(repeating: segment, count: 33),
        direction: .bidirectional
      )
    }
    let most = try DriverCommand.wrapClientMemory(
      Array(repeating: segment, count: 32),
      direction: .bidirectional
    )
    #expect(most.payload.count == 8 + 32 * 16)
    #expect(throws: DriverMemoryError.invalidSegment) {
      try DriverCommand.wrapClientMemory(
        [DriverClientMemorySegment(address: 0x1000, length: 0)],
        direction: .deviceReads
      )
    }
    #expect(throws: DriverMemoryError.invalidSegment) {
      try DriverCommand.wrapClientMemory(
        [segment, DriverClientMemorySegment(address: .max, length: 1)],
        direction: .deviceReads
      )
    }
    #expect(throws: Never.self) {
      try DriverCommand.wrapClientMemory(
        [DriverClientMemorySegment(address: .max - 1, length: 1)],
        direction: .deviceReads
      )
    }
  }

  @Test
  func hostMemoryIsPageAlignedZeroedAndWholePages() throws {
    let page = DriverHostMemory.pageSize
    #expect(page > 0 && page & (page - 1) == 0)
    #expect(DriverHostMemory(minimumLength: 0) == nil)
    #expect(DriverHostMemory(minimumLength: .max) == nil)
    let memory = try #require(DriverHostMemory(minimumLength: page + 1))
    #expect(memory.length == 2 * page)
    #expect(memory.segment.length == UInt64(2 * page))
    #expect(memory.segment.address.isMultiple(of: UInt64(page)))
    memory.withUnsafeMutableBytes { bytes in
      #expect(bytes.allSatisfy { $0 == 0 })
      bytes[page] = 0xA5
    }
    #expect(memory.withUnsafeMutableBytes { $0[page] } == 0xA5)
    let command = try DriverCommand.wrapClientMemory([memory.segment], direction: .deviceReads)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt64 == memory.segment.address)
  }
}
