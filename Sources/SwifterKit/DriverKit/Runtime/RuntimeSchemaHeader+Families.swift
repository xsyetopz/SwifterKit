/// Renders the per-family schema declarations, each under the native name the extension uses.
extension RuntimeSchemaHeader {
  /// The family sections, in header order; `render()` separates them with blank lines.
  static func familySections() -> [[String]] { serviceSections() }

  /// `static constexpr` declarations of one native type, from name and value pairs.
  static func constants(_ type: String, _ entries: [(name: String, value: String)]) -> [String] {
    entries.map { constant(type, $0.name, $0.value) }
  }

  /// An `enum class` whose cases take the native names of a Swift enumeration's cases.
  static func enumeration<Value: RawRepresentable>(
    _ name: String,
    type: String,
    _ cases: [Value]
  ) -> [String] where Value.RawValue: BinaryInteger {
    enumeration(name, type: type, cases: cases.map { (nativeName($0), "\($0.rawValue)") })
  }

  /// Concatenates declaration groups that share one section.
  static func joined(_ groups: [String]...) -> [String] { groups.flatMap { $0 } }

  private static func serviceSections() -> [[String]] {
    let dispatch = RuntimeDispatchLimits.self
    let reporting = RuntimeReportingLimits.self
    return [
      joined(
        constants(
          "uint32_t",
          [
            ("kSwifterKitMaximumTimers", "\(dispatch.maximumTimers)"),
            ("kSwifterKitMaximumServiceWatches", "\(dispatch.maximumServiceWatches)"),
            ("kSwifterKitMaximumWatchedStateItems", "\(dispatch.maximumWatchedStateItems)"),
          ]
        ),
        constants(
          "uint64_t",
          [
            (
              "kSwifterKitTimerMinimumIntervalNanoseconds",
              "\(dispatch.timerMinimumIntervalNanoseconds)ULL"
            ), ("kSwifterKitTimerMaximumNanoseconds", "\(dispatch.timerMaximumNanoseconds)ULL"),
          ]
        )
      ),
      enumeration(
        "SwifterKitServiceWatchKind",
        type: "uint32_t",
        [RuntimeServiceWatchKind.terminated, .matched]
      ),
      constants(
        "uint32_t",
        [
          ("kSwifterKitMaximumReporters", "\(reporting.maximumReporters)"),
          ("kSwifterKitMaximumReportChannels", "\(reporting.maximumReportChannels)"),
          ("kSwifterKitMaximumReportStates", "\(reporting.maximumReportStates)"),
          ("kSwifterKitMaximumHistogramSegments", "\(reporting.maximumHistogramSegments)"),
          ("kSwifterKitMaximumHistogramBuckets", "\(reporting.maximumHistogramBuckets)"),
        ]
      ), enumeration("SwifterKitReporterKind", type: "uint32_t", RuntimeReporterKind.allCases),
      enumeration(
        "SwifterKitReporterOperation",
        type: "uint32_t",
        RuntimeReporterOperation.allCases
      ),
      joined(
        enumeration("SwifterKitPropertyTag", type: "uint8_t", RuntimePropertyTag.allCases),
        constants(
          "uint32_t",
          [
            ("kSwifterKitPropertyMaximumDepth", "\(RuntimePropertyLimits.maximumDepth)"),
            ("kSwifterKitPropertyNameMaximumLength", "\(RuntimePropertyLimits.nameMaximumLength)"),
          ]
        )
      ),
    ]
  }
}
