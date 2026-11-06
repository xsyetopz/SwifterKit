# Findings

Paths are relative to `Sources/SwifterKit/Resources/DriverKitExtension/Sources/` unless they start with a top-level directory. Lines are at `26daf6f`.

## Environment

- Branch `fix/runtime-buffer-writes` from `origin/main` `26daf6f`. DriverKit SDK 27.0.
- The working tree also carries the user's uncommitted edits to `.swift-format`, `.swift-version` (6.4.0), `.swiftlint.yml`, and `Package.swift` (tools 6.4.0). They are part of the baseline and are not modified by this change.

## Hardware preconditions

| ID | Check | Evidence | Status |
| --- | --- | --- | --- |
| E-1 | Razer `1532:0A15` speaks GIP | `ioreg`: device class/subclass/protocol `0xFF/0x47/0xD0`. Interfaces 0 to 2 are the same triple, which is the GIP interface class. | Confirmed |
| E-2 | Razer interrupt OUT endpoint | `ioreg` publishes no endpoint descriptors for unopened interfaces. Interface 0 is held only by the Steam and Chrome user clients. | Open: needs the configuration descriptor from a matched dext |
| E-3 | Profile grants `transport.usb` for vendor `0x1532` | Both `OpenJoystickDriver_XboxUSBDevice*.provisionprofile` grant only vendor `0x045E`, products `0x02D1 0x02EA 0x0B12 0x0B00 0x02E3 0x0B0A 0x02DD` | Failed |

E-3 blocks tasks 2.1, 2.2, 2.4, and 4.2. The blocker is outside this repository: Apple has to approve a `transport.usb` entitlement for `1532:0A15`, or a listed Microsoft device has to be available.

## Hypotheses

| ID | Evidence | Status |
| --- | --- | --- |
| H1 | DriverKit 27.0 `IOMemoryDescriptor.h:149-150`: "kIOMemoryDirectionIn memory described will be writable / kIOMemoryDirectionOut memory described will be readable". The SDK does not document a dext write through an `Out` buffer. | Supported by source citation. A hardware measurement is blocked by E-3. |
| H2 | `IOBufferMemoryDescriptor.h:91`: `GetAddressRange` is `LOCALONLY`, so it is only valid for buffers created in the dext's own address space. `CreateIOBuffer` buffers come from the USB host family. | Not measured, blocked by E-3 |
| H3 | Same as H2: the allocators differ in where they allocate. | Not measured, blocked by E-3 |
| H4 | `IOBufferMemoryDescriptor.h:95`: `SetLength` sets the valid length within the capacity, and mapping uses the length passed in | Not measured, blocked by E-3 |

## Defects

