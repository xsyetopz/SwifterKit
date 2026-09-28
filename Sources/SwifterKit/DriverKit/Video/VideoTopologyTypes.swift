import Foundation

/// Static metadata for one `IOUserVideoBox`.
public struct VideoBoxConfiguration: Sendable, Hashable {
  /// Stable box identifier reported to the host.
  public let uid: String
  /// Human-readable box name.
  public let name: String
  /// Physical transport reported for the box.
  public let transport: VideoTransport
  /// Whether the host may acquire the box.
  public let isAcquirable: Bool
  /// Whether the box starts acquired.
  public let isAcquired: Bool
  /// Whether the box contains audio hardware.
  public let hasAudio: Bool
  /// Whether the box contains MIDI hardware.
  public let hasMIDI: Bool
  /// Whether the box contains video hardware.
  public let hasVideo: Bool
  /// Whether the box's content is protected.
  public let isProtected: Bool
  /// Whether the box owns the configured video device.
  public let ownsDevice: Bool
  /// Indices into ``VideoDeviceConfiguration/clockDevices`` that the box owns.
  public let clockDevices: [UInt32]

  /// Creates static box metadata.
  public init(
    uid: String,
    name: String,
    transport: VideoTransport = .unknown,
    isAcquirable: Bool = false,
    isAcquired: Bool = true,
    hasAudio: Bool = false,
    hasMIDI: Bool = false,
    hasVideo: Bool = true,
    isProtected: Bool = false,
    ownsDevice: Bool = false,
    clockDevices: [UInt32] = []
  ) {
    self.uid = uid
    self.name = name
    self.transport = transport
    self.isAcquirable = isAcquirable
    self.isAcquired = isAcquired
    self.hasAudio = hasAudio
    self.hasMIDI = hasMIDI
    self.hasVideo = hasVideo
    self.isProtected = isProtected
    self.ownsDevice = ownsDevice
    self.clockDevices = clockDevices
  }
}

/// Static metadata for one `IOUserVideoClockDevice`, a device that publishes a clock but no
/// streams.
public struct VideoClockDeviceConfiguration: Sendable, Hashable {
  /// Stable device identifier reported to the host.
  public let deviceUID: String
  /// Stable model identifier reported to the host.
  public let modelUID: String
  /// Stable manufacturer identifier reported to the host.
  public let manufacturerUID: String
  /// Human-readable device name.
  public let name: String
  /// Physical transport reported for the device.
  public let transport: VideoTransport
  /// Sample rates offered to the host.
  public let sampleRates: [Double]
  /// Sample rate selected during device creation.
  public let initialSampleRate: Double
  /// Clock domain shared by devices that run from one clock. Zero means none.
  public let clockDomain: UInt32
  /// The timestamp smoothing algorithm.
  public let clockAlgorithm: VideoClockAlgorithm
  /// Whether the clock is stable.
  public let clockIsStable: Bool
  /// Whether the device is hidden from device lists.
  public let isHidden: Bool
  /// Input latency in frames.
  public let inputLatency: UInt32
  /// Output latency in frames.
  public let outputLatency: UInt32

  /// Creates static clock-device metadata.
  public init(
    deviceUID: String,
    modelUID: String,
    manufacturerUID: String,
    name: String,
    transport: VideoTransport = .unknown,
    sampleRates: [Double],
    initialSampleRate: Double,
    clockDomain: UInt32 = 0,
    clockAlgorithm: VideoClockAlgorithm = .simpleIIR,
    clockIsStable: Bool = true,
    isHidden: Bool = false,
    inputLatency: UInt32 = 0,
    outputLatency: UInt32 = 0
  ) {
    self.deviceUID = deviceUID
    self.modelUID = modelUID
    self.manufacturerUID = manufacturerUID
    self.name = name
    self.transport = transport
    self.sampleRates = sampleRates
    self.initialSampleRate = initialSampleRate
    self.clockDomain = clockDomain
    self.clockAlgorithm = clockAlgorithm
    self.clockIsStable = clockIsStable
    self.isHidden = isHidden
    self.inputLatency = inputLatency
    self.outputLatency = outputLatency
  }
}

