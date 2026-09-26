import Foundation

/// A Core Audio channel label for a preferred channel layout.
public struct AudioChannelLabel: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IOUserAudioChannelLabel` value.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserAudioChannelLabel` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The channel carries no signal.
  public static let unused = Self(rawValue: 0)
  /// Front left.
  public static let left = Self(rawValue: 1)
  /// Front right.
  public static let right = Self(rawValue: 2)
  /// Front center.
  public static let center = Self(rawValue: 3)
  /// Low-frequency effects.
  public static let lfeScreen = Self(rawValue: 4)
  /// Surround left.
  public static let leftSurround = Self(rawValue: 5)
  /// Surround right.
  public static let rightSurround = Self(rawValue: 6)
}

/// The kind of terminal an AudioDriverKit stream connects to.
public struct AudioStreamTerminalType: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IOUserAudioStreamTerminalType` value.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserAudioStreamTerminalType` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The terminal type is not known.
  public static let unknown = Self(rawValue: 0)
  /// A line-level connection.
  public static let line = Self(rawValue: 0x6C69_6E65)
  /// A digital audio interface such as S/PDIF.
  public static let digitalAudioInterface = Self(rawValue: 0x7370_6466)
  /// A speaker.
  public static let speaker = Self(rawValue: 0x7370_6B72)
  /// Headphones.
  public static let headphones = Self(rawValue: 0x6864_7068)
  /// A microphone.
  public static let microphone = Self(rawValue: 0x6D69_6372)
  /// HDMI.
  public static let hdmi = Self(rawValue: 0x6864_6D69)
  /// DisplayPort.
  public static let displayPort = Self(rawValue: 0x6470_7274)
}

/// A snapshot of `IOUserAudioDevice` state that has no other typed reader.
public struct AudioDeviceState: Sendable, Hashable {
  /// The device's audio object ID.
  public let objectID: UInt32
  /// `CanBeDefaultInputDevice`.
  public let canBeDefaultInput: Bool
  /// `CanBeDefaultOutputDevice`.
  public let canBeDefaultOutput: Bool
  /// `CanBeDefaultSystemOutputDevice`.
  public let canBeDefaultSystemOutput: Bool
  /// `GetInputSafetyOffset`, in frames.
  public let inputSafetyOffset: UInt32
  /// `GetOutputSafetyOffset`, in frames.
  public let outputSafetyOffset: UInt32
  /// `GetPreferredChannelsForStereo`, as one-based channel numbers.
  public let preferredStereoChannels: AudioStereoChannels
  /// `GetCurrentClientIOTime` for input: the client's sample time and host time.
  public let inputClientTime: AudioClientIOTime
  /// `GetCurrentClientIOTime` for output: the client's sample time and host time.
  public let outputClientTime: AudioClientIOTime

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 64 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    let flags: [UInt32] = try [4, 8, 12].map { try runtimePayload.readRuntimeInteger(at: $0) }
    guard flags.allSatisfy({ $0 <= 1 }) else { throw AudioRuntimeError.invalidPayload }
    canBeDefaultInput = flags[0] == 1
    canBeDefaultOutput = flags[1] == 1
    canBeDefaultSystemOutput = flags[2] == 1
    inputSafetyOffset = try runtimePayload.readRuntimeInteger(at: 16)
    outputSafetyOffset = try runtimePayload.readRuntimeInteger(at: 20)
    preferredStereoChannels = AudioStereoChannels(
      left: try runtimePayload.readRuntimeInteger(at: 24),
      right: try runtimePayload.readRuntimeInteger(at: 28)
    )
    inputClientTime = AudioClientIOTime(
      sampleTime: try runtimePayload.readRuntimeInteger(at: 32),
      hostTime: try runtimePayload.readRuntimeInteger(at: 40)
    )
    outputClientTime = AudioClientIOTime(
      sampleTime: try runtimePayload.readRuntimeInteger(at: 48),
      hostTime: try runtimePayload.readRuntimeInteger(at: 56)
    )
  }
}

