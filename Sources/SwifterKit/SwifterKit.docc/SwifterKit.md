# ``SwifterKit``

Write DriverKit extensions in Swift.

## Overview

A driver has three parts:

- ``DriverConfiguration`` describes the extension: bundle identifier, provider matching,
  ``RuntimeCapabilities``, and static device metadata.
- ``DriverExtensionGenerator`` writes the native DriverKit extension project from that
  configuration. Driver authors write no C++, C, Objective-C, or IIG.
- A ``SwiftDriver`` type runs in the host process. ``DriverHost`` delivers lifecycle and device
  events to it, and the driver acts through typed methods on ``DriverContext``.

SwifterKit covers HID, USB, PCI, serial, block storage, MIDI, Ethernet, audio, SCSI, video,
interrupts, and managed native memory. A generated extension exposes only the capabilities in
its ``DriverConfiguration``.

SwifterKit 0.3.0 requires Swift 6.1 (Xcode 16.3) or later and macOS 10.15 or later. The IOKit
transport builds only on Apple platforms. Configuration and generation also build on Linux. No
0.3.0 path has run on physical hardware.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Capabilities>
- <doc:NativeBoundary>
- <doc:FastPath>
- <doc:DriverKitCoverage>

### Driver authoring

- ``SwiftDriver``
- ``DriverConfiguration``
- ``DriverExtensionConfiguration``
- ``DriverContext``
- ``DriverEvent``
- ``DriverHost``
- ``DriverEventSequence``
- ``DriverExtensionGenerator``
- ``DriverExtensionGenerator/generate(extension:options:at:)``

### Service access

- ``DriverClient``
- ``DriverSession``
- ``DriverServiceMatch``
- ``DriverRequest``

### Runtime contract

- ``RuntimeCapabilities``
- ``DriverCommand``
- ``DriverKitError``
