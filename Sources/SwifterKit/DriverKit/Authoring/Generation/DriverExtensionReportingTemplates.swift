extension DriverExtensionGenerator {
  /// Native reporter tables for `SwifterKitRuntimeReporting.cpp`.
  ///
  /// Each reporter indexes runs of the shared channel, state, and segment tables. Arrays hold at
  /// least one element so the tables stay valid C++ when they are empty.
  static func reportingDeclarations(_ reporting: ReportingConfiguration?) -> String {
    let reporters = reporting?.reporters ?? []
    var channels: [String] = []
    var states: [String] = []
    var segments: [String] = []
    let entries = reporters.map { reporter -> String in
      let channelStart = channels.count
      let stateStart = states.count
      let segmentStart = segments.count
      channels += reporter.channels.map { "    {\($0.id)ULL, \(cString($0.name))}" }
      let kind: RuntimeReporterKind
      switch reporter.kind {
      case .simple: kind = .simple
      case .state(let values):
        kind = .state
        states += values.map { "\($0)ULL" }
      case .histogram(let values):
        kind = .histogram
        segments += values.map {
          "    {\($0.baseBucketWidth), \($0.scale.rawValue), \($0.bucketCount)}"
        }
      }
      let subgroup = reporter.subgroup.map(cString) ?? "nullptr"
      return
        "    {\(kind.rawValue), \(reporter.categories.rawValue), \(reporter.unit.rawValue)ULL, "
        + "\(cString(reporter.group)), \(subgroup), \(channelStart), "
        + "\(reporter.channels.count), \(stateStart), \(states.count - stateStart), "
        + "\(segmentStart), \(segments.count - segmentStart)}"
    }
    func table(_ rows: [String]) -> String {
      rows.isEmpty ? "{}" : "{\n" + rows.joined(separator: ",\n") + "\n}"
    }
    return """
      struct SwifterKitReportChannelConfiguration {
          uint64_t identifier;
          const char* name;
      };
      struct SwifterKitHistogramSegmentConfiguration {
          uint32_t baseBucketWidth;
          uint32_t scale;
          uint32_t bucketCount;
      };
      struct SwifterKitReporterConfiguration {
          uint32_t kind;
          uint16_t categories;
          uint64_t unit;
          const char* group;
          const char* subgroup;
          uint32_t channelStart;
          uint32_t channelCount;
          uint32_t stateStart;
          uint32_t stateCount;
          uint32_t segmentStart;
          uint32_t segmentCount;
      };
      static constexpr SwifterKitReportChannelConfiguration
          kSwifterKitReportChannels[\(max(channels.count, 1))] = \(table(channels));
      static constexpr uint64_t kSwifterKitReportStates[\(max(states.count, 1))] = {\(
        states.isEmpty ? "0" : states.joined(separator: ", "))};
      static constexpr SwifterKitHistogramSegmentConfiguration
          kSwifterKitHistogramSegments[\(max(segments.count, 1))] = \(table(segments));
      static constexpr SwifterKitReporterConfiguration
          kSwifterKitReporters[\(max(entries.count, 1))] = \(table(entries));
      static constexpr uint32_t kSwifterKitReporterCount = \(entries.count);
      static constexpr bool kSwifterKitReportLegendPublic = \(
        reporting?.isLegendPublic == true ? "true" : "false");
      """
  }

  static let reportingMethods = """
        virtual IOReturn ConfigureReport(
            OSData* channels,
            uint32_t action,
            uint32_t* outCount) override;
        virtual IOReturn UpdateReport(
            OSData* channels,
            uint32_t action,
            uint32_t* outElementCount,
            uint64_t offset,
            uint64_t capacity,
            IOMemoryDescriptor* buffer) override;
        kern_return_t StartReporting() LOCALONLY;
        void StopReporting() LOCALONLY;
        kern_return_t ReporterCommand(
            uint32_t opcode,
            const uint8_t* payload,
            uint32_t payloadLength,
            OSData** response) LOCALONLY;
    """
}
