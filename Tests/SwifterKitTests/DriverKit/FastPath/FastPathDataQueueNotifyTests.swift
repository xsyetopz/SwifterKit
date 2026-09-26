import Foundation
import Testing

@testable import SwifterKit

/// The to-extension doorbell: its payload, the identifier checks Swift makes before sending, and
/// the reply it decodes.
@Suite
struct FastPathDataQueueNotifyTests {
  private static let configuration = FastPathConfiguration(
    programs: [
      FastPathProgram(
        trigger: .dataAvailable(4),
        argumentCount: 1,
        operations: [.delay(microseconds: 1)]
      )
    ],
    dataQueues: [
      FastPathDataQueue(id: 3, capacityBytes: 4096, maximumEntrySize: 8, direction: .toHost),
      FastPathDataQueue(id: 4, capacityBytes: 4096, maximumEntrySize: 8, direction: .toExtension),
    ]
  )

  private static func reply(
    status: UInt32 = 0,
    moved: UInt32 = 3,
    waiting: UInt32 = 2,
    reserved: UInt32 = 0,
    refusals: UInt64 = 1
  ) -> Data {
    var payload = Data()
    for value in [status, moved, waiting, reserved] { payload.appendRuntimeInteger(value) }
    payload.appendRuntimeInteger(refusals)
    return payload
  }

  @Test
  func commandCarriesTheIdentifierAndReservesTheRest() throws {
    let command = try DriverCommand.notifyDataQueue(4, in: Self.configuration)
    #expect(command.opcode == RuntimeOpcode.fastPathDataQueueNotify.rawValue)
    #expect(command.opcode == 0x0F02)
    #expect(command.payload == Data([4, 0, 0, 0, 0, 0, 0, 0]))
    #expect(command.payload.count == RuntimeFastPathRow.dataQueueNotifyRequest.size)
    #expect(
      command.maximumResponseSize == RuntimeMessage.headerSize
        + RuntimeFastPathRow.dataQueueNotifyReply.size
    )
    #expect(
      try DriverCommand.notifyDataQueue(0xFF_FFFF).payload.prefix(4) == Data([255, 255, 255, 0])
    )
  }

  @Test
  func commandRefusesQueuesTheHostDoesNotProduce() {
    #expect(throws: FastPathRuntimeError.unknownDataQueue(0x100_0000)) {
      try DriverCommand.notifyDataQueue(0x100_0000)
    }
    #expect(throws: FastPathRuntimeError.unknownDataQueue(3)) {
      try DriverCommand.notifyDataQueue(3, in: Self.configuration)
    }
    #expect(throws: FastPathRuntimeError.unknownDataQueue(9)) {
      try DriverCommand.notifyDataQueue(9, in: Self.configuration)
    }
  }

  @Test
  func replyDecodesMovedWaitingAndRefusals() throws {
    let moved = try FastPathDataQueueNotification(runtimePayload: Self.reply())
    #expect(
      moved
        == FastPathDataQueueNotification(status: 0, movedEntries: 3, waitingEntries: 2, refusals: 1)
    )
    #expect(moved.succeeded)
    let corrupt = try FastPathDataQueueNotification(
      runtimePayload: Self.reply(status: RuntimeFastPathStatus.corrupt.rawValue, waiting: 0)
    )
    #expect(!corrupt.succeeded)
    #expect(corrupt.status == Int32(bitPattern: 0xE000_02CA))
  }

  @Test
  func replyRejectsMalformedPayloads() {
    for payload in [
      Self.reply().dropLast(), Self.reply(reserved: 1), Self.reply(status: 0xE000_02C2),
    ] {
      #expect(throws: FastPathRuntimeError.invalidPayload) {
        try FastPathDataQueueNotification(runtimePayload: Data(payload))
      }
    }
  }
}
