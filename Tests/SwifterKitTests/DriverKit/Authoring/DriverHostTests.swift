import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverHostTests {
  @Test func startsProcessesEventAndStops() async throws {
    let recorder = HostRecorder()
    let connection = HostConnection(
      capabilities: [.hid],
      events: [DriverEvent(type: 5, payload: [6])]
    )
    let service = DriverService(id: 10, name: "Hosted")
    let client = DriverClient(transport: HostTransport(service: service, connection: connection))
    let host = DriverHost(driver: HostedDriver(recorder: recorder), client: client)

    #expect(try await host.start() == service)
    #expect(await host.state == .running)
    #expect(try await host.processNextEvent())
    #expect(try await !host.processNextEvent())

    await host.stop()
    await host.stop()

    #expect(await host.state == .stopped)
    #expect(await recorder.started)
    #expect(await recorder.events == [DriverEvent(type: 5, payload: [6])])
    #expect(await recorder.stopped)
    #expect(await connection.closeCount == 1)
  }

  @Test func handlesNanosecondValuesOutsideDurationRange() async throws {
    let connection = HostConnection(capabilities: [.hid])
    let client = DriverClient(
      transport: HostTransport(
        service: DriverService(id: 2, name: "Hosted"),
        connection: connection
      )
    )
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    try await host.start()
    let loop = Task { try await host.runEvents(idlePollNanoseconds: .max) }
    #expect(await waitForEmptyPoll(connection))
    loop.cancel()
    await #expect(throws: CancellationError.self) { try await loop.value }
    await host.stop()
  }

  @Test func runsWithDurationRepresentableNanoseconds() async throws {
    let connection = HostConnection(capabilities: [.hid])
    let client = DriverClient(
      transport: HostTransport(
        service: DriverService(id: 3, name: "Hosted"),
        connection: connection
      )
    )
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    try await host.start()
    let loop = Task { try await host.runEvents(idlePollNanoseconds: 1) }
    #expect(await waitForEmptyPoll(connection))
    loop.cancel()
    await #expect(throws: CancellationError.self) { try await loop.value }
    await host.stop()
  }

  @Test func restoresStoppedStateWhenServiceIsMissing() async {
    let client = DriverClient(transport: EmptyHostTransport())
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    await #expect(throws: DriverHostError.self) { try await host.start() }
    #expect(await host.state == .stopped)
  }

  @Test func rejectsSecondStartWhileRunning() async throws {
    let connection = HostConnection(capabilities: [.hid])
    let client = DriverClient(
      transport: HostTransport(
        service: DriverService(id: 1, name: "Hosted"),
        connection: connection
      )
    )
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    try await host.start()
    await #expect(throws: DriverHostError.self) { try await host.start() }
    await host.stop()
  }
}

private func waitForEmptyPoll(_ connection: HostConnection) async -> Bool {
  for _ in 0..<1_000 {
    if await connection.emptyPollCount > 0 { return true }
    await Task.yield()
  }
  return false
}

private struct HostedDriver: SwiftDriver {
  static let configuration = DriverConfiguration(
    bundleIdentifier: "com.example.hosted",
    providerClass: "IOUserResources",
    capabilities: [.hid]
  )

  let recorder: HostRecorder

  func start(context: DriverContext) async throws {
    try context.require(.hid)
    await recorder.recordStart()
  }

  func handle(event: DriverEvent, context: DriverContext) async throws {
    try context.require(.hid)
    await recorder.record(event)
  }

  func stop(context: DriverContext) async { await recorder.recordStop() }
}

private actor HostRecorder {
  var started = false
  var events: [DriverEvent] = []
  var stopped = false

  func recordStart() { started = true }

  func record(_ event: DriverEvent) { events.append(event) }

  func recordStop() { stopped = true }
}

private actor HostTransport: DriverTransport {
  let service: DriverService
  let connection: HostConnection

  init(service: DriverService, connection: HostConnection) {
    self.service = service
    self.connection = connection
  }

  func services(matching criteria: DriverServiceMatch) -> [DriverService] { [service] }

  func open(_ service: DriverService, type: UInt32) -> any DriverConnection { connection }
}

private actor EmptyHostTransport: DriverTransport {
  func services(matching criteria: DriverServiceMatch) -> [DriverService] { [] }

  func open(_ service: DriverService, type: UInt32) throws -> any DriverConnection {
    throw DriverHostError.serviceNotFound(DriverServiceMatch(serviceClass: "Missing"))
  }
}

private actor HostConnection: DriverConnection {
  let capabilities: RuntimeCapabilities
  var events: [DriverEvent]
  var closeCount = 0
  var emptyPollCount = 0

  init(capabilities: RuntimeCapabilities, events: [DriverEvent] = []) {
    self.capabilities = capabilities
    self.events = events
  }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    let message = try RuntimeMessage(decoding: request.structureInput)
    switch message.kind {
    case .handshake:
      var payload = Data()
      payload.appendRuntimeInteger(capabilities.rawValue)
      return try response(kind: .response, requestID: message.requestID, payload: payload)
    case .command:
      let opcode: UInt32 = try message.payload.readRuntimeInteger(at: 0)
      if opcode == 1, events.isEmpty { emptyPollCount += 1 }
      guard opcode == 1, !events.isEmpty else {
        return try response(kind: .response, requestID: message.requestID, payload: Data())
      }
      let event = events.removeFirst()
      var payload = Data()
      payload.appendRuntimeInteger(event.type)
      payload.append(contentsOf: event.payload)
      return try response(kind: .event, requestID: message.requestID, payload: payload)
    case .response, .event, .error: throw RuntimeProtocolError.unknownMessageKind
    }
  }

  func close() { closeCount += 1 }

  private func response(kind: RuntimeMessageKind, requestID: UInt64, payload: Data) throws
    -> DriverResponse
  {
    DriverResponse(
      structureOutput: try RuntimeMessage(kind: kind, requestID: requestID, payload: payload)
        .encoded()
    )
  }
}
