import Foundation
import Testing

@testable import SwifterKit

@Suite
struct RuntimeSchemaTests {
  /// The checked-in native header, located relative to this file so the test runs on any host.
  private static let headerURL = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
    url.deletingLastPathComponent()  // Runtime, DriverKit, SwifterKitTests, Tests, package root.
  }.appendingPathComponent("Sources/SwifterKit/Resources/DriverKitExtension/Sources")
    .appendingPathComponent(RuntimeSchemaHeader.fileName)

  @Test
  func checkedInNativeHeaderMatchesSchema() throws {
    let rendered = RuntimeSchemaHeader.render()
    if ProcessInfo.processInfo.environment["SWIFTERKIT_UPDATE_SCHEMA"] == "1" {
      try Data(rendered.utf8).write(to: Self.headerURL, options: .atomic)
      return
    }

    let checkedIn = try String(contentsOf: Self.headerURL, encoding: .utf8)
    #expect(
      checkedIn == rendered,
      """
      \(RuntimeSchemaHeader.fileName) differs from RuntimeSchema.swift. Regenerate it with \
      `SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests` and commit the result.
      """
    )
  }

  @Test
  func rendersNativeNamesForAcronymPrefixes() {
    let header = RuntimeSchemaHeader.render()

    #expect(header.contains("    PCIGetBARInfo = 0x0402,\n"))
    #expect(header.contains("    SCSIPeripheralSendCDB = 0x0B10,\n"))
    #expect(header.contains("    BlockStorageCompleteIO = 0x0701,\n"))
    #expect(header.contains("static constexpr uint32_t kSwifterKitEventHIDReport = 0x0300;\n"))
    #expect(header.contains("static constexpr uint64_t kSwifterKitCapabilityUSB = 0x4;\n"))
    #expect(header.contains("static constexpr uint32_t kSwifterKitRuntimeMagic = 0x53574B54;\n"))
  }

  @Test
  func schemaValuesAreUnique() {
    #expect(Set(RuntimeOpcode.allCases.map(\.rawValue)).count == RuntimeOpcode.allCases.count)
    #expect(Set(RuntimeEventType.allCases.map(\.rawValue)).count == RuntimeEventType.allCases.count)
    #expect(
      RuntimeCapability.allCases.allSatisfy { $0.rawValue.nonzeroBitCount == 1 }
        && Set(RuntimeCapability.allCases.map(\.rawValue)).count == RuntimeCapability.allCases.count
    )
    #expect(RuntimeSchema.minimumVersion <= RuntimeSchema.maximumVersion)
  }
}
