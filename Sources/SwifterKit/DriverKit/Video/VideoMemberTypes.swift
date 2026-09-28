import Foundation

/// An `IOUserVideoChannelLabel` for a preferred channel layout.
public struct VideoChannelLabel: RawRepresentable, Sendable, Hashable {
  /// The raw `IOUserVideoChannelLabel` value passed to the runtime.
  public let rawValue: UInt32
  /// Creates a channel label from its unmodified `IOUserVideoChannelLabel` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Maps to the `IOUserVideoChannelLabel` value for an unknown channel.
  public static let unknown = Self(rawValue: 0xFFFF_FFFF)
  /// Maps to the `IOUserVideoChannelLabel` value for an unused channel.
  public static let unused = Self(rawValue: 0)
  /// Maps to the `IOUserVideoChannelLabel` value for the left channel.
  public static let left = Self(rawValue: 1)
  /// Maps to the `IOUserVideoChannelLabel` value for the right channel.
  public static let right = Self(rawValue: 2)
  /// Maps to the `IOUserVideoChannelLabel` value for the center channel.
  public static let center = Self(rawValue: 3)
}

/// An `IOUserVideoStreamTerminalType`.
public struct VideoStreamTerminalType: RawRepresentable, Sendable, Hashable {
  /// The raw `IOUserVideoStreamTerminalType` value passed to the runtime.
  public let rawValue: UInt32
  /// Creates a terminal type from its unmodified native value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Maps to the native terminal type for an unspecified endpoint.
  public static let unknown = Self(rawValue: 0)
  /// Maps to the native terminal type for a line connection.
  public static let line = Self(rawValue: 0x6C69_6E65)
  /// Maps to the native terminal type for a digital video interface.
  public static let digitalVideoInterface = Self(rawValue: 0x7370_6466)
  /// Maps to the native terminal type for a speaker endpoint.
  public static let speaker = Self(rawValue: 0x7370_6B72)
  /// Maps to the native terminal type for a headphone endpoint.
  public static let headphones = Self(rawValue: 0x6864_7068)
  /// Maps to the native terminal type for a microphone endpoint.
  public static let microphone = Self(rawValue: 0x6D69_6372)
}

/// A left and right channel pair.
public struct VideoStereoChannels: Sendable, Hashable {
  /// The `IOUserVideoChannelLabel` value for the left preferred stereo channel.
  public let left: UInt32
  /// The `IOUserVideoChannelLabel` value for the right preferred stereo channel.
  public let right: UInt32
  /// Creates a preferred stereo channel pair from its left and right labels.
  public init(left: UInt32, right: UInt32) {
    self.left = left
    self.right = right
  }
}

/// A client's current I/O position from `GetCurrentClientIOTime`.
public struct VideoClientIOTime: Sendable, Hashable {
  /// The sample position returned by `GetCurrentClientIOTime`.
  public let sampleTime: UInt64
  /// The host clock time returned by `GetCurrentClientIOTime`.
  public let hostTime: UInt64
}

/// `IOUserVideoDevice` state that has no other typed reader.
public struct VideoDeviceState: Sendable, Hashable {
  /// The `IOUserVideoDevice` object identifier.
  public let objectID: UInt32
  /// Whether the device can serve as the default input.
  public let canBeDefaultInput: Bool
  /// Whether the device can serve as the default output.
  public let canBeDefaultOutput: Bool
  /// Whether the device can serve as the default system output.
  public let canBeDefaultSystemOutput: Bool
  /// The input safety offset in audio frames.
  public let inputSafetyOffset: UInt32
  /// The output safety offset in audio frames.
  public let outputSafetyOffset: UInt32
  /// The left and right labels for the device preferred stereo channels.
  public let preferredStereoChannels: VideoStereoChannels
  /// The current client I/O position for input.
  public let inputClientTime: VideoClientIOTime
  /// The current client I/O position for output.
  public let outputClientTime: VideoClientIOTime

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 64 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    let flags: [UInt32] = try [4, 8, 12].map { try runtimePayload.readRuntimeInteger(at: $0) }
    guard flags.allSatisfy({ $0 <= 1 }) else { throw VideoRuntimeError.invalidPayload }
    canBeDefaultInput = flags[0] == 1
    canBeDefaultOutput = flags[1] == 1
    canBeDefaultSystemOutput = flags[2] == 1
    inputSafetyOffset = try runtimePayload.readRuntimeInteger(at: 16)
    outputSafetyOffset = try runtimePayload.readRuntimeInteger(at: 20)
    preferredStereoChannels = VideoStereoChannels(
      left: try runtimePayload.readRuntimeInteger(at: 24),
      right: try runtimePayload.readRuntimeInteger(at: 28)
    )
    inputClientTime = VideoClientIOTime(
      sampleTime: try runtimePayload.readRuntimeInteger(at: 32),
      hostTime: try runtimePayload.readRuntimeInteger(at: 40)
    )
    outputClientTime = VideoClientIOTime(
      sampleTime: try runtimePayload.readRuntimeInteger(at: 48),
      hostTime: try runtimePayload.readRuntimeInteger(at: 56)
    )
  }
}

