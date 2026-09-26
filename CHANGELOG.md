# Changelog

SwifterKit records user-visible changes in this file.

## [Unreleased]

### Changed

- **Breaking:** `SCSIControllerRuntimeError` gains `invalidPropertyUpdate` and
  `invalidDataRange`.
- **Breaking:** `SCSIControllerEvent` gains the `targetCreated` case, which
  carries a `SCSITargetCreationResult`, so exhaustive switches over it must
  handle the new case.
- Video generation requires DriverKit 25.5 instead of 27.0. The DriverKit 25.5
  SDK in Xcode 26.6 ships VideoDriverKit with the same headers and exported
  symbols as the DriverKit 27.0 SDK, and generated video extensions build
  against it; the DriverKit 24.4 SDK has no VideoDriverKit.
- **Breaking:** `VideoRuntimeError` gains `invalidObjectTarget`, `invalidName`,
  `invalidPropertySelectors`, and `invalidSampleRates`.
- **Breaking:** `AudioRuntimeError` gains `invalidObjectTarget`, `invalidName`,
  `invalidPropertySelectors`, and `invalidSampleRates`.
- Stopping the audio runtime removes the device's controls and custom
  properties before the device leaves the driver.
- **Breaking:** transmit events carry a 72-byte packet metadata block before
  the frame, `EthernetTransmitRequest` gains `metadata`, `EthernetEvent` gains
  `interfaceCommand`, and `EthernetRuntimeError` gains `invalidBatch` and
  `invalidPacketMetadata`. `packetBufferSize` may be at most 65,420 bytes so a
  frame and its metadata fit in one event.
- **Breaking:** `EthernetEvent` gains the `hardwareAssistsChanged`, `polling`,
  `packetTap`, and `nicProxyConfiguration` cases, and `EthernetRuntimeError`
  gains `invalidLinkStatus`, `invalidLinkQuality`, `invalidBandwidths`, and
  `invalidPollingParameters`, so exhaustive switches over them must handle the
  new cases.
- The networking runtime registers its queues through
  `registerEthernetInterface(queues, numQueues, txPool, rxPool)`, which reads
  the address from `getHardwareAddress`, and checks each packet pool's packet
  and buffer counts after creating it.
- `SwifterKitRuntimeServiceWatches.cpp` and the USB protocol header use the
  shared `kSwifterKitMaximumEventPayloadLength` instead of their own copies of
  the event payload limit.
- **Breaking:** `USBEvent` gains the `deviceRequest` and `bundledIO` cases, and
  `USBRuntimeError` gains `invalidBundleRing`, `invalidBundledTransfer`, and
  `invalidEndpointPolicy`, so exhaustive switches over them must handle the
  new cases.
- **Breaking:** every generated service overrides `IOService::SetPowerState`
  and, while a host is connected, delivers each power change as a
  `ServicePowerStateRequest` from `DriverEvent.servicePowerState()`. DriverKit
  changes power only after the change is acknowledged, so handle the event and
  call `completePowerState(requestID:)` once the device is safe. A driver that
  ignores it delays each sleep and wake by ten seconds, after which the
  extension acknowledges the change itself; it also does so when the host
  disconnects, when the service stops, and at once when no host is connected.
  Completing a request the extension already acknowledged fails with
  `kIOReturnNotFound`, which ends `runEvents()` if the handler rethrows it.
- **Breaking:** event delivery is push-based. The extension notifies the host
  through an asynchronous external method when events are queued, and the host
  drains the queue until it is empty. `DriverHost.runEvents()` replaces
  `runEvents(idlePollNanoseconds:)`, `runEvents(idlePollInterval:)`, and
  `processNextEvent()`, which are removed. `DriverRuntimeConnection.events()`
  returns the events as a `DriverEventSequence`, and
  `DriverRuntimeConnection.nextEvent()` is no longer public.
- **Breaking:** `DriverConnection` requires `notifications(selector:)`, which
  registers an asynchronous external method and returns its completions as an
  `AsyncStream`. `DriverSession.notifications(selector:)` forwards to it.
- When the registered host closes its connection or exits, the extension empties
  its event queues and answers the requests that host can no longer complete:
  block-storage requests complete with `kIOReturnAborted`, SCSI parallel tasks
  complete with a delivery failure, and Ethernet transmits return to their pool.

