# The native DriverKit boundary

SwifterKit separates Swift driver behavior from the native extension required by the DriverKit ABI. ``DriverExtensionGenerator`` copies and configures that internal extension from ``DriverConfiguration``; driver authors do not provide C++ or IIG source to the generator.

## Configuration becomes extension metadata

``DriverConfiguration`` contains the bundle identifier, provider class, IOKit matching properties, and ``RuntimeCapabilities``. It can also carry metadata for one or more supported capability layers, such as ``USBDeviceConfiguration``, ``PCIDeviceConfiguration``, ``AudioDeviceConfiguration``, or ``MemoryPoolConfiguration``.

The generator validates combinations that the native runtime supports. A declared capability needs its matching configuration object when required, and some capability combinations are mutually exclusive. For example, USB matching requires `IOUSBHostInterface` or `IOUSBHostDevice` as the provider class, and PCI matching requires `IOPCIDevice`.

HID host-report acceptance is static capability policy owned by ``HIDDeviceConfiguration/acceptedHostReportTypes``. The generator writes that typed allowlist into the native runtime configuration. The extension checks it synchronously in `setReport` and returns `kIOReturnUnsupported` for a disallowed type before reading or forwarding the report payload.

## Runtime messages stay typed

The generated extension and Swift host exchange versioned ``RuntimeMessage`` values. ``DriverContext`` checks ``RuntimeCapabilities`` before it sends a ``DriverCommand``. Capability extensions expose typed methods such as ``DriverContext/usbRead(endpoint:length:timeout:)``, ``DriverContext/pciRead(space:offset:width:options:)``, and ``DriverContext/allocateMemory(capacity:length:direction:alignment:)`` instead of exposing DriverKit objects or native pointers.

### Protocol versions and message limits

``DriverRuntimeConnection/connect(session:requiring:maximumResponseSize:)`` starts with a handshake that offers ``RuntimeProtocolVersion/supported``. The extension selects the highest version in both its own range and the offered range, returns it with its ``RuntimeCapabilities``, and fails the handshake when the ranges do not overlap. Every later message uses the selected ``DriverRuntimeConnection/protocolVersion``, and ``RuntimeMessage/init(decoding:)`` accepts only versions in the supported range. Protocol version 2 is the first version that negotiates; version 1 extensions are not supported.

A complete message, header included, is at most ``RuntimeMessage/maximumSize`` bytes in either direction. ``RuntimeMessage/encoded()`` throws ``RuntimeProtocolError/payloadTooLarge`` for a larger message, so an oversize command fails before it reaches IOKit.

### One protocol schema

SwifterKit declares the wire protocol's magic value, version range, message size limit, message kinds, message flags, opcodes, event types, and capability bits once in Swift. The native extension includes a header rendered from those declarations, and a package test fails when the checked-in header drifts from the Swift schema. Fixed-size native payload layouts stay hand-written; the extension checks the header and handshake layouts against the sizes the schema declares.

``DriverEvent`` has an event type and payload at the transport layer. Decode it with the extension for the capability that owns the event, such as ``DriverEvent/hidReport()``, ``DriverEvent/serial()``, ``DriverEvent/ethernet()``, or ``DriverEvent/video()``. Each decoder returns `nil` for events from other capability families and throws for malformed payloads in its own family.

## Event delivery

The extension queues events in two classes with separate capacity. Required events carry DriverKit work that Swift must answer or a result Swift must see: block-storage requests, SCSI parallel tasks and task-management notifications, Ethernet transmit packets and control changes, audio or video control, custom-property, and stream-format changes, USB pipe completions, and HID get-report requests. Lossy events are notifications such as HID host reports, input reports, element values, LED and property changes, interrupts, serial and MIDI notifications, and audio or video I/O state; Swift may miss them without leaving a DriverKit request outstanding.

An event, including its type and the runtime message header, must fit in one runtime message; a larger event is rejected when it is queued, not when Swift takes it. The required queue holds 512 events and the lossy queue holds 64. Lossy traffic never uses required capacity. Each request for an event returns the oldest required event before any lossy event. Events keep their order within a class, but a required event can overtake an earlier lossy event.

### Notifications instead of polling

``DriverRuntimeConnection/events()`` registers the host with an asynchronous external method (`IOConnectCallAsyncStructMethod`) before it returns. The extension keeps the host's completion and signals it through `AsyncCompletion` when events are pending. ``DriverEventSequence`` then takes events until the queue is empty and waits for the next signal; ``DriverHost/runEvents()`` iterates that sequence.

The extension keeps an armed flag, changed only under its event lock, so no event is left waiting and no event triggers more than one signal:

- A request that finds both queues empty arms the flag.
- Queuing an event while the flag is armed clears it and sends one signal after the lock is released. Events queued while the host is still taking events send nothing; the host finds them before its queue is empty.
- Registering arms the flag, or signals at once when events are already queued.