/// A left and right channel pair.
public struct AudioStereoChannels: Sendable, Hashable {
  /// The left channel or element.
  public let left: UInt32
  /// The right channel or element.
  public let right: UInt32
  /// Creates a channel pair.
  public init(left: UInt32, right: UInt32) {
    self.left = left
    self.right = right
  }
}

/// A sample-time and host-time pair from the client's ring-buffer position.
public struct AudioClientIOTime: Sendable, Hashable {
  /// The client's current sample time.
  public let sampleTime: UInt64
  /// The host time paired with `sampleTime`.
  public let hostTime: UInt64
}

/// One settable `IOUserAudioDevice` property.
public enum AudioDeviceProperty: Sendable, Hashable {
  /// `SetCanBeDefaultInputDevice`.
  case canBeDefaultInput(Bool)
  /// `SetCanBeDefaultOutputDevice`.
  case canBeDefaultOutput(Bool)
  /// `SetCanBeDefaultSystemOutputDevice`.
  case canBeDefaultSystemOutput(Bool)
  /// `SetInputSafetyOffset`, in frames.
  case inputSafetyOffset(UInt32)
  /// `SetOutputSafetyOffset`, in frames.
  case outputSafetyOffset(UInt32)
  /// `SetPreferredChannelsForStereo`, as one-based channel numbers.
  case preferredStereoChannels(AudioStereoChannels)
  /// `SetWantsStreamFormatsRestored`.
  case wantsStreamFormatsRestored(Bool)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .canBeDefaultInput(let flag): (1, flag ? 1 : 0)
    case .canBeDefaultOutput(let flag): (2, flag ? 1 : 0)
    case .canBeDefaultSystemOutput(let flag): (3, flag ? 1 : 0)
    case .inputSafetyOffset(let frames): (4, UInt64(frames))
    case .outputSafetyOffset(let frames): (5, UInt64(frames))
    case .preferredStereoChannels(let pair): (6, UInt64(pair.left) | UInt64(pair.right) << 32)
    case .wantsStreamFormatsRestored(let flag): (7, flag ? 1 : 0)
    }
  }
}

/// A snapshot of one configured `IOUserAudioStream`.
public struct AudioStreamState: Sendable, Hashable {
  /// The stream's audio object ID, usable with ``AudioObjectTarget/object(_:)``.
  public let objectID: UInt32
  /// `GetStreamDirection`.
  public let direction: AudioStreamDirection
  /// `GetTerminalType`.
  public let terminalType: AudioStreamTerminalType
  /// `GetStartingChannel`.
  public let startingChannel: UInt32
  /// `GetLatency`, in frames.
  public let latency: UInt32
  /// `GetStreamIsActive`.
  public let isActive: Bool
  /// Whether the stream is currently added to the device.
  public let isAttached: Bool
  /// Byte length of the descriptor `GetIOMemoryDescriptor` returns.
  public let memoryLength: UInt64
  /// `GetCurrentStreamFormat`.
  public let currentFormat: AudioStreamFormat
  /// `GetAvailableStreamFormats`.
  public let availableFormats: [AudioStreamFormat]

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 80 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    let rawDirection: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    guard let direction = AudioStreamDirection(rawValue: rawDirection) else {
      throw AudioRuntimeError.invalidPayload
    }
    self.direction = direction
    terminalType = AudioStreamTerminalType(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    startingChannel = try runtimePayload.readRuntimeInteger(at: 12)
    latency = try runtimePayload.readRuntimeInteger(at: 16)
    let active: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    let attached: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
    let count = Int(try runtimePayload.readRuntimeInteger(at: 28) as UInt32)
    guard active <= 1, attached <= 1, count <= 16, runtimePayload.count == 80 + count * 40 else {
      throw AudioRuntimeError.invalidPayload
    }
    isActive = active == 1
    isAttached = attached == 1
    memoryLength = try runtimePayload.readRuntimeInteger(at: 32)
    currentFormat = try Self.format(runtimePayload, at: 40)
    availableFormats = try (0..<count).map { try Self.format(runtimePayload, at: 80 + $0 * 40) }
  }