- **Breaking:** every generated extension now rejects a runtime user-client
  connection unless the host process has the
  `com.apple.developer.driverkit.userclient-access` entitlement listing the
  extension's bundle identifier. Before this, only audio extensions checked it.
  Video extensions, which carry `allow-any-userclient-access`, accepted any
  process. Add the entitlement to every host application.
- **Breaking:** `pciRead` and `pciWrite` take `options: PCIAccessOptions`
  instead of a raw `UInt32`, and reject unknown option bits and any option for
  configuration space. `PCIRuntimeError` gains `invalidAccessOptions`,
  `invalidOptions`, and `emptyPropertyUpdate`.
- **Breaking:** PCI aperture accesses past the end of a BAR, or to a memory
  index that is not BAR0 through BAR5, such as the expansion ROM, now fail with
  `kIOReturnBadArgument` before reaching DriverKit.

### Fixed

- `scsiCreateTarget` called `UserCreateTargetForID` on the user client's
  queue. DriverKit starts the new target inside that call and waits for its
  INQUIRY, which Swift can only poll and complete through the same, blocked,
  queue, so the create stalled until INQUIRY timed out. The extension now runs
  the create on its own queue, and `scsiCreateTarget` returns once the
  properties are validated and the create is queued. The create's `IOReturn`,
  which the queued create had discarded so a failure never reached Swift, now
  arrives as a required `SCSIControllerEvent.targetCreated` event with the
  target identifier and status.
- The timer and watch limits, `SwifterKitServiceWatchKind`, the IOReporting
  limits, `SwifterKitReporterKind`, `SwifterKitReporterOperation`,
  `SwifterKitPropertyTag`, and the registry-property depth and name limits were
  written by hand in both the Swift sources and the native Dispatch, Reporting,
  and Service protocol headers. They are now declared once in the Swift runtime
  schema and emitted into the generated `SwifterKitRuntimeSchema.h`, which
  `RuntimeSchemaTests` checks for drift and for native redeclarations. The SCSI
  management kinds and property limits, the block-storage request kinds, the
  serial event and USB serial packet kinds, and the MIDI event, target, key, and
  value kinds with the MIDI driver class, listed-object, name, and property
  limits, which the SCSI, BlockStorage, Serial, USBSerial, and MIDI runtime
  sources and their Swift decoders each spelled out, come from the same schema.
- The queued `UserCreateTargetForID` discarded the result of enqueueing its
  required `SCSIControllerEvent.targetCreated` event, so a registered host that
  had let the required queue fill lost the event. The create's queue now
  retries with a backoff of up to 64 ms while a host is registered. When that
  host detaches, the extension empties its queues and stops retrying, and the
  next host finds the target through `scsiTargetPresent`.
- The video runtime attached and detached streams, set safety offsets, and set
  clock latencies directly. `IOUserVideoDriver.iig` allows changes that affect
  IO or the device's structure only in `PerformDeviceConfigurationChange`.
  These now go through `RequestDeviceConfigurationChange`, so the calls return
  once the change is requested. VideoDriverKit has no zero-timestamp period
  setter, so there is no such change to move.
- The audio runtime attached and detached streams, set safety offsets, and set
  clock latencies and the zero-timestamp period directly. `IOUserAudioDriver.iig`
  allows changes that affect IO or the device's structure only in
  `PerformDeviceConfigurationChange`, and `IOUserAudioClockDevice.iig` says the
  zero-timestamp period "should only be done during
  PerformDeviceConfigurationChange()". These now go through
  `RequestDeviceConfigurationChange`, so the calls return once the change is
  requested.
- A failed video buffer-capacity change left the buffers set so far on the new
  descriptors while the runtime kept the old ones; the change now restores
  every buffer it touched. A failed buffer detach no longer leaves the stream
  with no buffers: the runtime builds both buffer lists before removing any and
  re-adds the previous list when the re-add fails.
- A failed video queue-length change left the stream with no queues; the
  runtime now recreates the queues at their previous length.
- The video runtime sets each control's owning device with
  `_SetOwningDeviceID` before `AddControl`. The VideoDriverKit headers do not
  say that `AddControl` sets it, so `videoControlInfo` could have read an unset
  owner.
