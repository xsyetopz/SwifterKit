import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverRuntimeConnectionTests {
  @Test func negotiatesCapabilitiesAndExecutesPing() async throws {
    let backend = RuntimeMockConnection(capabilities: [.usb, .memory])
    let runtime = try await makeRuntime(backend: backend, requiring: [.usb])

    let payload = Data([1, 2, 3])
    let response = try await runtime.execute(.ping(payload))

    #expect(response == payload)
    #expect(await runtime.capabilities == [.usb, .memory])
  }

  @Test func rejectsMissingRequiredCapabilities() async {
    let backend = RuntimeMockConnection(capabilities: [.hid])

    await #expect(throws: DriverRuntimeError.missingCapabilities(required: .usb, available: .hid)) {
      try await makeRuntime(backend: backend, requiring: .usb)
    }
  }

  @Test func rejectsCommandWithMissingCapabilityBeforeTransport() async throws {
    let backend = RuntimeMockConnection(capabilities: [.usb])
    let runtime = try await makeRuntime(backend: backend)
    let callsBeforeCommand = await backend.callCount

    await #expect(throws: DriverRuntimeError.missingCapabilities(required: .pci, available: .usb)) {
      try await runtime.execute(DriverCommand(opcode: 100, requiredCapabilities: .pci))
    }
    #expect(await backend.callCount == callsBeforeCommand)
  }

  @Test func returnsQueuedEventThenNil() async throws {
    let event = DriverEvent(type: 7, payload: [8, 9])
    let backend = RuntimeMockConnection(capabilities: [], events: [event])
    let runtime = try await makeRuntime(backend: backend)

    #expect(try await runtime.nextEvent() == event)
    #expect(try await runtime.nextEvent() == nil)
  }

  @Test func rejectsMismatchedRequestIdentifier() async {
    let backend = RuntimeMockConnection(capabilities: [], corruptResponseID: true)

    await #expect(throws: DriverRuntimeError.self) { try await makeRuntime(backend: backend) }
  }

  @Test func closeIsIdempotentAndPreventsTransactions() async throws {
    let backend = RuntimeMockConnection(capabilities: [])
    let runtime = try await makeRuntime(backend: backend)

    await runtime.close()
    await runtime.close()

    #expect(await backend.closeCount == 1)
    await #expect(throws: DriverRuntimeError.closed) { try await runtime.execute(.ping()) }
  }

  @Test func rejectsResponseLimitSmallerThanHandshake() async {
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
  var events: [DriverEvent]
  var callCount = 0
  var closeCount = 0

  init(
    capabilities: RuntimeCapabilities,
    events: [DriverEvent] = [],
    corruptResponseID: Bool = false
  ) {
    self.capabilities = capabilities
    self.events = events
    self.corruptResponseID = corruptResponseID
  }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    callCount += 1
    let message = try RuntimeMessage(decoding: request.structureInput)
    let responseID = corruptResponseID ? message.requestID &+ 1 : message.requestID

    switch message.kind {
    case .handshake:
      var payload = Data()
      payload.appendRuntimeInteger(capabilities.rawValue)
      return try response(kind: .response, requestID: responseID, payload: payload)
    case .command:
      let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
      if opcode == 0 {
        return try response(
          kind: .response,
          requestID: responseID,
          payload: message.payload.dropFirst(16)
        )
      }
      if opcode == 1, !events.isEmpty {
        let event = events.removeFirst()
        var payload = Data()
        payload.appendRuntimeInteger(event.type)
        payload.append(contentsOf: event.payload)
        return try response(kind: .event, requestID: responseID, payload: payload)
      }
      return try response(kind: .response, requestID: responseID, payload: Data())
    case .response, .event, .error: throw RuntimeProtocolError.unknownMessageKind
    }
  }

  func close() { closeCount += 1 }

  private func response(kind: RuntimeMessageKind, requestID: UInt64, payload: Data) throws
    -> DriverResponse
  {
    DriverResponse(
      structureOutput: try RuntimeMessage(
        kind: kind,
        requestID: requestID,
        flags: .finalFragment,
        payload: payload
      ).encoded()
    )
  }
}
