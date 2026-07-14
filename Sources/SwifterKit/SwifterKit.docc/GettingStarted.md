# Getting started with a Swift driver

Define a ``SwiftDriver`` type, generate its extension project, then run the driver in the host process that connects to the extension. The extension project contains the DriverKit-facing implementation; the driver type contains application-specific behavior.

## Define a virtual HID driver

The report descriptor and device identity are static configuration. The example sends one input report during startup and decodes HID output or feature reports when they arrive.

```swift
import Foundation
import SwifterKit

struct ExampleHIDDriver: SwiftDriver {
  static let configuration = DriverConfiguration(
    bundleIdentifier: "com.example.ExampleHID",
    providerClass: "IOUserResources",
    matchingProperties: ["IOResourceMatch": .string("IOKit")],
    capabilities: .hid,
    hidDevice: HIDDeviceConfiguration(
      reportDescriptor: [0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0xC0],
      vendorID: 0x1234,
      productID: 0x5678,
      manufacturer: "Example",
      product: "Swift HID",
      serialNumber: "swift-hid-1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1
    )
  )

  func start(context: DriverContext) async throws {
    try await context.submitHIDInputReport(HIDReport(bytes: [0], type: .input))
  }

  func handle(event: DriverEvent, context: DriverContext) async throws {
    guard let report = try event.hidReport() else { return }
    switch report.type {
    case .output, .feature:
      break
    case .input:
      break
    }
  }
}
```

``SwiftDriver/start(context:)`` and ``SwiftDriver/handle(event:context:)`` run after the runtime has negotiated the capabilities declared by the generated extension. ``DriverContext`` throws ``DriverContextError/unsupportedCapability(_:)`` when a requested operation is not available.

## Generate the extension project

Pass the static configuration to ``DriverExtensionGenerator``. Generation creates a new directory and fails if the destination already exists.

```swift
let outputDirectory = URL(fileURLWithPath: "/tmp/ExampleHID")
try DriverExtensionGenerator.generate(
  configuration: ExampleHIDDriver.configuration,
  at: outputDirectory
)
```

The generator validates capability metadata before writing files. For example, `.hid` requires ``HIDDeviceConfiguration``; a configuration object without matching metadata is rejected.

## Host the driver

Use ``DriverHost`` with a connected runtime to deliver startup, events, and shutdown to a ``SwiftDriver`` implementation. The host serializes lifecycle state and exposes its state through ``DriverHost/state``.

For direct access to another DriverKit service rather than a generated SwifterKit extension, use ``DriverClient`` to enumerate services and open a ``DriverSession``. ``DriverSession/call(_:)`` sends a raw ``DriverRequest`` through that service's user client.

## Next steps

- Read <doc:NativeBoundary> before relying on raw commands or memory mappings.
- Use <doc:Capabilities> to choose configuration metadata and event or command APIs for a device family.
