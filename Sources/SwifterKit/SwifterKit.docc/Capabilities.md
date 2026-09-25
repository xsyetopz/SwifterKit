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

Use `.usb` with ``USBDeviceConfiguration``. Set ``DriverConfiguration/providerClass`` to ``USBDeviceConfiguration/interfaceProviderClass`` to match one interface, or to ``USBDeviceConfiguration/deviceProviderClass`` to match the whole device. A device configuration cannot set ``USBDeviceConfiguration/configurationValue`` or the interface fields, because `IOUSBHostDevice` matching has no such keys. The extension opens the provider when it starts and closes it when it stops.

Both providers support ``DriverContext/usbControlTransfer(_:data:timeout:)``, ``DriverContext/usbDeviceDescriptor()``, ``DriverContext/usbConfigurationDescriptor(_:)``, ``DriverContext/usbStringDescriptor(index:languageID:)``, ``DriverContext/usbCapabilityDescriptors()``, ``DriverContext/usbDescriptor(type:index:languageID:requestType:recipient:length:)``, speed, address, port status, frame and microframe numbers, and ``DriverContext/usbAbortDeviceRequests()``. A device provider also selects a configuration with ``DriverContext/usbSetConfiguration(_:matchInterfaces:)``, lists its interfaces with ``DriverContext/usbInterfaces()``, and resets with ``DriverContext/usbResetDevice()``. An interface provider adds endpoint I/O, stall clearing, alternate settings, ``DriverContext/usbInterfaceDescriptor()``, and the idle policy.

A descriptor that does not fit in one runtime message throws ``USBDescriptorError/tooLarge(length:)`` instead of arriving truncated. The microframe calls report `kIOReturnUnsupported` when the extension was built with an SDK older than DriverKit 25.

Endpoint I/O is synchronous with ``DriverContext/usbRead(endpoint:length:timeout:)`` and ``DriverContext/usbWrite(endpoint:data:timeout:)``, or asynchronous with ``DriverContext/usbEnqueueRead(endpoint:length:timeout:)``, ``DriverContext/usbEnqueueWrite(endpoint:data:timeout:)``, ``DriverContext/usbEnqueueIsochronousRead(endpoint:frameLengths:firstFrame:)``, and ``DriverContext/usbEnqueueIsochronousWrite(endpoint:frames:firstFrame:)``. An enqueue call returns a request identifier, and ``DriverEvent/usb()`` decodes the completion as a ``USBPipeIOCompletion`` or ``USBIsochronousCompletion`` with the `IOReturn` status. The completion can arrive before the enqueue call returns, so match completions by request identifier. At most 32 transfers are outstanding; a further enqueue fails with `kIOReturnNoResources`. A transfer, its completion event, and an isochronous frame list must each fit in one runtime message, so reads are limited to ``DriverCommand/usbMaximumAsyncReadLength`` bytes and writes to ``DriverCommand/usbMaximumAsyncWriteLength`` bytes. ``DriverContext/usbAbortPipe(endpoint:)`` and ``DriverContext/usbAbortDeviceRequests()`` abort asynchronously; each aborted transfer still completes with `kIOReturnAborted`.

Use `.pci` with ``PCIDeviceConfiguration`` for an `IOPCIDevice` provider. Read and write configuration or BAR space with ``DriverContext/pciRead(space:offset:width:options:)`` and ``DriverContext/pciWrite(space:offset:value:width:options:)``; inspect BARs with ``DriverContext/pciBaseAddressInfo(index:)``.

Configuration-space accesses stay inside the 4 KiB extended configuration area and take no options. Aperture accesses name a memory index from ``PCIBaseAddressInfo/memoryIndex``; the extension checks each access against the size `GetBARInfo` reports for BAR0 through BAR5 and rejects accesses past the end of the BAR or to the expansion ROM, whose size DriverKit does not report. ``PCIAccessOptions/latencyTolerant`` lets DriverKit offload an aperture access.

Device-control operations change device state, so each one is an explicit call with no implicit use by the runtime:

- ``DriverContext/pciReset(type:options:)`` resets the device, or every function of a multifunction device. Nothing may access the device during the reset. ``PCIResetType/warmDisable`` leaves the device unusable until a ``PCIResetType/warmEnable`` reset, and ``PCIResetOptions/terminate`` terminates the device and this extension, so the call may not return a response.
- ``DriverContext/pciSaveDeviceState(options:)`` and ``DriverContext/pciRestoreDeviceState()`` save and rewrite configuration space.
- ``DriverContext/pciHasPowerManagement(support:)`` and ``DriverContext/pciEnablePowerManagement(state:)`` query and select the sleep power state.
- ``DriverContext/pciLinkSpeed()`` reads the link speed. ``DriverContext/pciSetLinkSpeed(_:retrain:)`` sets the upstream bridge's target speed and, with `retrain`, retrains the link immediately.
- ``DriverContext/pciSetASPMState(_:)`` enables or disables ASPM levels on the device and its upstream bridge.
- ``DriverContext/pciSetProperties(_:)`` sets the Boolean sleep properties in ``PCIDeviceProperties``.

