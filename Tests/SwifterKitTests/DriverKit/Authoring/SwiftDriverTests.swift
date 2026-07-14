import Testing

@testable import SwifterKit

@Suite struct SwiftDriverTests {
  @Test func contextAcceptsNegotiatedCapability() throws {
    let context = DriverContext(capabilities: [.usb, .interrupts])
    try context.require(.usb)
  }

  @Test func contextRejectsMissingCapability() {
    let context = DriverContext(capabilities: [.usb])

    #expect(throws: DriverContextError.unsupportedCapability(.pci)) { try context.require(.pci) }
  }

  @Test func detachedContextRejectsExecution() async {
    let context = DriverContext(capabilities: [])

    await #expect(throws: DriverContextError.notConnected) { try await context.execute(.ping()) }
  }

  @Test func driverCanBeDefinedUsingSwiftOnly() async throws {
    let driver = ExampleDriver()
    let context = DriverContext(capabilities: [.hid])

    try await driver.start(context: context)
    try await driver.handle(event: DriverEvent(type: 1), context: context)
    await driver.stop(context: context)
  }
}

private struct ExampleDriver: SwiftDriver {
  static let configuration = DriverConfiguration(
    bundleIdentifier: "com.example.driver",
    providerClass: "IOUserResources",
    capabilities: [.hid]
  )

  func handle(event: DriverEvent, context: DriverContext) async throws {
    await Task.yield()
    try context.require(.hid)
  }
}