- The SCSI controller runtime's `UserProcessBundledParallelTasks` returned
  without answering its completion. It now hands every slot back through
  `BundledParallelTaskCompletion`; the runtime still declines the shared
  buffers, so the framework does not call it.
- The MIDI runtime wrote its device, entity, source, and destination pointers
  in `StartMIDI` and `StopMIDI` on the service queue while `midiSend`,
  `StartIO`, and `StopIO` read them from other queues without
  synchronization. A `midiLock` now guards them; readers retain the object
  they use, and destination I/O blocks never take the lock. A `StartMIDI` that
  fails after adding the device to the driver now removes it again.

- A clock device's `HandleChangeSampleRate`, in both AudioDriverKit and
  VideoDriverKit, reported success after queuing the Swift request, and without
  a host after only requesting a configuration change, although the headers
  require the rate to be updated on success. The clock now sets the requested
  rate before it reports success and uses the framework default without a host.
  Accepting the request reports `clockDeviceSampleRateChanged`; rejecting it,
  a timeout, or a detach restores the previous rate through a device
  configuration change unless the rate changed again.

- `StartVideo` stored the video device without `videoLock`, which
  `VideoCommand` holds while it reads the device; the device is now published
  under the lock.
- Stopping the video runtime removed the device from the driver while its
  controls and custom properties were still attached; they are now removed
  first.
- `coverage/driverkit.json` listed `IOUserVideoDriver::AddCustomProperty` as
  generated although the runtime never called it; `videoSetCustomPropertyOwner`
  now calls it and its removal counterpart.
- An audio box's `HandleChangeAcquireBox` returned success before
  `SetIsAcquired` ran, although `IOUserAudioBox` requires the acquired state
  to be updated when the callback reports success. The box now takes the
  requested state before it queues the request, rejecting the request with
  `audioCompleteRequest` restores the previous state, and a request for the
  state the box already has succeeds without an event.
- `HIDSubmitInputReport` called into the service without checking that the
  user client still had one, so a report sent after the service detached
  dereferenced a null pointer. It now returns `kIOReturnBadArgument`, as
  `HIDGetRuntimeStatistics` does.
- A transmit Swift completed with a nonzero status was freed back to the pool
  instead of returning to the stack. It now carries the status through
  `setCompletionStatus` and returns through the transmit completion queue, and
  every packet returns to the pool it came from (`getPacketBufferPool`).
- `xcodebuild analyze` no longer reports leaks of the timer source and action
  in `SwifterKitRuntimeTimers.cpp`. `SwifterKitReleaseSource` consumes the
  references it is given, and its parameters now say so with `os_consumed`, so
  the analyzer follows the ownership that `TimerCommand` hands it on failure.
- `EthernetEvent.wakeOnMagicPacket` was decoded but never sent. The extension
  now delivers it when the stack changes `kIOUserNetworkHWAssistWOMP` through
  `setHardwareAssists(assists, mask)`, and advertises that assist whenever
  `supportsWakeOnMagicPacket` is set.
- The extension accepted an MTU of 0 from the networking stack. It now rejects
  an MTU below `EthernetDeviceConfiguration.minimumTransferUnit` (68 by
  default).
- `pciReset(type:options:)` with `.terminate` now documents that the call
  returns the reset's result: DriverKit starts termination without waiting for
  it. The extension holds the PCI device across the reset, since termination
  can stop the service concurrently. Before this, the documentation said the
  response might never arrive.
- A SCSI parallel task that the extension cannot take, because every task slot
  is in use or the task is malformed, now completes with a delivery failure
  and reports `Request_In_Process`. Before this, the extension returned an
  error without setting the task's response or completing it.
- A block-storage request that the extension cannot take, because the request
  table is full or its arguments are invalid, now completes through `Complete`
  or `CompleteIO` with the failure status. Before this, the extension returned
  the error without completing the request. A request whose identifier matches
  an outstanding one is still refused with `kIOReturnExclusiveAccess` and no
  completion, because completing it would answer the outstanding request.
- An Ethernet extension now acknowledges each power change through the
  superclass even when the Swift notification cannot be queued. Before this, a
  full required-event queue skipped the superclass and stalled the transition.
- Block-storage unmap requests, host `setReport` reports, and received MIDI
  words are now checked against the event-queue payload limit, 65,508 bytes,
  before they are queued. Before this, the checks allowed payloads up to 24
  bytes larger, which the event queue then rejected.