/// One settable `IOUserVideoDevice` property.
public enum VideoDeviceProperty: Sendable, Hashable {
  /// Sets whether the device can serve as the default input.
  case canBeDefaultInput(Bool)
  /// Sets whether the device can serve as the default output.
  case canBeDefaultOutput(Bool)
  /// Sets whether the device can serve as the default system output.
  case canBeDefaultSystemOutput(Bool)
  /// Sets the input safety offset in audio frames.
  case inputSafetyOffset(UInt32)
  /// Sets the output safety offset in audio frames.
  case outputSafetyOffset(UInt32)
  /// Two distinct, nonzero channels.
  case preferredStereoChannels(VideoStereoChannels)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    let fields: (RuntimeVideoDeviceProperty, UInt64) =
      switch self {
      case .canBeDefaultInput(let flag): (.canBeDefaultInput, flag ? 1 : 0)
      case .canBeDefaultOutput(let flag): (.canBeDefaultOutput, flag ? 1 : 0)
      case .canBeDefaultSystemOutput(let flag): (.canBeDefaultSystemOutput, flag ? 1 : 0)
      case .inputSafetyOffset(let frames): (.inputSafetyOffset, UInt64(frames))
      case .outputSafetyOffset(let frames): (.outputSafetyOffset, UInt64(frames))
      case .preferredStereoChannels(let pair):
        (.preferredStereoChannels, UInt64(pair.left) | UInt64(pair.right) << 32)
      }
    return (fields.0.rawValue, fields.1)
  }
}

/// The shared `IOStreamBufferQueue` of one stream direction.
public struct VideoQueueState: Sendable, Hashable {
  /// The number of entries in the shared `IOStreamBufferQueue`.
  public let entryCount: UInt32
  /// The index of the next queue entry to read.
  public let headIndex: UInt32
  /// The index of the next queue entry to write.
  public let tailIndex: UInt32
  /// Length of the queue's `IOMemoryDescriptor`, or zero without a queue.
  public let memoryLength: UInt64

  init(_ data: Data, at offset: Int) throws {
    entryCount = try data.readRuntimeInteger(at: offset)
    headIndex = try data.readRuntimeInteger(at: offset + 4)
    tailIndex = try data.readRuntimeInteger(at: offset + 8)
    let reserved: UInt32 = try data.readRuntimeInteger(at: offset + 12)
    guard reserved == 0 else { throw VideoRuntimeError.invalidPayload }
    memoryLength = try data.readRuntimeInteger(at: offset + 16)
  }
}

