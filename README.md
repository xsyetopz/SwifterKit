# SwifterKit

SwifterKit wraps DriverKit for Swift 6 driver authors. Driver configuration and
behavior stay in Swift; SwifterKit owns the generated C++/IIG boundary required
by the DriverKit ABI.

See the [SwifterKit 0.2.0 release notes](docs/releases/0.2.0.md) for the breaking
release summary and hardware validation status.

Use SwifterKit when a driver needs:

- a generated DriverKit extension project without application-owned C++, C,
  Objective-C, or IIG glue;
- typed commands and events for supported DriverKit families;
- raw user-client access when no capability-specific API fits; or
- one Swift concurrency model for driver lifecycle, events, and completion work.

## Requirements

- Swift 6.1 (Xcode 16.3) or later for package consumers
- the Swift version in `.swift-version` for local development
- macOS 10.15 or later for the IOKit host transport and base DriverKit runtime;
  configuration, validation, protocol, and generation code also builds on
  Linux, where the IOKit transport is unavailable
- Xcode with the DriverKit SDK for generated extension builds
- Apple-approved entitlements, signing assets, a host application, and physical
  hardware for deployment testing

Signing is not required to build or test the package or its generated extension
project locally.

DriverKit family frameworks were added across later releases.
`DriverExtensionGenerationOptions.deploymentTarget` defaults to `19.0`; the
generator rejects a capability when its native runtime needs a newer DriverKit version.
Build a 19.0 or 20.x target with an Xcode whose DriverKit SDK still accepts
it, such as Xcode 16.3 (DriverKit 24.4 accepts 19.0 and later). The DriverKit
SDK in Xcode 27 accepts deployment targets from 21.0.

### Deployment targets

The package target and the generated extension target are independent. Swift
package clients can run on macOS 10.15 while a generated extension selects the
narrowest DriverKit target required by its capabilities.

| Generated capability | Minimum DriverKit target | Host availability |
| --- | ---: | --- |
| Base runtime, HID device, HID device factory, USB HID device, USB, serial, interrupts, memory | 19.0 | macOS 10.15 |
| PCI | 19.0 | macOS 11.1 |
| SCSI controller | 20.4 | macOS 11.3 |
| Block storage, audio, HID event service | 21.0 | macOS 12 |
| Networking, SCSI peripheral | 22.0 | macOS 13 |
| MIDI | 24.0 | macOS 15 |
| Video | 25.5 | macOS 26.5 |

