# The native DriverKit boundary

SwifterKit separates Swift driver behavior from the native extension that the DriverKit ABI requires. ``DriverExtensionGenerator`` copies and configures that internal extension from ``DriverConfiguration``. Driver authors do not provide C++ or IIG source to the generator.

Toolchain and platform requirements are in <doc:Capabilities#Deployment-requirements>. No 0.2.1 paths have run on physical hardware.

## Configuration becomes extension metadata

``DriverConfiguration`` contains the bundle identifier, provider class, IOKit matching properties, and ``RuntimeCapabilities``. It can also carry metadata for one or more supported capability layers, such as ``USBDeviceConfiguration``, ``PCIDeviceConfiguration``, ``AudioDeviceConfiguration``, or ``MemoryPoolConfiguration``.

The generator validates combinations that the native runtime supports:

- A declared capability needs its matching configuration object when required.
- Some capability combinations are mutually exclusive.
- USB matching requires `IOUSBHostInterface` or `IOUSBHostDevice` as the provider class. PCI matching requires `IOPCIDevice`.

``HIDDeviceConfiguration/acceptedHostReportTypes`` owns HID host-report acceptance as static capability policy. The generator writes that typed allowlist into the native runtime configuration. The extension checks it synchronously in `setReport`. For a disallowed type it returns `kIOReturnUnsupported` before it reads or forwards the report payload.

## Runtime messages stay typed

The generated extension and Swift host exchange versioned ``RuntimeMessage`` values. ``DriverContext`` checks ``RuntimeCapabilities`` before it sends a ``DriverCommand``. Capability extensions expose typed methods instead of DriverKit objects or native pointers. Examples are ``DriverContext/usbRead(endpoint:length:timeout:)``, ``DriverContext/pciRead(space:offset:width:options:)``, and ``DriverContext/allocateMemory(capacity:length:direction:alignment:)``.

### Protocol versions and message limits

``DriverRuntimeConnection/connect(session:requiring:maximumResponseSize:)`` starts with a handshake that offers ``RuntimeProtocolVersion/supported``. The extension selects the highest version in both its own range and the offered range. It returns that version with its ``RuntimeCapabilities``. The handshake fails when the ranges do not overlap.

Every later message uses the selected ``DriverRuntimeConnection/protocolVersion``. ``RuntimeMessage/init(decoding:)`` accepts only versions in the supported range. Protocol version 2 is the first version that negotiates. Version 1 extensions are not supported.

A complete message, header included, is at most ``RuntimeMessage/maximumSize`` bytes in either direction. ``RuntimeMessage/encoded()`` throws ``RuntimeProtocolError/payloadTooLarge`` for a larger message. An oversize command therefore fails before it reaches IOKit.

### One protocol schema

SwifterKit declares these wire-protocol values once in Swift:

- the magic value
- the version range
- the message size limit
- message kinds and message flags
- opcodes and event types
- capability bits

The native extension includes a header rendered from those declarations. A package test fails when the checked-in header drifts from the Swift schema. Fixed-size native payload layouts stay hand-written. The extension checks the header and handshake layouts against the sizes the schema declares.

``DriverEvent`` has an event type and payload at the transport layer. Decode it with the extension for the capability that owns the event, such as ``DriverEvent/hidReport()``, ``DriverEvent/serial()``, ``DriverEvent/ethernet()``, or ``DriverEvent/video()``. Each decoder returns `nil` for events from other capability families. It throws for malformed payloads in its own family.

## Event delivery

The extension queues events in two classes with separate capacity.

Required events carry DriverKit work that Swift must answer, or a result Swift must see:

- block-storage requests
- SCSI parallel tasks and task-management notifications
- Ethernet transmit packets and control changes
- audio or video control, custom-property, and stream-format changes
- audio box-acquisition and clock-device sample-rate requests
- USB pipe completions
- HID get-report requests

Lossy events are notifications. Swift may miss them without leaving a DriverKit request outstanding:

