import Testing

@testable import SwifterKit

@Suite struct DriverSessionTests {
  @Test func closeIsIdempotentAndPreventsFurtherCalls() async throws {
    let connection = CountingConnection()
    let session = DriverSession(
      service: DriverService(id: 11, name: "Mock"),
      connection: connection
    )

    await session.close()
    await session.close()

    #expect(await connection.closeCount == 1)
    await #expect(throws: DriverKitError.self) {
      try await session.call(DriverRequest(selector: 0))
    }
  }
}

private actor CountingConnection: DriverConnection {
  var closeCount = 0

  func call(_ request: DriverRequest) -> DriverResponse { DriverResponse() }

  func close() { closeCount += 1 }
}
