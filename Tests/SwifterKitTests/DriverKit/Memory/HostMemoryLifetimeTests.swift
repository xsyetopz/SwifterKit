import Foundation
import Testing

@testable import SwifterKit

/// When wrapped host pages may be freed: only after the extension confirms the wrapping handle is
/// released, never while a subrange or chain still uses it.
@Suite
struct HostMemoryLifetimeTests {
  @Test
  func releasingTheWrappedHandleLetsThePagesGo() async throws {
    let backend = HostMemoryConnection()
    let context = try await makeContext(backend)
    let memory = try #require(DriverHostMemory(minimumLength: 1))
    let handle = try await memory.wrap(in: context, direction: .bidirectional)
    #expect(memory.isWrapped)
    try await context.releaseMemory(handle)
    #expect(!memory.isWrapped)
  }

  @Test
  func theConnectionHoldsWrappedMemoryUntilTheReleaseSucceeds() async throws {
    let backend = HostMemoryConnection()
    let context = try await makeContext(backend)
    weak var weakMemory: DriverHostMemory?
    let handle = try await {
      let memory = try #require(DriverHostMemory(minimumLength: 1))
      weakMemory = memory
      return try await memory.wrap(in: context, direction: .deviceReads)
    }()
    #expect(weakMemory?.isWrapped == true)
    await #expect(throws: DriverKitError.self) {
      try await context.releaseMemory(DriverMemoryHandle(rawValue: handle.rawValue + 1))
    }
    #expect(weakMemory?.isWrapped == true)
    try await context.releaseMemory(handle)
    #expect(weakMemory == nil)
  }

  @Test
  func aSourceStaysWrappedWhileASubrangeOrChainUsesIt() async throws {
    let backend = HostMemoryConnection()
    let context = try await makeContext(backend)
    let memory = try #require(DriverHostMemory(minimumLength: 1))
    let handle = try await memory.wrap(in: context, direction: .bidirectional)
    let subrange = try await context.memorySubrange(
      handle,
      offset: 0,
      length: 16,
      direction: .deviceReads
    )
    let chain = try await context.memoryChain([handle, subrange, handle], direction: .deviceReads)
    await #expect(throws: DriverMemoryError.inUse) { try await context.releaseMemory(handle) }
    await #expect(throws: DriverMemoryError.inUse) { try await context.releaseMemory(subrange) }
    try await context.releaseMemory(chain)
    await #expect(throws: DriverMemoryError.inUse) { try await context.releaseMemory(handle) }
    #expect(memory.isWrapped)
    try await context.releaseMemory(subrange)
    try await context.releaseMemory(handle)
    #expect(!memory.isWrapped)
  }

  @Test
  func closingDropsTheHoldButNotTheWrap() async throws {
    let backend = HostMemoryConnection()
    let session = DriverSession(service: DriverService(id: 1, name: "Memory"), connection: backend)
    let runtime = try await DriverRuntimeConnection.connect(session: session, requiring: .memory)
    let context = await DriverContext(runtime: runtime)
    let kept = try #require(DriverHostMemory(minimumLength: 1))
    _ = try await kept.wrap(in: context, direction: .bidirectional)
    weak var dropped: DriverHostMemory?
    _ = try await {
      let memory = try #require(DriverHostMemory(minimumLength: 1))
      dropped = memory
      return try await memory.wrap(in: context, direction: .bidirectional)
    }()
    #expect(dropped != nil)
    await runtime.close()
    // The extension releases the entries only when DriverKit later stops the user client, which
    // the host cannot observe, so the wrap stays outstanding and a dropped allocation's deinit
    // keeps its pages.
    #expect(dropped == nil)
    #expect(kept.isWrapped)
  }

  @Test
  func wrapRequiresTheMemoryCapabilityAndAConnection() async throws {
    let memory = try #require(DriverHostMemory(minimumLength: 1))
    await #expect(throws: DriverContextError.notConnected) {
      try await memory.wrap(in: DriverContext(capabilities: .memory), direction: .deviceReads)
    }
    #expect(!memory.isWrapped)
  }

  private func makeContext(_ backend: HostMemoryConnection) async throws -> DriverContext {
    let session = DriverSession(service: DriverService(id: 1, name: "Memory"), connection: backend)
    let runtime = try await DriverRuntimeConnection.connect(session: session, requiring: .memory)
    return await DriverContext(runtime: runtime)
  }
}

/// A runtime connection that models the extension's memory entries: wraps and compositions get
/// fresh handles, a composition counts as a dependent of each source it names, and a release
/// answers once: kIOReturnBusy while the entry has dependents, success otherwise.
private actor HostMemoryConnection: DriverConnection {
  private var nextHandle: UInt64 = 1
  /// Each live handle's sources, one per occurrence.
  private var sources: [UInt64: [UInt64]] = [:]

  func call(_ request: DriverRequest) throws -> DriverResponse {
    let message = try RuntimeMessage(decoding: request.structureInput)
    guard message.kind != .handshake else {
      let acceptance = RuntimeHandshakeAcceptance(version: .current, capabilities: .memory)
      return try response(message.requestID, acceptance.encoded())
    }
    let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
    let payload = message.payload.dropFirst(16)
    switch RuntimeOpcode(rawValue: opcode) {
    case .memoryWrapClient: return try create(message.requestID, sources: [])
    case .memorySubrange:
      let source: UInt64 = try payload.readRuntimeInteger(at: 0)
      return try create(message.requestID, sources: [source])
    case .memoryChain:
      let count: UInt32 = try payload.readRuntimeInteger(at: 0)
      let named = try (0..<Int(count)).map { index -> UInt64 in
        try payload.readRuntimeInteger(at: 8 + index * 8)
      }
      return try create(message.requestID, sources: named)
    case .memoryRelease:
      let handle: UInt64 = try payload.readRuntimeInteger(at: 0)
      guard sources[handle] != nil else { throw Self.status(-536_870_160) }
      guard !sources.values.contains(where: { $0.contains(handle) }) else {
        throw Self.status(RuntimeMemoryStatus.inUse.ioReturn)
      }
      sources[handle] = nil
      return try response(message.requestID, Data())
    default: return try response(message.requestID, Data())
    }
  }

  func notifications(selector: UInt32) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  func mapMemory(type: UInt32, readOnly: Bool) throws -> DriverSharedMemory {
    throw MappingUnsupported()
  }

  func close() {}

  private func create(_ requestID: UInt64, sources named: [UInt64]) throws -> DriverResponse {
    guard named.allSatisfy({ sources[$0] != nil }) else { throw Self.status(-536_870_160) }
    let handle = nextHandle
    nextHandle += 1
    sources[handle] = named
    var payload = Data()
    payload.appendRuntimeInteger(handle)
    return try response(requestID, payload)
  }

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