  private static func format(_ data: Data, at offset: Int) throws -> AudioStreamFormat {
    let reserved: UInt32 = try data.readRuntimeInteger(at: offset + 36)
    guard reserved == 0 else { throw AudioRuntimeError.invalidPayload }
    return AudioStreamFormat(
      sampleRate: Double(bitPattern: try data.readRuntimeInteger(at: offset)),
      formatID: AudioFormatID(rawValue: try data.readRuntimeInteger(at: offset + 8)),
      formatFlags: AudioFormatFlags(rawValue: try data.readRuntimeInteger(at: offset + 12)),
      bytesPerPacket: try data.readRuntimeInteger(at: offset + 16),
      framesPerPacket: try data.readRuntimeInteger(at: offset + 20),
      bytesPerFrame: try data.readRuntimeInteger(at: offset + 24),
      channelsPerFrame: try data.readRuntimeInteger(at: offset + 28),
      bitsPerChannel: try data.readRuntimeInteger(at: offset + 32)
    )
  }
}

/// One settable `IOUserAudioStream` property.
public enum AudioStreamProperty: Sendable, Hashable {
  /// `SetStreamIsActive`.
  case isActive(Bool)
  /// `SetLatency`, in frames.
  case latency(UInt32)
  /// `SetStartingChannel`, one-based.
  case startingChannel(UInt32)
  /// `SetTerminalType`.
  case terminalType(AudioStreamTerminalType)
  /// `SetCurrentStreamFormat`, by index into the stream's available formats.
  case currentFormat(index: UInt32)
  /// Replaces the ring buffer through `SetIOMemoryDescriptor` with one sized for this many
  /// frames of the widest available format. The old contents are discarded.
  case ringBufferFrameCapacity(UInt32)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .isActive(let flag): (1, flag ? 1 : 0)
    case .latency(let frames): (2, UInt64(frames))
    case .startingChannel(let channel): (3, UInt64(channel))
    case .terminalType(let type): (4, UInt64(type.rawValue))
    case .currentFormat(let index): (5, UInt64(index))
    case .ringBufferFrameCapacity(let frames): (6, UInt64(frames))
    }
  }
}

/// A snapshot of one configured `IOUserAudioControl`.
public struct AudioControlInfo: Sendable, Hashable {
  /// The concrete control class the runtime created.
  public enum Kind: UInt32, Sendable, Hashable {
    case boolean = 1
    case level = 2
    case selector = 3
    case slider = 4
    case stereoPan = 5
  }

  /// The control's audio object ID, usable with ``AudioObjectTarget/object(_:)``.
  public let objectID: UInt32
  /// The concrete control class.
  public let kind: Kind
  /// `GetControlScope`.
  public let scope: AudioObjectScope
  /// `GetControlElement`.
  public let element: UInt32
  /// `GetIsSettable`.
  public let isSettable: Bool
  /// Whether the control is currently added to the device.
  public let isAttached: Bool
  /// `IOUserAudioSliderControl::GetRange`, for slider controls.
  public let sliderRange: ClosedRange<UInt32>?
  /// `IOUserAudioStereoPanControl::GetPanningChannels`, for stereo-pan controls.
  public let panningChannels: AudioStereoChannels?
  /// `IOUserAudioSelectorControl::GetControlValueDescriptions`, for selector controls.
  public let selectorItems: [AudioSelectorValue]

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 48 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    guard let kind = Kind(rawValue: try runtimePayload.readRuntimeInteger(at: 4)) else {
      throw AudioRuntimeError.invalidPayload
    }
    self.kind = kind
    scope = AudioObjectScope(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    element = try runtimePayload.readRuntimeInteger(at: 12)
    let settable: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
    let attached: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    let minimum: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
    let maximum: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    let left: UInt32 = try runtimePayload.readRuntimeInteger(at: 32)
    let right: UInt32 = try runtimePayload.readRuntimeInteger(at: 36)
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 40)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 44)
    guard settable <= 1, attached <= 1, reserved == 0, count <= 32, kind == .selector || count == 0,
      kind != .slider || minimum <= maximum
    else { throw AudioRuntimeError.invalidPayload }
    isSettable = settable == 1
    isAttached = attached == 1
    sliderRange = kind == .slider ? minimum...maximum : nil
    panningChannels = kind == .stereoPan ? AudioStereoChannels(left: left, right: right) : nil
    var items: [AudioSelectorValue] = []
    var offset = 48
    for _ in 0..<count {
      let value: UInt32 = try runtimePayload.readRuntimeInteger(at: offset)
      let length = Int(try runtimePayload.readRuntimeInteger(at: offset + 4) as UInt32)
      let end = offset + 8 + length
      guard length <= 255, end <= runtimePayload.count,
        let name = String(data: runtimePayload[(offset + 8)..<end], encoding: .utf8)
      else { throw AudioRuntimeError.invalidPayload }
      items.append(AudioSelectorValue(value: value, name: name))
      offset = end
    }
    guard offset == runtimePayload.count else { throw AudioRuntimeError.invalidPayload }
    selectorItems = items
  }
}

