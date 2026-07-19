# Capability APIs

Choose a ``RuntimeCapabilities`` value and the corresponding configuration metadata in ``DriverConfiguration``. The generated extension validates supported combinations before it is written.

## Deployment requirements

The Swift package supports macOS 10.15 and later. ``DriverExtensionGenerationOptions/deploymentTarget`` controls the generated extension separately and defaults to DriverKit 19.0.

| Capability | Minimum DriverKit target | Earliest host release |
| --- | ---: | --- |
| Base runtime, HID, USB, serial, interrupts, memory | 19.0 | macOS 10.15 |
| PCI | 19.0 | macOS 11.1 |
| SCSI controller | 20.4 | macOS 11.3 |
| Block storage, audio | 21.0 | macOS 12 |
| Networking, SCSI peripheral | 22.0 | macOS 13 |
| MIDI | 24.0 | macOS 15 |
| Video | 27.0 | macOS 27 beta |

Networking uses the DriverKit 22.0 queue-registration API. VideoDriverKit is currently beta and requires an SDK that contains the framework. The generator reports the existing capability-specific configuration error when a selected deployment target is too old.

## Device families

### Virtual HID

Use `.hid` with ``HIDDeviceConfiguration``. Submit input reports with ``DriverContext/submitHIDInputReport(_:)`` and decode host output or feature reports with ``DriverEvent/hidReport()``. Read extension-side delivery evidence with ``DriverContext/hidRuntimeStatistics()``; its counters distinguish attempted, successful, and failed HIDDriverKit submissions.

``HIDDeviceConfiguration/acceptedHostReportTypes`` defaults to ``HIDHostReportTypes/all``, preserving output and feature report delivery. Use ``HIDHostReportTypes/output`` for an output-only descriptor. The generated extension returns `kIOReturnUnsupported` synchronously for disallowed types before it reads, allocates, or enqueues their payloads, so the Swift host never receives those events.

### USB and PCI

Use `.usb` with ``USBDeviceConfiguration`` for an `IOUSBHostInterface` provider. ``DriverContext`` provides control transfers, endpoint reads and writes, stall clearing, and alternate-setting selection.

Use `.pci` with ``PCIDeviceConfiguration`` for an `IOPCIDevice` provider. Read and write configuration or BAR space with ``DriverContext/pciRead(space:offset:width:options:)`` and ``DriverContext/pciWrite(space:offset:value:width:options:)``; inspect BARs with ``DriverContext/pciBaseAddressInfo(index:)``.

### Serial and block storage

Use `.serial` with ``SerialPortConfiguration``. Receive typed serial events from ``DriverEvent/serial()``, queue received bytes, dequeue transmitted bytes, and update modem or receive-error state through ``DriverContext``.

Use `.blockStorage` with ``BlockStorageDeviceConfiguration``. Decode ``DriverEvent/blockStorage()`` and explicitly complete every request with ``DriverContext/completeBlockStorageRequest(requestID:status:)`` or ``DriverContext/completeBlockStorageIO(requestID:bytesTransferred:status:)``.

### MIDI, Ethernet, audio, and video

Use `.midi` with ``MIDIDeviceConfiguration`` and send source packets through ``DriverContext/midiSend(sourceIndex:words:)``. Decode lifecycle and destination packets with ``DriverEvent/midi()``.

Use `.networking` with ``EthernetDeviceConfiguration``. ``DriverEvent/ethernet()`` delivers transmit work; Swift completes it, receives frames, and reports link state through ``DriverContext``.

Use `.audio` with ``AudioDeviceConfiguration``. Audio APIs read and write stream ranges, query I/O state, update timestamps, request sample-rate changes, and work with typed controls and custom properties.

Use `.video` with ``VideoDeviceConfiguration``. Video APIs access bounded buffer planes, operate stream queues, update timestamps, request sample-rate changes, and handle device, control, property, stream, and input events.

## Hardware support

Use `.interrupts` with one or more ``InterruptSourceConfiguration`` values. Enable delivery, read the type or latest snapshot, and decode ``DriverEvent/interrupt()``.

Use `.memory` with ``MemoryPoolConfiguration``. Allocate ``DriverMemoryHandle`` values, access bounded ranges, inspect mapping metadata, and prepare or complete DMA through ``DriverContext``.

Use `.scsi` with exactly one of ``SCSIControllerConfiguration`` or ``SCSIPeripheralConfiguration``. Controller drivers decode ``DriverEvent/scsiController()`` and complete pending parallel tasks. Peripheral drivers send ``SCSIPeripheralCommand`` values and control their published services.

## Related articles

- <doc:GettingStarted>
- <doc:NativeBoundary>