The networking runtime uses queue registration introduced in DriverKit 22.0
even though NetworkingDriverKit itself appeared earlier. Apple currently marks
VideoDriverKit as beta; video generation requires an SDK containing that
framework. The DriverKit 25.5 SDK in Xcode 26.6, which pairs with the macOS
26.5 SDK, is the oldest SDK known to contain it: its VideoDriverKit headers and
exported symbols match the DriverKit 27.0 SDK's, and the DriverKit 24.4 SDK has
no VideoDriverKit. See [DriverKit](https://developer.apple.com/documentation/driverkit)
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
| HID device factory | `HIDDeviceFactoryConfiguration` | Create and terminate up to 32 virtual HID devices at run time, each with its own descriptor and identity; per-device input reports, host reports, and get-report answers tagged with the device handle |
| USB | `USBDeviceConfiguration` | Interface or device providers; synchronous and asynchronous control transfers, synchronous and asynchronous endpoint I/O, bundled bulk I/O over descriptor rings, isochronous I/O, endpoint bandwidth adjustment, descriptors, configuration, frame numbers, idle policy, aborts |
| PCI | `PCIDeviceConfiguration`, `PCIInterruptConfiguration` | Configuration space, bounded BAR access with access options, device location, capability search, MSI/MSI-X allocation, reset, state save/restore, power management, link speed, ASPM, sleep properties |
| Serial | `SerialPortConfiguration` | Queue I/O, modem state, receive errors, UART events |
| USB serial | `USBSerialPortConfiguration` | `IOUserUSBSerial` on a USB interface; UART events, modem state, receive errors, received and interrupt packet events |
| Block storage | `BlockStorageDeviceConfiguration` | Eject, synchronize, unmap, read/write requests and completions |
| MIDI | `MIDIDeviceConfiguration` | Endpoint topology, Universal MIDI Packet sends, destination events, object identity and names, typed property get, set, and copy, device running state, adding and removing the entity, sources, and destinations |
| Networking | `EthernetDeviceConfiguration` | Packet queues and pools, transmit completion, receive injection, link status, quality, and bandwidths, offloads (checksum, TSO, LRO, VLAN, wake on magic packet, NIC proxy), MTU range, hardware counters, BPF tap, hybrid polling, per-packet metadata in both directions (offsets, checksum/TSO/LRO, VLAN, timestamps, service class, trace IDs), batched receive and completion, queue enable/purge/service, private interface commands |
| Audio | `AudioDeviceConfiguration` | Stream rings, timestamps, formats, controls, custom properties, boxes and acquisition, clock devices (sample rates, clock domain and algorithm, latency, zero timestamps), object and element names, property-change notifications, `StartDevice`/`StopDevice` events, device defaults, safety offsets, preferred channels and layouts, stream state, formats, terminal type, and ring resizing, control ranges, panning channels, and selector items, adding and removing streams, controls, and custom properties |
| SCSI | `SCSIControllerConfiguration` or `SCSIPeripheralConfiguration` | Parallel tasks, task management, CDBs, logical-unit services |
| Video | `VideoDeviceConfiguration` | Formats, controls, buffers, queues, timestamps, stream events, boxes, clock devices, device defaults, safety offsets, preferred channels and layouts, stream state and queues, buffer identity, capacity, IDs, and membership, control scope, owner, ranges, channels, and selector items, custom-property info, stream and control attachment |
| Interrupts | `InterruptSourceConfiguration` | Delivery control, interrupt metadata, typed events |
| Memory and DMA | `MemoryPoolConfiguration` | Bounded buffers, valid lengths, provider mappings, DMA lifecycle |
| Service (every extension) | None | Registry properties, provider properties, name and registry ID, power-state requests and changes, power override, PM assertions, busy state, bus-stall limits, termination, system state items, CoreAnalytics events |
| Timers and watches (every extension) | None | One-shot and repeating timers with leeway, service match and termination events, system state item changes |
| IOReporting (every extension) | `ReportingConfiguration` | Simple, state, and histogram reporters with a published legend; value and state updates and reads |

A generated extension advertises only the capabilities implemented by its
native runtime. Some device-family combinations are invalid because DriverKit
requires different superclasses or providers.

See [Capability APIs](Sources/SwifterKit/SwifterKit.docc/Capabilities.md) for
configuration and completion details.

## DriverKit coverage

The DocC article
[DriverKit Coverage](Sources/SwifterKit/SwifterKit.docc/DriverKitCoverage.md)
tells driver authors how much of the DriverKit API a Swift driver reaches. For
each framework it counts the members Apple's SDK `.iig` headers declare, and it
lists every public member a Swift driver cannot reach and every member Apple
keeps from DriverKit clients.

`SwifterKitCoverage` computes the article on every run from three sources, and
stores nothing else:

| Status | Source |
| --- | --- |
| Swift API | The runtime reaches the member, and a `///` comment in `Sources/SwifterKit` names it as `` `Class::member` `` |
| Runtime | Clang's AST of the generated extension trees shows the runtime calling or overriding the member |
| Gap | The header makes the member public and nothing reaches it |
| Not exposed | The header makes the member public and the article gives SwifterKit's reason for not reaching it |
| Apple only | The header keeps the member from DriverKit clients: private members, private `EXTENDS` class extensions, and declarations compiled only for the kernel or under `#if 0` or private conditions |

Evidence resolves each call or override to the declaring class and overload.
The only hand-written text is the reasons under "Members SwifterKit does not
expose", one member per line:

```text
- `IOService` `kern_return_t Example(uint32_t)`: The runtime owns this call
```

Regenerate the article after changing the runtime, its documentation, or the
installed SDKs. Pass every installed DriverKit SDK, as `validate.sh` does;
`--exclusions FILE` adds or replaces reasons from a local file in the same line
format:

```sh
generated_trees="$PWD/.build/SwifterKitGeneratedTrees"
SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE="$generated_trees" swift test
swift run SwifterKitCoverage docc \
  --sdk "$(xcrun --sdk driverkit --show-sdk-path)" --trees "$generated_trees" \
  --article Sources/SwifterKit/SwifterKit.docc/DriverKitCoverage.md
```

`check` fails when a documented `Class::member` names no declared member or
names one the runtime does not reach, and when an exclusion names no public
member, names one the runtime reaches, or describes intent such as "planned" or
"not yet". With `--trees` and the same SDKs the article names, it also fails
when the article differs from what `docc` writes; otherwise it prints a note
and skips that comparison. CI runs it with the selected SDK and no trees;
`validate.sh` runs it with every installed SDK and the trees.

## Native boundary

`DriverExtensionGenerator` copies a single packaged native source tree from
`Sources/SwifterKit/Resources/DriverKitExtension`. Driver authors do not supply
native glue to the generator.

The generated extension and the Swift host exchange versioned runtime messages.
Swift receives typed values, opaque memory handles, and bounded payloads rather
than DriverKit objects or native pointers. The extension notifies the host when
events are queued, and `DriverHost.runEvents()` delivers them without polling. Ethernet, block-storage, SCSI, and
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

The compatibility job runs the tests with Xcode 16.3, Swift 6.1, and the
DriverKit 24.4 SDK while retaining the macOS 10.15 deployment target. A Linux
job runs the tests in the `swift:6.1` container. The main validation job uses
the latest passing local toolchain.

Tests that build a generated extension use the DriverKit SDK in
`SWIFTERKIT_DRIVERKIT_DEVELOPER_DIR`, or `DEVELOPER_DIR` when that is unset.
Point it at Xcode 16.3 to build the default DriverKit 19.0 target unchanged.
`validate.sh` builds the checked-in native project, which links every family
framework including VideoDriverKit, with `DEVELOPER_DIR`. With a newer SDK the
build's deployment target is raised to the SDK minimum (the Xcode 27 SDK starts
at DriverKit 21.0). Build tests for projects that need a newer SDK, such as
video (DriverKit 25.5), report as skipped on older SDKs; the Xcode 26.6 and
Xcode 27 SDKs build video. Set `SWIFTERKIT_REQUIRE_DRIVERKIT=1` to fail
the run when no SDK is installed. Unset `TOOLCHAINS` when it selects a
swift.org toolchain, because the generated-project builds must use Xcode's
compilers.

