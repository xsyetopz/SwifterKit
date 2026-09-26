/// Renders the video schema declarations under the native names the extension uses.
extension RuntimeSchemaHeader {
  static func videoSections() -> [[String]] {
    let video = RuntimeVideoLimits.self
    return [
      constants(
        "uint32_t",
        [
          ("kSwifterKitVideoObjectTableCount", "\(video.objectTableCount)"),
          ("kSwifterKitVideoPendingRequestCount", "\(video.pendingRequestCount)"),
          ("kSwifterKitVideoMaximumSampleRates", "\(video.maximumSampleRates)"),
          ("kSwifterKitVideoNameMaximumLength", "\(video.nameMaximumLength)"),
          (
            "kSwifterKitVideoCustomPropertyValueMaximumLength",
            "\(video.customPropertyValueMaximumLength)"
          ), ("kSwifterKitVideoMaximumChangedProperties", "\(video.maximumChangedProperties)"),
          ("kSwifterKitVideoMaximumStreams", "\(video.maximumStreams)"),
          ("kSwifterKitVideoMaximumBuffers", "\(video.maximumBuffers)"),
          ("kSwifterKitVideoMaximumControls", "\(video.maximumControls)"),
          ("kSwifterKitVideoMaximumCustomProperties", "\(video.maximumCustomProperties)"),
          ("kSwifterKitVideoMaximumStreamFormats", "\(video.maximumStreamFormats)"),
          ("kSwifterKitVideoMaximumSelectorItems", "\(video.maximumSelectorItems)"),
          ("kSwifterKitVideoMaximumChannelLabels", "\(video.maximumChannelLabels)"),
          ("kSwifterKitVideoMaximumQueueEntries", "\(video.maximumQueueEntries)"),
          ("kSwifterKitVideoMaximumDataCapacity", "\(video.maximumDataCapacity)"),
          ("kSwifterKitVideoMaximumControlCapacity", "\(video.maximumControlCapacity)"),
          ("kSwifterKitVideoTransferHeaderSize", "\(video.transferHeaderSize)"),
          ("kSwifterKitVideoMaximumReadLength", "\(video.maximumReadLength)"),
          ("kSwifterKitVideoMaximumWriteLength", "\(video.maximumWriteLength)"),
        ]
      ),
      joined(
        constants("kSwifterKitVideoTarget", type: "uint32_t", RuntimeVideoTargetKind.allCases),
        constants(
          "kSwifterKitVideoOwner",
          type: "uint32_t",
          [RuntimeVideoOwner.detached, .device, .driver]
        ),
        constants(
          "kSwifterKitVideoElement",
          type: "uint32_t",
          [RuntimeVideoElementNameKind.name, .category, .number]
        ),
        constants("kSwifterKitVideoMember", type: "uint32_t", RuntimeVideoMemberKind.allCases),
        constants(
          "kSwifterKitVideoNotify",
          type: "uint32_t",
          [
            RuntimeVideoQueueNotification.bufferQueueChange, .outputBufferNotification,
            .streamBufferQueueChange,
          ]
        ),
        constants(
          "kSwifterKitVideoDirection",
          type: "uint32_t",
          [RuntimeVideoDirection.output, .input]
        ),
        constants("kSwifterKitVideoPlane", type: "uint32_t", [RuntimeVideoPlane.data, .control])
      ),
      joined(
        constants("kSwifterKitVideoEvent", type: "uint32_t", RuntimeVideoEventKind.allCases),
        constants(
          "kSwifterKitVideoObjectEvent",
          type: "uint32_t",
          RuntimeVideoObjectEventKind.allCases
        )
      ),
      joined(
        constants(
          "kSwifterKitVideoValue",
          type: "uint32_t",
          [
            RuntimeVideoValueKind.boolean, .decibels, .scalar, .selector, .slider, .stereoPan,
            .direction,
          ]
        ),
        constants(
          "kSwifterKitVideoControl",
          type: "uint32_t",
          [RuntimeVideoControlKind.boolean, .level, .selector, .slider, .stereoPan, .direction]
        )
      ),
      joined(
        constants(
          "kSwifterKitVideoDeviceProperty",
          type: "uint32_t",
          RuntimeVideoDeviceProperty.allCases
        ),
        constants(
          "kSwifterKitVideoStreamProperty",
          type: "uint32_t",
          RuntimeVideoStreamProperty.allCases
        ),
        constants(
          "kSwifterKitVideoBufferProperty",
          type: "uint32_t",
          RuntimeVideoBufferProperty.allCases
        ),
        constants(
          "kSwifterKitVideoControlProperty",
          type: "uint32_t",
          RuntimeVideoControlProperty.allCases
        ),
        constants(
          "kSwifterKitVideoBoxProperty",
          type: "uint32_t",
          RuntimeVideoBoxProperty.allCases
        ),
        constants(
          "kSwifterKitVideoClockProperty",
          type: "uint32_t",
          RuntimeVideoClockProperty.allCases
        )
      ),
      joined(
        bits(
          "kSwifterKitVideoBoxState",
          RuntimeVideoBoxState.self,
          all: "kSwifterKitVideoBoxStateAll"
        ),
        bits(
          "kSwifterKitVideoClockState",
          RuntimeVideoClockState.self,
          all: "kSwifterKitVideoClockStateAll"
        )
      ),
    ]
  }
}
