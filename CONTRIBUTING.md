# Contributing

SwifterKit accepts focused fixes, tests, documentation, and capability work that preserves the Swift-facing DriverKit boundary.

## Before opening a change

- Search existing issues and pull requests for the same behavior.
- Keep public Swift APIs source-compatible unless the change explicitly requires a breaking release.
- Add or update tests under the directory matching the affected `Sources/SwifterKit` area.
- Update `CHANGELOG.md` for user-visible behavior.
- Do not commit certificates, provisioning profiles, `.env` files, private keys, device identifiers, or captured driver data.

Bug reports should include the Swift and Xcode versions, macOS version, affected DriverKit family, reproduction steps, and the smallest useful log. Remove signing identities, team identifiers, bundle identifiers, serial numbers, and other private device data before posting.

## Development setup

The checked-in package manifest requires Swift 6.1. Local development uses the latest passing Swift version recorded in `.swift-version`; check the floor with Xcode 16.3's toolchain before submitting. Generated extension builds require Xcode with the DriverKit SDK. Keep IOKit-only code behind `#if canImport(IOKit)` so the package still builds on Linux. Install SwiftLint and LLVM tools when they are not already available:

```sh
brew install swiftlint llvm
```

Run Swift tests during development:

```sh
swift test -Xswiftc -warnings-as-errors
```

Run the full repository validation before submitting a pull request:

```sh
./scripts/ci/validate.sh
```

The full validation builds an unsigned DriverKit extension for arm64 and x86_64. Signed validation needs the Apple assets described in [docs/publishing.md](docs/publishing.md); ordinary pull requests do not need those assets.

## Formatting and file layout

Format Swift and native source with the checked-in configurations:

```sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
xcrun clang-format -i Sources/SwifterKit/Resources/DriverKitExtension/Sources/*.{cpp,h,iig}
swiftlint lint --strict
```

Fix source instead of weakening `.swift-format`, `.swiftlint.yml`, `.clang-format`, or `.clang-tidy`. Keep source and test files below 800 lines after formatting and aim for 500. Markdown is excluded from the LOC audit.

Directories below `Tests/SwifterKitTests` mirror the corresponding `Sources/SwifterKit` areas. Put shared test support in the narrowest matching test directory.

## Swift and native boundaries

Public Swift APIs require documentation and Swift 6 concurrency-safe behavior. Preserve error types, diagnostics, payload layouts, request identifiers, and completion ownership.

`Sources/SwifterKit/Resources/DriverKitExtension` is the only native extension source tree. Native code uses C++20, warnings as errors, const-correctness, and the repository Clang checks. Keep ABI-required IIG declarations and explicit DriverKit types when modernization would change generated interfaces or framework contracts.

Driver authors should not need to copy or maintain C++, C, Objective-C, or IIG glue. Add native work inside SwifterKit and expose it through typed Swift configuration, commands, events, and tests.

When a change adds or removes support for a DriverKit member, update its entry in `coverage/driverkit.json`: set `status`, and add `swiftSymbol` for `swift-api`, `note` for `excluded`, and both for `fast-path`, whose member the native runtime must also reference. A note on a covered member describes what SwifterKit does, never intent such as "planned" or "not yet". `swift run SwifterKitCoverage check --manifest coverage/driverkit.json --sdk "$(xcrun --sdk driverkit --show-sdk-path)"` verifies the claims against the sources and the selected SDK.

## Pull requests

A pull request should describe:

- the behavior being changed;
- the DriverKit family or runtime boundary involved;
- validation performed; and
- signing or hardware behavior that was not tested.

Keep unrelated cleanup out of the change. Do not include generated build products, derived data, signing assets, or local environment files.

Participation follows the [Swift Code of Conduct](CODE_OF_CONDUCT.md).