### Hardware runtime coverage

CI does not run on macOS 10.15 and cannot activate a signed extension or attach
physical hardware. The following macOS 10.15 runtime paths remain
compile-checked but unexecuted in CI:

- IOKit service discovery and user-client opening through `kIOMasterPortDefault`;
- Swift concurrency back-deployment during the driver lifecycle and event loop;
- event notifications through `IOConnectCallAsyncStructMethod`, the IOKit
  notification port, and the extension's `AsyncCompletion` calls;
- generated extension activation, runtime negotiation, and device I/O on a
  macOS 10.15 host; and
- signed entitlement, provisioning, and hardware behavior.

SwifterKit 0.3.0 has not been run on physical hardware. This includes fast-path
programs, DMA rings, host-shared data queues, wrapped or mapped host memory, and
device I/O for every capability family: HID, USB and USB serial, PCI, serial,
block storage, MIDI, Ethernet networking, audio, SCSI, video, interrupts,
memory and DMA, service operations, timers and watches, and IOReporting.

Unit tests model the extension's event notifications with mock connections.
IOKit port selection depends on the running operating system and needs a macOS
10.15 host for runtime coverage.

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

The host application needs the `com.apple.developer.driverkit.userclient-access`
entitlement, and its array must contain the extension's bundle identifier.
Every generated extension rejects runtime connections from processes without
it. See [The native DriverKit boundary](Sources/SwifterKit/SwifterKit.docc/NativeBoundary.md#host-access).

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

[MIT](LICENSE)