- A serial extension whose start fails after its queues are connected now
  disconnects them before the service stops.
- A generated `IOUserHIDDevice` or `IOUserUSBHostHIDDevice` that accepts
  output or feature reports from the host now calls `CompleteReport` exactly
  once, with success and the report length, as soon as `setReport` queues the
  report to Swift. Before this, `setReport` returned success without ever
  completing the request. An error return still leaves completion to the
  caller.
- Required events (block-storage requests, SCSI tasks, Ethernet transmits and
  controls, and audio and video changes that wait for Swift) now have a
  512-event queue separate from the 64-event lossy queue. Lossy events cannot
  use required capacity, and polling returns required events first.
- When the required queue rejects an event, block-storage requests complete
  with the enqueue error and SCSI parallel tasks complete with a delivery
  failure. Before this, block-storage requests and SCSI tasks were returned as
  errors without a completion, and task-management responses were left unset.
  The extension counts dropped lossy events.
- USB pipe completions that the full required queue rejected are also retried
  when a poll takes a required event, so a host that only receives events gets
  them. Before this, only a USB command from Swift retried them.
- When a different connection registers for events, the extension answers the
  requests the previous connection took (block storage, SCSI, Ethernet
  transmits) as it does when a host disconnects. Before this, they stayed
  outstanding until the service stopped.

### Added

- SCSI controller drivers create, destroy, and query targets with
  `DriverContext.scsiCreateTarget(_:properties:)`, `scsiDestroyTarget(_:)`, and
  `scsiTargetPresent(_:)`; set and remove HBA and target registry properties
  keyed by `SCSIProtocolPropertyKey`; and report media-parameter changes with
  `scsiMediaParametersChanged()`, on opcodes 0x0B20-0x0B27.
- `SCSIControllerConfiguration.constraints` reports `SCSIControllerConstraints`
  through `UserReportHBAConstraints` during `UserInitializeController`, always
  with every key the header requires.
- `SCSIControllerConfiguration.providesTaskDataBuffers` fetches each task's
  buffer with `UserGetDataBuffer` inside `UserProcessParallelTask`, and
  `scsiReadTaskData(requestID:offset:count:)` and
  `scsiWriteTaskData(requestID:offset:bytes:)` access it until the task
  completes (opcodes 0x0B28-0x0B29). A task whose buffer cannot be fetched
  completes with a delivery failure.
- MIDIDriverKit object, property, and membership support on opcodes
  0x0810-0x0819: `midiObjectInfo`, `midiSetObjectName`, `midiPropertyType`,
  `midiCopyProperty`, `midiSetProperty`, `midiProperties`,
  `midiSetProperties`, `midiDeviceState`, `midiEntityMembers`, and
  `midiSetMemberAttachment` on `DriverContext`, with `MIDIObjectTarget`,
  `MIDIClassID`, `MIDIObjectInfo`, `MIDIProperty`, `MIDIPropertyKey`,
  `MIDIPropertyType`, `MIDIPropertyValue`, `MIDIDeviceState`,
  `MIDIEntityMembers`, and `MIDIMember`. `MIDIRuntimeError` gains
  `invalidObjectTarget`, `invalidName`, `invalidPropertyKey`,
  `invalidPropertyValue`, and `propertyValueTooLarge`. Every MIDIDriverKit,
  BlockStorageDeviceDriverKit, and SerialDriverKit member is now covered or
  excluded with a reason.

- VideoDriverKit device, stream, buffer, control, and custom-property support
  on opcodes 0x0C20-0x0C2D: `videoDeviceState`, `videoSetDeviceProperty`,
  `videoSetPreferredChannelLayout`, `videoStreamState`,
  `videoSetStreamProperty`, `videoBufferInfo`, `videoSetBufferProperty`,
  `videoControlInfo`, `videoSetControlProperty`, `videoRemoveSelectorItems`,
  `videoCustomPropertyInfo`, `videoSetMemberAttachment`,
  `videoEnqueueOutputBuffer`, and `videoStreamMemoryObjectID` on
  `DriverContext`, with `VideoDeviceState`, `VideoStreamState`,
  `VideoBufferInfo`, `VideoControlInfo`, `VideoCustomPropertyInfo`, and their
  property enums. Buffer capacities, queue sizes, buffer IDs, and buffer-list
  membership change inside `PerformDeviceConfigurationChange`, as
  `IOUserVideoBuffer` requires. `VideoBufferQueueNotification` gains
  `streamBufferQueueChange` and `VideoObjectEvent` gains
  `deviceStreamFormatChanged`. Every VideoDriverKit member is now covered or
  excluded with a reason.

