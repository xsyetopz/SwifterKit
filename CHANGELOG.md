# Changelog

SwifterKit records user-visible changes in this file.

## [Unreleased]

### Changed

- Set the package deployment target to macOS 10.15, matching the first DriverKit release and the generated extension default of DriverKit 19.0. Swift 6.1 compatibility is checked only in CI; local development uses the version in `.swift-version`.
- Added strict DriverKit deployment-version validation and capability floors for SCSI, block storage, networking, audio, MIDI, and video extension generation.

### Added

- Swift 6 APIs for authoring DriverKit behavior, configuration, commands, events, and request completions.
- A generated C++20/IIG DriverKit extension runtime owned by SwifterKit.
- Typed capability layers for HID, USB, PCI, serial, block storage, MIDI, networking, audio, SCSI, video, interrupts, and managed native memory.
- Raw DriverKit user-client access through `DriverClient`, `DriverSession`, and `DriverCommand`.
- Swift-DocC documentation, unsigned dual-architecture DriverKit validation, signed-build tooling, and source-release automation.
