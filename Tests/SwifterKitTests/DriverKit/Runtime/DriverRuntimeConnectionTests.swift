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

  func close() { closeCount += 1 }

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