/// A snapshot of an `IOUserVideoBox`'s state.
public struct VideoBoxState: Sendable, Hashable {
  /// The box's object identifier.
  public let objectID: UInt32
  /// The reported transport.
  public let transport: VideoTransport
  /// `HasAudio()`.
  public let hasAudio: Bool
  /// `HasMIDI()`.
  public let hasMIDI: Bool
  /// `HasVideo()`.
  public let hasVideo: Bool
  /// `IsAcquirable()`.
  public let isAcquirable: Bool
  /// `IsAcquired()`.
  public let isAcquired: Bool
  /// `IsProtected()`.
  public let isProtected: Bool
  /// `GetAcquisitionFailure()`, a `kern_return_t`.
  public let acquisitionFailure: Int32

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 16 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    transport = VideoTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 4))
    let flags: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    typealias Flag = RuntimeVideoBoxState
    guard flags & ~Flag.allBits == 0 else { throw VideoRuntimeError.invalidPayload }
    hasAudio = flags & Flag.hasAudio.rawValue != 0
    hasMIDI = flags & Flag.hasMIDI.rawValue != 0
    hasVideo = flags & Flag.hasVideo.rawValue != 0
    isAcquirable = flags & Flag.isAcquirable.rawValue != 0
    isAcquired = flags & Flag.isAcquired.rawValue != 0
    isProtected = flags & Flag.isProtected.rawValue != 0
    acquisitionFailure = try runtimePayload.readRuntimeInteger(at: 12)
  }
}

/// A box property Swift can change.
public enum VideoBoxProperty: Sendable, Hashable {
  /// Sets the transport reported by the box.
  case transport(VideoTransport)
  /// Sets whether the box contains audio.
  case hasAudio(Bool)
  /// Sets whether the box contains MIDI.
  case hasMIDI(Bool)
  /// Sets whether the box contains video.
  case hasVideo(Bool)
  /// Sets whether the host can acquire the box.
  case isAcquirable(Bool)
  /// Sets whether the host acquired the box.
  case isAcquired(Bool)
  /// Sets whether the box protects its contents.
  case isProtected(Bool)
  /// A `kern_return_t` the host reports when acquisition fails.
  case acquisitionFailure(Int32)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    let fields: (RuntimeVideoBoxProperty, UInt64) =
      switch self {
      case .transport(let value): (.transport, UInt64(value.rawValue))
      case .hasAudio(let value): (.hasAudio, value ? 1 : 0)
      case .hasMIDI(let value): (.hasMIDI, value ? 1 : 0)
      case .hasVideo(let value): (.hasVideo, value ? 1 : 0)
      case .isAcquirable(let value): (.isAcquirable, value ? 1 : 0)
      case .isAcquired(let value): (.isAcquired, value ? 1 : 0)
      case .isProtected(let value): (.isProtected, value ? 1 : 0)
      case .acquisitionFailure(let value): (.acquisitionFailure, UInt64(UInt32(bitPattern: value)))
      }
    return (fields.0.rawValue, fields.1)
  }
}

/// A snapshot of an `IOUserVideoClockDevice`'s clock, timing, and I/O state.
public struct VideoClockDeviceState: Sendable, Hashable {
  /// The object identifier.
  public let objectID: UInt32
  /// The current nominal sample rate.
  public let sampleRate: Double
  /// The sample rates offered to the host.
  public let availableSampleRates: [Double]
  /// The last `UpdateCurrentZeroTimestamp` sample time.
  public let zeroSampleTime: UInt64
  /// The last `UpdateCurrentZeroTimestamp` host time.
  public let zeroHostTime: UInt64
  /// The host's current input sample time.
  public let clientInputSampleTime: UInt64
  /// The host's current output sample time.
  public let clientOutputSampleTime: UInt64
  /// The clock domain.
  public let clockDomain: UInt32
  /// The timestamp smoothing algorithm.
  public let clockAlgorithm: VideoClockAlgorithm
  /// The reported transport.
  public let transport: VideoTransport
  /// The I/O transport state.
  public let transportState: VideoDeviceTransportState
  /// `GetClockIsStable()`.
  public let clockIsStable: Bool
  /// `GetDeviceIsAlive()`.
  public let isAlive: Bool
  /// `GetDeviceIsRunning()`.
  public let isRunning: Bool
  /// `GetIsHidden()`.
  public let isHidden: Bool
  /// Input latency in frames.
  public let inputLatency: UInt32
  /// Output latency in frames.
  public let outputLatency: UInt32