/// State, formats, queues, and buffers of a configured stream.
public struct VideoStreamState: Sendable, Hashable {
  /// The configured `IOUserVideoStream` object identifier.
  public let objectID: UInt32
  /// The stream input or output direction.
  public let direction: VideoStreamDirection
  /// The stream endpoint type set through `SetTerminalType`.
  public let terminalType: VideoStreamTerminalType
  /// The first channel assigned to the stream.
  public let startingChannel: UInt32
  /// Whether the stream is active and can perform I/O.
  public let isActive: Bool
  /// Whether the stream is attached to the device.
  public let isAttached: Bool
  /// Current byte capacity of each buffer's data memory.
  public let dataBufferCapacity: UInt32
  /// Current byte capacity of each buffer's control memory.
  public let controlBufferCapacity: UInt32
  /// The shared queue state for stream input.
  public let inputQueue: VideoQueueState
  /// The shared queue state for stream output.
  public let outputQueue: VideoQueueState
  /// The format currently set on the stream.
  public let currentFormat: VideoStreamFormat
  /// The formats available for the stream.
  public let availableFormats: [VideoStreamFormat]
  /// `IOStreamBufferID`s of the stream's buffer list, in list order.
  public let bufferIDs: [UInt32]

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 128 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    guard
      let direction = VideoStreamDirection(rawValue: try runtimePayload.readRuntimeInteger(at: 4))
    else { throw VideoRuntimeError.invalidPayload }
    self.direction = direction
    terminalType = VideoStreamTerminalType(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    startingChannel = try runtimePayload.readRuntimeInteger(at: 12)
    let active: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
    let attached: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    let formatCount = Int(try runtimePayload.readRuntimeInteger(at: 24) as UInt32)
    let bufferCount = Int(try runtimePayload.readRuntimeInteger(at: 28) as UInt32)
    guard active <= 1, attached <= 1, formatCount <= RuntimeVideoLimits.maximumStreamFormats,
      bufferCount <= RuntimeVideoLimits.maximumBuffers,
      runtimePayload.count == 128 + formatCount * 40 + bufferCount * 4
    else { throw VideoRuntimeError.invalidPayload }
    isActive = active == 1
    isAttached = attached == 1
    dataBufferCapacity = try runtimePayload.readRuntimeInteger(at: 32)
    controlBufferCapacity = try runtimePayload.readRuntimeInteger(at: 36)
    inputQueue = try VideoQueueState(runtimePayload, at: 40)
    outputQueue = try VideoQueueState(runtimePayload, at: 64)
    currentFormat = try Self.format(runtimePayload, at: 88)
    availableFormats = try (0..<formatCount).map {
      try Self.format(runtimePayload, at: 128 + $0 * 40)
    }
    let idStart = 128 + formatCount * 40
    bufferIDs = try (0..<bufferCount).map {
      try runtimePayload.readRuntimeInteger(at: idStart + $0 * 4)
    }
  }

  private static func format(_ data: Data, at offset: Int) throws -> VideoStreamFormat {
    let reserved: UInt32 = try data.readRuntimeInteger(at: offset + 36)
    guard reserved == 0 else { throw VideoRuntimeError.invalidPayload }
    return VideoStreamFormat(
      frameRate: Double(bitPattern: try data.readRuntimeInteger(at: offset)),
      frameTimeValue: try data.readRuntimeInteger(at: offset + 8),
      frameTimeScale: try data.readRuntimeInteger(at: offset + 16),
      codec: VideoCodec(rawValue: try data.readRuntimeInteger(at: offset + 20)),
      codecFlags: try data.readRuntimeInteger(at: offset + 24),
      width: try data.readRuntimeInteger(at: offset + 28),
      height: try data.readRuntimeInteger(at: offset + 32)
    )
  }
}

/// One settable property of a configured stream.
///
/// `bufferCapacity` and `queueEntryCount` change the stream's structure. The runtime requests a
/// device configuration change and applies them in `PerformDeviceConfigurationChange`, where I/O
/// is stopped:
///
/// - `bufferCapacity` replaces every buffer's memory through `SetDataMemoryDescriptor` and
///   `SetControlMemoryDescriptor`, and discards its contents.
/// - `queueEntryCount` recreates the shared queues through `destroyQueues` and `createQueues`.
public enum VideoStreamProperty: Sendable, Hashable {
  /// Sets whether the stream is active and can perform I/O.
  case isActive(Bool)
  /// A nonzero first channel.
  case startingChannel(UInt32)
  /// Sets the terminal type through `SetTerminalType`.
  case terminalType(VideoStreamTerminalType)
  /// An index into ``VideoStreamState/availableFormats``, below 16.
  case currentFormat(index: UInt32)
  /// Data bytes in 1...64 MiB and control bytes in 1...1 MiB per buffer.
  case bufferCapacity(data: UInt32, control: UInt32)
  /// Queue entries in 1...256.
  case queueEntryCount(UInt32)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    let fields: (RuntimeVideoStreamProperty, UInt64) =
      switch self {
      case .isActive(let flag): (.isActive, flag ? 1 : 0)
      case .startingChannel(let channel): (.startingChannel, UInt64(channel))
      case .terminalType(let type): (.terminalType, UInt64(type.rawValue))
      case .currentFormat(let index): (.currentFormat, UInt64(index))
      case .bufferCapacity(let data, let control):
        (.bufferCapacity, UInt64(data) | UInt64(control) << 32)
      case .queueEntryCount(let count): (.queueEntryCount, UInt64(count))
      }
    return (fields.0.rawValue, fields.1)
  }
}

