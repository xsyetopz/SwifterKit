/// Renders the HID schema as its own header so neither generated header outgrows the source size
/// limit.
extension RuntimeSchemaHeader {
  /// The HID header's file name inside the native extension's `Sources` directory.
  static let hidFileName = "SwifterKitRuntimeHIDSchema.h"

  /// Returns the complete clang-format-clean HID header text.
  static func renderHID() -> String {
    var lines = [
      "// Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema+HID.swift.",
      "// Do not edit.",
      "// Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests", "",
      "#ifndef SwifterKitRuntimeHIDSchema_h", "#define SwifterKitRuntimeHIDSchema_h", "",
      "#include <stdint.h>",
    ]
    for section in hidSections() { lines += [""] + section }
    lines += ["", "#endif"]
    return lines.joined(separator: "\n") + "\n"
  }
}