  /// The most sample rates one state snapshot carries.
  static let maximumSampleRates = RuntimeVideoLimits.maximumSampleRates

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 80 else { throw VideoRuntimeError.invalidPayload }
    sampleRate = Double(bitPattern: try runtimePayload.readRuntimeInteger(at: 0))
    zeroSampleTime = try runtimePayload.readRuntimeInteger(at: 8)
    zeroHostTime = try runtimePayload.readRuntimeInteger(at: 16)
    clientInputSampleTime = try runtimePayload.readRuntimeInteger(at: 24)
    clientOutputSampleTime = try runtimePayload.readRuntimeInteger(at: 32)
    objectID = try runtimePayload.readRuntimeInteger(at: 40)
    clockDomain = try runtimePayload.readRuntimeInteger(at: 44)
    clockAlgorithm = VideoClockAlgorithm(rawValue: try runtimePayload.readRuntimeInteger(at: 48))
    transport = VideoTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 52))
    let rawState: UInt32 = try runtimePayload.readRuntimeInteger(at: 56)
    let flags: UInt32 = try runtimePayload.readRuntimeInteger(at: 60)
    inputLatency = try runtimePayload.readRuntimeInteger(at: 64)
    outputLatency = try runtimePayload.readRuntimeInteger(at: 68)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 72)
    let count = Int(try runtimePayload.readRuntimeInteger(at: 76) as UInt32)
    typealias Flag = RuntimeVideoClockState
    guard let transportState = VideoDeviceTransportState(rawValue: rawState),
      flags & ~Flag.allBits == 0, reserved == 0, count <= Self.maximumSampleRates,
      runtimePayload.count == 80 + count * 8
    else { throw VideoRuntimeError.invalidPayload }
    self.transportState = transportState
    clockIsStable = flags & Flag.clockIsStable.rawValue != 0
    isAlive = flags & Flag.isAlive.rawValue != 0
    isRunning = flags & Flag.isRunning.rawValue != 0
    isHidden = flags & Flag.isHidden.rawValue != 0
    availableSampleRates = try (0..<count).map {
      Double(bitPattern: try runtimePayload.readRuntimeInteger(at: 80 + $0 * 8))
    }
  }
}

/// A clock-device property Swift can change.
public enum VideoClockDeviceProperty: Sendable, Hashable {
  /// Sets the clock domain shared by synchronized devices.
  case clockDomain(UInt32)
  /// Sets the timestamp smoothing algorithm.
  case clockAlgorithm(VideoClockAlgorithm)
  /// Sets whether the clock reports stable timestamps.
  case clockIsStable(Bool)
  /// Sets whether the clock device reports that it is alive.
  case isAlive(Bool)
  /// Sets whether the host hides the clock device from device lists.
  case isHidden(Bool)
  /// Sets the clock device input latency in frames.
  case inputLatency(UInt32)
  /// Sets the clock device output latency in frames.
  case outputLatency(UInt32)
  /// Sets the transport reported by the clock device.
  case transport(VideoTransport)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    let fields: (RuntimeVideoClockProperty, UInt64) =
      switch self {
      case .clockDomain(let value): (.clockDomain, UInt64(value))
      case .clockAlgorithm(let value): (.clockAlgorithm, UInt64(value.rawValue))
      case .clockIsStable(let value): (.clockIsStable, value ? 1 : 0)
      case .isAlive(let value): (.isAlive, value ? 1 : 0)
      case .isHidden(let value): (.isHidden, value ? 1 : 0)
      case .inputLatency(let value): (.inputLatency, UInt64(value))
      case .outputLatency(let value): (.outputLatency, UInt64(value))
      case .transport(let value): (.transport, UInt64(value.rawValue))
      }
    return (fields.0.rawValue, fields.1)
  }
}