To allocate MSI, MSI-X, or legacy vectors, set ``PCIDeviceConfiguration/interrupts`` to a ``PCIInterruptConfiguration`` and enable `.interrupts`. The extension calls `IOPCIDevice::ConfigureInterrupts` while starting, after it opens the provider and before it creates any interrupt source, because that call allocates the vectors the sources use. Every ``InterruptSourceConfiguration/index`` must be below ``PCIInterruptConfiguration/requiredVectorCount``, the only vectors DriverKit guarantees; the generator and the extension both reject other indices. MSI allows 32 vectors, MSI-X 2,048, and legacy one. DriverKit documents that interrupt dispatch sources support only MSI for `IOPCIDevice` providers, so prefer ``PCIInterruptType/msi`` or ``PCIInterruptType/msiX``. Confirm the assigned type with ``DriverContext/interruptType(index:)`` and ``PCIInterruptType/init(interruptTypeFlags:)``.

The SDK headers declare every `IOPCIDevice` member used here in DriverKit 24.4 and later without an availability attribute, so the generator applies no deployment floor beyond the PCI row above. An older system can still return an error for an operation it does not implement.

### Serial and block storage

Use `.serial` with ``SerialPortConfiguration``. Receive typed serial events from ``DriverEvent/serial()``, queue received bytes, dequeue transmitted bytes, and update modem or receive-error state through ``DriverContext``.

Use `.blockStorage` with ``BlockStorageDeviceConfiguration``. Decode ``DriverEvent/blockStorage()`` and explicitly complete every request with ``DriverContext/completeBlockStorageRequest(requestID:status:)`` or ``DriverContext/completeBlockStorageIO(requestID:bytesTransferred:status:)``.

### MIDI, Ethernet, audio, and video

Use `.midi` with ``MIDIDeviceConfiguration`` and send source packets through ``DriverContext/midiSend(sourceIndex:words:)``. Decode lifecycle and destination packets with ``DriverEvent/midi()``.

Use `.networking` with ``EthernetDeviceConfiguration``. ``DriverEvent/ethernet()`` delivers transmit work; Swift completes it, receives frames, and reports link state through ``DriverContext``.

Use `.audio` with ``AudioDeviceConfiguration``. Audio APIs read and write stream ranges, query I/O state, update timestamps, request sample-rate changes, and work with typed controls and custom properties.

Use `.video` with ``VideoDeviceConfiguration``. Video APIs access bounded buffer planes, operate stream queues, update timestamps, request sample-rate changes, and handle device, control, property, stream, and input events.

## Hardware support

Use `.interrupts` with one or more ``InterruptSourceConfiguration`` values. Enable delivery, read the type or latest snapshot, and decode ``DriverEvent/interrupt()``. For PCI providers, ``PCIInterruptConfiguration`` selects MSI, MSI-X, or legacy allocation before the sources are created.

Use `.memory` with ``MemoryPoolConfiguration``. Allocate ``DriverMemoryHandle`` values, access bounded ranges, inspect mapping metadata, and prepare or complete DMA through ``DriverContext``.

Use `.scsi` with exactly one of ``SCSIControllerConfiguration`` or ``SCSIPeripheralConfiguration``. Controller drivers decode ``DriverEvent/scsiController()`` and complete pending parallel tasks. Peripheral drivers send ``SCSIPeripheralCommand`` values and control their published services.

## Service operations

Every generated extension exposes `IOService` operations on its own service, with no capability flag.

- ``DriverContext/setServiceProperties(_:)``, ``DriverContext/serviceProperties()``, ``DriverContext/removeServiceProperty(named:)``, and ``DriverContext/searchServiceProperty(named:options:plane:)`` work with registry properties as ``DriverProperty`` values. `IOService` rejects property updates unless a family superclass accepts them. DriverKit numbers are unsigned, so numbers read back as ``DriverProperty/unsignedInteger(_:)`` and ``DriverProperty/real(_:)`` cannot be stored. Values nest at most eight levels and must fit one runtime message; Swift and the extension both reject anything else with ``ServiceRuntimeError``.
- ``DriverContext/providerProperties(keys:)`` returns the supportable properties of each provider towards the registry root. ``DriverContext/serviceName()`` and ``DriverContext/registryEntryID()`` identify the service.
- ``DriverContext/changePowerState(_:)``, ``DriverContext/setPowerOverride(_:)``, ``DriverContext/createPMAssertion(_:synced:)``, and ``DriverContext/releasePMAssertion(_:)`` drive power management. Assertions need the DriverKit 25.5 SDK or later; builds with an older SDK report `kIOReturnUnsupported`.
- ``DriverContext/adjustBusy(by:)``, ``DriverContext/busyState()``, ``DriverContext/requireMaxBusStall(_:)``, and ``DriverContext/terminateService()`` control busy state, DMA latency, and termination.
- ``DriverContext/systemStateItem(named:)``, ``DriverContext/createSystemStateItem(named:value:)``, and ``DriverContext/setSystemStateItem(named:value:)`` use the system state notification service, for example the `com.apple.iokit.pm.*` keys. ``DriverContext/sendCoreAnalyticsEvent(named:payload:)`` posts to CoreAnalytics.

The extension overrides `IOService::SetPowerState`. Decode ``DriverEvent/servicePowerState()``, make the device safe for ``ServicePowerStateRequest/capability``, and answer with ``DriverContext/completePowerState(requestID:)``; DriverKit changes power only after the change is acknowledged. The extension acknowledges on the driver's behalf after ten seconds, when the host disconnects or the service stops, and at once when no host is connected, so a missing or failed Swift handler cannot stall the system. DriverKit's acknowledgement has no status, so every path acknowledges the same way. A driver that ignores the event delays every sleep and wake by the ten-second timeout. Completing a request the extension already acknowledged fails with `kIOReturnNotFound`.

## Related articles

- <doc:GettingStarted>
- <doc:NativeBoundary>
