import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverRuntimeConnectionTests {
  @Test
  func negotiatesCapabilitiesAndExecutesPing() async throws {
    let backend = RuntimeMockConnection(capabilities: [.usb, .memory])
    let runtime = try await makeRuntime(backend: backend, requiring: [.usb])

    let payload = Data([1, 2, 3])
    let response = try await runtime.execute(.ping(payload))

    #expect(response == payload)
    #expect(await runtime.capabilities == [.usb, .memory])
    #expect(await runtime.protocolVersion == .current)
    #expect(
      await backend.offers == [RuntimeHandshakeOffer(versions: RuntimeProtocolVersion.supported)]
    )
    #expect(await backend.requestVersions.allSatisfy { $0 == .current })
  }

  @Test
  func rejectsHandshakeSelectingVersionOutsideOffer() async {
    let unsupported = RuntimeProtocolVersion(rawValue: RuntimeSchema.maximumVersion + 1)
    let backend = RuntimeMockConnection(
      capabilities: [],
      selectedVersion: unsupported,
      headerVersion: .current
    )

    await #expect(throws: DriverRuntimeError.invalidHandshake) {
      try await makeRuntime(backend: backend)
    }
  }

  @Test
  func rejectsHandshakeResponseEncodedWithUnsupportedVersion() async {
    let unsupported = RuntimeProtocolVersion(rawValue: RuntimeSchema.maximumVersion + 1)
    let backend = RuntimeMockConnection(capabilities: [], selectedVersion: unsupported)

    await #expect(throws: RuntimeProtocolError.unsupportedVersion(unsupported.rawValue)) {
      try await makeRuntime(backend: backend)
    }
  }

  @Test
  func rejectsOversizeCommandBeforeTransport() async throws {
    let backend = RuntimeMockConnection(capabilities: [])
    let runtime = try await makeRuntime(backend: backend)
    let callsBeforeCommand = await backend.callCount
    let largestPayload =
      RuntimeMessage.maximumSize - RuntimeMessage.headerSize - RuntimeSchema.commandHeaderSize

    await #expect(throws: RuntimeProtocolError.payloadTooLarge) {
      try await runtime.execute(.ping(Data(count: largestPayload + 1)))
    }
    #expect(await backend.callCount == callsBeforeCommand)
    _ = try await runtime.execute(
      DriverCommand(opcode: .ping, payload: Data(count: largestPayload))
    )
    #expect(await backend.callCount == callsBeforeCommand + 1)
  }

  @Test
  func rejectsMissingRequiredCapabilities() async {
    let backend = RuntimeMockConnection(capabilities: [.hid])

    await #expect(throws: DriverRuntimeError.missingCapabilities(required: .usb, available: .hid)) {
      try await makeRuntime(backend: backend, requiring: .usb)
    }
  }

  @Test
  func rejectsCommandWithMissingCapabilityBeforeTransport() async throws {
    let backend = RuntimeMockConnection(capabilities: [.usb])
    let runtime = try await makeRuntime(backend: backend)
    let callsBeforeCommand = await backend.callCount

    await #expect(throws: DriverRuntimeError.missingCapabilities(required: .pci, available: .usb)) {
      try await runtime.execute(DriverCommand(opcode: 100, requiredCapabilities: .pci))
    }
    #expect(await backend.callCount == callsBeforeCommand)
  }

  @Test
  func readsTypedHIDRuntimeStatistics() async throws {
    let backend = RuntimeMockConnection(capabilities: [.hid])
    let runtime = try await makeRuntime(backend: backend, requiring: .hid)
    let context = await DriverContext(runtime: runtime)

    #expect(
      try await context.hidRuntimeStatistics()
        == HIDRuntimeStatistics(
          inputReportAttempts: 8,
          inputReportSuccesses: 7,
          inputReportFailures: 1
        )
    )
  }

  @Test
  func returnsQueuedEventThenNil() async throws {
    let event = DriverEvent(type: 7, payload: [8, 9])
    let backend = RuntimeMockConnection(capabilities: [], events: [event])
    let runtime = try await makeRuntime(backend: backend)

    #expect(try await runtime.nextEvent() == event)
    #expect(try await runtime.nextEvent() == nil)
  }

  @Test
  func rejectsMismatchedRequestIdentifier() async {
    let backend = RuntimeMockConnection(capabilities: [], corruptResponseID: true)

    await #expect(throws: DriverRuntimeError.self) { try await makeRuntime(backend: backend) }
  }

  @Test
  func closeIsIdempotentAndPreventsTransactions() async throws {
    let backend = RuntimeMockConnection(capabilities: [])
    let runtime = try await makeRuntime(backend: backend)

    await runtime.close()
    await runtime.close()

    #expect(await backend.closeCount == 1)
    await #expect(throws: DriverRuntimeError.closed) { try await runtime.execute(.ping()) }
  }

  @Test
  func rejectsResponseLimitSmallerThanHandshake() async {
    let backend = RuntimeMockConnection(capabilities: [])

    await #expect(throws: DriverRuntimeError.invalidMaximumResponseSize) {
      try await makeRuntime(backend: backend, maximumResponseSize: RuntimeMessage.headerSize)
    }
  }

  @Test
  func mapsClientMemoryAndUnmapsItOnceWhenTheConnectionCloses() async throws {
    let backend = RuntimeMockConnection(capabilities: [.memory, .networking])
    let runtime = try await makeRuntime(backend: backend)
    let context = await DriverContext(runtime: runtime)
    let buffer = try await context.mapMemory(DriverMemoryHandle(rawValue: 7))
    #expect(!buffer.isReadOnly)
    #expect(try await context.mapMemory(DriverMemoryHandle(rawValue: 7)) === buffer)
    let pool = try await context.mapPacketPool(.receive)
    #expect(pool.isReadOnly)
    #expect(await backend.mappings.types == [0x0100_0007, 0x0200_0001])
    try buffer.store(UInt32(5), toByteOffset: 0)

    await runtime.close()
    #expect(!buffer.isMapped)
    #expect(!pool.isMapped)
    #expect(await backend.mappings.unmaps.total == 2)
    buffer.unmap()
    #expect(await backend.mappings.unmaps.total == 2)
    #expect(throws: DriverSharedMemoryError.unmapped) {
      try buffer.load(UInt32.self, fromByteOffset: 0)
    }
    await #expect(throws: DriverRuntimeError.closed) {
      try await context.mapMemory(DriverMemoryHandle(rawValue: 7))
    }
  }

  @Test
  func refusesMappingsWithoutCapabilityOrEncodableHandle() async throws {
    let backend = RuntimeMockConnection(capabilities: [.memory])
    let context = await DriverContext(runtime: try await makeRuntime(backend: backend))
    await #expect(throws: DriverMemoryError.invalidHandle) {
      try await context.mapMemory(DriverMemoryHandle(rawValue: 0))
    }
    await #expect(throws: DriverMemoryError.invalidHandle) {
      try await context.mapMemory(
        DriverMemoryHandle(rawValue: RuntimeMemoryLimits.maximumHandle + 1)
      )
    }
    await #expect(throws: DriverContextError.unsupportedCapability(.networking)) {
      try await context.mapPacketPool(.transmit)
    }
    #expect(await backend.mappings.types.isEmpty)
    await #expect(throws: DriverContextError.notConnected) {
      try await DriverContext(capabilities: .memory).mapMemory(DriverMemoryHandle(rawValue: 1))
    }
  }

  private func makeRuntime(
    backend: RuntimeMockConnection,
    requiring capabilities: RuntimeCapabilities = [],
    maximumResponseSize: Int = DriverRuntimeConnection.defaultMaximumResponseSize
  ) async throws -> DriverRuntimeConnection {
    let session = DriverSession(service: DriverService(id: 1, name: "Runtime"), connection: backend)
    return try await DriverRuntimeConnection.connect(
      session: session,
      requiring: capabilities,
      maximumResponseSize: maximumResponseSize
    )
  }
}

