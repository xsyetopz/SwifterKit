import Foundation

/// An AudioDriverKit transport identifier.
public struct AudioTransport: RawRepresentable, Sendable, Hashable {
  /// The unmodified AudioDriverKit transport value.
  public let rawValue: UInt32
  /// Preserves a raw AudioDriverKit transport identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Unknown or unspecified device transport.
  public static let unknown = Self(rawValue: 0)
  /// Audio hardware integrated into the host.
  public static let builtIn = Self(rawValue: 0x626C_746E)
  /// PCI audio transport.
  public static let pci = Self(rawValue: 0x7063_6920)
  /// USB audio transport.
  public static let usb = Self(rawValue: 0x7573_6220)
  /// Thunderbolt audio transport.
  public static let thunderbolt = Self(rawValue: 0x7468_756E)
}

/// The direction of an AudioDriverKit stream.
public enum AudioStreamDirection: UInt32, Sendable, Hashable {
  case output = 0
  case input = 1
}

/// An AudioDriverKit stream format identifier.
public struct AudioFormatID: RawRepresentable, Sendable, Hashable {
  /// The unmodified AudioDriverKit format identifier.
  public let rawValue: UInt32
  /// Preserves a raw AudioDriverKit format identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Linear pulse-code modulation.
  public static let linearPCM = Self(rawValue: 0x6C70_636D)
}

/// AudioDriverKit stream-format option bits.
public struct AudioFormatFlags: OptionSet, Sendable, Hashable {
  /// The unmodified AudioDriverKit format flags.
  public let rawValue: UInt32
  /// Preserves raw AudioDriverKit format flags.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Samples use floating-point representation.
  public static let floatingPoint = Self(rawValue: 1 << 0)
  /// Samples use big-endian byte order.
  public static let bigEndian = Self(rawValue: 1 << 1)
  /// Samples use signed integer representation.
  public static let signedInteger = Self(rawValue: 1 << 2)
  /// Valid sample bits are packed into each sample word.
  public static let packed = Self(rawValue: 1 << 3)
  /// Valid sample bits are aligned to the high end of each word.
  public static let alignedHigh = Self(rawValue: 1 << 4)
  /// Each channel occupies a separate buffer.
  public static let nonInterleaved = Self(rawValue: 1 << 5)
  /// The format must not be mixed by the host.
  public static let nonMixable = Self(rawValue: 1 << 6)
}

/// A constant-rate AudioDriverKit stream description.
public struct AudioStreamFormat: Sendable, Hashable {
  /// Sample frames processed per second.
  public let sampleRate: Double
  /// Audio data format identifier.
  public let formatID: AudioFormatID
  /// Format-specific option bits.
  public let formatFlags: AudioFormatFlags
  /// Bytes in one complete audio packet.
  public let bytesPerPacket: UInt32
  /// Sample frames in one packet.
  public let framesPerPacket: UInt32
  /// Bytes in one sample frame.
  public let bytesPerFrame: UInt32
  /// Channels represented by one sample frame.
  public let channelsPerFrame: UInt32
  /// Significant sample bits for each channel.
  public let bitsPerChannel: UInt32

  /// Creates a constant-rate stream description from raw AudioDriverKit fields.
  public init(
    sampleRate: Double,
    formatID: AudioFormatID = .linearPCM,
    formatFlags: AudioFormatFlags = [.signedInteger, .packed],
    bytesPerPacket: UInt32,
    framesPerPacket: UInt32 = 1,
    bytesPerFrame: UInt32,
    channelsPerFrame: UInt32,
    bitsPerChannel: UInt32
  ) {
    self.sampleRate = sampleRate
    self.formatID = formatID
    self.formatFlags = formatFlags
    self.bytesPerPacket = bytesPerPacket
    self.framesPerPacket = framesPerPacket
    self.bytesPerFrame = bytesPerFrame
    self.channelsPerFrame = channelsPerFrame
    self.bitsPerChannel = bitsPerChannel
  }

  /// Creates an interleaved, native-endian signed linear PCM format.
  public static func linearPCM(sampleRate: Double, channels: UInt32, bitsPerChannel: UInt32 = 16)
    -> Self
  {
    let bytesPerSample = (bitsPerChannel + 7) / 8
    let bytesPerFrame = bytesPerSample * channels
    return Self(
      sampleRate: sampleRate,
      bytesPerPacket: bytesPerFrame,
      bytesPerFrame: bytesPerFrame,
      channelsPerFrame: channels,
      bitsPerChannel: bitsPerChannel
    )
  }
}

/// Static metadata and ring-buffer sizing for one audio stream.
public struct AudioStreamConfiguration: Sendable, Hashable {
  /// Direction relative to the host audio engine.
  public let direction: AudioStreamDirection
  /// Human-readable stream name.
  public let name: String
  /// Formats available to the host.
  public let formats: [AudioStreamFormat]
  /// Index of the initially selected format.
  public let initialFormatIndex: UInt32
  /// Number of sample frames allocated in the native ring buffer.
  public let ringBufferFrameCapacity: UInt32

  /// Creates static stream metadata and ring-buffer sizing.
  public init(
    direction: AudioStreamDirection,
    name: String,
    formats: [AudioStreamFormat],
    initialFormatIndex: UInt32 = 0,
    ringBufferFrameCapacity: UInt32 = 32_768
  ) {
    self.direction = direction
    self.name = name
    self.formats = formats
    self.initialFormatIndex = initialFormatIndex
    self.ringBufferFrameCapacity = ringBufferFrameCapacity
  }
}