- HID host reports, input reports, element values, and LED and property changes
- interrupts
- serial and MIDI notifications
- audio or video I/O state

An event, including its type and the runtime message header, must fit in one runtime message. The extension rejects a larger event when it is queued, not when Swift takes it.

The required queue holds 512 events and the lossy queue holds 64. Lossy traffic never uses required capacity. Each request for an event returns the oldest required event before any lossy event. Events keep their order within a class. A required event can overtake an earlier lossy event.

### Notifications instead of polling

``DriverRuntimeConnection/events()`` registers the host with an asynchronous external method (`IOConnectCallAsyncStructMethod`) before it returns. The extension keeps the host's completion and signals it through `AsyncCompletion` when events are pending. ``DriverEventSequence`` then takes events until the queue is empty and waits for the next signal. ``DriverHost/runEvents()`` iterates that sequence.

The extension keeps an armed flag, changed only under its event lock. No event is left waiting, and no event triggers more than one signal:

- A request that finds both queues empty arms the flag.
- Queuing an event while the flag is armed clears it and sends one signal after the lock is released. Events queued while the host is still taking events send nothing. The host finds them before its queue is empty.
- Registering arms the flag, or signals at once when events are already queued.

The host's connection buffers at most one signal. Signals that arrive while the host is busy coalesce into one more pass over the queue.

A second registration replaces the first, and the earlier ``DriverEventSequence`` ends. The second registration can come from a different connection. The first connection is then no longer the registered host, so the extension detaches it the same way it detaches a departed host. It empties both queues and answers the tracked requests, as described below. Closing the first connection afterwards answers nothing more.

### Host detach

When the registered host goes away, the extension answers the requests that host can no longer complete. These all detach the host:

- closing the connection
- host process exit
- a DriverKit client-crash report for the runtime client
- stopping the extension's service

Detaching empties both queues. It then answers tracked requests the same way the service does when it stops:

- Block-storage requests complete with `kIOReturnAborted` and zero bytes transferred.
- SCSI parallel tasks complete with `kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE`.
- Ethernet transmit packets return to their buffer pool.
- Pending HID get-report requests complete with `kIOReturnAborted`.
- Pending audio box-acquisition and clock-device sample-rate requests are rejected. The box reports `kIOReturnAborted` as its acquisition failure, and the sample rate stays unchanged.

Other HID, serial, MIDI, interrupt, audio, video, and SCSI peripheral events leave no DriverKit request waiting for Swift. Those families have nothing to answer.

Events queued while no host is registered wait for the next host, as they do before the first host connects. A request queued while a host detaches can leave a stale event for the next host. The next host's completion for that event then fails.

### Full queues

When the lossy queue is full or the event cannot be allocated, the extension drops the event and counts the drop in its service state. When the DriverKit caller has a result, the extension returns `kIOReturnNoSpace` or `kIOReturnNoMemory` to it.

When the required queue rejects an event, the extension answers the DriverKit request itself, and Swift never sees it:

- Block storage completes the request through `Complete` or `CompleteIO` with the enqueue status and zero bytes transferred. The status is `kIOReturnNoSpace`, `kIOReturnNoMemory` when allocation fails, or `kIOReturnBadArgument` when the event would not fit in one runtime message.
- An SCSI parallel task completes through its completion action with `kSCSIServiceResponse_SERVICE_DELIVERY_OR_TARGET_FAILURE` and `kSCSITaskStatus_No_Status`. Task-management requests return that service response and the enqueue error synchronously. Target initialization returns the enqueue error.
- An Ethernet transmit packet returns to its buffer pool, the same outcome as a failed Swift completion. Ethernet control changes return the enqueue error to NetworkingDriverKit.
- Audio and video control, custom-property, stream-format, and stream-activity changes return the enqueue error to the framework, which rejects the change.

A request that the extension answers this way has no request identifier for Swift to complete.

A USB pipe completion has no DriverKit request to answer. When the required queue rejects one, the extension keeps the transfer's slot, its result, and its data. The request identifier is therefore not reused, and a full table refuses new transfers. The extension retries delivery, oldest completion first, at these points:

