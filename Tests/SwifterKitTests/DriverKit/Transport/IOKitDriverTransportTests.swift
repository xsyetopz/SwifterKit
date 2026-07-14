import Testing

@testable import SwifterKit

@Suite struct IOKitDriverTransportTests {
  @Test func rejectsEmptyServiceClass() async {
    let transport = IOKitDriverTransport()

    await #expect(throws: DriverKitError.self) {
      try await transport.services(matching: DriverServiceMatch(serviceClass: ""))
    }
  }
}
