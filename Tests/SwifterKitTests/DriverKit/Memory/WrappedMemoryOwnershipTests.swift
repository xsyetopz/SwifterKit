import Foundation
import Testing

@testable import SwifterKit

/// How Swift reports the extension refusing memory another connection wrapped: every command
/// that names a handle throws ``DriverMemoryError/notOwner``, a release still throws
/// ``DriverMemoryError/inUse`` for its own status, and a wrap's own refusal is not relabeled.
@Suite
struct WrappedMemoryOwnershipTests {
  private static let foreign = DriverMemoryHandle(rawValue: 7)

  @Test
  func everyHandleCommandFromAnotherConnectionThrowsNotOwner() async throws {
    let context = try await makeContext(ForeignMemoryConnection())
    let handle = Self.foreign
    await #expect(throws: DriverMemoryError.notOwner) {
      _ = try await context.readMemory(handle, offset: 0, length: 4)
    }
    await #expect(throws: DriverMemoryError.notOwner) {
      try await context.writeMemory(handle, offset: 0, bytes: [1])
    }
    await #expect(throws: DriverMemoryError.notOwner) { _ = try await context.memoryInfo(handle) }
    await #expect(throws: DriverMemoryError.notOwner) {
      try await context.setMemoryLength(handle, length: 1)
    }
    await #expect(throws: DriverMemoryError.notOwner) {
      _ = try await context.prepareMemoryForDMA(handle)
    }
    await #expect(throws: DriverMemoryError.notOwner) {
      try await context.completeMemoryDMA(handle)
    }
    await #expect(throws: DriverMemoryError.notOwner) {
      _ = try await context.memorySubrange(handle, offset: 0, length: 1, direction: .deviceReads)
    }
    await #expect(throws: DriverMemoryError.notOwner) {
      _ = try await context.memoryChain([handle], direction: .deviceReads)
    }
    await #expect(throws: DriverMemoryError.notOwner) { try await context.releaseMemory(handle) }
  }

  @Test
  func releaseKeepsInUseAndAWrapKeepsItsOwnStatus() async throws {
    let context = try await makeContext(ForeignMemoryConnection())
    await #expect(throws: DriverMemoryError.inUse) {
      try await context.releaseMemory(DriverMemoryHandle(rawValue: 1))
    }
    // CreateMemoryDescriptorFromClient's own kIOReturnNotPermitted is not an ownership refusal.
    await #expect(throws: DriverKitError.self) {
      _ = try await context.wrapClientMemory(
        [DriverClientMemorySegment(address: 0x1000, length: 16)],
        direction: .deviceReads
      )
    }
  }

  private func makeContext(_ backend: ForeignMemoryConnection) async throws -> DriverContext {
    let session = DriverSession(service: DriverService(id: 1, name: "Memory"), connection: backend)
    let runtime = try await DriverRuntimeConnection.connect(session: session, requiring: .memory)
    return await DriverContext(runtime: runtime)
  }
}

/// A runtime connection whose handle 7 another connection wrapped: every command that names it
/// answers kIOReturnNotPermitted. Handle 1 has a dependent, so its release
/// answers kIOReturnBusy, and a wrap answers kIOReturnNotPermitted as a refused
/// CreateMemoryDescriptorFromClient would.
private actor ForeignMemoryConnection: DriverConnection {
  func call(_ request: DriverRequest) throws -> DriverResponse {
    let message = try RuntimeMessage(decoding: request.structureInput)
    guard message.kind != .handshake else {
      let acceptance = RuntimeHandshakeAcceptance(version: .current, capabilities: .memory)
      return try response(message.requestID, acceptance.encoded())
    }
    let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
    let payload = message.payload.dropFirst(16)
    let named: UInt64 =
      opcode == RuntimeOpcode.memoryChain.rawValue
      ? try payload.readRuntimeInteger(at: 8) : try payload.readRuntimeInteger(at: 0)
    if opcode == RuntimeOpcode.memoryWrapClient.rawValue || named == 7 {
      throw Self.status(RuntimeMemoryStatus.notOwner.ioReturn)
    }
    if opcode == RuntimeOpcode.memoryRelease.rawValue {
      throw Self.status(RuntimeMemoryStatus.inUse.ioReturn)
    }
    return try response(message.requestID, Data())
  }

  func notifications(selector: UInt32) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  func mapMemory(type: UInt32, readOnly: Bool) throws -> DriverSharedMemory {
    throw MappingUnsupported()
  }

  func close() {}

  private static func status(_ value: Int32) -> DriverKitError {
    DriverKitError(kind: .ioReturn(value), operation: "IOConnectCallMethod")
  }

  private func response(_ requestID: UInt64, _ payload: Data) throws -> DriverResponse {
    DriverResponse(
      structureOutput: try RuntimeMessage(kind: .response, requestID: requestID, payload: payload)
        .encoded()
    )
  }
}
