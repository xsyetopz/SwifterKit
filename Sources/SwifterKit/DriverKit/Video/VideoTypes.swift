import Foundation

/// A VideoDriverKit transport identifier.
public struct VideoTransport: RawRepresentable, Sendable, Hashable {
  /// The unmodified framework value.
  public let rawValue: UInt32
  /// Preserves a raw transport identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// Unknown or unspecified transport.
  public static let unknown = Self(rawValue: 0)
  /// Hardware integrated into the host.
  public static let builtIn = Self(rawValue: 0x626C_746E)
  /// PCI transport.
  public static let pci = Self(rawValue: 0x7063_6920)
  /// USB transport.
  public static let usb = Self(rawValue: 0x7573_6220)
  /// HDMI transport.
  public static let hdmi = Self(rawValue: 0x6864_6D69)
  /// DisplayPort transport.
  public static let displayPort = Self(rawValue: 0x6470_7274)
  /// Thunderbolt transport.
  public static let thunderbolt = Self(rawValue: 0x7468_756E)
}

/// Direction of a VideoDriverKit stream relative to the host.
public enum VideoStreamDirection: UInt32, Sendable, Hashable {
  /// Frames produced for the host.
  case output = 0
  /// Frames supplied by the host.
  case input = 1
}

/// A VideoDriverKit codec or pixel-format identifier.
public struct VideoCodec: RawRepresentable, Sendable, Hashable {
  /// The unmodified framework value.
  public let rawValue: UInt32
  /// Preserves a raw codec identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  /// 32-bit ARGB pixels.
  public static let argb32 = Self(rawValue: 32)
  /// 32-bit BGRA pixels.
  public static let bgra32 = Self(rawValue: 0x4247_5241)
  /// 8-bit 4:2:2 YCbCr pixels.
  public static let yCbCr4228 = Self(rawValue: 0x3276_7579)
  /// 10-bit 4:2:2 YCbCr pixels.
  public static let yCbCr42210 = Self(rawValue: 0x7632_3130)
}

/// A constant-rate video stream description.
public struct VideoStreamFormat: Sendable, Hashable {
  /// Nominal frames per second.
  public let frameRate: Double
  /// Frame duration numerator.
  public let frameTimeValue: UInt64
  /// Frame duration denominator.
  public let frameTimeScale: UInt32
  /// Codec or pixel format.
  public let codec: VideoCodec
  /// Codec-specific flags.
  public let codecFlags: UInt32
  /// Pixel width.
  public let width: UInt32
  /// Pixel height.
  public let height: UInt32

  /// Creates a video format from the framework fields.
  public init(
    frameRate: Double,
    frameTimeValue: UInt64 = 1,
    frameTimeScale: UInt32,
    codec: VideoCodec,
    codecFlags: UInt32 = 0,
    width: UInt32,
    height: UInt32
  ) {
    self.frameRate = frameRate
    self.frameTimeValue = frameTimeValue
    self.frameTimeScale = frameTimeScale
    self.codec = codec
    self.codecFlags = codecFlags
    self.width = width
    self.height = height
  }
}

/// Static topology and native buffer sizing for one video stream.
public struct VideoStreamConfiguration: Sendable, Hashable {
  /// Stable stream identifier.
  public let identifier: String
  /// Stream direction.
  public let direction: VideoStreamDirection
  /// Formats offered to the host.
  public let formats: [VideoStreamFormat]
  /// Initially selected format index.
  public let initialFormatIndex: UInt32
  /// Number of native buffers.
  public let bufferCount: UInt32
  /// Capacity of each data plane.
  public let dataBufferCapacity: UInt32
  /// Capacity of each control plane.
  public let controlBufferCapacity: UInt32

  /// Creates stream metadata, formats, and bounded buffer storage.
  public init(
    identifier: String,
    direction: VideoStreamDirection,
    formats: [VideoStreamFormat],
    initialFormatIndex: UInt32 = 0,
    bufferCount: UInt32 = 4,
    dataBufferCapacity: UInt32,
    controlBufferCapacity: UInt32 = 256
  ) {
    self.identifier = identifier
    self.direction = direction
    self.formats = formats
    self.initialFormatIndex = initialFormatIndex
    self.bufferCount = bufferCount
    self.dataBufferCapacity = dataBufferCapacity
    self.controlBufferCapacity = controlBufferCapacity
  }
}

/// Static VideoDriverKit device and stream topology.
public struct VideoDeviceConfiguration: Sendable, Hashable {
  /// Stable device identifier.
  public let deviceUID: String
  /// Stable model identifier.
  public let modelUID: String
  /// Stable manufacturer identifier.
  public let manufacturerUID: String
  /// Human-readable device name.
  public let name: String
  /// Physical transport.
  public let transport: VideoTransport
  /// Sample rates offered to the host.
  public let sampleRates: [Double]
  /// Initially selected sample rate.
  public let initialSampleRate: Double
  /// Published input and output streams.
  public let streams: [VideoStreamConfiguration]
  /// Boolean, direction, level, selector, slider, and stereo-pan controls.
  public let controls: [VideoControlConfiguration]
  /// String-backed custom properties.
  public let customProperties: [VideoCustomPropertyConfiguration]
  /// Boxes that group the device and clock devices, at most four.
  public let boxes: [VideoBoxConfiguration]
  /// Clock-only devices, at most four.
  public let clockDevices: [VideoClockDeviceConfiguration]

