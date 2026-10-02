import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionPersonalityRenamingTests {
  @Test(arguments: [
    ("SwifterKitRuntimeService", "SwifterKitPadRuntimeService"),
    ("SwifterKitRuntimeService.iig", "SwifterKitPadRuntimeService.iig"),
    ("SwifterKitHandleMessage", "SwifterKitPadHandleMessage"),
    ("kSwifterKitRuntimeCapabilities", "kSwifterKitRuntimeCapabilities"),
    ("SWIFTERKIT_ENABLE_USB", "SWIFTERKIT_ENABLE_USB"),
    ("_SwifterKitRuntime", "_SwifterKitRuntime"),
    ("Sources/SwifterKit/Runtime.swift", "Sources/SwifterKit/Runtime.swift"),
    ("IOUserHIDDevice", "IOUserHIDDevice"),
  ])
  func renamesNamesThatStartWithSwifterKit(_ name: String, _ expected: String) {
    #expect(DriverExtensionPersonalityRenaming.renamed(name, personality: "Pad") == expected)
  }

  @Test
  func renamesCodeCommentsAndIncludesButNotLiterals() {
    let source = """
      #include "SwifterKitRuntimeProtocol.h"
        #import <SwifterKitRuntimeService.h>
      // SwifterKitRuntimeService owns the user client.
      /* SwifterKitRuntimeHIDDevice
         SwifterKitRuntimeUserClient */
      static constexpr uint64_t kSwifterKitRuntimeCapabilities = 1'000;
      #if SWIFTERKIT_ENABLE_USB
      SwifterKitRuntimeService::Start(SwifterKitRuntimeUserClient *client) {
        auto key = "SwifterKitRuntimeService";
        auto escaped = "\\"SwifterKitRuntimeService";
        char quote = '"'; SwifterKitHandleMessage(key, 'S');
        char tick = '\\''; SwifterKitDecodeProperty(tick);
      }
      #endif
      """
    let expected = """
      #include "SwifterKitPadRuntimeProtocol.h"
        #import <SwifterKitPadRuntimeService.h>
      // SwifterKitPadRuntimeService owns the user client.
      /* SwifterKitPadRuntimeHIDDevice
         SwifterKitPadRuntimeUserClient */
      static constexpr uint64_t kSwifterKitRuntimeCapabilities = 1'000;
      #if SWIFTERKIT_ENABLE_USB
      SwifterKitPadRuntimeService::Start(SwifterKitPadRuntimeUserClient *client) {
        auto key = "SwifterKitRuntimeService";
        auto escaped = "\\"SwifterKitRuntimeService";
        char quote = '"'; SwifterKitPadHandleMessage(key, 'S');
        char tick = '\\''; SwifterKitPadDecodeProperty(tick);
      }
      #endif
      """
    #expect(
      DriverExtensionPersonalityRenaming.renamedSource(source, personality: "Pad") == expected
    )
  }

  @Test
  func commentApostrophesDoNotStartLiterals() {
    let source = "// the service's SwifterKitRuntimeService\nSwifterKitRuntimeService x;\n"
    #expect(
      DriverExtensionPersonalityRenaming.renamedSource(source, personality: "Pad")
        == "// the service's SwifterKitPadRuntimeService\nSwifterKitPadRuntimeService x;\n"
    )
  }

  @Test
  func renamesEveryTemplateSourceFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try DriverExtensionPersonalityRenaming.renameSources(
      at: checkedInNativeSources,
      into: root,
      personality: "Pad"
    )
    let template = try FileManager.default.contentsOfDirectory(atPath: checkedInNativeSources.path)
    let renamed = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(
      Set(renamed)
        == Set(template.map { DriverExtensionPersonalityRenaming.renamed($0, personality: "Pad") })
    )
    #expect(renamed.allSatisfy { $0.hasPrefix("SwifterKitPad") })

    #expect(throws: DriverExtensionGenerationError.invalidPersonalityName("Pad")) {
      try DriverExtensionPersonalityRenaming.renameSources(
        at: checkedInNativeSources,
        into: root,
        personality: "Pad"
      )
    }
  }

  /// Each personality compiles only its own families, so a command for any other family must
  /// reach the `#else` branch that reports `kIOReturnUnsupported`.
  @Test
  func familyDispatchersRejectFamiliesThatAreNotCompiled() throws {
    let dispatch = try String(
      contentsOf: checkedInNativeSources.appendingPathComponent(
        "SwifterKitRuntimeCommandDispatch.cpp"
      ),
      encoding: .utf8
    )
    let lines = dispatch.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let gates = lines.indices.filter { lines[$0].hasPrefix("#if SWIFTERKIT_ENABLE_") }
    #expect(gates.count >= 10)
    for gate in gates {
      let end = try #require(lines[gate...].firstIndex { $0 == "#endif" })
      let branch = try #require(
        lines[gate..<end].firstIndex { $0 == "#else" },
        "\(lines[gate]) has no #else branch"
      )
      #expect(
        Array(lines[(branch + 1)..<end]) == ["return kIOReturnUnsupported;"],
        "\(lines[gate])"
      )
    }
  }
}
