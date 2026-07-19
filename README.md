# SwifterKit

SwifterKit wraps DriverKit for Swift 6 driver authors. Driver configuration and
behavior stay in Swift; SwifterKit owns the generated C++/IIG boundary required
by the DriverKit ABI.

Use SwifterKit when a driver needs:

- a generated DriverKit extension project without application-owned C++, C,
  Objective-C, or IIG glue;
- typed commands and events for supported DriverKit families;
- raw user-client access when no capability-specific API fits; or
- one Swift concurrency model for driver lifecycle, events, and completion work.

## Requirements

- Swift 6.2 or later for package consumers
- the Swift version in `.swift-version` for local development; CI alone runs
  the Swift 6.1 compatibility build
- macOS 10.15 or later for the Swift package and base DriverKit runtime
- Xcode with the DriverKit SDK for generated extension builds
- Apple-approved entitlements, signing assets, a host application, and physical
  hardware for deployment testing

Signing is not required to build or test the package or its generated extension
project locally.

DriverKit family frameworks were added across later releases.
`DriverExtensionGenerationOptions.deploymentTarget` defaults to `19.0`; the
generator rejects a capability when its native runtime needs a newer DriverKit version.

### Deployment targets

The package target and the generated extension target are independent. Swift
package clients can run on macOS 10.15 while a generated extension selects the
narrowest DriverKit target required by its capabilities.

| Generated capability | Minimum DriverKit target | Host availability |
| --- | ---: | --- |
| Base runtime, HID, USB, serial, interrupts, memory | 19.0 | macOS 10.15 |
| PCI | 19.0 | macOS 11.1 |
| SCSI controller | 20.4 | macOS 11.3 |
| Block storage, audio | 21.0 | macOS 12 |
| Networking, SCSI peripheral | 22.0 | macOS 13 |
| MIDI | 24.0 | macOS 15 |
| Video | 27.0 | macOS 27 beta |