/// Identity and memory of one configured `IOUserVideoBuffer`.
public struct VideoBufferInfo: Sendable, Hashable {
  /// The `IOUserVideoBuffer` object identifier.
  public let objectID: UInt32
  /// The class identifier of the configured buffer.
  public let classID: VideoClassID
  /// The base class identifier of the configured buffer.
  public let baseClassID: VideoClassID
  /// The buffer's current `IOStreamBufferID`.
  public let bufferID: UInt32
  /// Whether the buffer is in the stream's buffer list.
  public let isAttached: Bool
  /// The object identifier of the buffer data memory.
  public let dataMemoryObjectID: UInt32
  /// The object identifier of the buffer control memory.
  public let controlMemoryObjectID: UInt32
  /// The byte length of the buffer data memory.
  public let dataLength: UInt64
  /// The byte length of the buffer control memory.
  public let controlLength: UInt64
  /// Lengths the stream reports for the memory object IDs, or zero when it reports none.
  public let outputDataLength: UInt64
  /// The byte length of the buffer control memory reported by the stream.
  public let outputControlLength: UInt64

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 64 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    classID = VideoClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 4))
    baseClassID = VideoClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    bufferID = try runtimePayload.readRuntimeInteger(at: 12)
    let attached: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    guard attached <= 1, reserved == 0 else { throw VideoRuntimeError.invalidPayload }
    isAttached = attached == 1
    dataMemoryObjectID = try runtimePayload.readRuntimeInteger(at: 20)
    controlMemoryObjectID = try runtimePayload.readRuntimeInteger(at: 24)
    dataLength = try runtimePayload.readRuntimeInteger(at: 32)
    controlLength = try runtimePayload.readRuntimeInteger(at: 40)
    outputDataLength = try runtimePayload.readRuntimeInteger(at: 48)
    outputControlLength = try runtimePayload.readRuntimeInteger(at: 56)
  }
}

/// One settable property of a configured buffer, applied in `PerformDeviceConfigurationChange`.
public enum VideoBufferProperty: Sendable, Hashable {
  /// A new `IOStreamBufferID`, unique in the stream and below `0xFFFFFFFF`. Queue entries keep
  /// naming the buffer by index.
  case bufferID(UInt32)
  /// Adds the buffer to the stream's buffer list through `addBuffer`, or removes it. The
  /// runtime calls `removeAllBuffers` and adds the others back through `addBuffers`.
  case isAttached(Bool)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .bufferID(let identifier):
      (RuntimeVideoBufferProperty.bufferID.rawValue, UInt64(identifier))
    case .isAttached(let flag): (RuntimeVideoBufferProperty.isAttached.rawValue, flag ? 1 : 0)
    }
  }
}

/// Scope, element, owner, range, channels, and selector items of a configured control.
public struct VideoControlInfo: Sendable, Hashable {
  /// The configured control kind.
  public enum Kind: UInt32, Sendable, Hashable {
    /// Identifies a control that stores a Boolean value.
    case boolean = 1
    /// Identifies a control that stores a level value.
    case level = 2
    /// Identifies a control that selects one of its selector items.
    case selector = 3
    /// Identifies a control with a numeric slider range.
    case slider = 4
    /// Identifies a control that pans across a stereo channel pair.
    case stereoPan = 5
    /// Identifies a control that stores a direction value.
    case direction = 6
  }

  /// The configured control object identifier.
  public let objectID: UInt32
  /// The kind of value that the control stores.
  public let kind: Kind
  /// The scope in which the control operates.
  public let scope: VideoObjectScope
  /// The element index that identifies the control.
  public let element: UInt32
  /// Whether the control accepts property changes.
  public let isSettable: Bool
  /// Whether the control is attached to the device.
  public let isAttached: Bool
  /// `GetOwningDeviceID`.
  public let owningDeviceID: UInt32
  /// The inclusive minimum and maximum values for a slider control.
  public let sliderRange: ClosedRange<UInt32>?
  /// The left and right channel labels used by a stereo-pan control.
  public let panningChannels: VideoStereoChannels?
  /// The values and names that a selector control can select.
  public let selectorItems: [VideoSelectorValue]

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 48 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    guard let kind = Kind(rawValue: try runtimePayload.readRuntimeInteger(at: 4)) else {
      throw VideoRuntimeError.invalidPayload
    }
    self.kind = kind
    scope = VideoObjectScope(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    element = try runtimePayload.readRuntimeInteger(at: 12)
    let settable: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
    let attached: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    let minimum: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
    let maximum: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    let left: UInt32 = try runtimePayload.readRuntimeInteger(at: 32)
    let right: UInt32 = try runtimePayload.readRuntimeInteger(at: 36)
    let count: UInt32 = try runtimePayload.readRuntimeInteger(at: 40)
    owningDeviceID = try runtimePayload.readRuntimeInteger(at: 44)
    guard settable <= 1, attached <= 1, count <= RuntimeVideoLimits.maximumSelectorItems,
      kind == .selector || count == 0, kind != .slider || minimum <= maximum
    else { throw VideoRuntimeError.invalidPayload }
    isSettable = settable == 1
    isAttached = attached == 1
    sliderRange = kind == .slider ? minimum...maximum : nil
    panningChannels = kind == .stereoPan ? VideoStereoChannels(left: left, right: right) : nil
    var items: [VideoSelectorValue] = []
    var offset = 48
    for _ in 0..<count {
      let value: UInt32 = try runtimePayload.readRuntimeInteger(at: offset)
      let length = Int(try runtimePayload.readRuntimeInteger(at: offset + 4) as UInt32)
      let start = runtimePayload.startIndex + offset + 8
      guard length <= RuntimeVideoLimits.nameMaximumLength,
        offset + 8 + length <= runtimePayload.count,
        let name = String(data: runtimePayload[start..<(start + length)], encoding: .utf8)
      else { throw VideoRuntimeError.invalidPayload }
      items.append(VideoSelectorValue(value: value, name: name))
      offset += 8 + length
    }
    guard offset == runtimePayload.count else { throw VideoRuntimeError.invalidPayload }
    selectorItems = items
  }
}