| ID | Class | Site | Defect | Status |
| --- | --- | --- | --- | --- |
| F-01 | C1 | `SwifterKitRuntimeHIDElements.cpp:300` | SetReport buffer allocated `Out`, written at `:275` | Fixed on the H1 SDK citation, not hardware-tested (E-3). `NativeBufferContractTests.everyAllocatedBufferIsWritable` failed on it before the fix and passes after it. The allocation uses `SwifterKitWritableDirection` (`SwifterKitRuntimeMappedMemory.h`), which turns `Out` into `InOut` |
| F-02 | C1 | `SwifterKitRuntimeSCSIPeripheral.cpp:177` | Outbound data buffer allocated `Out`, written at `:56` | Fixed on the H1 SDK citation, not hardware-tested (E-3). `NativeBufferContractTests.everyAllocatedBufferIsWritable` failed on it before the fix and passes after it. The allocation uses `SwifterKitWritableDirection` (`SwifterKitRuntimeMappedMemory.h`), which turns `Out` into `InOut` |
| F-03 | C1 | `SwifterKitRuntimeMemory.cpp:550` | Author `Out` memory backing allocated `Out`, written by `MemoryWrite` at `:679` | Fixed on the H1 SDK citation, not hardware-tested (E-3). `NativeBufferContractTests.everyAllocatedBufferIsWritable` failed on it before the fix and passes after it. Only the backing allocation widens: `entry->direction` keeps the author's direction, so composition still refuses an `In` subrange or chain of an `Out` source (`poolMemoryKeepsTheAuthorDirection`). DMA prepares the descriptor itself (`EntryMemory`), so the device's DMA access to an `Out` pool entry widens to `InOut`. `PrepareForDMA` reports the descriptor's direction in `flags` (`IODMACommand.h:131-133`), and the runtime passes them unchanged to `DriverDMAMapping.flags`. For an `Out` pool entry they likely now include the writable bit. This is unmeasured because DriverKit fills the value |
| F-04 | C1 | `SwifterKitRuntimeFastPath.cpp:281` | Ring allocated with the row direction, then zeroed and its header written at `:293-297` | Fixed on the H1 SDK citation, not hardware-tested (E-3). `NativeBufferContractTests.everyAllocatedBufferIsWritable` failed on it before the fix and passes after it. The allocation uses `SwifterKitWritableDirection` (`SwifterKitRuntimeMappedMemory.h`), which turns `Out` into `InOut` |
| F-05 | C1 | `SwifterKitRuntimeMemory.cpp:243` | Composed `Out` entry mapped and then written by `MemoryWrite` | Fixed on the H1 SDK citation, not hardware-tested (E-3). `NativeBufferContractTests.composedOutputMemoryIsReadOnly` failed before the fix and passes after it. The mapping is `kIOMemoryMapReadOnly` and `MemoryWrite` returns `kIOReturnNotWritable`. The descriptor is not widened, because a wrapped `Out` client memory can sit on read-only host pages |
| F-06 | C2 | `SwifterKitRuntimeSCSIPeripheral.cpp:50` | Mapping length not checked before write | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-07 | C2 | `SwifterKitRuntimeFastPath.cpp:286` | Mapping length not checked before zeroing `bytes` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-08 | C2 | `SwifterKitRuntimeFastPathDataQueues.cpp:195` | Mapping length not checked before zeroing `bytes` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-09 | C2 | `SwifterKitRuntimeHIDShared.h:153` | Mapping length not checked before `memcpy` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-10 | C2 | `SwifterKitRuntimeHIDShared.h:135` | Mapping length not checked before reading `length` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-11 | C2 | `SwifterKitRuntimeHIDRequests.cpp:199` | Mapping length not checked before reading `length` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-12 | C2 | `SwifterKitRuntimeMemory.cpp:243` | Composed mapping length not checked against `entry->length` | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-13 | C2 | `SwifterKitRuntimeMemory.cpp:563` | Author mapping length not checked against capacity | Fixed. `NativeBufferContractTests.everyMappingLengthIsChecked` failed on it before the fix and passes after it |
| F-14 | C3 | `SwifterKitRuntimeUSBSupport.h:84` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-15 | C3 | `SwifterKitRuntimeUSBBundled.cpp:99` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-16 | C3 | `SwifterKitRuntimeUSBPipes.cpp:179` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-17 | C3 | `SwifterKitRuntimeHIDElements.cpp:267` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-18 | C3 | `SwifterKitRuntimeHIDRequests.cpp:251` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-19 | C3 | `SwifterKitRuntimeHIDShared.h:174` | `SetLength` result discarded | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |
| F-20 | C4 | `SwifterKitRuntimeHIDElements.cpp:270`, `:315` | `Map()` called twice on one buffer. The get path does not check the mapped length. | Fixed. `NativeBufferContractTests` failed on it at `26daf6f` and passes after the fix |

Task 1.4 coverage: every `CreateMapping`, `->Map(` and `SetLength` match from `grep -nE "CreateMapping|->Map\(|SetLength" *.cpp *.h` has a row here or under Ruled out. The checked `SetLength` calls at `SwifterKitRuntimeFastPath.cpp:283`, `SwifterKitRuntimeFastPathDataQueues.cpp:192`, `SwifterKitRuntimeMemory.cpp:560`, `:567`, `:643` and `SwifterKitRuntimeSCSIPeripheral.cpp:48` propagate their result. Task 3.3 says 4 discarded `SetLength` sites. The grep finds 6 (F-14 to F-19), and all 6 are in scope.

## Ruled out