- VideoDriverKit object, box, and clock-device support on opcodes
  0x0C10-0x0C1F and the `videoObject` event type 0x0C01, mirroring audio:
  `VideoDeviceConfiguration` gains `boxes` and `clockDevices`;
  `videoObjectInfo`, `videoSetObjectName`, `videoElementName`,
  `videoSetElementName`, `videoPropertiesChanged`, `videoBoxState`,
  `videoSetBoxProperty`, `videoSetBoxOwnership`, `videoClockDeviceState`,
  `videoSetClockDeviceProperty`, `videoSetClockSampleRates`,
  `videoUpdateClockTimestamp`, `videoRequestClockSampleRate`, and
  `videoCompleteRequest` on `DriverContext`; `videoNotifyBufferQueue` for
  `BufferQueueChange` and `OutputBufferNotification`;
  `videoSetCustomPropertyOwner` to move custom properties between the device
  and the driver; and `DriverEvent.videoObject()` decoding `VideoObjectEvent`,
  whose box-acquisition and clock-rate requests must be answered within ten
  seconds.
- AudioDriverKit device, stream, control, and custom-property state on opcodes
  0x0A20-0x0A29: `audioDeviceState` and `audioSetDeviceProperty` for
  default-device flags, safety offsets, preferred stereo channels, stream-format
  restoration, and client I/O times; `audioSetPreferredChannelLayout`;
  `audioStreamState` and `audioSetStreamProperty` for direction, terminal type,
  starting channel, latency, activity, formats, and ring-buffer size;
  `audioControlInfo`, `audioSetControlProperty`, and `audioRemoveSelectorItems`
  for control scope, element, slider ranges, panning channels, and selector
  items; `audioCustomPropertyInfo`; and `audioSetMemberAttachment`, which
  removes and re-adds streams, controls, and custom properties and moves a
  custom property to the driver.
- Audio drivers declare up to four `IOUserAudioBox` objects and four
  stream-less `IOUserAudioClockDevice` objects through
  `AudioDeviceConfiguration.boxes` and `clockDevices`. `AudioObjectTarget`
  addresses the driver, device, boxes, clock devices, or any object ID, and new
  `DriverContext` calls on opcodes 0x0A10-0x0A1D read object identity, set
  object and element names, post `PropertiesChanged`, read and set box and
  clock-device state, change box membership, sample rates, and zero
  timestamps, and answer requests. `AudioObjectEvent` (event type 0x0A01)
  reports `StartDevice`, `StopDevice`, and clock-device I/O and rate changes,
  and delivers box-acquisition and clock sample-rate requests that Swift
  answers with `audioCompleteRequest` within ten seconds.
- NetworkingDriverKit packet metadata: `EthernetTransmitMetadata` on every
  transmit, `EthernetReceiveMetadata` and `EthernetReceivedFrame` for
  `ethernetReceive(frames:)` batches (opcode 0x0920), and
  `EthernetTransmitCompletion` for `completeEthernetTransmits(_:)` (0x0921).
  VLAN tags need an extension built with the DriverKit 25.5 SDK or newer.
- Queue control: `setEthernetQueueEnabled(_:enabled:)` (0x0922),
  `purgeEthernetTransmitQueue()` (0x0923), `serviceEthernetTransmitQueue()`
  (0x0924), and `EthernetDeviceConfiguration.transmitServiceClass` with
  `EthernetServiceClass`.
- `processInterfaceCommand` forwards private interface ioctls as
  `EthernetEvent.interfaceCommand`, answered by
  `completeEthernetInterfaceCommand(requestID:status:)` (0x0925) within two
  seconds.
- Ethernet capabilities: `EthernetDeviceConfiguration` takes typed hardware
  assists (`EthernetHardwareAssists`: checksum, TSO with `EthernetTSOOptions`,
  LRO, VLAN, timestamps, wake on magic packet, NIC proxy), feature flags, a
  minimum MTU, transmit headroom, tailroom, and data offset, the interface
  subfamily, BSD name prefix and unit, a BPF tap, packet pool options
  (`EthernetPacketPoolOptions`), a separate receive pool, and hybrid polling
  through `IOUserNetworkPacketPoller` (`EthernetPacketPolling`).
