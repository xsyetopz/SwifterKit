# ``SwifterKit``

Author DriverKit extensions in Swift. ``SwiftDriver`` supplies lifecycle behavior, ``DriverConfiguration`` describes the extension, and ``DriverContext`` issues typed operations after the internal runtime connects.

## Overview

A driver declares the capabilities and static device metadata required by its generated extension. At runtime, the extension forwards lifecycle and device events to Swift, and the driver responds through capability-specific methods on ``DriverContext``.

The package includes APIs for HID, USB, PCI, serial, block storage, MIDI, Ethernet, audio, SCSI, video, interrupts, and managed native memory. A generated extension only exposes the capabilities included in its ``DriverConfiguration``.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:NativeBoundary>
- <doc:Capabilities>

### Driver authoring

- ``SwiftDriver``
- ``DriverConfiguration``
- ``DriverContext``
- ``DriverEvent``
- ``DriverHost``
- ``DriverExtensionGenerator``

### Service access

- ``DriverClient``
- ``DriverSession``
- ``DriverServiceMatch``
- ``DriverRequest``

### Runtime contract

- ``RuntimeCapabilities``
- ``DriverCommand``
- ``DriverKitError``