The networking runtime uses queue registration introduced in DriverKit 22.0
even though NetworkingDriverKit itself appeared earlier. Apple currently marks
VideoDriverKit as beta; video generation requires an SDK containing that
framework. See [DriverKit](https://developer.apple.com/documentation/driverkit)
and the family framework documentation for Apple’s platform availability.

## Installation

For a local checkout, add SwifterKit to `Package.swift`:

```swift
let package = Package(
  dependencies: [
    .package(path: "../SwifterKit")
  ],
  targets: [
    .target(
      name: "MyDriver",
      dependencies: [
        .product(name: "SwifterKit", package: "SwifterKit")
      ]
    )
  ]
)
```

Use a repository URL and a tagged version after publishing SwifterKit through a
Swift package host.

## Define a driver

A `SwiftDriver` declares static extension metadata and handles runtime work in Swift:

```swift
import SwifterKit

struct ExampleHIDDriver: SwiftDriver {
  static let configuration = DriverConfiguration(
    bundleIdentifier: "com.example.ExampleHID",
    providerClass: "IOUserResources",
    matchingProperties: ["IOResourceMatch": .string("IOKit")],
    capabilities: .hid,
    hidDevice: HIDDeviceConfiguration(
      reportDescriptor: [
        0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00,
        0x75, 0x08, 0x95, 0x0F, 0x09, 0x02, 0x91, 0x02, 0x09, 0x03, 0x81, 0x02,
        0xC0,
      ],
      vendorID: 0x1234,
      productID: 0x5678,
      manufacturer: "Example",
      product: "Swift HID",
      serialNumber: "swift-hid-1",
      primaryUsagePage: 0xFF00,
      primaryUsage: 1,
      acceptedHostReportTypes: .output
    )
  )

  func start(context: DriverContext) async throws {
    try await context.submitHIDInputReport(
      HIDReport(bytes: [0], type: .input)
    )
  }

  func handle(event: DriverEvent, context: DriverContext) async throws {
    guard let report = try event.hidReport() else { return }
    // Handle the allowlisted output report here.
    _ = report
  }
}
```

Generate the internal extension project from the same configuration:

```swift
import Foundation
import SwifterKit

let outputDirectory = URL(fileURLWithPath: "/tmp/ExampleHID")
try DriverExtensionGenerator.generate(
  configuration: ExampleHIDDriver.configuration,
  at: outputDirectory
)
```

The generator writes the personality, entitlements, runtime configuration, IIG
declarations, native sources, and Xcode project. Generation rejects unsupported
capability combinations and never overwrites an existing destination.

`HIDDeviceConfiguration` accepts both output and feature reports by default.
The example selects `acceptedHostReportTypes: .output` because its descriptor
supports only output reports. Rejected report types return
`kIOReturnUnsupported` without being forwarded to the Swift host.

## Capability APIs

| Capability | Configuration | Swift operations |
| --- | --- | --- |
| HID | `HIDDeviceConfiguration` | Input reports; allowlisted output and feature events |
| USB | `USBDeviceConfiguration` | Control transfers, endpoint I/O, stall clearing, alternate settings |
| PCI | `PCIDeviceConfiguration` | Configuration space, BAR access, device location, capability search |
| Serial | `SerialPortConfiguration` | Queue I/O, modem state, receive errors, UART events |
| Block storage | `BlockStorageDeviceConfiguration` | Eject, synchronize, unmap, read/write requests and completions |
| MIDI | `MIDIDeviceConfiguration` | Endpoint topology, Universal MIDI Packet sends, destination events |
| Networking | `EthernetDeviceConfiguration` | Packet queues, transmit completion, receive injection, link state |
| Audio | `AudioDeviceConfiguration` | Stream rings, timestamps, formats, controls, custom properties |
| SCSI | `SCSIControllerConfiguration` or `SCSIPeripheralConfiguration` | Parallel tasks, task management, CDBs, logical-unit services |
| Video | `VideoDeviceConfiguration` | Formats, controls, buffers, queues, timestamps, stream events |
| Interrupts | `InterruptSourceConfiguration` | Delivery control, interrupt metadata, typed events |
| Memory and DMA | `MemoryPoolConfiguration` | Bounded buffers, valid lengths, provider mappings, DMA lifecycle |

A generated extension advertises only the capabilities implemented by its
native runtime. Some device-family combinations are invalid because DriverKit
requires different superclasses or providers.

See [Capability APIs](Sources/SwifterKit/SwifterKit.docc/Capabilities.md) for
configuration and completion details.

## Native boundary

`DriverExtensionGenerator` copies a single packaged native source tree from
`Sources/SwifterKit/Resources/DriverKitExtension`. Driver authors do not supply
native glue to the generator.

The generated extension and the Swift host exchange versioned runtime messages.
Swift receives typed values, opaque memory handles, and bounded payloads rather
than DriverKit objects or native pointers. Ethernet, block-storage, SCSI, and
other completion-based APIs require Swift to return the matching request
identifier after transport work finishes.

`DriverClient`, `DriverSession`, and `DriverCommand` expose raw user-client
calls for operations that do not belong to a typed capability API.

Read [NativeBoundary](Sources/SwifterKit/SwifterKit.docc/NativeBoundary.md)
before adding raw commands or memory operations.

## Build and test

Run the complete validation suite:

```sh
./scripts/ci/validate.sh
```

The suite checks Swift and C++ formatting, SwiftLint, Swift 6 tests, a release
build with warnings as errors, DocC links, C++20 static analysis, unsigned
arm64 and x86_64 DriverKit builds, property lists, and source LOC limits.

The compatibility job builds the package and its tests with Xcode 16.3 and a
CI-only Swift 6.1 manifest header while retaining the macOS 10.15 deployment
target. The main validation job uses the checked-in manifest and latest passing
local toolchain.

CI does not run on macOS 10.15 and cannot activate a signed extension or attach
physical hardware. The following macOS 10.15 runtime paths remain
compile-checked but unexecuted in CI:

- IOKit service discovery and user-client opening through `kIOMasterPortDefault`;
- Swift concurrency back-deployment during the driver lifecycle and event loop;
- generated extension activation, runtime negotiation, and device I/O on a
  macOS 10.15 host; and
- signed entitlement, provisioning, and hardware behavior.

Unit tests force the legacy nanosecond sleep fallback and the modern
duration-based branch independently. IOKit port selection depends on the
running operating system and needs a macOS 10.15 host for runtime coverage.

For a smaller Swift-only cycle:

```sh
swift test -Xswiftc -warnings-as-errors
swiftlint lint --strict
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
```

Format edited source before submitting a change:

```sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
xcrun clang-format -i Sources/SwifterKit/Resources/DriverKitExtension/Sources/*.{cpp,h,iig}
```

Source and test files must remain below 800 lines after formatting; aim for
500. Directories below `Tests/SwifterKitTests` mirror the matching `Sources/
SwifterKit` areas.

## Troubleshooting

**Generation reports that the destination exists.** `DriverExtensionGenerator`
does not overwrite files. Choose a new directory or remove the old output after
confirming it is disposable.

**A capability configuration is rejected.** Check that `RuntimeCapabilities`,
the matching configuration value, and the DriverKit provider class describe the
same device family. Some families cannot share one generated superclass.

**The DriverKit SDK cannot be found.** Select an Xcode installation that
includes DriverKit. CI sets `DEVELOPER_DIR` explicitly; local commands can do
the same when multiple Xcode versions are installed.

**A signed build fails.** Confirm that the certificate, private key,
provisioning profile, team identifier, bundle identifier, and approved
entitlements agree. See [Publishing](docs/publishing.md) for the local and
GitHub Actions setup.

## Signed DriverKit builds and publishing

A source release does not need Apple signing. A downstream driver needs
approved DriverKit entitlements, matching certificates and provisioning
profiles, a host application, and the target device environment.

[Publishing](docs/publishing.md) covers release tags, GitHub Actions, local `.
env` files, signed validation, and Apple account requirements.

## Documentation

- [Getting started with a Swift driver](Sources/SwifterKit/SwifterKit.docc/GettingStarted.md)
- [Capability APIs](Sources/SwifterKit/SwifterKit.docc/Capabilities.md)
- [The native DriverKit boundary](Sources/SwifterKit/SwifterKit.docc/NativeBoundary.md)
- [Publishing](docs/publishing.md)
- [Changelog](CHANGELOG.md)

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change.

## AI Coding agents

Read [AGENTS.md](AGENTS.md) after this README. `CLAUDE.md` and `GEMINI.md`
point to the same repository guidance.

## License

[ISC](LICENSE)
