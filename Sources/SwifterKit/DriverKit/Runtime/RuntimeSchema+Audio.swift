// Audio wire constants: object targets, event and value kinds, property selectors, state bits,
// and the bounds of the audio commands.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeAudioProtocol.h` and the `SwifterKitRuntimeAudio*.cpp` sources read, so
// neither side spells a value twice.

/// Bounds the audio commands, events, and generated configuration share with the extension.
enum RuntimeAudioLimits {
  /// The boxes or clock devices one driver declares, ``AudioObjectTarget/maximumTableCount``.
  static let objectTableCount = Int(AudioObjectTarget.maximumTableCount)
  /// The box and clock-device requests waiting for Swift at once.
  static let pendingRequestCount = 8
  /// The most sample rates a clock-device state reports.
  static let maximumReportedSampleRates = 64
  /// The most sample rates Swift or a configuration offers.
  static let maximumSampleRates = 16
  /// The lowest sample rate Swift or a configuration offers, in hertz.
  static let minimumSampleRate: Double = 8_000
  /// The highest sample rate Swift or a configuration offers, in hertz.
  static let maximumSampleRate: Double = 768_000
  /// The longest object, element, control, selector-item, or qualifier name, in UTF-8 bytes.
  static let nameMaximumLength = 255
  /// The longest custom-property value, in UTF-8 bytes.
  static let customPropertyValueMaximumLength = 4_096
  /// The most selectors one `PropertiesChanged` names.
  static let maximumChangedProperties = 32
  /// The streams one device declares.
  static let maximumStreams = 8
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
  /// The shortest zero-timestamp period, in sample frames.
  static let minimumZeroTimestampPeriod = 16
  /// The longest zero-timestamp period and the largest ring buffer, in sample frames.
  static let maximumFrameCount = 1_048_576
  /// The largest stream ring buffer, in bytes: 16 MiB.
  static let maximumRingBufferSize = 16_777_216
  /// The bytes of `SwifterKitAudioTransferHeader`, which precedes written stream bytes.
  static let transferHeaderSize = 24
  /// The most bytes one stream read returns: a response carries only the message header.
  static let maximumReadLength = RuntimeSchema.maximumMessageSize - RuntimeSchema.headerSize
  /// The most bytes one stream write carries, after the command and transfer headers.
  static let maximumWriteLength =
    maximumReadLength - RuntimeSchema.commandHeaderSize - transferHeaderSize
}

/// The object an audio command addresses, the `kind` of `SwifterKitAudioObjectTarget`.
enum RuntimeAudioTargetKind: UInt32, CaseIterable {
  case driver = 0
  case device = 1
  case box = 2
  case clock = 3
  case object = 4
}

/// What an `audio` event reports, the `kind` of `SwifterKitAudioEvent` and of the control and
/// custom-property event headers.
enum RuntimeAudioEventKind: UInt32, CaseIterable {
  case started = 1
  case stopped = 2
  case sampleRateChanged = 3
  case controlChanged = 4
  case customPropertyChanged = 5
  case streamFormatChanged = 6
  case streamActiveChanged = 7
}

/// What an `audioObject` event reports, the `kind` of `SwifterKitAudioObjectEvent`.
enum RuntimeAudioObjectEventKind: UInt32, CaseIterable {
  case deviceStarted = 1
  case deviceStopped = 2
  case clockStarted = 3
  case clockStopped = 4
  case clockRateChanged = 5
  /// A required box acquisition request.
  case boxRequest = 6
  /// A required clock-device sample-rate request.
  case clockRequest = 7
}

/// `SetDeviceProperty` selectors.
enum RuntimeAudioDeviceProperty: UInt32, CaseIterable {
  case canBeDefaultInput = 1
  case canBeDefaultOutput = 2
  case canBeDefaultSystemOutput = 3
  case inputSafetyOffset = 4
  case outputSafetyOffset = 5
  case preferredStereoChannels = 6
  case wantsStreamFormatsRestored = 7
}

/// `SetStreamProperty` selectors.
enum RuntimeAudioStreamProperty: UInt32, CaseIterable {
  case isActive = 1
  case latency = 2
  case startingChannel = 3
  case terminalType = 4
  case currentFormat = 5
  case ringBufferFrameCapacity = 6
}

/// `SetControlProperty` selectors.
enum RuntimeAudioControlProperty: UInt32, CaseIterable {
  case sliderRange = 1
  case panningChannels = 2
}

/// `SetBoxProperty` selectors.
enum RuntimeAudioBoxProperty: UInt32, CaseIterable {
  case transport = 1
  case hasAudio = 2
  case hasMIDI = 3
  case hasVideo = 4
  case isAcquirable = 5
  case isAcquired = 6
  case isProtected = 7
  case acquisitionFailure = 8
}

/// `SwifterKitAudioBoxState` flag bits.
enum RuntimeAudioBoxState: UInt32, CaseIterable {
  case hasAudio = 0x1
  case hasMIDI = 0x2
  case hasVideo = 0x4
  case isAcquirable = 0x8
  case isAcquired = 0x10
  case isProtected = 0x20
}

/// `SetClockDeviceProperty` selectors.
enum RuntimeAudioClockProperty: UInt32, CaseIterable {
  case clockDomain = 1
  case clockAlgorithm = 2
  case clockIsStable = 3
  case isAlive = 4
  case isHidden = 5
  case inputLatency = 6
  case outputLatency = 7
  case transport = 8
  case zeroTimestampPeriod = 9
  case wantsControlsRestored = 10
}

/// `SwifterKitAudioClockState` flag bits.
enum RuntimeAudioClockState: UInt32, CaseIterable {
  case clockIsStable = 0x1
  case isAlive = 0x2
  case isRunning = 0x4
  case isHidden = 0x8
  case supportsPrewarming = 0x10
}

/// What `SwifterKitAudioMemberAttachment` moves.
enum RuntimeAudioMemberKind: UInt32, CaseIterable {
  case stream = 1
  case control = 2
  case customProperty = 3
}

/// The control representations a value carries. The public type carries the wire values.
typealias RuntimeAudioValueKind = AudioControlValueKind

/// The kinds of configured controls. The public type carries the wire values.
typealias RuntimeAudioControlKind = AudioControlInfo.Kind

/// Where a custom property sits. The public type carries the wire values.
typealias RuntimeAudioOwner = AudioMemberOwner

/// Which per-element string an element-name command addresses. The public type carries the
/// wire values.
typealias RuntimeAudioElementNameKind = AudioElementNameKind
