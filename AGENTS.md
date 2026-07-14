# AGENTS.md

## Overview

SwifterKit is a Swift 6 wrapper for DriverKit. Driver authors use Swift APIs; the package owns the generated C++20/IIG runtime required by DriverKit.

## Read next

- `README.md` for supported workflows and capability scope.
- `CONTRIBUTING.md` for validation, layout, and change requirements.
- `Sources/SwifterKit/SwifterKit.docc/` for public API and native-boundary contracts.
- `docs/publishing.md` for releases, signing, secrets, and downstream Apple requirements.
- `Package.swift`, exact source, tests, and native project files remain authoritative.

## Commands

- Full validation: `./scripts/ci/validate.sh`
- Swift tests: `swift test -Xswiftc -warnings-as-errors`
- Swift lint: `swiftlint lint --strict`
- Swift format check: `xcrun swift-format lint --strict --recursive Sources Tests Package.swift`
- Swift formatting: `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`
- Native formatting: `xcrun clang-format -i Sources/SwifterKit/Resources/DriverKitExtension/Sources/*.{cpp,h,iig}`

## Boundaries and invariants

- Preserve public APIs, diagnostics, runtime payloads, DriverKit/IIG ABI declarations, and completion ownership unless the request explicitly changes them.
- Keep Swift 6 concurrency checks clean. Add tests in the path matching the affected `Sources/SwifterKit` area.
- `Sources/SwifterKit/Resources/DriverKitExtension` is the single native extension source tree. Do not add a second generated or hand-maintained copy.
- Driver authors must not need application-owned C++, C, Objective-C, or IIG glue. Native changes belong inside SwifterKit and need a typed Swift surface.
- Source and test files must stay below 800 formatted lines; aim for 500. Markdown does not count. `scripts/ci/audit_loc.py` must remain a LOC-only helper.
- Fix source rather than weakening `.swift-format`, `.swiftlint.yml`, `.clang-format`, or `.clang-tidy`.
- Keep secrets, signing identities, provisioning profiles, `.env` files, private keys, and device data out of source and output.

## Precedence

Direct user instructions override this file. A closer subtree `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` overrides this map for that subtree.
