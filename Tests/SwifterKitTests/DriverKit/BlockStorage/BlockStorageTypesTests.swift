import Foundation
import Testing

@testable import SwifterKit

@Suite struct BlockStorageTypesTests {
  @Test func encodesCompletionCommands() throws {
    let normal = DriverCommand.completeBlockStorageRequest(
      requestID: 7,
      status: BlockStorageCompletionStatus(rawValue: -3)
    )
    let io = DriverCommand.completeBlockStorageIO(requestID: 9, bytesTransferred: 4_096)

    #expect(normal.opcode == 0x0700)
    #expect(normal.requiredCapabilities == .blockStorage)
    #expect(try normal.payload.readRuntimeInteger(at: 0) as UInt32 == 7)
    #expect(try normal.payload.readRuntimeInteger(at: 4) as Int32 == -3)
    #expect(io.opcode == 0x0701)
    #expect(try io.payload.readRuntimeInteger(at: 8) as UInt64 == 4_096)
  }

  @Test func decodesReadAndWriteRequests() throws {
    let read = DriverEvent(type: 0x0700, payload: ioPayload(kind: 4))
    let write = DriverEvent(type: 0x0700, payload: ioPayload(kind: 5))
    let expected = BlockStorageIORequest(
      requestID: 11,
      dmaAddress: 0x1234,
      byteCount: 8_192,
      startBlock: 20,
      blockCount: 2,
      options: .forceUnitAccess
    )

    #expect(try read.blockStorage() == .read(expected))
    #expect(try write.blockStorage() == .write(expected))
  }

  @Test func decodesControlRequests() throws {
    #expect(try event(kind: 1, requestID: 3).blockStorage() == .eject(requestID: 3))

    var synchronize = Data(event(kind: 2, requestID: 4).payload)
    synchronize.appendRuntimeInteger(UInt64(9))
    synchronize.appendRuntimeInteger(UInt64(10))
    #expect(
      try DriverEvent(type: 0x0700, payload: Array(synchronize)).blockStorage()
        == .synchronize(requestID: 4, startBlock: 9, blockCount: 10)
    )

    var unmap = Data(event(kind: 3, requestID: 5).payload)
    unmap.appendRuntimeInteger(UInt32(1))
    unmap.appendRuntimeInteger(UInt32(0))
    unmap.appendRuntimeInteger(UInt64(30))
    unmap.appendRuntimeInteger(UInt64(4))
    #expect(
      try DriverEvent(type: 0x0700, payload: Array(unmap)).blockStorage()
        == .unmap(requestID: 5, ranges: [BlockStorageRange(startBlock: 30, blockCount: 4)])
    )
  }

  @Test func rejectsMalformedAndForeignEvents() throws {
    #expect(try DriverEvent(type: 0x0100).blockStorage() == nil)
    #expect(throws: BlockStorageRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0700, payload: [1]).blockStorage()
    }
    #expect(throws: BlockStorageRuntimeError.invalidRequestKind(99)) {
      try event(kind: 99, requestID: 1).blockStorage()
    }
  }

  private func event(kind: UInt32, requestID: UInt32) -> DriverEvent {
    var data = Data()
    data.appendRuntimeInteger(kind)
    data.appendRuntimeInteger(requestID)
    return DriverEvent(type: 0x0700, payload: Array(data))
  }

  private func ioPayload(kind: UInt32) -> [UInt8] {
    var data = Data(event(kind: kind, requestID: 11).payload)
    data.appendRuntimeInteger(UInt64(0x1234))
    data.appendRuntimeInteger(UInt64(8_192))
    data.appendRuntimeInteger(UInt64(20))
    data.appendRuntimeInteger(UInt64(2))
    data.appendRuntimeInteger(BlockStorageOptions.forceUnitAccess.rawValue)
    data.appendRuntimeInteger(UInt32(0))
    return Array(data)
  }
}
