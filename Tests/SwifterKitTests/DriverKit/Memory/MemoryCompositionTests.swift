import Foundation
import Testing

@testable import SwifterKit

/// Subrange and chain commands: their payloads, Swift-side bounds, and handle decoding.
@Suite
struct MemoryCompositionTests {
  private static let handle = DriverMemoryHandle(rawValue: 5)

  @Test
  func encodesSubrange() throws {
    let command = try DriverCommand.memorySubrange(
      Self.handle,
      offset: 0x40,
      length: 0x100,
      direction: .deviceReads
    )
    #expect(command.opcode == RuntimeOpcode.memorySubrange.rawValue)
    #expect(command.requiredCapabilities == .memory)
    #expect(command.payload.count == RuntimeMemoryLimits.subrangeHeaderSize)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt64 == 5)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt64 == 0x40)
    #expect(try command.payload.readRuntimeInteger(at: 16) as UInt64 == 0x100)
    #expect(try command.payload.readRuntimeInteger(at: 24) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 28) as UInt32 == 0)
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 8)
  }

  @Test
  func validatesSubrange() {
    #expect(throws: DriverMemoryError.invalidHandle) {
      try DriverCommand.memorySubrange(
        DriverMemoryHandle(rawValue: 0),
        offset: 0,
        length: 1,
        direction: .bidirectional
      )
    }
    #expect(throws: DriverMemoryError.invalidSize) {
      try DriverCommand.memorySubrange(Self.handle, offset: 0, length: 0, direction: .bidirectional)
    }
    #expect(throws: DriverMemoryError.invalidRange) {
      try DriverCommand.memorySubrange(
        Self.handle,
        offset: .max,
        length: 1,
        direction: .bidirectional
      )
    }
    #expect(throws: Never.self) {
      try DriverCommand.memorySubrange(
        Self.handle,
        offset: .max - 1,
        length: 1,
        direction: .bidirectional
      )
    }
  }

  @Test
  func encodesChainAtBothBounds() throws {
    let single = try DriverCommand.memoryChain([Self.handle], direction: .deviceWrites)
    #expect(single.opcode == RuntimeOpcode.memoryChain.rawValue)
    #expect(single.payload.count == RuntimeMemoryLimits.chainHeaderSize + 8)
    #expect(try single.payload.readRuntimeInteger(at: 0) as UInt32 == 1)
    #expect(try single.payload.readRuntimeInteger(at: 4) as UInt32 == 1)
    #expect(try single.payload.readRuntimeInteger(at: 8) as UInt64 == 5)

    let handles = (1...UInt64(RuntimeMemoryLimits.maximumChainLength)).map(
      DriverMemoryHandle.init(rawValue:)
    )
    let full = try DriverCommand.memoryChain(handles, direction: .bidirectional)
    #expect(full.payload.count == RuntimeMemoryLimits.chainHeaderSize + 32 * 8)
    #expect(try full.payload.readRuntimeInteger(at: 0) as UInt32 == 32)
    #expect(try full.payload.readRuntimeInteger(at: 8 + 31 * 8) as UInt64 == 32)
  }

  @Test
  func validatesChain() {
    #expect(throws: DriverMemoryError.invalidChainLength) {
      try DriverCommand.memoryChain([], direction: .bidirectional)
    }
    #expect(throws: DriverMemoryError.invalidChainLength) {
      try DriverCommand.memoryChain(
        Array(repeating: Self.handle, count: RuntimeMemoryLimits.maximumChainLength + 1),
        direction: .bidirectional
      )
    }
    #expect(throws: DriverMemoryError.invalidHandle) {
      try DriverCommand.memoryChain(
        [Self.handle, DriverMemoryHandle(rawValue: 0)],
        direction: .bidirectional
      )
    }
  }

  @Test
  func decodesHandlesWithinTheClientMemoryRange() throws {
    func payload(_ value: UInt64) -> Data {
      var data = Data()
      data.appendRuntimeInteger(value)
      return data
    }
    #expect(
      try DriverMemoryHandle(runtimePayload: payload(RuntimeMemoryLimits.maximumHandle)).rawValue
        == 0xFF_FFFF
    )
    #expect(throws: DriverMemoryError.invalidPayload) {
      try DriverMemoryHandle(runtimePayload: payload(0))
    }
    #expect(throws: DriverMemoryError.invalidPayload) {
      try DriverMemoryHandle(runtimePayload: payload(RuntimeMemoryLimits.maximumHandle + 1))
    }
    #expect(throws: DriverMemoryError.invalidPayload) {
      try DriverMemoryHandle(runtimePayload: Data([1, 0, 0, 0]))
    }
  }
}
