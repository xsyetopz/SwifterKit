# Tasks

## 1. Baseline

- [x] 1.1 Branch `fix/runtime-buffer-writes` from `origin/main` (`26daf6f`). Run `SWIFTERKIT_REQUIRE_DRIVERKIT=1 swift test -Xswiftc -warnings-as-errors` and `./scripts/ci/validate.sh`. Record pass and fail counts and every failure in `findings.md` (create it in this change; columns: ID, class, file:line, hypothesis, evidence, status).
- [ ] 1.2 Read the endpoint descriptors of the Razer `1532:0A15` with `ioreg -p IOUSB -l -w0`, without serial numbers. Verify that it has an interrupt OUT endpoint, record its address and max packet size, and record whether it answers the GIP power-on packet. (Handed to the PR author, who tests on hardware.)
- [x] 1.3 Read the DriverKit provisioning profile with `security cms -D -i <profile>`, and print only its entitlements. Verify that `com.apple.developer.driverkit.transport.usb` covers vendor `0x1532` (`5426`). Record the result without team IDs. (Handed to the PR author, who tests on hardware.)
- [x] 1.4 List every C1 to C6 site from design.md (Context) in `findings.md`. Then grep for more. Verify that each `CreateMapping`, `Map(`, `SetLength`, and mapped `memcpy`/`memset` in the native sources has a row.

## 2. Reproduce and probe (team-signed, SIP on)

- [ ] 2.1 Build a team-signed dext on `783840e` that matches only `1532:0A15` and sends the GIP power-on packet on interrupt OUT. Run it and capture `log stream --predicate 'subsystem CONTAINS "SwifterKit"'` and any `.ips` report. Record whether it crashed, and the `esr`, `far`, and `vmRegionInfo` values. (Handed to the PR author, who tests on hardware.)
- [ ] 2.2 Repeat 2.1 on `26daf6f`. Verify that a result is recorded for each of 2.1 and 2.2. (Handed to the PR author, who tests on hardware.)
- [ ] 2.3 On branch `probe/buffer-writes`, add the H1 to H4 strategies from design.md D2 behind `SWIFTERKIT_BUFFER_PROBE`. Verify that `DriverExtensionUSBGeneratorTests` passes with the flag. (Handed to the PR author, who tests on hardware.)
- [ ] 2.4 Run each probe strategy in its own launch on the Razer. Verify that each of H1 to H4 has a log line or crash report quoted in `findings.md`, and is marked confirmed or refuted. (Handed to the PR author, who tests on hardware.)

## 3. Hunt and fix (failing test first, per class)

- [x] 3.1 C1: write the direction contract test. Verify that it fails on `26daf6f` and names `HIDElements`, `SCSIPeripheral`, `Memory`, and `FastPath`. Then fix each site the way 2.4 points, and verify that it passes. (2.4 is blocked by E-3. The user chose to land C1 on the H1 SDK citation. See findings.md.)
- [x] 3.2 C2 and C6: write the mapped-length contract test. Verify that it fails on every site that lacks a check. Add the `GetLength()` offset-and-length check, then verify that it passes.
- [x] 3.3 C3: write the test that rejects `(void)` before `SetLength`. Verify that it fails on all 4 sites. Propagate the errors, then verify that it passes.
- [x] 3.4 C4: replace the two `Map()` calls in `SwifterKitRuntimeHIDElements.cpp` with one `CreateMapping` per request. Verify that `HIDRuntimeContractTests` passes and that a new test rejects `->Map(`.
- [x] 3.5 C1, author memory: read `PrepareDMA` for `GetDirection()` versus `entry->direction`. Change only the backing allocation. Verify with tests that an `Out` write and read round-trip succeeds and that `Out`-source/`In`-request composition is still rejected.
- [x] 3.6 C5: trace the owner and release point of every `IOMemoryMap` in `findings.md`. Fix each use after release, adding a test for each. Verify that every row reads fixed, or blocked with a named blocker.
- [x] 3.7 Fix every new defect that `findings.md` gained during 1 to 3, failing test first. Verify that no row is open.
- [x] 3.8 (Fixes recorded; the 2.1/2.2 hardware results go to the PR author.) Extend the `CHANGELOG.md` Unreleased entry from `14c06f4` with the 2.1/2.2 hardware results and each fix. Update the DocC native-boundary notes that describe buffers. Verify with `grep -rn "kIOMemoryDirection\|CreateMapping" Sources/SwifterKit/SwifterKit.docc`.

## 4. Integration

- [x] 4.1 Run `xcrun clang-format -i Sources/SwifterKit/Resources/DriverKitExtension/Sources/*.{cpp,h,iig}`, `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`, `swiftlint lint --strict`, `SWIFTERKIT_REQUIRE_DRIVERKIT=1 swift test -Xswiftc -warnings-as-errors`, and `./scripts/ci/validate.sh`. Verify that each exits 0, and record the output in `findings.md`.
- [ ] 4.2 Build the fixed branch team-signed and run the 2.1 scenario 25 times on the Razer. Verify that no `.ips` report appears and that each OUT transfer completes. (Handed to the PR author, who tests on hardware.)
- [x] 4.3 Run a `claudetto:Athena` review of the diff against this change. Verify that each reported defect is fixed, test first, and recorded in `findings.md`.

## Workflow follow-up

- Needs approval because others can see it: push `fix/runtime-buffer-writes`, open the PR, and comment the 2.1/2.2/4.2 results on xsyetopz/OpenJoystickDriver#55.
- Delete `probe/buffer-writes` after its results are in `findings.md`.
- Archive this change with `/openspec-archive-change` after merge.