| Site | Why it is not a defect |
| --- | --- |
| `SwifterKitRuntimeNetworkMetadata.h:131`, C6 write `:142` | `SwifterKitRuntimeNetworkControl.cpp:134` checks `entry.length <= bufferSize` first, so the subtraction cannot underflow, and `:131` keeps `offset + entry.length` within `bufferSize` before the `memcpy` at `:142`. The caller passes `kSwifterKitEthernetPacketBufferSize` (`SwifterKitRuntimeNetworkControl.cpp:160`), the size of each pool buffer with one buffer per packet (`SwifterKitRuntimeNetworkSetup.cpp:50-51`) |
| `SwifterKitRuntimeMemory.cpp:678-683`, C6 `MemoryRead`/`MemoryWrite` | `:669` checks `offset + length` against `entry->length`. `entry->length <= capacity` holds at allocation (`:539`) and resize (`:641`), and composed entries cannot resize (`:638`). The F-12 and F-13 checks make the map at least `capacity` long, or drop it, which `:673` rejects |
| `SwifterKitRuntimeAudioDevice.cpp:183`, `:211` | Offset and length checked against `map->GetLength()`, and `GetOffset()` is 0 because the mapping offset is 0 |
| `SwifterKitRuntimeVideoDevice.cpp:266`, `:293` | `IsValidRange` against `map->GetLength()` under `bufferLock` |
| `SwifterKitRuntimeSCSIControl.cpp:291-298` | Access bounded by `dataMap->GetLength()` |
| `SwifterKitRuntimeSCSI.cpp:280` | Holds the map created at `SwifterKitRuntimeSCSIControl.cpp:145`, whose length comes from the buffer's own `GetLength` and whose access is bounded as above |
| `SwifterKitRuntimeSCSIPeripheral.cpp:77` | Declaration of the `map_` field created at `:50`, covered by F-06 |
| `SwifterKitRuntimeSerial.cpp:136-148` | Arena length and ring bounds validated against map lengths |
| `SwifterKitRuntimeUSBPipes.cpp:180`, `SwifterKitRuntimeUSBBundled.cpp:100`, `SwifterKitRuntimeUSBSupport.h:85` | `GetLength() < length` checked |
| `SwifterKitRuntimeAudioMembers.cpp:354`, `SwifterKitRuntimeVideoMembers.cpp:469` | Map is held for lifetime only. Accessors check its length. |

## C5 map lifetimes

Result: no map in the runtime is used after its release. C5 therefore does not explain the "not in any region" crash. That crash stays with H1 to H4, which need hardware.

USB rows were traced by hand. The other rows come from a read-only trace of every non-USB source. I checked its single suspect (Serial) against the source.

