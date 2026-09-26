import Foundation

/// An `IOUserVideoChannelLabel` for a preferred channel layout.
public struct VideoChannelLabel: RawRepresentable, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let unknown = Self(rawValue: 0xFFFF_FFFF)
  public static let unused = Self(rawValue: 0)
  public static let left = Self(rawValue: 1)
  public static let right = Self(rawValue: 2)
  public static let center = Self(rawValue: 3)
}

/// An `IOUserVideoStreamTerminalType`.
public struct VideoStreamTerminalType: RawRepresentable, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let unknown = Self(rawValue: 0)
  public static let line = Self(rawValue: 0x6C69_6E65)
  public static let digitalVideoInterface = Self(rawValue: 0x7370_6466)
  public static let speaker = Self(rawValue: 0x7370_6B72)
  public static let headphones = Self(rawValue: 0x6864_7068)
  public static let microphone = Self(rawValue: 0x6D69_6372)
}

/// A left and right channel pair.
public struct VideoStereoChannels: Sendable, Hashable {
  public let left: UInt32
  public let right: UInt32
  public init(left: UInt32, right: UInt32) {
    self.left = left
    self.right = right
  }
}

/// A client's current I/O position from `GetCurrentClientIOTime`.
public struct VideoClientIOTime: Sendable, Hashable {
  public let sampleTime: UInt64
  public let hostTime: UInt64
}

/// `IOUserVideoDevice` state that has no other typed reader.
public struct VideoDeviceState: Sendable, Hashable {
  public let objectID: UInt32
  public let canBeDefaultInput: Bool
  public let canBeDefaultOutput: Bool
  public let canBeDefaultSystemOutput: Bool
  public let inputSafetyOffset: UInt32
  public let outputSafetyOffset: UInt32
  public let preferredStereoChannels: VideoStereoChannels
  public let inputClientTime: VideoClientIOTime
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
  case canBeDefaultInput(Bool)
  case canBeDefaultOutput(Bool)
  case canBeDefaultSystemOutput(Bool)
  case inputSafetyOffset(UInt32)
  case outputSafetyOffset(UInt32)
  /// Two distinct, nonzero channels.
  case preferredStereoChannels(VideoStereoChannels)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .canBeDefaultInput(let flag): (1, flag ? 1 : 0)
    case .canBeDefaultOutput(let flag): (2, flag ? 1 : 0)
    case .canBeDefaultSystemOutput(let flag): (3, flag ? 1 : 0)
    case .inputSafetyOffset(let frames): (4, UInt64(frames))
    case .outputSafetyOffset(let frames): (5, UInt64(frames))
    case .preferredStereoChannels(let pair): (6, UInt64(pair.left) | UInt64(pair.right) << 32)
    }
  }
}

/// The shared `IOStreamBufferQueue` of one stream direction.
public struct VideoQueueState: Sendable, Hashable {
  public let entryCount: UInt32
  public let headIndex: UInt32
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
  public let objectID: UInt32
  public let direction: VideoStreamDirection
  public let terminalType: VideoStreamTerminalType
  public let startingChannel: UInt32
  public let isActive: Bool
  /// Whether the stream is attached to the device; see ``VideoMember``.
  public let isAttached: Bool
  /// Current byte capacity of each buffer's data memory.
  public let dataBufferCapacity: UInt32
  /// Current byte capacity of each buffer's control memory.
  public let controlBufferCapacity: UInt32
  public let inputQueue: VideoQueueState
  public let outputQueue: VideoQueueState
  public let currentFormat: VideoStreamFormat
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
    guard active <= 1, attached <= 1, formatCount <= 16, bufferCount <= 32,
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
/// `bufferCapacity` and `queueEntryCount` change the stream's structure, so the runtime requests
/// a device configuration change and applies them in `PerformDeviceConfigurationChange`, where
/// IO is stopped. `bufferCapacity` replaces every buffer's memory through
/// `SetDataMemoryDescriptor` and `SetControlMemoryDescriptor` and discards its contents;
/// `queueEntryCount` recreates the shared queues through `destroyQueues` and `createQueues`.
public enum VideoStreamProperty: Sendable, Hashable {
  case isActive(Bool)
  /// A nonzero first channel.
  case startingChannel(UInt32)
  case terminalType(VideoStreamTerminalType)
  /// An index into ``VideoStreamState/availableFormats``, below 16.
  case currentFormat(index: UInt32)
  /// Data bytes in 1...64 MiB and control bytes in 1...1 MiB per buffer.
  case bufferCapacity(data: UInt32, control: UInt32)
  /// Queue entries in 1...256.
  case queueEntryCount(UInt32)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .isActive(let flag): (1, flag ? 1 : 0)
    case .startingChannel(let channel): (2, UInt64(channel))
    case .terminalType(let type): (3, UInt64(type.rawValue))
    case .currentFormat(let index): (4, UInt64(index))
    case .bufferCapacity(let data, let control): (5, UInt64(data) | UInt64(control) << 32)
    case .queueEntryCount(let count): (6, UInt64(count))
    }
  }
}