private actor RuntimeMockConnection: DriverConnection {
  let capabilities: RuntimeCapabilities
  let corruptResponseID: Bool
  let selectedVersion: RuntimeProtocolVersion
  let headerVersion: RuntimeProtocolVersion?
  var events: [DriverEvent]
  var callCount = 0
  var closeCount = 0
  var offers: [RuntimeHandshakeOffer] = []
  var requestVersions: [RuntimeProtocolVersion] = []
  var mappings = InMemoryMappings()

  init(
    capabilities: RuntimeCapabilities,
    events: [DriverEvent] = [],
    corruptResponseID: Bool = false,
    selectedVersion: RuntimeProtocolVersion = .current,
    headerVersion: RuntimeProtocolVersion? = nil
  ) {
    self.capabilities = capabilities
    self.events = events
    self.corruptResponseID = corruptResponseID
    self.selectedVersion = selectedVersion
    self.headerVersion = headerVersion
  }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    callCount += 1
    let message = try RuntimeMessage(decoding: request.structureInput)
    let responseID = corruptResponseID ? message.requestID &+ 1 : message.requestID
    requestVersions.append(message.version)

    switch message.kind {
    case .handshake:
      offers.append(try RuntimeHandshakeOffer(decoding: message.payload))
      let acceptance = RuntimeHandshakeAcceptance(
        version: selectedVersion,
        capabilities: capabilities
      )
      return try response(
        kind: .response,
        version: headerVersion ?? selectedVersion,
        requestID: responseID,
        payload: acceptance.encoded()
      )
    case .command:
      let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
      if opcode == RuntimeOpcode.ping.rawValue {
        return try response(
          kind: .response,
          requestID: responseID,
          payload: message.payload.dropFirst(16)
        )
      }
      if opcode == RuntimeOpcode.pollEvent.rawValue, !events.isEmpty {
        let event = events.removeFirst()
        var payload = Data()
        payload.appendRuntimeInteger(event.type)
        payload.append(contentsOf: event.payload)
        return try response(kind: .event, requestID: responseID, payload: payload)
      }
      if opcode == RuntimeOpcode.hidGetRuntimeStatistics.rawValue {
        var payload = Data()
        payload.appendRuntimeInteger(UInt64(8))
        payload.appendRuntimeInteger(UInt64(7))
        payload.appendRuntimeInteger(UInt64(1))
        return try response(kind: .response, requestID: responseID, payload: payload)
      }
      return try response(kind: .response, requestID: responseID, payload: Data())
    case .response, .event, .error: throw RuntimeProtocolError.unknownMessageKind
    }
  }

  func notifications(selector: UInt32) -> AsyncStream<Void> { AsyncStream { $0.finish() } }

  func close() {
    closeCount += 1
    mappings.unmapAll()
  }

  func mapMemory(type: UInt32, readOnly: Bool) -> DriverSharedMemory {
    mappings.map(type: type, readOnly: readOnly)
  }

  private func response(
    kind: RuntimeMessageKind,
    version: RuntimeProtocolVersion = .current,
    requestID: UInt64,
    payload: Data
  ) throws -> DriverResponse {
    DriverResponse(
      structureOutput: try RuntimeMessage(
        version: version,
        kind: kind,
        requestID: requestID,
        payload: payload
      ).encoded()
    )
  }
}