| Map | Create | Owner and release | Uses | Verdict |
| --- | --- | --- | --- | --- |
| Sync transfer `TransferBuffer::map` | `SwifterKitRuntimeUSB.cpp:36` | Local. Destructor `:26` | `MakeTransferResponse` `:51`, `:58`, before the destructor runs | Safe |
| Async device request `transfer.map` | `SwifterKitRuntimeUSBRequests.cpp:166`, `:173` | Moved into the slot under `usbLock` at `:208`. Released by `SwifterKitReleaseUSBTransfer` under `usbLock`: failed submit `:249`, delivery `SwifterKitRuntimeUSBPipes.cpp:513`, teardown `:525` | `QueueCompletion` `SwifterKitRuntimeUSBPipes.cpp:82` under the same lock | Safe |
| Pipe IO and isoch `transfer.map`, `transfer.frameMap` | `SwifterKitRuntimeUSBPipes.cpp:331`, `:372`, `:180` | Same slot path as above | `QueueCompletion` `:82`, `:101` under `usbLock`. A completion after release fails the `requestID` and `action` match at `:463`, `:487` | Safe |
| Bundle ring `entry.map` | `SwifterKitRuntimeUSBBundled.cpp:100` | `ReleaseRing` `:44`. The release opcode `:212-224` takes only rings whose entries are all idle. `ReleaseUSBBundleRings` `:423` runs after `StopUSB` aborts | Enqueue write `:284-287` and delivery `:413` under `usbLock`. A completion after release fails the `ready`, `action` and `generation` checks at `:357` | Safe |
| Serial arena, receive and transmit maps, and cached `serialInterface` | `SwifterKitRuntimeSerial.cpp:124-129`, `:140` | `StopSerial` `:179-182`, without `serialLock` | Only `SerialCommand` `:212-266`, reached only from the user client's `ExternalMethod` | Safe. The user client's `Stop` runs on the `ExternalMethod` queue and drops the service (`SwifterKitRuntimeUserClient.cpp:149-162`). IOKit stops a client before its provider, so no command is in flight when the service's `Stop` reaches `StopSerial`. `ReleaseClientMemory` relies on the same ordering (`SwifterKitRuntimeMemory.cpp:497-503`) |
| SCSI task `dataMap` | `SwifterKitRuntimeSCSIControl.cpp:145` | Moved into the slot at `SwifterKitRuntimeSCSI.cpp:335`. Released from a slot copy removed under `scsiLock` at `:353`, `:456`, `:484` | `SwifterKitRuntimeSCSIControl.cpp:291-304` under `scsiLock` | Safe |
| SCSI peripheral `MappedBuffer::map_` | `SwifterKitRuntimeSCSIPeripheral.cpp:50` | Stack object. Destructor `:33-36`, map before descriptor | `:213-214` to the synchronous `UserSendCDB` `:217`, `:238-239` | Safe |
| Audio `ivars->maps[i]` | `SwifterKitRuntimeAudioDevice.cpp:127`, replaced at `SwifterKitRuntimeAudioMembers.cpp:354` | Swapped under `ringLock` `:363-368`, old map released after unlock `:369`. `free` `SwifterKitRuntimeAudioDevice.cpp:77` | `ReadMappedStream` and `WriteMappedStream` `:182-219`, called only under `ringLock` | Safe |
| Video `dataMaps`, `controlMaps` | `SwifterKitRuntimeVideoDevice.cpp:143-157`, replaced at `SwifterKitRuntimeVideoMembers.cpp:469` | Swapped under `bufferLock` `:495-512`, released after unlock `:516` | `ReadBuffer` and `WriteBuffer` `SwifterKitRuntimeVideoDevice.cpp:261-300` under `bufferLock` | Safe |
| Fast-path ring `map`, cached `address` | `SwifterKitRuntimeFastPath.cpp:286`, `:292` | `ReleaseRings` `:260-270` under `fastPathLock` after `fastPathRunning` is cleared `:511-516` | Programs run only under `fastPathLock` with `fastPathRunning` `:365-395` | Safe |
| Fast-path data queue `map`, cached `address` | `SwifterKitRuntimeFastPathDataQueues.cpp:195`, `:201` | `ReleaseDataQueues` `:241-260` under `fastPathLock` | `Drain`, `Take`, `Consume` under `fastPathLock`, which recheck `fastPathRunning` | Safe |
| Memory entry `map` | `SwifterKitRuntimeMemory.cpp:243`, `:563` | `ReleaseMemoryEntry` `:122` under `memoryLock`, map before descriptor | `MemoryRead` and `MemoryWrite` `:673-677` under `memoryLock` | Safe |
| HID local maps | `SwifterKitRuntimeHIDShared.h:135`, `:153`, `SwifterKitRuntimeHIDRequests.cpp:199` | Released at `:144`, `:160`, `:208` after the last use | Copied into `OSData` or `memcpy` before release | Safe |

## Baseline

Run at `26daf6f` on the working tree described under Environment, Swift 6.4, before any change in this branch.

| Command | Result |
| --- | --- |
| `SWIFTERKIT_REQUIRE_DRIVERKIT=1 swift test -Xswiftc -warnings-as-errors` | Exit 0. 567 tests in 116 suites passed, and 27 tests in 6 suites passed. 0 failures |
| `./scripts/ci/validate.sh` | Exit 1 at its first step, `swift-format lint`. The later steps did not run, so they were run on their own below |
| `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` | 310 errors in 88 files: 308 `BeginDocumentationCommentWithOneLineSummary`, 2 `NoAccessLevelOnExtensionDeclaration`. Both rules are switched on by the uncommitted `.swift-format`. With the committed `.swift-format`, the only errors are in this change's new test file, which now passes under both configs |
| `swiftlint lint --strict Sources Tests Package.swift` | Exit 2, 2165 `missing_docs` violations, a rule enabled by the uncommitted `.swiftlint.yml`. With the committed `.swiftlint.yml`, 0 violations outside this change's test file, which now passes under both configs |
| `xcrun clang-format --dry-run --Werror Sources/SwifterKit/Resources/DriverKitExtension/Sources/*.{cpp,h,iig}` | Exit 0 |

