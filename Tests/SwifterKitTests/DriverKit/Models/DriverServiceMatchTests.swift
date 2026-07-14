import Testing

@testable import SwifterKit

@Suite struct DriverServiceMatchTests {
  @Test func preservesCriteria() {
    let match = DriverServiceMatch(
      serviceClass: "IOUserService",
      name: "Example",
      registryProperties: ["IOUserClass": .string("ExampleDriver")]
    )

    #expect(match.serviceClass == "IOUserService")
    #expect(match.name == "Example")
    #expect(match.registryProperties["IOUserClass"] == .string("ExampleDriver"))
  }
}