/// Static AudioDriverKit device and stream topology.
public struct AudioDeviceConfiguration: Sendable, Hashable {
  /// Stable device identifier reported to Core Audio.
  public let deviceUID: String
  /// Stable model identifier reported to Core Audio.
  public let modelUID: String
  /// Stable manufacturer identifier reported to Core Audio.
  public let manufacturerUID: String
  /// Human-readable device name.
  public let name: String
  /// Physical transport reported for the device.
  public let transport: AudioTransport
  /// Whether the hardware supports prewarming before normal I/O.
  public let supportsPrewarming: Bool
  /// Sample frames expected between zero-timestamp updates.
  public let zeroTimestampPeriod: UInt32
  /// Sample rates offered to the host.
  public let sampleRates: [Double]
  /// Sample rate selected during device creation.
  public let initialSampleRate: Double
  /// Input and output streams published by the device.
  public let streams: [AudioStreamConfiguration]
  /// Boolean, level, selector, slider, and stereo-pan controls published by the device.
  public let controls: [AudioControlConfiguration]
  /// String-backed custom properties published by the device.
  public let customProperties: [AudioCustomPropertyConfiguration]

  /// Creates static AudioDriverKit device metadata and topology.
  public init(
    deviceUID: String,
    modelUID: String,
    manufacturerUID: String,
    name: String,
    transport: AudioTransport = .unknown,
    supportsPrewarming: Bool = false,
    zeroTimestampPeriod: UInt32 = 32_768,
    sampleRates: [Double],
    initialSampleRate: Double,
    streams: [AudioStreamConfiguration],
    controls: [AudioControlConfiguration] = [],
    customProperties: [AudioCustomPropertyConfiguration] = []
  ) {
    self.deviceUID = deviceUID
    self.modelUID = modelUID
    self.manufacturerUID = manufacturerUID
    self.name = name
    self.transport = transport
    self.supportsPrewarming = supportsPrewarming
    self.zeroTimestampPeriod = zeroTimestampPeriod
    self.sampleRates = sampleRates
    self.initialSampleRate = initialSampleRate
    self.streams = streams
    self.controls = controls
    self.customProperties = customProperties
  }
}

/// A lock-free snapshot of the latest real-time AudioDriverKit operation.
public struct AudioIOState: Sendable, Hashable {
  /// An operation observed in the real-time I/O callback.
  public enum Operation: UInt32, Sendable, Hashable {
    case beginRead = 0
    case writeEnd = 1
    case unavailable = 0xFFFF_FFFF
  }

  /// Monotonically increasing even snapshot sequence.
  public let sequence: UInt64
  /// Most recently observed I/O operation.
  public let operation: Operation
  /// Frames covered by the operation.
  public let frameCount: UInt32
  /// Device sample-timeline position.
  public let sampleTime: UInt64
  /// Host clock value associated with the operation.
  public let hostTime: UInt64

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 32 else { throw AudioRuntimeError.invalidPayload }
    sequence = try runtimePayload.readRuntimeInteger(at: 0)
    let rawOperation: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    guard let operation = Operation(rawValue: rawOperation) else {
      throw AudioRuntimeError.invalidOperation(rawOperation)
    }
    self.operation = operation
    frameCount = try runtimePayload.readRuntimeInteger(at: 12)
    sampleTime = try runtimePayload.readRuntimeInteger(at: 16)
    hostTime = try runtimePayload.readRuntimeInteger(at: 24)
  }
}

/// A lifecycle, format, control, or custom-property request from AudioDriverKit.
public enum AudioEvent: Sendable, Hashable {
  case started(flags: UInt64)
  case stopped(flags: UInt64)
  case sampleRateChanged(Double)
  case controlChanged(identifier: UInt32, value: AudioControlValue)
  case customPropertyChanged(identifier: UInt32, qualifier: String, value: String)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 4 else { throw AudioRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    switch kind {
    case 1...3:
      guard runtimePayload.count == 16 else { throw AudioRuntimeError.invalidPayload }
      let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let value: UInt64 = try runtimePayload.readRuntimeInteger(at: 8)
      guard reserved == 0 else { throw AudioRuntimeError.invalidPayload }
      switch kind {
      case 1: self = .started(flags: value)
      case 2: self = .stopped(flags: value)
      default: self = .sampleRateChanged(Double(bitPattern: value))
      }
    case 4:
      guard runtimePayload.count >= 20 else { throw AudioRuntimeError.invalidPayload }
      let identifier: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let value = try AudioControlValue(runtimePayload: Data(runtimePayload.dropFirst(4)))
      self = .controlChanged(identifier: identifier, value: value)
    case 5:
      guard runtimePayload.count >= 20 else { throw AudioRuntimeError.invalidPayload }
      let identifier: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
      let qualifierLength: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
      let valueLength: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
      let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 16)
      let qualifierEnd = 20 + Int(qualifierLength)
      let valueEnd = qualifierEnd + Int(valueLength)
      guard reserved == 0, qualifierLength > 0, qualifierLength <= 255, valueLength <= 4_096,
        valueEnd == runtimePayload.count,
        let qualifier = String(data: runtimePayload[20..<qualifierEnd], encoding: .utf8),
        let value = String(data: runtimePayload[qualifierEnd..<valueEnd], encoding: .utf8)
      else { throw AudioRuntimeError.invalidPayload }
      self = .customPropertyChanged(identifier: identifier, qualifier: qualifier, value: value)
    default: throw AudioRuntimeError.invalidEventKind(kind)
    }
  }
}

/// An invalid AudioDriverKit configuration, transfer, or runtime payload.
public enum AudioRuntimeError: Error, Sendable, Equatable {
  case invalidStreamIndex
  case invalidTransferRange
  case transferTooLarge
  case invalidPayload
  case invalidOperation(UInt32)
  case invalidEventKind(UInt32)
  case invalidControlValue
  case invalidCustomPropertyValue
}