- `DriverContext` reports Ethernet link status flags, link quality, data
  bandwidths, hardware counters, and NIC proxy limits, and enables or
  reconfigures the packet poller (opcodes `0x0910`-`0x0915`).
- USB serial ports: `USBSerialPortConfiguration` generates an `IOUserUSBSerial`
  service on an `IOUSBHostInterface` (`.serial` and `.usb`). USBSerialDriverKit
  owns the bulk and interrupt data path; Swift receives the usual
  `SerialEvent` hardware requests, programs the device with USB control
  transfers, reports modem state with `serialSetModemStatus(_:)`, and can
  observe received and interrupt packets as `USBSerialEvent` from
  `DriverEvent.usbSerial()`. An optional base name and suffix replace
  USBSerialDriverKit's `usbserial-` terminal name. `serialEnqueueReceive(_:)`
  and `serialDequeueTransmit(maximumLength:)` report `kIOReturnUnsupported` on
  these ports.
- Asynchronous control requests: `usbEnqueueControlTransfer(_:data:timeout:)`
  uses `AsyncDeviceRequest` on either provider and returns a request
  identifier; the result arrives as `USBEvent.deviceRequest` and is aborted by
  `usbAbortDeviceRequests()`.
- Bundled bulk I/O: `usbCreateBundleRing(endpoint:entryCount:bufferLength:)`
  gives a bulk pipe a runtime-owned descriptor ring, and
  `usbEnqueueBundledReads` and `usbEnqueueBundledWrites` submit up to 16
  transfers with `AsyncIOBundled`. Each ring entry completes as
  `USBEvent.bundledIO`; `usbReleaseBundleRing(endpoint:)` frees an idle ring.
- `usbAdjustPipe(endpoint:descriptors:)` changes a periodic endpoint's reserved
  bandwidth with `AdjustPipe`. `USBPipeDescriptors` and
  `USBSuperSpeedEndpointCompanion` gain public initializers.
- HID event services: `HIDEventServiceConfiguration` generates an
  `IOUserHIDEventService` or `IOUserHIDEventDriver` that matches an
  `IOHIDInterface` (DriverKit 21.0 or later). Input reports and updated element
  values arrive as `DriverEvent.hidInputReport()` and `hidElementValues()`, LED
  and property changes as `hidLEDState()` and `hidProperties()`. Typed
  `dispatchHID*` calls cover keyboard, relative and absolute pointer, scroll,
  stylus, touch, digitizer-collection, and standard and extended game-controller
  events; `HIDEventDriverCategories` choose what Apple's element parser handles.
- HID elements: `hidElements()` reads the interface's element tree, and
  `hidElementValue`, `setHIDElementValue`, `setHIDElementData`,
  `commitHIDElement`, `commitHIDElements`, and `hidElementConforms` use it;
  `hidInterfaceReport`, `setHIDInterfaceReport`, and `processHIDInterfaceReport`
  reach the interface's reports.
- USB HID devices: `USBHIDDeviceConfiguration` generates an
  `IOUserUSBHostHIDDevice` on a USB HID interface with optional report
  descriptor and device-property overrides, host report routing to Swift, and
  `hidDeviceReport`, `setHIDDeviceProtocol`, `setHIDDeviceIdle`,
  `setHIDDeviceIdlePolicy`, and `resetHIDDevice`.
- HID devices answer host get-report requests from Swift:
  `answeredReportTypes` routes them as `DriverEvent.hidGetReportRequest()`, and
  `completeHIDGetReport(_:bytes:status:)` completes each once. Pending requests
  complete with `kIOReturnAborted` when the host detaches or the service stops.

- Extension timers, with no capability flag, on runtime opcodes
  `0x0E00`-`0x0E01`: `startTimer(afterNanoseconds:repeatingEveryNanoseconds:leewayNanoseconds:)`
  creates and arms an `IOTimerDispatchSource`, one-shot or repeating with a
  leeway, and `cancelTimer(_:)` cancels it. Each firing is a lossy event that
  `DriverEvent.timerFiring()` decodes as a `ServiceTimerFiring` with the timer
  ID, firing count, and `CLOCK_UPTIME_RAW` timestamp. At most 16 timers run;
  intervals are at least 1 ms and durations at most one day.
