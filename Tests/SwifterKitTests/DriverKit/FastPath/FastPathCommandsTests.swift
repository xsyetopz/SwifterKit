import Foundation
import Testing

@testable import SwifterKit

@Suite
struct FastPathCommandsTests {
  static let configuration = FastPathConfiguration(programs: [
    FastPathProgram(trigger: .start, operations: [.delay(microseconds: 1)]),
    FastPathProgram(
      trigger: .command,
      argumentCount: 2,
      operations: [.compute(.v0, .add, .value(.v1))]
    ),
  ])

  @Test
  func encodesRunRequests() throws {
    let command = try DriverCommand.runFastPathProgram(1, arguments: [0x1122, .max])
    #expect(command.opcode == 0x0F00)
    #expect(command.requiredCapabilities.isEmpty)
    #expect(command.maximumResponseSize == RuntimeMessage.headerSize + 72)
    #expect(command.payload.count == 40)
    #expect(try command.payload.readRuntimeInteger(at: 0) as UInt32 == 1)
    #expect(try command.payload.readRuntimeInteger(at: 4) as UInt32 == 2)
    #expect(try command.payload.readRuntimeInteger(at: 8) as UInt64 == 0x1122)
    #expect(try command.payload.readRuntimeInteger(at: 16) as UInt64 == .max)
    #expect(command.payload[24...].allSatisfy { $0 == 0 })

    let status = DriverCommand.fastPathStatus
    #expect(status.opcode == 0x0F01)
    #expect(status.payload.isEmpty)
    #expect(status.maximumResponseSize == RuntimeMessage.headerSize + 16)
  }

  @Test
  func refusesRequestsBeforeSending() {
    #expect(throws: FastPathRuntimeError.unknownProgram(-1)) {
      try DriverCommand.runFastPathProgram(-1)
    }
    #expect(throws: FastPathRuntimeError.unknownProgram(32)) {
      try DriverCommand.runFastPathProgram(32)
    }
    #expect(throws: FastPathRuntimeError.invalidArgumentCount(program: 0, count: 5)) {
      try DriverCommand.runFastPathProgram(0, arguments: [1, 2, 3, 4, 5])
    }
    let configuration = Self.configuration
    #expect(throws: FastPathRuntimeError.unknownProgram(2)) {
      try DriverCommand.runFastPathProgram(2, in: configuration)
    }
    #expect(throws: FastPathRuntimeError.notACommandProgram(0)) {
      try DriverCommand.runFastPathProgram(0, in: configuration)
    }
    #expect(throws: FastPathRuntimeError.invalidArgumentCount(program: 1, count: 1)) {
      try DriverCommand.runFastPathProgram(1, arguments: [1], in: configuration)
    }
    #expect(throws: Never.self) {
      try DriverCommand.runFastPathProgram(1, arguments: [1, 2], in: configuration)
    }
  }

  @Test
  func contextChecksTheConfigurationAndDecodesReplies() async throws {
    let backend = FastPathMockConnection()
    let session = DriverSession(
      service: DriverService(id: 1, name: "FastPath"),
      connection: backend
    )
    let runtime = try await DriverRuntimeConnection.connect(session: session)
    let context = await DriverContext(runtime: runtime, fastPath: Self.configuration)

    let result = try await context.runFastPathProgram(1, arguments: [7, 9])
    #expect(result == FastPathResult(status: 0, values: [7, 9, 1, 0, 0, 0, 0, 0xFFFF_FFFF]))
    #expect(result.succeeded)
    let commands = await backend.commands
    #expect(commands.map(\.opcode) == [0x0F00])

    await #expect(throws: FastPathRuntimeError.notACommandProgram(0)) {
      try await context.runFastPathProgram(0)
    }
    #expect(await backend.commands.count == 1)

    await backend.setRunStatus(0xE000_02D6)
    let timedOut = try await context.runFastPathProgram(1, arguments: [0, 0])
    #expect(timedOut.status == Int32(bitPattern: 0xE000_02D6))
    #expect(!timedOut.succeeded)

    let status = try await context.fastPathStatus()
    #expect(status == FastPathStatus(status: Int32(bitPattern: 0xE000_02BE), droppedEvents: 3))
    #expect(!status.isRunning)
  }

  @Test
  func decodesEmittedEvents() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(4))
    payload.appendRuntimeInteger(UInt32(3))
    for value: UInt64 in [0xAA, 0, .max, 0, 0, 0, 0, 0] { payload.appendRuntimeInteger(value) }
    let event = DriverEvent(type: 0x0F00, payload: Array(payload))
    #expect(try event.fastPath() == FastPathEvent(program: 4, values: [0xAA, 0, .max]))
    #expect(try DriverEvent(type: 0x0100, payload: Array(payload)).fastPath() == nil)

    var extra = payload
    extra[8 + 8 * 3] = 1
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0F00, payload: Array(extra)).fastPath()
    }
    var empty = payload
    empty[4] = 0
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0F00, payload: Array(empty)).fastPath()
    }
    var program = payload
    program[0] = 32
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0F00, payload: Array(program)).fastPath()
    }
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0F00, payload: Array(payload.dropLast())).fastPath()
    }
  }

  @Test
  func rejectsMalformedReplies() {
    var reply = Data(count: 72)
    reply[4] = 1
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try FastPathResult(runtimePayload: reply)
    }
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try FastPathResult(runtimePayload: Data(count: 64))
    }
    #expect(throws: FastPathRuntimeError.invalidPayload) {
      try FastPathStatus(runtimePayload: Data(count: 12))
    }
  }
}

/// Answers the handshake, then a run with the request's arguments followed by the program index
/// in `v2` and `0xFFFF_FFFF` in `v7`, and a status query with a refused fast path.
private actor FastPathMockConnection: DriverConnection {
  var commands: [(opcode: UInt32, payload: Data)] = []
  var runStatus: UInt32 = 0

  func setRunStatus(_ status: UInt32) { runStatus = status }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    let message = try RuntimeMessage(decoding: request.structureInput)
    var payload = Data()
    switch message.kind {
    case .handshake:
      payload = RuntimeHandshakeAcceptance(version: .current, capabilities: []).encoded()
    case .command:
      let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
      let body = Data(message.payload.dropFirst(RuntimeSchema.commandHeaderSize))
      commands.append((opcode, body))
      if opcode == RuntimeOpcode.fastPathRun.rawValue {
        payload.appendRuntimeInteger(runStatus)
        payload.appendRuntimeInteger(UInt32(0))
        payload.appendRuntimeInteger(try body.readRuntimeInteger(at: 8) as UInt64)
        payload.appendRuntimeInteger(try body.readRuntimeInteger(at: 16) as UInt64)
        payload.appendRuntimeInteger(UInt64(try body.readRuntimeInteger(at: 0) as UInt32))
        for value: UInt64 in [0, 0, 0, 0, 0xFFFF_FFFF] { payload.appendRuntimeInteger(value) }
      } else if opcode == RuntimeOpcode.fastPathStatus.rawValue {
        payload.appendRuntimeInteger(UInt32(0xE000_02BE))
        payload.appendRuntimeInteger(UInt32(0))
        payload.appendRuntimeInteger(UInt64(3))
      }
    case .response, .event, .error: throw RuntimeProtocolError.unknownMessageKind
    }
    return DriverResponse(
      structureOutput: try RuntimeMessage(
        kind: .response,
        requestID: message.requestID,
        payload: payload
      ).encoded()
    )
  }

  func notifications(selector: UInt32) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  func close() {}

  func mapMemory(type: UInt32, readOnly: Bool) throws -> DriverSharedMemory {
    throw MappingUnsupported()
  }
}
