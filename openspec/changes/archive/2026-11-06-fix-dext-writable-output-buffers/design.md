# Design

## Context

See `proposal.md` (Why). Facts read from source at `26daf6f`:

- `14c06f4` changed `SwifterKitRuntimeUSBSupport.h:78` and `SwifterKitRuntimeUSBBundled.cpp:92` to `kIOMemoryDirectionInOut`. Its test, `outputBuffersAreWritableThroughTheDriverMapping`, checks only the source text.
- C1 sites still allocate output-only before a runtime write:
  - `SwifterKitRuntimeHIDElements.cpp:300`, written at `:275`.
  - `SwifterKitRuntimeSCSIPeripheral.cpp:177`, written at `:56`.
  - `SwifterKitRuntimeMemory.cpp:550` (direction comes from the author), written at `:679`.
  - `SwifterKitRuntimeFastPath.cpp:281` (direction comes from the table), zeroed at `:293`.
- C2: 18 `CreateMapping` calls and 4 `GetLength() <` checks.
- C3: `(void)...->SetLength` at `HIDElements.cpp:267`, `HIDRequests.cpp:251`, `HIDShared.h:174`, and `USBSupport.h:84`.
- C4: `Map()` at `HIDElements.cpp:270` and `:315`, on the same buffer.
- Unknown, and not assumed either way: whether `kIOMemoryDirectionOut` buffers can be written by the dext on macOS 27, and whether the buffers that already use `InOut` (audio, video, iso, data queues) have ever run on macOS 27.0.1.

## Goals / Non-Goals

**Goals:**

- Reproduce the crash, then measure the merged fix, on hardware with SIP enabled.
- Find and fix every defect in classes C1 to C6 across the native runtime. Any new class found during the hunt is added to `findings.md` and handled the same way.

**Non-Goals:**

- Disabling SIP, using `systemextensionsctl developer`, or any other step that weakens system security. No task requires it, and no document will suggest it.
- New public Swift API.
- Keeping the probe code in `main`.

## Decisions

### D1. Device under test: Razer Wolverine Tournament Edition, team-signed

The connected `1532:0A15` pad is Xbox One-compatible. If it speaks GIP, it takes the same power-on packet that crashed the Elite. That is a hypothesis, and task 1.2 checks it from the device's endpoint descriptors before any run. The probe dext is signed with the Apple Development certificate and a DriverKit profile that grants `transport.usb` for vendor `0x1532`. It is installed through a host app with SIP on, as `docs/publishing.md` describes. Alternative rejected: an unsigned dext with SIP disabled, because it weakens the user's system.

### D2. Reproduce, then run the probe matrix

1. Run `783840e` (before the fix) and send the GIP power-on packet. Expected: the crash from #55. Record the outcome either way.
2. Run `26daf6f` the same way. Record the outcome.
3. Run the probe build. Each strategy gets its own dext launch, and `os_log` records each result before the 1-byte write:

| ID | Hypothesis | Strategy | Confirmed when |
| --- | --- | --- | --- |
| H1 | An `Out` buffer's dext mapping cannot be written | `CreateIOBuffer(Out)`, then `CreateMapping`, then write | `Out` faults and `InOut` writes |
| H2 | The second mapping is bad, not the direction | Same `Out` buffer, written through `GetAddressRange` | That write succeeds where `CreateMapping` faults |
| H3 | Controller memory differs from `IOBufferMemoryDescriptor::Create` | Same write on `IOBufferMemoryDescriptor::Create(Out)` | Only one allocator faults |
| H4 | `SetLength` before mapping shrinks the mapping | Map before `SetLength`, then compare `GetLength` and the region | The fault follows `SetLength` |

If step 1 does not reproduce the crash, that result is recorded as a finding. Steps 2 and 3 still run, because they measure the merged behavior and the other classes. The fix for each site follows the hypothesis the data confirms. A hypothesis the data does not confirm drives no code change.

### D3. Defect hunt, class by class

For each class C1 to C6, list every site in `findings.md`. Then write a failing contract test, fix the site, and re-run the test. Fixes:

- C1: the direction H1 to H4 points to.
- C2/C6: compare `GetLength()` with offset plus length before access, and return `kIOReturnNoMemory` or `kIOReturnBadArgument`.
- C3: propagate the error.
- C4: replace `Map()` with one `CreateMapping`, held for the whole request and released once.
- C5: trace each map's owner and release point.

`MemoryAllocate` keeps the author's direction in `SwifterKitMemoryEntry::direction` for composition and DMA checks. Task 3.5 reads `PrepareDMA` first, to see whether it depends on the descriptor's own direction.

### D4. Contract tests per class

A new test file in `Tests/SwifterKitTests/DriverKit/Authoring/Generation/` scans the generated runtime sources once per class. It extends `outputBuffersAreWritableThroughTheDriverMapping` and does not duplicate it. These are source-text guards against regressions. Runtime correctness rests on the D2 hardware results.

## Risks / Trade-offs

- [The Razer pad may not have an interrupt OUT endpoint, or may not use GIP] → Task 1.2 checks the descriptors first. If it fails, the result is recorded and the user is asked for another device before any probe run.
- [The provisioning profile may not grant vendor `0x1532`] → Task 1.3 checks the profile's entitlements before any build.
- [A probe dext takes over the pad while it runs] → The personality matches only `1532:0A15`. The dext is removed through the host app after each run.
- [`InOut` lets the device write memory meant as output-only] → Harmless for runtime-owned OUT buffers that are freed on completion.

## Migration Plan

No API or payload migration. Downstream projects rebuild against the new SwifterKit. Rollback means reverting the commit. The probe branch is deleted after its results are recorded.
