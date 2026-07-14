import Testing

@testable import SwifterKit

@Suite struct DriverConfigurationTests {
  @Test func separatesProviderMatchingFromRuntimeDiscovery() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.driver",
      providerClass: "IOUSBHostInterface",
      matchingProperties: ["idVendor": .integer(1)],
      capabilities: [.usb, .memory]
    )

    #expect(configuration.serviceMatch.serviceClass == "IOService")
    #expect(
      configuration.serviceMatch.registryProperties["CFBundleIdentifier"]
        == .string("com.example.driver")
    )
    #expect(
      configuration.serviceMatch.registryProperties["IOUserClass"]
        == .string(DriverConfiguration.runtimeServiceClass)
    )
    #expect(configuration.matchingProperties["idVendor"] == .integer(1))
    #expect(configuration.capabilities.contains(.usb))
    #expect(configuration.capabilities.contains(.memory))
  }
}