- Service and system-state watches on opcodes `0x0E10`-`0x0E12`:
  `watchServices(matching:)` observes services matching a `DriverServiceMatch`
  through `IOServiceNotificationDispatchSource` and reports each match and
  termination as a `ServiceMatchNotification` with its registry entry ID and
  name. `watchSystemState(items:)` observes up to eight system state items
  through `IOServiceStateNotificationDispatchSource` and reports each change as
  a `SystemStateNotification` with the item's dictionary. `cancelWatch(_:)`
  ends either kind. At most eight watches run, and events carry sequence
  numbers so dropped lossy events are detectable. Timers and watches end when
  the host disconnects or the service stops.
- IOReporting: `DriverConfiguration.reporting` declares simple, state, and
  histogram reporters with channels, categories, units, and legend groups,
  validated against `ReportingLimits` at generation. The extension creates them
  when the service starts, publishes their legend with `IOService::SetLegend`,
  and serves `ConfigureReport` and `UpdateReport` for the system's IOReport
  clients. On opcodes `0x0E20`-`0x0E21`, Swift updates values with
  `setReportValue`, `incrementReportValue`, `setReportState`,
  `adjustReportState`, `tallyReportValue`, and `overrideHistogramBucket`, and
  reads them with `reportValue` and `reportStateStatistics`.
- IOService operations for every generated service, with no capability flag,
  on runtime opcodes `0x0D00`-`0x0D33`: `setServiceProperties(_:)`,
  `serviceProperties()`, `removeServiceProperty(named:)`,
  `searchServiceProperty(named:options:plane:)`, `providerProperties(keys:)`,
  `serviceName()`, `registryEntryID()`, `changePowerState(_:)`,
  `setPowerOverride(_:)`, `createPMAssertion(_:synced:)`,
  `releasePMAssertion(_:)`, `adjustBusy(by:)`, `busyState()`,
  `requireMaxBusStall(_:)`, `terminateService()`, `systemStateItem(named:)`,
  `createSystemStateItem(named:value:)`, `setSystemStateItem(named:value:)`,
  and `sendCoreAnalyticsEvent(named:payload:)`. Registry values use
  `DriverProperty`, are bounded to one runtime message, and are validated by
  Swift and the extension; `.real` is rejected and numbers read back as
  `.unsignedInteger`. `ServiceRuntimeError` reports invalid requests.
- IOService and IOUserServer have no remaining coverage gaps except the
  IOReporting members `ConfigureReport`, `UpdateReport`, and `SetLegend`.
- PCI device control: `pciReset(type:options:)`, `pciSaveDeviceState(options:)`,
  `pciRestoreDeviceState()`, `pciHasPowerManagement(support:)`,
  `pciEnablePowerManagement(state:)`, `pciLinkSpeed()`,
  `pciSetLinkSpeed(_:retrain:)`, `pciSetASPMState(_:)`, and
  `pciSetProperties(_:)`, with typed options and states, runtime opcodes
  `0x0410`-`0x0418`, and native validation of every value.
- `PCIDeviceConfiguration.interrupts` takes a `PCIInterruptConfiguration` that
  allocates MSI, MSI-X, or legacy vectors through
  `IOPCIDevice::ConfigureInterrupts` before the extension creates its interrupt
  sources. The generator and the extension reject vector counts above the
  type's limit and source indices at or above the required vector count.
  `PCIInterruptType(interruptTypeFlags:)` classifies `interruptType(index:)`.
- The extension bounds every PCI aperture access by the BAR size `GetBARInfo`
  reports. PCIDriverKit coverage in `coverage/driverkit.json` has no remaining
  gaps.
- USB drivers can match a whole device: set `providerClass` to
  `USBDeviceConfiguration.deviceProviderClass` (`IOUSBHostDevice`) and leave the
  configuration and interface matching fields unset. A device driver selects a
  configuration, lists interfaces, resets the device, and sends control
  transfers on the default endpoint.
