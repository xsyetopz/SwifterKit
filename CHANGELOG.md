# Changelog

SwifterKit records user-visible changes in this file.

## [Unreleased]

### Changed

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
- Every generated service overrides `IOService::SetPowerState` and delivers the
  change as a `ServicePowerStateRequest` from `DriverEvent.servicePowerState()`.
  Swift answers with `completePowerState(requestID:)`. The extension
  acknowledges the change itself after ten seconds, when the host disconnects,
  when the service stops, or at once when no host is connected.
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