  /// Creates one device and its stream topology.
  public init(
    deviceUID: String,
    modelUID: String,
    manufacturerUID: String,
    name: String,
    transport: VideoTransport = .unknown,
    sampleRates: [Double],
    initialSampleRate: Double,
    streams: [VideoStreamConfiguration],
    controls: [VideoControlConfiguration] = [],
    customProperties: [VideoCustomPropertyConfiguration] = [],
    boxes: [VideoBoxConfiguration] = [],
    clockDevices: [VideoClockDeviceConfiguration] = []
  ) {
    self.deviceUID = deviceUID
    self.modelUID = modelUID
    self.manufacturerUID = manufacturerUID
    self.name = name
    self.transport = transport
    self.sampleRates = sampleRates
    self.initialSampleRate = initialSampleRate
    self.streams = streams
    self.controls = controls
    self.customProperties = customProperties
    self.boxes = boxes
    self.clockDevices = clockDevices
  }
}

/// Data or metadata plane of a native video buffer.
public enum VideoBufferPlane: UInt32, Sendable, Hashable {
  /// Frame bytes.
  case data = 0
  /// Per-frame control metadata.
  case control = 1
}

/// One entry exchanged through a framework stream queue.
public struct VideoBufferQueueEntry: Sendable, Hashable {
  /// Buffer index within the stream.
  public let bufferIndex: UInt32
  /// First valid data byte.
  public let dataOffset: UInt32
  /// Number of valid data bytes.
  public let dataLength: UInt32
  /// First valid control byte.
  public let controlOffset: UInt32
  /// Number of valid control bytes.
  public let controlLength: UInt32

  /// Creates a queue entry describing valid data and control ranges.
  public init(
    bufferIndex: UInt32,
    dataOffset: UInt32 = 0,
    dataLength: UInt32,
    controlOffset: UInt32 = 0,
    controlLength: UInt32 = 0
  ) {
    self.bufferIndex = bufferIndex
    self.dataOffset = dataOffset
    self.dataLength = dataLength
    self.controlOffset = controlOffset
    self.controlLength = controlLength
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 32 else { throw VideoRuntimeError.invalidPayload }
    bufferIndex = try runtimePayload.readRuntimeInteger(at: 0)
    dataOffset = try runtimePayload.readRuntimeInteger(at: 4)
    dataLength = try runtimePayload.readRuntimeInteger(at: 8)
    controlOffset = try runtimePayload.readRuntimeInteger(at: 12)
    controlLength = try runtimePayload.readRuntimeInteger(at: 16)
    let reserved0: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    let reserved1: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
    let reserved2: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    guard reserved0 == 0, reserved1 == 0, reserved2 == 0 else {
      throw VideoRuntimeError.invalidPayload
    }
  }
}

