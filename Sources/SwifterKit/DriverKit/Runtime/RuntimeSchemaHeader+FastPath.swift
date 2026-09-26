/// Renders the fast-path schema, under the native names the extension uses, as its own header so
/// neither generated header outgrows the source size limit.
extension RuntimeSchemaHeader {
  /// The fast-path header's file name inside the native extension's `Sources` directory.
  static let fastPathFileName = "SwifterKitRuntimeFastPathSchema.h"

  /// Returns the complete clang-format-clean fast-path header text.
  static func renderFastPath() -> String {
    var lines = [
      "// Generated from Sources/SwifterKit/DriverKit/Runtime/RuntimeSchema+FastPath.swift.",
      "// Do not edit.",
      "// Regenerate: SWIFTERKIT_UPDATE_SCHEMA=1 swift test --filter RuntimeSchemaTests", "",
      "#ifndef SwifterKitRuntimeFastPathSchema_h", "#define SwifterKitRuntimeFastPathSchema_h", "",
      "#include <stdint.h>",
    ]
    for section in fastPathSections() { lines += [""] + section }
    lines += ["", "#endif"]
    return lines.joined(separator: "\n") + "\n"
  }

  private static func fastPathSections() -> [[String]] {
    let limits = RuntimeFastPathLimits.self
    return [
      constants(
        "uint32_t",
        [
          ("kSwifterKitFastPathMaximumPrograms", "\(limits.maximumPrograms)"),
          ("kSwifterKitFastPathMaximumOperations", "\(limits.maximumOperations)"),
          ("kSwifterKitFastPathSlotCount", "\(limits.slotCount)"),
          ("kSwifterKitFastPathMaximumArguments", "\(limits.maximumArguments)"),
          ("kSwifterKitFastPathMaximumPollIterations", "\(limits.maximumPollIterations)"),
          (
            "kSwifterKitFastPathMaximumPollIntervalMicroseconds",
            "\(limits.maximumPollIntervalMicroseconds)"
          ), ("kSwifterKitFastPathMaximumDelayMicroseconds", "\(limits.maximumDelayMicroseconds)"),
          (
            "kSwifterKitFastPathMaximumDelayBudgetMicroseconds",
            "\(limits.maximumDelayBudgetMicroseconds)"
          ), ("kSwifterKitFastPathBARCount", "\(limits.barCount)"),
          ("kSwifterKitFastPathShiftLimit", "\(limits.shiftLimit)"),
        ]
      ), enumeration("SwifterKitFastPathOpcode", type: "uint32_t", RuntimeFastPathOpcode.allCases),
      enumeration(
        "SwifterKitFastPathOperandKind",
        type: "uint32_t",
        RuntimeFastPathOperandKind.allCases
      ),
      enumeration(
        "SwifterKitFastPathComputeOperation",
        type: "uint32_t",
        RuntimeFastPathComputeOperation.allCases
      ),
      enumeration(
        "SwifterKitFastPathConditionTest",
        type: "uint32_t",
        RuntimeFastPathConditionTest.allCases
      ),
      enumeration(
        "SwifterKitFastPathTriggerKind",
        type: "uint32_t",
        RuntimeFastPathTriggerKind.allCases
      ),
      enumeration(
        "SwifterKitFastPathInterruptDelivery",
        type: "uint32_t",
        RuntimeFastPathInterruptDelivery.allCases
      ),
    ] + RuntimeFastPathRow.all.map(structure)
  }

  /// A plain C++ structure with a size assertion.
  private static func structure(_ row: RuntimeFastPathRow) -> [String] {
    ["struct \(row.name) {"] + row.fields.map { "    \($0.type) \($0.name);" } + [
      "};", "static_assert(sizeof(\(row.name)) == \(row.size));",
    ]
  }
}