The swift-format and swiftlint failures come from the user's uncommitted config edits, not from this change. Task 4.1 cannot exit 0 under those configs until the docs they require are written or the configs are settled.

## After the C2 to C4 fixes

Run on the working tree with F-06 to F-20 fixed.

| Command | Result |
| --- | --- |
| `SWIFTERKIT_REQUIRE_DRIVERKIT=1 swift test -Xswiftc -warnings-as-errors` | Exit 0. 570 tests in 117 suites and 27 tests in 6 suites passed |
| `validate.sh` without its two lint lines (4-5) | First run exit 1 in `validate-native.sh:32`: no `clang-tidy` on this Mac. Every step before it passed: the capture test run, the release build, `docc convert --warnings-as-errors`, clang-format, the coverage check, and the native build (arm64 and x86_64) and analyze. The coverage check did not compare the article: it names the 24.4, 25.5 and 27.0 SDKs and only 27.0 is installed |
| `brew install llvm`, then `./scripts/ci/validate-native.sh .build/SwifterKitDriverKitDerived .build/SwifterKitGeneratedTrees` | Exit 0, no diagnostics. clang-tidy from Homebrew LLVM 23.1.4 over the checked-in tree (`validate-native.sh:46`) and the generated trees |
| `plutil -lint` on `Info.plist` and the entitlements, `./scripts/ci/audit_loc.py` | Exit 0 and exit 0. 406 files audited, maximum 776 LOC |

## After the C1 fixes

Run on the working tree with F-01 to F-20 fixed.

| Command | Result |
| --- | --- |
| `swift test --filter NativeBufferContractTests` at `26daf6f` plus the new tests | `everyAllocatedBufferIsWritable` failed on exactly `SwifterKitRuntimeFastPath.cpp:281`, `SwifterKitRuntimeHIDElements.cpp:264`, `SwifterKitRuntimeMemory.cpp:551` and `SwifterKitRuntimeSCSIPeripheral.cpp:44`. `composedOutputMemoryIsReadOnly` failed on both expectations |
| `swift test -Xswiftc -warnings-as-errors --filter NativeBufferContractTests` after the fix | 6 tests passed |
| Mutation checks, each reverted afterwards | Reverting FastPath to `row.direction` fails `everyAllocatedBufferIsWritable`. Replacing `kIOReturnNotWritable` fails `composedOutputMemoryIsReadOnly`. Dropping the SCSI peripheral `GetLength` check fails `everyMappingLengthIsChecked`. Dropping its `result = ` before `SetLength` fails `everySetLengthResultIsChecked`. Storing the widened direction in `entry->direction` fails `poolMemoryKeepsTheAuthorDirection` |
| `validate.sh` without its two lint lines (4-5), `SWIFTERKIT_REQUIRE_DRIVERKIT=1` | Exit 0. 572 tests in 117 suites and 27 tests in 6 suites passed, then the release build, DocC, clang-format, the coverage check, the native build (arm64 and x86_64) and analyze, clang-tidy, plutil, and `audit_loc` (406 files, maximum 776 LOC). The only warnings are `Package.swift:16` `v10_15` deprecation and the macOS 12 link-target notes, which come from the uncommitted `Package.swift` |
| `docc convert --warnings-as-errors` after the `Capabilities.md` edit | Exit 0 |
| `xcrun swift-format lint --strict` and `swiftlint lint --strict` on `NativeBufferContractTests.swift` under the committed and the uncommitted configs | 0 violations under each |

Task 3.7: no row under Defects has the status Open.

## Task 4.1 lint, stopped at the weekly limit

Task 4.1 stays open. The user's uncommitted `.swiftlint.yml` and `.swift-format` turn on `missing_docs` and one-line doc summaries, which gave 2165 `swiftlint` and 309 `swift-format` findings. Doc comments were being added in batches. The user stopped the batches when weekly usage reached 99%.

| Batch | Files | `swiftlint` left | `swift-format` left |
| --- | --- | --- | --- |
| Runtime and `RuntimeSchema*` | `Sources/SwifterKit/DriverKit/Runtime` | 0 | 0 |
| Authoring and `SwifterKitCoverage` | `/tmp/lint41/S3-authoring-coverage.files`, without `Package.swift` | 0 | 0 |
| Other capability sources | `/tmp/lint41/S4-capabilities.files` | 183 | 123 |
| Tests, Authoring | `/tmp/lint41/T1-authoring.files` | 208 | 3 |
| Tests, core | `/tmp/lint41/T2-core.files` | 284 | 9 |
| Tests, rest | `/tmp/lint41/T3-rest.files` | 336 | 2 |
| `Package.swift` | the user's uncommitted file, untouched | 4 (lines 7, 10, 12, 14) | 0 |

