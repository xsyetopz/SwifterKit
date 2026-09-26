/// Renders ``RuntimeSchema`` as the native `SwifterKitRuntimeSchema.h` header.
enum RuntimeSchemaHeader {
  /// The header's file name inside the native extension's `Sources` directory.
  static let fileName = "SwifterKitRuntimeSchema.h"

  /// Returns the complete clang-format-clean header text.
  static func render() -> String {
    let wire: [(type: String, name: String, value: String)] = [
      ("uint32_t", "Magic", hex(RuntimeSchema.magic, digits: 8)),
      ("uint16_t", "VersionMinimum", "\(RuntimeSchema.minimumVersion)"),
      ("uint16_t", "VersionMaximum", "\(RuntimeSchema.maximumVersion)"),
      ("uint32_t", "MaximumMessageSize", "\(RuntimeSchema.maximumMessageSize)"),
      ("uint32_t", "HeaderSize", "\(RuntimeSchema.headerSize)"),
      ("uint32_t", "CommandHeaderSize", "\(RuntimeSchema.commandHeaderSize)"),
      ("uint32_t", "HandshakeRequestSize", "\(RuntimeSchema.handshakeRequestSize)"),
      ("uint32_t", "HandshakeResponseSize", "\(RuntimeSchema.handshakeResponseSize)"),
    ]
    var lines = preamble.components(separatedBy: "\n")
    lines += wire.map { constant($0.type, "kSwifterKitRuntime" + $0.name, $0.value) }
    lines.append("")
    lines += RuntimeMessageFlag.allCases.map {
      constant("uint32_t", "kSwifterKitMessageFlag" + nativeName($0), hex($0.rawValue, digits: 1))
    }
    lines.append("")
    lines += RuntimeSelector.allCases.map {
      constant("uint64_t", "kSwifterKitSelector" + nativeName($0), "\($0.rawValue)")
    }
    lines.append("")
    lines += RuntimeCapability.allCases.map {
      constant("uint64_t", "kSwifterKitCapability" + nativeName($0), hex($0.rawValue, digits: 1))
    }
    lines.append("")
    lines += enumeration(
      "SwifterKitRuntimeMessageKind",
      type: "uint16_t",
      cases: RuntimeMessageKind.allCases.map { (nativeName($0), "\($0.rawValue)") }
    )
    lines.append("")
    lines += enumeration(
      "SwifterKitRuntimeOpcode",
      type: "uint32_t",
      cases: RuntimeOpcode.allCases.map { (nativeName($0), hex($0.rawValue, digits: 4)) }
    )
    lines.append("")
    lines += RuntimeEventType.allCases.map {
      constant("uint32_t", "kSwifterKitEvent" + nativeName($0), hex($0.rawValue, digits: 4))
    }
    for section in familySections() { lines += [""] + section }
    lines += ["", "#endif"]
    return lines.joined(separator: "\n") + "\n"
  }

  private static let preamble = """
    // Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema.swift. Do not edit.
    // Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests

    #ifndef SwifterKitRuntimeSchema_h
    #define SwifterKitRuntimeSchema_h

    #include <stdint.h>

    """

  private static let acronyms: Set<String> = ["usb", "hid", "pci", "midi", "scsi", "led", "nic"]

  /// Converts a Swift case name such as `pciGetBARInfo` to a native name such as `PCIGetBARInfo`.
  static func nativeName(_ value: some Any) -> String {
    let name = String(describing: value)
    let prefix = String(name.prefix { $0.isLowercase })
    let rest = name.dropFirst(prefix.count)
    if acronyms.contains(prefix) { return prefix.uppercased() + rest }
    return prefix.prefix(1).uppercased() + prefix.dropFirst() + rest
  }

  static func constant(_ type: String, _ name: String, _ value: String) -> String {
    "static constexpr \(type) \(name) = \(value);"
  }

  static func enumeration(
    _ name: String,
    type: String,
    cases: [(name: String, value: String)]
  ) -> [String] {
    ["enum class \(name) : \(type) {"] + cases.map { "    \($0.name) = \($0.value)," } + ["};"]
  }

  static func hex(_ value: some BinaryInteger, digits: Int) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, digits - text.count)) + text
  }
}