The host's connection buffers at most one signal, so signals that arrive while the host is busy coalesce into one more pass over the queue. A second registration replaces the first, and the earlier ``DriverEventSequence`` ends. When the second registration comes from a different connection, the first connection is no longer the registered host, so the extension detaches it the same way it detaches a departed host: it empties both queues and answers the tracked requests, as described below. Closing the first connection afterwards answers nothing more.

When the registered host goes away, the extension answers the requests that host can no longer complete. Closing the connection, host process exit, a DriverKit client-crash report for the runtime client, and stopping the extension's service all detach the host. Detaching empties both queues and then answers tracked requests the same way the service does when it stops:

- Block-storage requests complete with `kIOReturnAborted` and zero bytes transferred.
- SCSI parallel tasks complete with `kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE`.
- Ethernet transmit packets return to their buffer pool.

Pending HID get-report requests complete with `kIOReturnAborted`. Other HID, serial, MIDI, interrupt, audio, video, and SCSI peripheral events leave no DriverKit request waiting for Swift, so those families have nothing to answer. Events queued while no host is registered wait for the next host, as they do before the first host connects. A request queued while a host detaches can leave a stale event for the next host, whose completion for it then fails.

When the lossy queue is full or the event cannot be allocated, the extension drops the event, counts the drop in its service state, and returns `kIOReturnNoSpace` or `kIOReturnNoMemory` to the DriverKit caller when the caller has a result. When the required queue rejects an event, the extension answers the DriverKit request itself and Swift never sees it:

- Block storage completes the request through `Complete` or `CompleteIO` with the enqueue status (`kIOReturnNoSpace`, `kIOReturnNoMemory` when allocation fails, or `kIOReturnBadArgument` when the event would not fit in one runtime message) and zero bytes transferred.
- An SCSI parallel task completes through its completion action with `kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE` and `kSCSITaskStatus_No_Status`. Task-management requests return that service response and the enqueue error synchronously, and target initialization returns the enqueue error.
- An Ethernet transmit packet returns to its buffer pool, the same outcome as a failed Swift completion. Ethernet control changes return the enqueue error to NetworkingDriverKit.
- Audio and video control, custom-property, stream-format, and stream-activity changes return the enqueue error to the framework, which rejects the change.

A request that the extension answers this way has no request identifier for Swift to complete.

A USB pipe completion has no DriverKit request to answer. When the required queue rejects one, the extension keeps the transfer's slot, its result, and its data, so the request identifier is not reused and a full table refuses new transfers. It retries delivery, oldest completion first, on every later USB command and completion, and after each request for an event that takes a required event and so frees required capacity. A host that only takes events therefore still receives it.

## Host access

The generated runtime user client accepts a host process only when that process has the `com.apple.developer.driverkit.userclient-access` entitlement and its array contains the extension's bundle identifier, ``DriverConfiguration/bundleIdentifier``. The extension checks this for every capability, not only audio. Add the entitlement to the host application that connects through ``DriverClient`` or ``DriverHost``:

```xml
<key>com.apple.developer.driverkit.userclient-access</key>
<array>
  <string>com.example.driver</string>
</array>
```

Audio and video extensions also carry `com.apple.developer.driverkit.allow-any-userclient-access`, because system audio and video services open the family user clients and do not hold the host application's entitlement. Those family clients bypass the SwifterKit runtime client. The runtime client still requires the host entitlement.

## Memory and completion ownership

Memory operations use opaque ``DriverMemoryHandle`` values and bounded read/write lengths. DMA preparation returns a ``DriverDMAMapping``; complete the mapping with ``DriverContext/completeMemoryDMA(_:)`` when the device is done.

Several device families forward work that Swift must complete explicitly. Complete an Ethernet transmit through ``DriverContext/completeEthernetTransmit(requestID:status:)``, a block-storage request through ``DriverContext/completeBlockStorageRequest(requestID:status:)`` or ``DriverContext/completeBlockStorageIO(requestID:bytesTransferred:status:)``, and an SCSI task through ``DriverContext/completeSCSIParallelTask(_:)``. Keep the matching request identifier or completion object until the transport result is known.

A block-storage request or SCSI task that the extension cannot take (invalid arguments, a full request table, or a payload over the event limit) is completed by the extension with a failure status, so it never reaches Swift and never needs a Swift completion. The one exception is a block-storage request whose identifier matches one still outstanding: the extension refuses it with `kIOReturnExclusiveAccess` and no completion, because completing that identifier would answer the outstanding request.

## Raw service access

``DriverClient`` and ``DriverSession`` are separate from the generated runtime protocol. They enumerate IOKit services and invoke raw user-client external methods through ``DriverRequest`` and ``DriverResponse``. Use those APIs only when a capability-specific ``DriverContext`` method does not describe the operation you need.

## Related articles

- <doc:GettingStarted>
- <doc:Capabilities>
