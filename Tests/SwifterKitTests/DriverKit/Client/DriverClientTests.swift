import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverClientTests {
  @Test func discoversAndOpensThroughInjectedTransport() async throws {
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
  var isClosed = false

  init(response: DriverResponse) { self.response = response }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    lastRequest = request
    return response
  }

  func close() { isClosed = true }
}
