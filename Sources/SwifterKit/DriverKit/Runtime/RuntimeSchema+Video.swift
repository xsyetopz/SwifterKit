// Video wire constants: object targets, event and value kinds, property selectors, state bits,
// and the bounds of the video commands.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeVideoProtocol.h` and the `SwifterKitRuntimeVideo*.cpp` sources read, so
// neither side spells a value twice. The header declares plain integers, so an extension built
// without VideoDriverKit still compiles it.

/// Bounds the video commands, events, and generated configuration share with the extension.
enum RuntimeVideoLimits {
  /// The boxes or clock devices one driver declares, ``VideoObjectTarget/maximumTableCount``.
  static let objectTableCount = Int(VideoObjectTarget.maximumTableCount)
  /// The box and clock-device requests waiting for Swift at once.
  static let pendingRequestCount = 8
  /// The most sample rates Swift, a configuration, or a clock-device state carries.
  static let maximumSampleRates = 16
  /// The longest object, element, control, selector-item, or qualifier name, in UTF-8 bytes.
  static let nameMaximumLength = 255
  /// The longest custom-property value, in UTF-8 bytes.
  static let customPropertyValueMaximumLength = 4_096
  /// The most selectors one `PropertiesChanged` names.
  static let maximumChangedProperties = 32
  /// The streams one device declares.
  static let maximumStreams = 8
  /// The buffers one stream declares.
  static let maximumBuffers = 32
  /// The controls one device declares.
  static let maximumControls = 64
  /// The custom properties one device declares.
  static let maximumCustomProperties = 32
  /// The formats one stream offers.
  static let maximumStreamFormats = 16
  /// The items one selector control offers or selects, and the values one control value carries.
  static let maximumSelectorItems = 32
  /// The labels one preferred channel layout carries.
  static let maximumChannelLabels = 64
  /// The most entries one stream queue holds.
  static let maximumQueueEntries = 256
  /// The largest data plane `SetStreamProperty` gives a buffer, in bytes: 64 MiB.
  static let maximumDataCapacity = 67_108_864
  /// The largest control plane `SetStreamProperty` gives a buffer, in bytes: 1 MiB.
  static let maximumControlCapacity = 1_048_576
  /// The bytes of `SwifterKitVideoTransferHeader`, which begins a buffer read or write.
  static let transferHeaderSize = 32
  /// The most bytes one buffer read returns: the most a transfer request may name.
  static let maximumReadLength =
    RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize - RuntimeSchema.commandHeaderSize
    - transferHeaderSize
  /// The most bytes one buffer write carries, one transfer header below the largest read.
  static let maximumWriteLength = maximumReadLength - transferHeaderSize
}

/// The object a video command addresses, the `kind` of `SwifterKitVideoObjectTarget`.
enum RuntimeVideoTargetKind: UInt32, CaseIterable {
  case driver = 0
  case device = 1
  case box = 2
  case clock = 3
  case object = 4
}

/// What a `video` event reports, the `kind` of `SwifterKitVideoEvent`, of the control and
/// custom-property event headers, and of `SwifterKitVideoStreamFormatEvent`.
enum RuntimeVideoEventKind: UInt32, CaseIterable {
  case started = 1
  case stopped = 2
  case sampleRateChanged = 3
  case controlChanged = 4
  case customPropertyChanged = 5
  case streamStarted = 6
  case streamStopped = 7
  case streamFormatChanged = 8
  case streamActiveChanged = 9
  case streamInputAvailable = 10
}

/// What a `videoObject` event reports, the `kind` of `SwifterKitVideoObjectEvent`.
enum RuntimeVideoObjectEventKind: UInt32, CaseIterable {
  case deviceStarted = 1
  case deviceStopped = 2
  case clockStarted = 3
  case clockStopped = 4
  case clockRateChanged = 5
  /// A required box acquisition request.
  case boxRequest = 6
  /// A required clock-device sample-rate request.
  case clockRequest = 7
  case clockFormatChanged = 8
  case deviceFormatChanged = 9
}

/// `SetDeviceProperty` selectors.
enum RuntimeVideoDeviceProperty: UInt32, CaseIterable {
  case canBeDefaultInput = 1
  case canBeDefaultOutput = 2
  case canBeDefaultSystemOutput = 3
  case inputSafetyOffset = 4
  case outputSafetyOffset = 5
  case preferredStereoChannels = 6
}

/// `SetStreamProperty` selectors.
enum RuntimeVideoStreamProperty: UInt32, CaseIterable {
  case isActive = 1
  case startingChannel = 2
  case terminalType = 3
  case currentFormat = 4
  case bufferCapacity = 5
  case queueEntryCount = 6
}

/// `SetBufferProperty` selectors.
enum RuntimeVideoBufferProperty: UInt32, CaseIterable {
  case bufferID = 1
  case isAttached = 2
}

/// `SetControlProperty` selectors.
enum RuntimeVideoControlProperty: UInt32, CaseIterable {
  case sliderRange = 1
  case panningChannels = 2
}

/// `SetBoxProperty` selectors.
enum RuntimeVideoBoxProperty: UInt32, CaseIterable {
  case transport = 1
  case hasAudio = 2
  case hasMIDI = 3
  case hasVideo = 4
  case isAcquirable = 5
  case isAcquired = 6
  case isProtected = 7
  case acquisitionFailure = 8
}

/// `SwifterKitVideoBoxState` flag bits.
enum RuntimeVideoBoxState: UInt32, CaseIterable {
  case hasAudio = 0x1
  case hasMIDI = 0x2
  case hasVideo = 0x4
  case isAcquirable = 0x8
  case isAcquired = 0x10
  case isProtected = 0x20
}

/// `SetClockDeviceProperty` selectors.
enum RuntimeVideoClockProperty: UInt32, CaseIterable {
  case clockDomain = 1
  case clockAlgorithm = 2
  case clockIsStable = 3
  case isAlive = 4
  case isHidden = 5
  case inputLatency = 6
  case outputLatency = 7
  case transport = 8
}

/// `SwifterKitVideoClockState` flag bits.
enum RuntimeVideoClockState: UInt32, CaseIterable {
  case clockIsStable = 0x1
  case isAlive = 0x2
  case isRunning = 0x4
  case isHidden = 0x8
}

/// What `SwifterKitVideoMemberAttachment` moves.
enum RuntimeVideoMemberKind: UInt32, CaseIterable {
  case stream = 1
  case control = 2
}

/// The control representations a value carries. The public type carries the wire values.
typealias RuntimeVideoValueKind = VideoControlValueKind

/// The kinds of configured controls. The public type carries the wire values.
typealias RuntimeVideoControlKind = VideoControlInfo.Kind

/// Where a custom property sits. The public type carries the wire values.
typealias RuntimeVideoOwner = VideoCustomPropertyOwner

/// Which per-element string an element-name command addresses. The public type carries the
/// wire values.
typealias RuntimeVideoElementNameKind = VideoElementNameKind

/// Which host notification `SwifterKitVideoQueueNotification` sends. The public type carries
/// the wire values.
typealias RuntimeVideoQueueNotification = VideoBufferQueueNotification

/// A stream's direction. The public type carries the wire values.
typealias RuntimeVideoDirection = VideoStreamDirection

/// A buffer plane a transfer addresses. The public type carries the wire values.
typealias RuntimeVideoPlane = VideoBufferPlane
