# The native DriverKit boundary

SwifterKit separates Swift driver behavior from the native extension required by the DriverKit ABI. ``DriverExtensionGenerator`` copies and configures that internal extension from ``DriverConfiguration``; driver authors do not provide C++ or IIG source to the generator.

## Configuration becomes extension metadata

``DriverConfiguration`` contains the bundle identifier, provider class, IOKit matching properties, and ``RuntimeCapabilities``. It can also carry metadata for one or more supported capability layers, such as ``USBDeviceConfiguration``, ``PCIDeviceConfiguration``, ``AudioDeviceConfiguration``, or ``MemoryPoolConfiguration``.

The generator validates combinations that the native runtime supports. A declared capability needs its matching configuration object when required, and some capability combinations are mutually exclusive. For example, USB matching requires `IOUSBHostInterface` as the provider class, and PCI matching requires `IOPCIDevice`.

HID host-report acceptance is static capability policy owned by ``HIDDeviceConfiguration/acceptedHostReportTypes``. The generator writes that typed allowlist into the native runtime configuration. The extension checks it synchronously in `setReport` and returns `kIOReturnUnsupported` for a disallowed type before reading or forwarding the report payload.

## Runtime messages stay typed

The generated extension and Swift host exchange versioned ``RuntimeMessage`` values. ``DriverContext`` checks ``RuntimeCapabilities`` before it sends a ``DriverCommand``. Capability extensions expose typed methods such as ``DriverContext/usbRead(endpoint:length:timeout:)``, ``DriverContext/pciRead(space:offset:width:options:)``, and ``DriverContext/allocateMemory(capacity:length:direction:alignment:)`` instead of exposing DriverKit objects or native pointers.

``DriverEvent`` has an event type and payload at the transport layer. Decode it with the extension for the capability that owns the event, such as ``DriverEvent/hidReport()``, ``DriverEvent/serial()``, ``DriverEvent/ethernet()``, or ``DriverEvent/video()``. Each decoder returns `nil` for events from other capability families and throws for malformed payloads in its own family.

## Memory and completion ownership

Memory operations use opaque ``DriverMemoryHandle`` values and bounded read/write lengths. DMA preparation returns a ``DriverDMAMapping``; complete the mapping with ``DriverContext/completeMemoryDMA(_:)`` when the device is done.

Several device families forward work that Swift must complete explicitly. Complete an Ethernet transmit through ``DriverContext/completeEthernetTransmit(requestID:status:)``, a block-storage request through ``DriverContext/completeBlockStorageRequest(requestID:status:)`` or ``DriverContext/completeBlockStorageIO(requestID:bytesTransferred:status:)``, and an SCSI task through ``DriverContext/completeSCSIParallelTask(_:)``. Keep the matching request identifier or completion object until the transport result is known.

## Raw service access

``DriverClient`` and ``DriverSession`` are separate from the generated runtime protocol. They enumerate IOKit services and invoke raw user-client external methods through ``DriverRequest`` and ``DriverResponse``. Use those APIs only when a capability-specific ``DriverContext`` method does not describe the operation you need.

## Related articles

- <doc:GettingStarted>
- <doc:Capabilities>