/// One settable control property beyond the control's value.
public enum AudioControlProperty: Sendable, Hashable {
  /// `IOUserAudioSliderControl::SetRange`.
  case sliderRange(ClosedRange<UInt32>)
  /// `IOUserAudioStereoPanControl::SetPanningChannels`.
  case panningChannels(AudioStereoChannels)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .sliderRange(let range): (1, UInt64(range.lowerBound) | UInt64(range.upperBound) << 32)
    case .panningChannels(let pair): (2, UInt64(pair.left) | UInt64(pair.right) << 32)
    }
  }
}

/// The data type of a custom property's value or qualifier.
public struct AudioCustomPropertyDataType: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IOUserAudioCustomPropertyDataType` value.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserAudioCustomPropertyDataType` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// No data.
  public static let none = Self(rawValue: 0)
  /// A string.
  public static let string = Self(rawValue: 0x6366_7374)
  /// A property-list dictionary.
  public static let dictionary = Self(rawValue: 0x706C_7374)
}

/// The object a stream, control, or custom property is added to.
public enum AudioMemberOwner: UInt32, Sendable, Hashable {
  /// Removed from its owner; configuration and values are kept.
  case detached = 0
  /// Added to the `IOUserAudioDevice`.
  case device = 1
  /// Added to the `IOUserAudioDriver`; only custom properties accept this owner.
  case driver = 2
}

/// A configured stream, control, or custom property.
public enum AudioMember: Sendable, Hashable {
  /// A stream, by its index in ``AudioDeviceConfiguration/streams``.
  case stream(UInt32)
  /// A control, by its identifier.
  case control(UInt32)
  /// A custom property, by its identifier.
  case customProperty(UInt32)

  var runtimeFields: (kind: UInt32, identifier: UInt32) {
    switch self {
    case .stream(let index): (1, index)
    case .control(let identifier): (2, identifier)
    case .customProperty(let identifier): (3, identifier)
    }
  }
}

/// A snapshot of one configured `IOUserAudioCustomProperty`.
public struct AudioCustomPropertyInfo: Sendable, Hashable {
  /// The property's audio object ID.
  public let objectID: UInt32
  /// `GetCustomPropertyInfo().mSelector`.
  public let selector: UInt32
  /// `GetCustomPropertyInfo().mPropertyDataType`.
  public let propertyDataType: AudioCustomPropertyDataType
  /// `GetCustomPropertyInfo().mQualifierDataType`.
  public let qualifierDataType: AudioCustomPropertyDataType
  /// The object the property is currently added to.
  public let owner: AudioMemberOwner

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    selector = try runtimePayload.readRuntimeInteger(at: 4)
    propertyDataType = AudioCustomPropertyDataType(
      rawValue: try runtimePayload.readRuntimeInteger(at: 8)
    )
    qualifierDataType = AudioCustomPropertyDataType(
      rawValue: try runtimePayload.readRuntimeInteger(at: 12)
    )
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    guard reserved == 0,
      let owner = AudioMemberOwner(rawValue: try runtimePayload.readRuntimeInteger(at: 16))
    else { throw AudioRuntimeError.invalidPayload }
    self.owner = owner
  }
}
