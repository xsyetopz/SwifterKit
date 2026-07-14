import Testing

@testable import SwifterKit

@Suite struct DriverServiceTests {
  @Test func identityUsesRegistryIdentifier() {
    let service = DriverService(
      id: 42,
      name: "Example",
      registryPath: "IOService:/Example",
      properties: ["Ready": .boolean(true)]
    )

    #expect(service.id == 42)
    #expect(service.name == "Example")
    #expect(service.registryPath == "IOService:/Example")
    #expect(service.properties["Ready"] == .boolean(true))
  }
}