/// A lifecycle request from VideoDriverKit.
public enum VideoEvent: Sendable, Hashable {
  /// Reports that device I/O started and carries the VideoDriverKit flags.
  case started(flags: UInt64)
  /// Reports that device I/O stopped and carries the VideoDriverKit flags.
  case stopped(flags: UInt64)
  /// Reports the new device sample rate in samples per second.
  case sampleRateChanged(Double)
  /// Reports a control value change by identifier.
  case controlChanged(identifier: UInt32, value: VideoControlValue)
  /// Reports a custom property change with its identifier, qualifier, and string value.
  case customPropertyChanged(identifier: UInt32, qualifier: String, value: String)
  /// Reports that the indexed stream started and carries the VideoDriverKit flags.
  case streamStarted(index: UInt32, flags: UInt64)
  /// Reports that the indexed stream stopped and carries the VideoDriverKit flags.
  case streamStopped(index: UInt32, flags: UInt64)
  /// Reports the new format for the indexed stream.
  case streamFormatChanged(index: UInt32, format: VideoStreamFormat)
  /// Reports whether the indexed stream is active.
  case streamActiveChanged(index: UInt32, isActive: Bool)
  /// Reports that input data is available for the indexed stream.
  case streamInputAvailable(index: UInt32)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 4 else { throw VideoRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    guard let eventKind = RuntimeVideoEventKind(rawValue: kind) else {
      throw VideoRuntimeError.invalidEventKind(kind)
    }
    switch eventKind {
    case .started, .stopped, .sampleRateChanged:
      guard runtimePayload.count == 16 else { throw VideoRuntimeError.invalidPayload }
      let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let value: UInt64 = try runtimePayload.readRuntimeInteger(at: 8)
      guard reserved == 0 else { throw VideoRuntimeError.invalidPayload }
      switch eventKind {
      case .started: self = .started(flags: value)
      case .stopped: self = .stopped(flags: value)
      default: self = .sampleRateChanged(Double(bitPattern: value))
      }
    case .controlChanged:
      guard runtimePayload.count >= 20 else { throw VideoRuntimeError.invalidPayload }
      let identifier: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let value = try VideoControlValue(runtimePayload: Data(runtimePayload.dropFirst(4)))
      self = .controlChanged(identifier: identifier, value: value)
    case .customPropertyChanged:
      guard runtimePayload.count >= 20 else { throw VideoRuntimeError.invalidPayload }
      let identifier: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let qualifierLength: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
      let valueLength: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
      let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
      let qualifierEnd = 20 + Int(qualifierLength)
      let valueEnd = qualifierEnd + Int(valueLength)
      guard reserved == 0, qualifierLength > 0,
        qualifierLength <= RuntimeVideoLimits.nameMaximumLength,
        valueLength <= RuntimeVideoLimits.customPropertyValueMaximumLength,
        valueEnd == runtimePayload.count,
        let qualifier = String(data: runtimePayload[20..<qualifierEnd], encoding: .utf8),
        let value = String(data: runtimePayload[qualifierEnd..<valueEnd], encoding: .utf8)
      else { throw VideoRuntimeError.invalidPayload }
      self = .customPropertyChanged(identifier: identifier, qualifier: qualifier, value: value)
    case .streamStarted, .streamStopped, .streamActiveChanged, .streamInputAvailable:
      guard runtimePayload.count == 16 else { throw VideoRuntimeError.invalidPayload }
      let index: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let value: UInt64 = try runtimePayload.readRuntimeInteger(at: 8)
      switch eventKind {
      case .streamStarted: self = .streamStarted(index: index, flags: value)
      case .streamStopped: self = .streamStopped(index: index, flags: value)
      case .streamActiveChanged where value <= 1:
        self = .streamActiveChanged(index: index, isActive: value != 0)
      case .streamInputAvailable where value == 0: self = .streamInputAvailable(index: index)
      default: throw VideoRuntimeError.invalidPayload
      }
    case .streamFormatChanged:
      guard runtimePayload.count == 52 else { throw VideoRuntimeError.invalidPayload }
      let index: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let frameRateBits: UInt64 = try runtimePayload.readRuntimeInteger(at: 8)
      let frameTimeValue: UInt64 = try runtimePayload.readRuntimeInteger(at: 16)
      let frameTimeScale: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
      let codec: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
      let codecFlags: UInt32 = try runtimePayload.readRuntimeInteger(at: 32)
      let width: UInt32 = try runtimePayload.readRuntimeInteger(at: 36)
      let height: UInt32 = try runtimePayload.readRuntimeInteger(at: 40)
      let reserved0: UInt32 = try runtimePayload.readRuntimeInteger(at: 44)
      let reserved1: UInt32 = try runtimePayload.readRuntimeInteger(at: 48)
      let frameRate = Double(bitPattern: frameRateBits)
      guard reserved0 == 0, reserved1 == 0, frameRate.isFinite, frameRate > 0, frameTimeValue > 0,
        frameTimeScale > 0, codec != 0, width > 0, height > 0
      else { throw VideoRuntimeError.invalidPayload }
      self = .streamFormatChanged(
        index: index,
        format: VideoStreamFormat(
          frameRate: frameRate,
          frameTimeValue: frameTimeValue,
          frameTimeScale: frameTimeScale,
          codec: VideoCodec(rawValue: codec),
          codecFlags: codecFlags,
          width: width,
          height: height
        )
      )
    }
  }
}

/// An invalid VideoDriverKit configuration, transfer, or runtime payload.
public enum VideoRuntimeError: Error, Sendable, Equatable {
  /// The command names a stream index outside the configured stream table.
  case invalidStreamIndex
  /// The command names a buffer index outside the configured buffer table.
  case invalidBufferIndex
  /// The stream transfer has an empty or invalid byte range.
  case invalidTransferRange
  /// The stream transfer exceeds the runtime byte limit.
  case transferTooLarge
  /// The command or response payload has an invalid size, value, or encoding.
  case invalidPayload
  /// The event payload contains an event kind the runtime does not define.
  case invalidEventKind(UInt32)
  /// The control value has too many items or cannot be encoded for the runtime.
  case invalidControlValue
  /// The custom-property qualifier or value exceeds its UTF-8 byte limit.
  case invalidCustomPropertyValue
  /// The command target is not a valid video object for that operation.
  case invalidObjectTarget
  /// The object name is empty, longer than 255 UTF-8 bytes, or contains NUL.
  case invalidName
  /// The property-change request is empty, names more than 32 selectors, or contains zero.
  case invalidPropertySelectors
  /// Sample rates are empty, duplicated, more than 16, or not finite and positive.
  case invalidSampleRates
}
