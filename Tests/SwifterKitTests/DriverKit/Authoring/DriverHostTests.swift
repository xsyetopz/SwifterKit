import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverHostTests {
  @Test
  func startsDeliversPushedEventsAndStops() async throws {
    let recorder = HostRecorder()
    let connection = EventSourceConnection(
      capabilities: [.hid],
      events: [DriverEvent(type: 5, payload: [6])]
    )
    let service = DriverService(id: 10, name: "Hosted")
    let client = DriverClient(transport: HostTransport(service: service, connection: connection))
    let host = DriverHost(driver: HostedDriver(recorder: recorder), client: client)

    #expect(try await host.start() == service)
    #expect(await host.state == .running)
    let delivery = Task { try await host.runEvents() }
    #expect(await eventually { await recorder.events.count == 1 })
    #expect(await eventually { await connection.emptyPollCount >= 1 })
    await connection.enqueue(DriverEvent(type: 7, payload: [8]))
    #expect(await eventually { await recorder.events.count == 2 })

    await host.stop()
    await host.stop()
    try await delivery.value

    #expect(await host.state == .stopped)
    #expect(await recorder.started)
    #expect(
      await recorder.events == [
        DriverEvent(type: 5, payload: [6]), DriverEvent(type: 7, payload: [8]),
      ]
    )
    #expect(await recorder.stopped)
    #expect(await connection.closeCount == 1)
    #expect(await connection.registrationCount == 1)
    #expect(await connection.notificationsSent == 2)
  }

  @Test
  func cancellingEventDeliveryThrowsCancellationError() async throws {
    let connection = EventSourceConnection(capabilities: [.hid])
    let client = DriverClient(
      transport: HostTransport(
        service: DriverService(id: 2, name: "Hosted"),
        connection: connection
      )
    )
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    try await host.start()
    let delivery = Task { try await host.runEvents() }
    #expect(await eventually { await connection.emptyPollCount >= 1 })
    delivery.cancel()
    await #expect(throws: CancellationError.self) { try await delivery.value }
    #expect(await host.state == .running)
    await host.stop()
  }

  @Test
  func rejectsEventDeliveryWhenStopped() async {
    let client = DriverClient(
      transport: HostTransport(
        service: DriverService(id: 3, name: "Hosted"),
        connection: EventSourceConnection(capabilities: [.hid])
      )
    )
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    await #expect(throws: DriverHostError.invalidState(expected: .running, actual: .stopped)) {
      try await host.runEvents()
    }
  }

  @Test
  func restoresStoppedStateWhenServiceIsMissing() async {
    let client = DriverClient(transport: EmptyHostTransport())
    let host = DriverHost(driver: HostedDriver(recorder: HostRecorder()), client: client)

    await #expect(throws: DriverHostError.self) { try await host.start() }
    #expect(await host.state == .stopped)
  }

  @Test
  func rejectsSecondStartWhileRunning() async throws {
    let connection = EventSourceConnection(capabilities: [.hid])
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
  let connection: EventSourceConnection

  init(service: DriverService, connection: EventSourceConnection) {
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
