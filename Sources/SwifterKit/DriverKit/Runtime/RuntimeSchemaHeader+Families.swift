/// Renders the per-family schema declarations, each under the native name the extension uses.
extension RuntimeSchemaHeader {
  /// The family sections, in header order. `render()` separates them with blank lines.
  static func familySections() -> [[String]] {
    serviceSections() + storageSections() + midiSections() + usbSections() + networkSections()
      + audioSections() + videoSections()
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

  /// `static constexpr` bit masks named `prefix` plus each case's native name, then `allName`
  /// with every bit set.
  static func bits<Value: CaseIterable & RawRepresentable>(
    _ prefix: String,
    _ type: Value.Type,
    all allName: String
  ) -> [String] where Value.RawValue: FixedWidthInteger {
    constants(
      "uint32_t",
      Value.allCases.map { (prefix + nativeName($0), hex($0.rawValue, digits: 1)) } + [
        (allName, hex(Value.allBits, digits: 1))
      ]
    )
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

  private static func usbSections() -> [[String]] {
    let usb = RuntimeUSBLimits.self
    let releases = usb.supportedReleases.map { hex($0, digits: 4) }.joined(separator: ", ")
    return [
      joined(
        constants(
          "uint32_t",
          [
            ("kSwifterKitUSBMaximumInterfaces", "\(usb.maximumInterfaces)"),
            ("kSwifterKitUSBMaximumPendingTransfers", "\(usb.maximumPendingTransfers)"),
            ("kSwifterKitUSBMaximumIsochronousFrames", "\(usb.maximumIsochronousFrames)"),
            ("kSwifterKitUSBMaximumBundleRings", "\(usb.maximumBundleRings)"),
            ("kSwifterKitUSBMaximumBundleRingEntries", "\(usb.maximumBundleRingEntries)"),
            ("kSwifterKitUSBMaximumBundleRingBytes", "\(usb.maximumBundleRingBytes)"),
            ("kSwifterKitUSBMaximumBundledTransfers", "\(usb.maximumBundledTransfers)"),
          ]
        ),
        ["static constexpr uint16_t kSwifterKitUSBSupportedReleases[] =", "    {\(releases)};"]
      ),
      joined(
        constants(
          "kSwifterKitUSBConfiguration",
          type: "uint8_t",
          RuntimeUSBConfigurationSelector.allCases
        ),
        constants(
          "kSwifterKitUSBPipeDescriptors",
          type: "uint8_t",
          [RuntimeUSBPipeDescriptorPolicy.original, .currentPolicy]
        )
      ),
    ]
  }

  /// The HID sections, which `renderHID()` writes to their own header.
  static func hidSections() -> [[String]] {
    let hid = RuntimeHIDLimits.self
    let collectionAll =
      RuntimeHIDCollectionFlag.allBits | RuntimeHIDCollectionChange.allBits
      << hid.collectionChangeShift
    return [
      constants(
        "uint32_t",
        [
          ("kSwifterKitHIDMaximumPendingReports", "\(hid.maximumPendingReports)"),
          ("kSwifterKitHIDMaximumFactoryDevices", "\(hid.maximumFactoryDevices)"),
          ("kSwifterKitHIDFactoryDeviceHeaderSize", "\(hid.factoryDeviceHeaderSize)"),
          ("kSwifterKitHIDFactoryHandleSize", "\(hid.factoryHandleSize)"),
          ("kSwifterKitHIDMaximumElementPage", "\(hid.maximumElementPage)"),
          ("kSwifterKitHIDMaximumCookies", "\(hid.maximumCookies)"),
          ("kSwifterKitHIDMaximumCollectionElements", "\(hid.maximumCollectionElements)"),
          ("kSwifterKitHIDMaximumTouches", "\(hid.maximumTouches)"),
          ("kSwifterKitHIDMaximumEventValues", "\(hid.maximumEventValues)"),
          ("kSwifterKitHIDLEDUsagePage", hex(hid.ledUsagePage, digits: 2)),
        ]
      ),
      enumeration(
        "SwifterKitHIDElementWriteKind",
        type: "uint32_t",
        RuntimeHIDElementWriteKind.allCases
      ),
      joined(
        bits(
          "kSwifterKitHIDHostReport",
          RuntimeHIDHostReportType.self,
          all: "kSwifterKitHIDHostReportTypesAll"
        ),
        bits(
          "kSwifterKitHIDGetReport",
          RuntimeHIDGetReportType.self,
          all: "kSwifterKitHIDGetReportTypesAll"
        ),
        bits("kSwifterKitHIDDeliver", RuntimeHIDEventDelivery.self, all: "kSwifterKitHIDDeliverAll")
      ),
      bits(
        "kSwifterKitHIDEventDriverCategory",
        RuntimeHIDEventDriverCategory.self,
        all: "kSwifterKitHIDEventDriverCategoriesAll"
      ),
      joined(
        bits(
          "kSwifterKitHIDStylus",
          RuntimeHIDStylusFlag.self,
          all: "kSwifterKitHIDStylusFlagsAll"
        ),
        bits("kSwifterKitHIDTouch", RuntimeHIDTouchFlag.self, all: "kSwifterKitHIDTouchFlagsAll"),
        bits(
          "kSwifterKitHIDCollection",
          RuntimeHIDCollectionFlag.self,
          all: "kSwifterKitHIDCollectionStateFlagsAll"
        ),
        bits(
          "kSwifterKitHIDCollectionChange",
          RuntimeHIDCollectionChange.self,
          all: "kSwifterKitHIDCollectionChangesAll"
        ),
        constants(
          "uint32_t",
          [
            ("kSwifterKitHIDCollectionChangeShift", "\(hid.collectionChangeShift)"),
            ("kSwifterKitHIDCollectionFlagsAll", hex(collectionAll, digits: 1)),
          ]
        ),
        bits(
          "kSwifterKitHIDGameController",
          RuntimeHIDGameControllerFlag.self,
          all: "kSwifterKitHIDGameControllerFlagsAll"
        )
      ),
    ]
  }
}
