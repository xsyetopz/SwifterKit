/// Renders the audio schema declarations under the native names the extension uses.
extension RuntimeSchemaHeader {
  static func audioSections() -> [[String]] {
    let audio = RuntimeAudioLimits.self
    return [
      joined(
        constants(
          "uint32_t",
          [
            ("kSwifterKitAudioObjectTableCount", "\(audio.objectTableCount)"),
            ("kSwifterKitAudioPendingRequestCount", "\(audio.pendingRequestCount)"),
            ("kSwifterKitAudioMaximumSampleRates", "\(audio.maximumReportedSampleRates)"),
            ("kSwifterKitAudioMaximumSettableSampleRates", "\(audio.maximumSampleRates)"),
            ("kSwifterKitAudioNameMaximumLength", "\(audio.nameMaximumLength)"),
            (
              "kSwifterKitAudioCustomPropertyValueMaximumLength",
              "\(audio.customPropertyValueMaximumLength)"
            ), ("kSwifterKitAudioMaximumChangedProperties", "\(audio.maximumChangedProperties)"),
            ("kSwifterKitAudioMaximumStreams", "\(audio.maximumStreams)"),
            ("kSwifterKitAudioMaximumControls", "\(audio.maximumControls)"),
            ("kSwifterKitAudioMaximumCustomProperties", "\(audio.maximumCustomProperties)"),
            ("kSwifterKitAudioMaximumStreamFormats", "\(audio.maximumStreamFormats)"),
            ("kSwifterKitAudioMaximumSelectorItems", "\(audio.maximumSelectorItems)"),
            ("kSwifterKitAudioMaximumChannelLabels", "\(audio.maximumChannelLabels)"),
            ("kSwifterKitAudioMinimumZeroTimestampPeriod", "\(audio.minimumZeroTimestampPeriod)"),
            ("kSwifterKitAudioMaximumFrameCount", "\(audio.maximumFrameCount)"),
            ("kSwifterKitAudioMaximumRingBufferSize", "\(audio.maximumRingBufferSize)"),
            ("kSwifterKitAudioMaximumReadLength", "\(audio.maximumReadLength)"),
            ("kSwifterKitAudioMaximumWriteLength", "\(audio.maximumWriteLength)"),
            ("kSwifterKitAudioTransferHeaderSize", "\(audio.transferHeaderSize)"),
          ]
        ),
        constants(
          "double",
          [
            ("kSwifterKitAudioMinimumSampleRate", "\(audio.minimumSampleRate)"),
            ("kSwifterKitAudioMaximumSampleRate", "\(audio.maximumSampleRate)"),
          ]
        )
      ),
      joined(
        constants("kSwifterKitAudioTarget", type: "uint32_t", RuntimeAudioTargetKind.allCases),
        constants(
          "kSwifterKitAudioOwner",
          type: "uint32_t",
          [RuntimeAudioOwner.detached, .device, .driver]
        ),
        constants(
          "kSwifterKitAudioElement",
          type: "uint32_t",
          [RuntimeAudioElementNameKind.name, .category, .number]
        ),
        constants("kSwifterKitAudioMember", type: "uint32_t", RuntimeAudioMemberKind.allCases)
      ),
      joined(
        constants("kSwifterKitAudioEvent", type: "uint32_t", RuntimeAudioEventKind.allCases),
        constants(
          "kSwifterKitAudioObjectEvent",
          type: "uint32_t",
          RuntimeAudioObjectEventKind.allCases
        )
      ),
      joined(
        constants(
          "kSwifterKitAudioValue",
          type: "uint32_t",
          [RuntimeAudioValueKind.boolean, .decibels, .scalar, .selector, .slider, .stereoPan]
        ),
        constants(
          "kSwifterKitAudioControl",
          type: "uint32_t",
          [RuntimeAudioControlKind.boolean, .level, .selector, .slider, .stereoPan]
        )
      ),
      joined(
        constants(
          "kSwifterKitAudioDeviceProperty",
          type: "uint32_t",
          RuntimeAudioDeviceProperty.allCases
        ),
        constants(
          "kSwifterKitAudioStreamProperty",
          type: "uint32_t",
          RuntimeAudioStreamProperty.allCases
        ),
        constants(
          "kSwifterKitAudioControlProperty",
          type: "uint32_t",
          RuntimeAudioControlProperty.allCases
        ),
        constants(
          "kSwifterKitAudioBoxProperty",
          type: "uint32_t",
          RuntimeAudioBoxProperty.allCases
        ),
        constants(
          "kSwifterKitAudioClockProperty",
          type: "uint32_t",
          RuntimeAudioClockProperty.allCases
        )
      ),
      joined(
        bits(
          "kSwifterKitAudioBoxState",
          RuntimeAudioBoxState.self,
          all: "kSwifterKitAudioBoxStateAll"
        ),
        bits(
          "kSwifterKitAudioClockState",
          RuntimeAudioClockState.self,
          all: "kSwifterKitAudioClockStateAll"
        )
      ),
    ]
  }
}
