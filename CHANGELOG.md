# Changelog

SwifterKit records user-visible changes in this file.

## [Unreleased]

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