/// Identity and memory of one configured `IOUserVideoBuffer`.
public struct VideoBufferInfo: Sendable, Hashable {
  public let objectID: UInt32
  public let classID: VideoClassID
  public let baseClassID: VideoClassID
  /// The buffer's current `IOStreamBufferID`.
  public let bufferID: UInt32
  /// Whether the buffer is in the stream's buffer list.
  public let isAttached: Bool
  public let dataMemoryObjectID: UInt32
  public let controlMemoryObjectID: UInt32
  public let dataLength: UInt64
  public let controlLength: UInt64
  /// Lengths the stream reports for the memory object IDs, or zero when it reports none.
  public let outputDataLength: UInt64
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
  /// Adds the buffer to the stream's buffer list through `addBuffer`, or removes it; the
  /// runtime calls `removeAllBuffers` and adds the others back through `addBuffers`.
  case isAttached(Bool)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .bufferID(let identifier): (1, UInt64(identifier))
    case .isAttached(let flag): (2, flag ? 1 : 0)
    }
  }
}

/// Scope, element, owner, range, channels, and selector items of a configured control.
public struct VideoControlInfo: Sendable, Hashable {
  /// The configured control kind.
  public enum Kind: UInt32, Sendable, Hashable {
    case boolean = 1
    case level = 2
    case selector = 3
    case slider = 4
    case stereoPan = 5
    case direction = 6
  }

  public let objectID: UInt32
  public let kind: Kind
  public let scope: VideoObjectScope
  public let element: UInt32
  public let isSettable: Bool
  /// Whether the control is attached to the device; see ``VideoMember``.
  public let isAttached: Bool
  /// `GetOwningDeviceID`.
  public let owningDeviceID: UInt32
  public let sliderRange: ClosedRange<UInt32>?
  public let panningChannels: VideoStereoChannels?
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
    guard settable <= 1, attached <= 1, count <= 32, kind == .selector || count == 0,
      kind != .slider || minimum <= maximum
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
      guard length <= 255, offset + 8 + length <= runtimePayload.count,
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
  case sliderRange(ClosedRange<UInt32>)
  /// Two distinct channels.
  case panningChannels(VideoStereoChannels)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .sliderRange(let range): (1, UInt64(range.lowerBound) | UInt64(range.upperBound) << 32)
    case .panningChannels(let pair): (2, UInt64(pair.left) | UInt64(pair.right) << 32)
    }
  }
}

/// An `IOUserVideoCustomPropertyDataType`.
public struct VideoCustomPropertyDataType: RawRepresentable, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  public static let none = Self(rawValue: 0)
  public static let string = Self(rawValue: 0x6366_7374)
  public static let dictionary = Self(rawValue: 0x706C_7374)
}

/// Selector, data types, and owner of a configured custom property.
public struct VideoCustomPropertyInfo: Sendable, Hashable {
  public let objectID: UInt32
  public let selector: UInt32
  public let propertyDataType: VideoCustomPropertyDataType
  public let qualifierDataType: VideoCustomPropertyDataType
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
  /// A stream by index; the runtime calls `AddStream` or `RemoveStream`.
  case stream(UInt32)
  /// A control by identifier; the runtime calls `AddControl` or `RemoveControl`.
  case control(UInt32)

  var runtimeFields: (kind: UInt32, identifier: UInt32) {
    switch self {
    case .stream(let index): (1, index)
    case .control(let identifier): (2, identifier)
    }
  }
}
