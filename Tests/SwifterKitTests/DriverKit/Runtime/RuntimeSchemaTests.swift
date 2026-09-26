import Foundation
import Testing

@testable import SwifterKit

@Suite
struct RuntimeSchemaTests {
  /// The checked-in native sources.
  private static let directory = checkedInNativeSources

  /// Each generated header's file name and rendered text.
  private static let headers = [
    (RuntimeSchemaHeader.fileName, RuntimeSchemaHeader.render()),
    (RuntimeSchemaHeader.fastPathFileName, RuntimeSchemaHeader.renderFastPath()),
  ]

  @Test
  func checkedInNativeHeaderMatchesSchema() throws {
    for (fileName, rendered) in Self.headers {
      let url = Self.directory.appendingPathComponent(fileName)
      if ProcessInfo.processInfo.environment["SWIFTERKIT_UPDATE_SCHEMA"] == "1" {
        try Data(rendered.utf8).write(to: url, options: .atomic)
        continue
      }

      let checkedIn = try String(contentsOf: url, encoding: .utf8)
      #expect(
        checkedIn == rendered,
        """
        \(fileName) differs from the RuntimeSchema sources. Regenerate it with \
        `SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests` and commit the result.
        """
      )
    }
  }

  @Test
  func nativeSourcesDeclareNoSchemaNameAgain() throws {
    let declared = try Self.names(
      in: Self.headers.map(\.1).joined(),
      matching: #"static constexpr [A-Za-z0-9_]+ ([A-Za-z0-9_]+)(?:\[\])? ="#,
      #"enum class ([A-Za-z0-9_]+) :"#,
      #"struct ([A-Za-z0-9_]+) \{"#
    )
    #expect(declared.count > 20)
    let generated = Set(Self.headers.map(\.0))
    let files = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter {
      !generated.contains($0)
    }.filter { [".h", ".cpp", ".iig"].contains(where: $0.hasSuffix) }
    #expect(!files.isEmpty)
    for file in files.sorted() {
      let text = try String(
        contentsOf: Self.directory.appendingPathComponent(file),
        encoding: .utf8
      )
      let redeclared = try Self.names(
        in: text,
        matching: #"constexpr\s+[A-Za-z0-9_:]+\s+([A-Za-z0-9_]+)\s*[=\[{]"#,
        #"enum\s+(?:class\s+)?([A-Za-z0-9_]+)\s*[:{]"#,
        #"(?m)^\s*([A-Za-z0-9_]+)\s*=\s*[-0-9]"#,
        #"#define\s+([A-Za-z0-9_]+)"#,
        #"struct\s+(?:__attribute__\(\(\w+\)\)\s+)?([A-Za-z0-9_]+)\s*\{"#
      ).intersection(declared)
      #expect(
        redeclared.isEmpty,
        "\(file) declares \(redeclared.sorted()), which a generated schema header declares"
      )
    }
  }

  private static func names(in text: String, matching patterns: String...) throws -> Set<String> {
    var names: Set<String> = []
    for pattern in patterns {
      let expression = try NSRegularExpression(pattern: pattern)
      let range = NSRange(text.startIndex..., in: text)
      for match in expression.matches(in: text, range: range) {
        if let name = Range(match.range(at: 1), in: text) { names.insert(String(text[name])) }
      }
    }
    return names
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
