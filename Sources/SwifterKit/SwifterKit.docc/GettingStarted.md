# Getting started with a Swift driver

Define a ``SwiftDriver`` type, generate its extension project, then run the driver in the host process that connects to the extension. The extension project holds the DriverKit-facing implementation. The driver type holds application-specific behavior.

Toolchain and platform requirements are in <doc:Capabilities#Deployment-requirements>.

## Define a virtual HID driver

The report descriptor and device identity are static configuration. The example sends one input report during startup. It decodes HID output or feature reports when they arrive.

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

``SwiftDriver/start(context:)`` and ``SwiftDriver/handle(event:context:)`` run after the runtime negotiates the capabilities that the generated extension declares. ``DriverContext`` throws ``DriverContextError/unsupportedCapability(_:)`` when a requested operation is not available.

The HID configuration accepts output and feature reports by default. A report descriptor can support output reports but no feature reports. In that case, pass `acceptedHostReportTypes: .output` to ``HIDDeviceConfiguration/init(reportDescriptor:transport:vendorID:productID:versionNumber:countryCode:locationID:manufacturer:product:serialNumber:primaryUsagePage:primaryUsage:acceptedHostReportTypes:answeredReportTypes:)``. The extension rejects disallowed report types, and they do not become ``DriverEvent`` values.

## Generate the extension project

Pass the static configuration to ``DriverExtensionGenerator``. Generation creates a new directory and fails if the destination already exists.

```swift
let outputDirectory = URL(fileURLWithPath: "/tmp/ExampleHID")
try DriverExtensionGenerator.generate(
  configuration: ExampleHIDDriver.configuration,
  at: outputDirectory
)
```

The generator validates capability metadata before it writes files. For example, `.hid` requires ``HIDDeviceConfiguration``. The generator rejects a configuration object without matching metadata.

## Host the driver

Use ``DriverHost`` with a connected runtime to deliver startup, events, and shutdown to a ``SwiftDriver`` implementation. The host serializes lifecycle state and exposes it through ``DriverHost/state``.

```swift
let host = DriverHost(driver: ExampleHIDDriver())
try await host.start()
let delivery = Task { try await host.runEvents() }
// ...
await host.stop()
try await delivery.value
```

``DriverHost/runEvents()`` passes each event to ``SwiftDriver/handle(event:context:)``. The extension notifies the host when events are queued, so the host does not poll while the queue is empty. The method returns after ``DriverHost/stop()``. It throws `CancellationError` when its task is cancelled. To run your own loop instead, iterate ``DriverRuntimeConnection/events()``.

The host application must have the `com.apple.developer.driverkit.userclient-access` entitlement. The entitlement's array must contain the extension's bundle identifier. The generated extension rejects a runtime connection from any process without it. See <doc:NativeBoundary#Host-access>.

To access another DriverKit service directly, instead of a generated SwifterKit extension, use ``DriverClient`` to enumerate services and open a ``DriverSession``. ``DriverSession/call(_:)`` sends a raw ``DriverRequest`` through that service's user client.

## Next steps

- Read <doc:NativeBoundary> before relying on raw commands or memory mappings.
- Use <doc:Capabilities> to choose configuration metadata and event or command APIs for a device family.