- The changes are doc comments only. Outside comment lines, the diff in `Sources/SwifterKit/DriverKit`, `Sources/SwifterKitCoverage` and `Tests` holds three kinds of change:
  - Enum cases split one per line: `ClangAST.Kind`, `IIGParser.Access`, `RuntimeMessageFlag`.
  - `private extension Character` becomes `extension Character` with `fileprivate var isIdentifier`, which keeps the same access.
  - The `StringProtocol.trimmed` extension is split over lines.
- Agents twice dropped spaces in code, for example `isValid(videovalue:` and `=FastPathConfiguration(`. Those 15 lines were restored, and the comment-only diff check and a `[a-z] =[a-zA-Z]` scan come back empty.
- Four doc comments that the agent had guessed from case names were corrected against the public decoders: `RuntimeNetworkEventKind` 8 and 12, and `RuntimeVideoObjectEventKind` 8 and 9.
- The permission classifier denied one doc comment, above `withGeneratedExtension` in `DriverExtensionEventNotificationContractTests.swift`. The user chose to leave it open.
- `SWIFTERKIT_REQUIRE_DRIVERKIT=1 swift test -Xswiftc -warnings-as-errors` on this tree: 573 tests in 117 suites and 27 tests in 6 suites passed.

## Task 4.1 lint, public-only documentation

The user narrowed the documentation rule to the API clients see. `missing_docs` now covers `open` and `public`, which includes the enum cases and protocol requirements of public types. `scripts/ci/audit_docs.py` reads the public symbol graph in `validate.sh` and rejects `///` on any other declaration.

- 1229 `///` lines on non-public declarations that had no HEAD doc comment were deleted. 1053 lines whose declaration had a HEAD doc comment became `//` comments.
- 88 public summaries were split for `BeginDocumentationCommentWithOneLineSummary`. Seven were reworded, because swift-format misreads `` `name`'s `` as an unterminated sentence.
- The one DriverKit mention that lived only on an internal declaration, `IOService::Create`, moved to `DriverContext.createHIDDevice(_:)`.
- `./scripts/ci/validate.sh` with `SWIFTERKIT_REQUIRE_DRIVERKIT=1` exits 0: 573 tests in 117 suites and 27 tests in 6 suites pass, DocC and the coverage check pass, and the largest file is 776 lines.
- Hardware tasks 1.2, 1.3, 2.x and 4.2 go to the PR author, who tests on hardware.

## Task 4.3 review

The review of the diff against this change reported no defects. It named two residual risks:

- The runtime reads some `kIOMemoryDirectionIn` buffers: HID get-report buffers (`SwifterKitRuntimeHIDElements.cpp`, `SwifterKitRuntimeHIDRequests.cpp`), SCSI data-in and sense buffers, and USB input buffers. DriverKit 27.2's `IOMemoryDescriptor.h` says `kIOMemoryDirectionIn` memory "will be writable". Neither arm64 nor x86_64 page tables can encode a write-only page, so a writable mapping is also readable. No change is needed. Hardware runs by the PR author confirm it.
- `DriverDMAMapping.flags` for `Out` pool entries stays as recorded in F-03.

## Tasks 1.2, 1.3, 2.x and 4.2 on this machine

- 1.3: both installed provisioning profiles list `com.apple.developer.driverkit.transport.usb` for vendor 1118 (`0x045E`) only, with products 721, 733, 739, 746, 2816, 2826 and 2834. Vendor 5426 (`0x1532`) is not covered, so a team-signed dext cannot match the Razer `1532:0A15`.
- 1.2: `ioreg -p IOUSB -l -w0` shows no device with vendor 5426. The Razer is not attached.
- 2.1, 2.2, 2.4 and 4.2 need the Razer and a profile that covers vendor 5426. Both are missing here, so these go to the PR author. 2.3 only feeds 2.4, and 3.1 already landed C1 on the SDK citation.
