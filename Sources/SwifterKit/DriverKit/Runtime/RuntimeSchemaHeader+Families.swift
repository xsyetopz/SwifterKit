/// Renders the per-family schema declarations, each under the native name the extension uses.
extension RuntimeSchemaHeader {
  /// The family sections, in header order; `render()` separates them with blank lines.
  static func familySections() -> [[String]] {
    serviceSections() + storageSections() + midiSections()
  }

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

  /// `static constexpr` declarations named `prefix` plus each case's native name.
  static func constants<Value: RawRepresentable>(
    _ prefix: String,
    type: String,
    _ cases: [Value]
  ) -> [String] where Value.RawValue: BinaryInteger {
    constants(type, cases.map { (prefix + nativeName($0), "\($0.rawValue)") })
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

  private static func storageSections() -> [[String]] {
    let scsi = RuntimeSCSILimits.self
    return [
      joined(
        enumeration(
          "SwifterKitSCSIManagementKind",
          type: "uint32_t",
          RuntimeSCSIManagementKind.allCases
        ),
        constants(
          "uint32_t",
          [
            ("kSwifterKitSCSIMaximumPropertyCount", "\(scsi.maximumPropertyCount)"),
            ("kSwifterKitSCSIMaximumFeatureRequests", "\(scsi.maximumFeatureRequests)"),
            (
              "kSwifterKitSCSICommandDescriptorBlockMaximumSize",
              "\(scsi.commandDescriptorBlockMaximumSize)"
            ),
            ("kSwifterKitSCSIPeripheralMaximumDataLength", "\(scsi.peripheralMaximumDataLength)"),
          ]
        ),
        constants(
          "uint16_t",
          [
            ("kSwifterKitSCSIPropertyKeyMaximumLength", "\(scsi.propertyKeyMaximumLength)"),
            ("kSwifterKitSCSIPropertyValueMaximumLength", "\(scsi.propertyValueMaximumLength)"),
          ]
        )
      ),
      enumeration(
        "SwifterKitBlockStorageRequestKind",
        type: "uint32_t",
        RuntimeBlockStorageRequestKind.allCases
      ),
      enumeration("SwifterKitSerialEventKind", type: "uint32_t", RuntimeSerialEventKind.allCases),
      enumeration(
        "SwifterKitUSBSerialPacketKind",
        type: "uint32_t",
        RuntimeUSBSerialPacketKind.allCases
      ),
    ]
  }

  private static func midiSections() -> [[String]] {
    let objects = RuntimeMIDIObjectLimits.self
    let properties = RuntimeMIDIPropertyLimits.self
    return [
      enumeration("SwifterKitMIDIEventKind", type: "uint32_t", RuntimeMIDIEventKind.allCases),
      joined(
        constants("kSwifterKitMIDITarget", type: "uint32_t", RuntimeMIDITargetKind.allCases),
        constants("kSwifterKitMIDIKey", type: "uint32_t", RuntimeMIDIKeyKind.allCases),
        constants(
          "uint32_t",
          [
            ("kSwifterKitMIDIDriverClass", hex(objects.driverClass, digits: 8)),
            ("kSwifterKitMIDIMaximumListedObjects", "\(objects.maximumListedObjects)"),
            ("kSwifterKitMIDINameMaximumLength", "\(objects.nameMaximumLength)"),
          ]
        )
      ),
      joined(
        constants("kSwifterKitMIDIValue", type: "uint32_t", RuntimeMIDIValueType.allCases),
        constants(
          "uint32_t",
          [
            ("kSwifterKitMIDIPropertyMaximumDepth", "\(properties.maximumDepth)"),
            ("kSwifterKitMIDIPropertyMaximumEntries", "\(properties.maximumEntries)"),
            ("kSwifterKitMIDIPropertyKeyMaximumLength", "\(properties.keyMaximumLength)"),
          ]
        )
      ),
    ]
  }
}