- on every later USB command and completion
- after each request for an event that takes a required event, and so frees required capacity

A host that only takes events therefore still receives it.

## Host access

The generated runtime user client accepts a host process only when both conditions hold:

- The process has the `com.apple.developer.driverkit.userclient-access` entitlement.
- The entitlement's array contains the extension's bundle identifier, ``DriverConfiguration/bundleIdentifier``.

The extension checks this for every capability, not only audio. Add the entitlement to the host application that connects through ``DriverClient`` or ``DriverHost``:

```xml
<key>com.apple.developer.driverkit.userclient-access</key>
<array>
  <string>com.example.driver</string>
</array>
```

Family clients bypass the SwifterKit runtime client, which still requires the host entitlement. The extensions differ in whether they carry `com.apple.developer.driverkit.allow-any-userclient-access`:

- Video extensions carry it. The system video service opens the family user client and does not hold the host application's entitlement.
- Audio extensions do not. coreaudiod's `com.apple.private.driverkit.driver-access` entitlement admits any extension holding `com.apple.developer.driverkit.family.audio`.
- MIDI extensions do not. MIDIServer opens the MIDI family user client through its own `com.apple.private.driverkit.driver-access` entitlement. `IOKitKeys.h` describes that entitlement as admitting any dext that holds one of the listed entitlements. MIDIServer lists `com.apple.developer.driverkit.family.midi`, which every generated MIDI extension carries.

## Memory and completion ownership

Memory operations use opaque ``DriverMemoryHandle`` values and bounded read/write lengths. DMA preparation returns a ``DriverDMAMapping``. Complete the mapping with ``DriverContext/completeMemoryDMA(_:)`` when the device is done.

Several device families forward work that Swift must complete explicitly:

- Complete an Ethernet transmit through ``DriverContext/completeEthernetTransmit(requestID:status:)``.
- Complete a block-storage request through ``DriverContext/completeBlockStorageRequest(requestID:status:)`` or ``DriverContext/completeBlockStorageIO(requestID:bytesTransferred:status:)``.
- Complete an SCSI task through ``DriverContext/completeSCSIParallelTask(_:)``.

Keep the matching request identifier or completion object until the transport result is known.

The extension cannot take a block-storage request or SCSI task with invalid arguments, a full request table, or a payload over the event limit. It completes that request itself with a failure status. The request never reaches Swift and never needs a Swift completion.

The one exception is a block-storage request whose identifier matches one still outstanding. The extension refuses it with `kIOReturnExclusiveAccess` and no completion, because completing that identifier would answer the outstanding request.

## Raw service access

``DriverClient`` and ``DriverSession`` are separate from the generated runtime protocol. They enumerate IOKit services and invoke raw user-client external methods through ``DriverRequest`` and ``DriverResponse``. Use those APIs only when no capability-specific ``DriverContext`` method describes the operation you need.

## DriverKit coverage manifest

The repository file `coverage/driverkit.json` lists every class and member function that the DriverKit SDK `.iig` headers declare. Each entry records the SDK versions that declare the member. It also records the member's `introduced` and `deprecated` DriverKit versions when the header gives them. Each entry also records a status:

- `gap`: Swift cannot reach the member yet.
- `generated`: the generated extension runtime calls or overrides the member.
- `swift-api`: the typed Swift API named in `swiftSymbol` exposes the member.
- `fast-path`: a fast-path program can declare the member. See <doc:FastPath>.
- `excluded`: the member is out of scope, and `note` gives the reason.

The `SwifterKitCoverage` package tool is separate from the `SwifterKit` library:

- Its `summary` command prints the counts per framework.
- Its `update` command records the surface of a new SDK.

CI checks the manifest against the DriverKit SDK in each job. The check fails when the SDK declares a member that the manifest does not list. It also fails when a non-`gap` entry has no supporting source or note.

## Related articles

- <doc:GettingStarted>
- <doc:Capabilities>