- USB device and interface queries: device, configuration, string, BOS, and
  arbitrary descriptors parsed into typed values; speed, address, port status,
  frame and microframe numbers; interface idle policy; and asynchronous abort
  of default-endpoint requests. A descriptor larger than one runtime message
  throws `USBDescriptorError.tooLarge(length:)` instead of being truncated.
- Asynchronous USB pipe I/O: `usbEnqueueRead`, `usbEnqueueWrite`,
  `usbEnqueueIsochronousRead`, and `usbEnqueueIsochronousWrite` return a
  request identifier, and `DriverEvent.usb()` decodes the completion with its
  `IOReturn` status, byte counts, timestamps, and data. Up to 32 transfers can
  be outstanding. Completions use the required event queue.
- USB pipe abort, idle policy, endpoint descriptors, speed, and device address.
- `coverage/driverkit.json` records every class and member function declared
  by the DriverKit 24.4, 25.5, and 27.0 SDK headers and how SwifterKit covers
  it. The `SwifterKitCoverage` tool updates, summarizes, and checks the manifest,
  and CI fails when the selected SDK declares a member the manifest omits.

### Changed

- The runtime protocol is now version 2. The handshake offers a version range,
  the extension selects the highest common version, and both sides use it for
  the rest of the connection; `DriverRuntimeConnection.protocolVersion` reports
  it. Hosts and extensions must both come from this release, because version 1
  extensions do not negotiate. `RuntimeProtocolVersion` is now `Comparable`,
  adds `version2`, `minimumSupported`, and `supported`, and no longer declares
  `version1`.
- **Breaking:** `RuntimeMessageFlags.finalFragment` is removed. The runtime
  never sent fragmented messages.
- Runtime messages larger than `RuntimeMessage.maximumSize` (64 KiB, header
  included) now throw `RuntimeProtocolError.payloadTooLarge` before the IOKit
  call instead of failing in the extension.
- Runtime magic, versions, limits, message kinds, flags, opcodes, event types,
  and capability bits are declared once in Swift. The native extension uses a
  header rendered from that schema, and a test fails when the checked-in header
  drifts.
- The package manifest now requires Swift 6.1 (Xcode 16.3) instead of 6.2, and
  CI runs the test suite on Swift 6.1 rather than only building it.
- The package builds on Linux. The IOKit transport, `DriverClient()`, and
  `DriverHost(driver:)` are available only where IOKit exists; elsewhere pass a
  `DriverClient(transport:)` explicitly.

### Fixed

- Registry numbers 0 and 1 no longer decode as Booleans. Only CoreFoundation
  Boolean values become `DriverProperty.boolean`, and registry integers decode
  as `DriverProperty.integer`.

## 0.1.3

### Fixed

- Generated DriverKit extensions now build IIG sources with the GNU C++20
  extensions required by current DriverKit SDK headers.
- Generated extensions now link only the DriverKit family frameworks selected
  by their configuration, avoiding launch-time dependencies on unused families.

### Added

- Added a typed HID host-report allowlist. Generated runtimes preserve output
  and feature report delivery by default and can reject feature reports
  synchronously with `acceptedHostReportTypes: .output`.

## 0.1.2

### Fixed

- Discover generated runtime services through their `IOUserClass` registry
  property instead of treating the DriverKit user class as a kernel service class.

## 0.1.1

### Added

- Added typed extension-side HID input-report delivery statistics for
  diagnostics and self-tests.
- Generated HID devices now publish a usage-pair array matching their primary
  usage metadata.

## 0.1.0

### Changed

- Set the package deployment target to macOS 10.15, matching the first
  DriverKit release and the generated extension default of DriverKit 19.0.
  Swift 6.1 compatibility is checked only in CI; local development uses the
  version in `.swift-version`.
- Added strict DriverKit deployment-version validation and capability floors
  for SCSI, block storage, networking, audio, MIDI, and video extension generation.

### Added

- Swift 6 APIs for authoring DriverKit behavior, configuration, commands,
  events, and request completions.
- A generated C++20/IIG DriverKit extension runtime owned by SwifterKit.
- Typed capability layers for HID, USB, PCI, serial, block storage, MIDI,
  networking, audio, SCSI, video, interrupts, and managed native memory.
- Raw DriverKit user-client access through `DriverClient`, `DriverSession`, and
  `DriverCommand`.
- Swift-DocC documentation, unsigned dual-architecture DriverKit validation,
  signed-build tooling, and source-release automation.
