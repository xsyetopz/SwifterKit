import Foundation
import Testing

@testable import SwifterKit

@Suite struct MemoryTypesTests {
  @Test func encodesAllocationAndAccess() throws {
    let allocate = try DriverCommand.allocateMemory(
      capacity: 4_096,
      length: 128,
      direction: .deviceReads,
      alignment: 64
    )
    #expect(allocate.opcode == 0x0500)
    #expect(allocate.requiredCapabilities == .memory)
    #expect(allocate.payload.count == 32)
    #expect(try allocate.payload.readRuntimeInteger(at: 0) as UInt64 == 4_096)
    #expect(try allocate.payload.readRuntimeInteger(at: 8) as UInt64 == 128)
    #expect(try allocate.payload.readRuntimeInteger(at: 24) as UInt32 == 2)

    let handle = DriverMemoryHandle(rawValue: 9)
    let write = try DriverCommand.writeMemory(handle, offset: 7, bytes: [1, 2, 3])
    #expect(write.opcode == 0x0504)
    #expect(write.payload.count == 27)
    #expect(Array(write.payload.suffix(3)) == [1, 2, 3])
  }

  @Test func validatesAllocationAndTransfers() {
    #expect(throws: DriverMemoryError.invalidSize) { try DriverCommand.allocateMemory(capacity: 0) }
    #expect(throws: DriverMemoryError.invalidSize) {
      try DriverCommand.allocateMemory(capacity: 4, length: 5)
    }
    #expect(throws: DriverMemoryError.invalidAlignment) {
      try DriverCommand.allocateMemory(capacity: 4_096, alignment: 3)
    }
    #expect(throws: DriverMemoryError.invalidHandle) {
      try DriverCommand.releaseMemory(DriverMemoryHandle(rawValue: 0))
    }
    #expect(throws: DriverMemoryError.transferTooLarge) {
      try DriverCommand.readMemory(
        DriverMemoryHandle(rawValue: 1),
        offset: 0,
        length: UInt32(DriverCommand.maximumMemoryTransferLength + 1)
      )
    }
    #expect(throws: DriverMemoryError.invalidAddressBits) {
      try DriverCommand.prepareMemoryForDMA(DriverMemoryHandle(rawValue: 1), maximumAddressBits: 0)
    }
  }

  @Test func decodesInfoAndDMASegments() throws {
    var info = Data()
    info.appendRuntimeInteger(UInt64(7))
    info.appendRuntimeInteger(UInt64(4_096))
    info.appendRuntimeInteger(UInt64(128))
    info.appendRuntimeInteger(DriverMemoryDirection.bidirectional.rawValue)
    info.appendRuntimeInteger(UInt32(64))
    #expect(
      try DriverMemoryInfo(runtimePayload: info)
        == DriverMemoryInfo(
          handle: DriverMemoryHandle(rawValue: 7),
          capacity: 4_096,
          length: 128,
          direction: .bidirectional,
          alignment: 64
        )
    )

    var dma = Data()
    dma.appendRuntimeInteger(UInt64(3))
    dma.appendRuntimeInteger(UInt32(2))
    dma.appendRuntimeInteger(UInt32(0))
    dma.appendRuntimeInteger(UInt64(0x1000))
    dma.appendRuntimeInteger(UInt64(256))
    dma.appendRuntimeInteger(UInt64(0x2000))
    dma.appendRuntimeInteger(UInt64(128))
    #expect(
      try DriverDMAMapping(runtimePayload: dma)
        == DriverDMAMapping(
          flags: 3,
          segments: [
            DriverDMASegment(address: 0x1000, length: 256),
            DriverDMASegment(address: 0x2000, length: 128),
          ]
        )
    )
  }

  @Test func rejectsMalformedNativeResults() {
    #expect(throws: DriverMemoryError.invalidPayload) {
      try DriverMemoryInfo(runtimePayload: Data(repeating: 0, count: 31))
    }
    var dma = Data(repeating: 0, count: 16)
    dma[8] = 33
    #expect(throws: DriverMemoryError.invalidPayload) { try DriverDMAMapping(runtimePayload: dma) }
  }
}
