import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverClientTests {
  @Test
  func discoversAndOpensThroughInjectedTransport() async throws {
    let service = DriverService(id: 10, name: "Mock")
    let response = DriverResponse(scalarOutput: [99], structureOutput: Data([0xAA]))
    let connection = MockConnection(response: response)
    let transport = MockTransport(service: service, connection: connection)
    let client = DriverClient(transport: transport)

    let services = try await client.services(
      matching: DriverServiceMatch(serviceClass: "MockService")
    )
    #expect(services == [service])

    let session = try await client.open(service, type: 3)
    let received = try await session.call(DriverRequest(selector: 4))
    #expect(received == response)
    #expect(await transport.lastOpenType == 3)
    #expect(await connection.lastRequest?.selector == 4)

    _ = try await session.notifications(selector: 5)
    #expect(await connection.lastNotificationSelector == 5)

    let memory = try await session.mapMemory(type: 0x0100_0001, readOnly: false)
    #expect(await connection.mappings.types == [0x0100_0001])
    await session.close()
    #expect(!memory.isMapped)
    #expect(await connection.mappings.unmaps.total == 1)
    await #expect(throws: DriverKitError.self) {
      try await session.mapMemory(type: 0x0100_0001, readOnly: false)
    }
  }
}

private actor MockTransport: DriverTransport {
  let service: DriverService
  let connection: MockConnection
  var lastOpenType: UInt32?

  init(service: DriverService, connection: MockConnection) {
    self.service = service
    self.connection = connection
  }

  func services(matching criteria: DriverServiceMatch) -> [DriverService] { [service] }

  func open(_ service: DriverService, type: UInt32) -> any DriverConnection {
    lastOpenType = type
    return connection
  }
}

private actor MockConnection: DriverConnection {
  let response: DriverResponse
  var lastRequest: DriverRequest?
  var lastNotificationSelector: UInt32?
  var isClosed = false
  var mappings = InMemoryMappings()

  init(response: DriverResponse) { self.response = response }

  func mapMemory(type: UInt32, readOnly: Bool) -> DriverSharedMemory {
    mappings.map(type: type, readOnly: readOnly)
  }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    lastRequest = request
    return response
  }

  func notifications(selector: UInt32) -> AsyncStream<Void> {
    lastNotificationSelector = selector
    return AsyncStream { $0.finish() }
  }

  func close() {
    isClosed = true
    mappings.unmapAll()
  }
}
