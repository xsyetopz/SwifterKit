# Proposal

## Why

SwifterKit 0.3.0 USB dexts (DriverKit extensions) crash on macOS 27.0.1 on their first interrupt OUT write. The fault is in `memcpy` in `SwifterKitCreateUSBBuffer`, on a page-aligned address that `vmRegionInfo` reports as "not in any region" (xsyetopz/OpenJoystickDriver#55). PR #2 was merged as `14c06f4` (merge `26daf6f`). It allocates the USB output buffers `kIOMemoryDirectionInOut`, but nobody has reproduced the crash, tested the fix on hardware, or found the cause.

The work follows FAFA ("Fuck Around and Find Out"): hunt for more defects instead of assuming. Every guess in the PR and in this plan is treated as a hypothesis that needs a measurement or a source citation. The hunt covers the whole native runtime, not only the line that crashed. Every defect it finds gets a failing test and a fix in this change.

## What Changes

- Reproduce the crash on hardware with the runtime from before the fix (`783840e`). Then measure `26daf6f` on the same device. The device is a Razer Wolverine Tournament Edition (`1532:0A15`), driven by a team-signed probe dext with SIP on.
- Run a probe matrix that tests four hypotheses about the cause (design.md D2), and record what each run actually shows.
- Hunt for defects in every buffer-mapping site in `Sources/SwifterKit/Resources/DriverKitExtension/Sources/`, by class:
  - C1: runtime writes through a mapping of a buffer allocated `kIOMemoryDirectionOut`. Five sites remain after `14c06f4`: HID SetReport, SCSI outbound data, author `MemoryWrite`, and the fast-path rings, plus a recheck of the USB helper.
  - C2: `CreateMapping` with no check that the mapped length covers the bytes written. Only 4 of 18 call sites check `GetLength()`.
  - C3: `SetLength` results thrown away with `(void)`. There are 4 sites.
  - C4: `IOMemoryDescriptor::Map` in `SwifterKitRuntimeHIDElements.cpp:270` and `:315`. It maps the same buffer twice, and its lifetime differs from `CreateMapping`.
  - C5: an `IOMemoryMap` released or replaced while its address is still used. This matches the "not in any region" symptom.
  - C6: writes to a mapped address plus an offset, which need a bounds check (`SwifterKitRuntimeNetworkMetadata.h:142`, `SwifterKitRuntimeMemory.cpp:679`).
- Add generated-source contract tests that fail on each class of defect.
- No public Swift API, wire payload, or IIG declaration changes.

## Capabilities

### New Capabilities

- `runtime-buffer-writes`: the native runtime writes bytes into its own DriverKit buffers without faulting, and only within the mapped length.

### Modified Capabilities

None. `openspec/specs/` is empty.

## Impact

- Native runtime: every file in `Sources/SwifterKit/Resources/DriverKitExtension/Sources/` that calls `CreateMapping`, `Map`, or `SetLength`.
- Tests: new contract tests under `Tests/SwifterKitTests/DriverKit/Authoring/Generation/`, next to `DriverExtensionUSBContractTests.swift`.
- `CHANGELOG.md`: the Unreleased entry from `14c06f4` is extended with the measured hardware result and every further fix.
- Hardware runs need an Apple Development certificate and a DriverKit provisioning profile whose `com.apple.developer.driverkit.transport.usb` entitlement covers vendor `0x1532` (`docs/publishing.md`). They also need host access to the Razer device. SIP stays enabled.