/// A slider range or stereo-pan channel pair.
public enum VideoControlProperty: Sendable, Hashable {
  /// Sets the inclusive minimum and maximum values for a slider control.
  case sliderRange(ClosedRange<UInt32>)
  /// Two distinct channels.
  case panningChannels(VideoStereoChannels)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .sliderRange(let range):
      (
        RuntimeVideoControlProperty.sliderRange.rawValue,
        UInt64(range.lowerBound) | UInt64(range.upperBound) << 32
      )
    case .panningChannels(let pair):
      (
        RuntimeVideoControlProperty.panningChannels.rawValue,
        UInt64(pair.left) | UInt64(pair.right) << 32
      )
    }
  }
}

/// An `IOUserVideoCustomPropertyDataType`.
public struct VideoCustomPropertyDataType: RawRepresentable, Sendable, Hashable {
  /// The raw `IOUserVideoCustomPropertyDataType` value.
  public let rawValue: UInt32
  /// Creates a data type from its unmodified `IOUserVideoCustomPropertyDataType` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Maps to the native data type value for no property data.
  public static let none = Self(rawValue: 0)
  /// Maps to the native data type value for a string.
  public static let string = Self(rawValue: 0x6366_7374)
  /// Maps to the native data type value for a property list dictionary.
  public static let dictionary = Self(rawValue: 0x706C_7374)
}

/// Selector, data types, and owner of a configured custom property.
public struct VideoCustomPropertyInfo: Sendable, Hashable {
  /// The configured custom property object identifier.
  public let objectID: UInt32
  /// The custom property selector passed to the native property API.
  public let selector: UInt32
  /// The native data type of the custom property value.
  public let propertyDataType: VideoCustomPropertyDataType
  /// The native data type of the custom property qualifier.
  public let qualifierDataType: VideoCustomPropertyDataType
  /// The stream or control that owns the custom property.
  public let owner: VideoCustomPropertyOwner

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    selector = try runtimePayload.readRuntimeInteger(at: 4)
    propertyDataType = VideoCustomPropertyDataType(
      rawValue: try runtimePayload.readRuntimeInteger(at: 8)
    )
    qualifierDataType = VideoCustomPropertyDataType(
      rawValue: try runtimePayload.readRuntimeInteger(at: 12)
    )
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    guard reserved == 0,
      let owner = VideoCustomPropertyOwner(rawValue: try runtimePayload.readRuntimeInteger(at: 16))
    else { throw VideoRuntimeError.invalidPayload }
    self.owner = owner
  }
}

/// A configured stream or control that can leave the device and return.
///
/// Custom properties move through ``DriverContext/videoSetCustomPropertyOwner(_:owner:)``.
public enum VideoMember: Sendable, Hashable {
  /// A stream by index. The runtime calls `AddStream` or `RemoveStream`.
  case stream(UInt32)
  /// A control by identifier. The runtime calls `AddControl` or `RemoveControl`.
  case control(UInt32)

  var runtimeFields: (kind: UInt32, identifier: UInt32) {
    switch self {
    case .stream(let index): (RuntimeVideoMemberKind.stream.rawValue, index)
    case .control(let identifier): (RuntimeVideoMemberKind.control.rawValue, identifier)
    }
  }
}
