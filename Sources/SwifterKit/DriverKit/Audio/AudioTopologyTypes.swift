import Foundation

/// Static metadata for one `IOUserAudioBox`.
public struct AudioBoxConfiguration: Sendable, Hashable {
  /// Stable box identifier reported to Core Audio.
  public let uid: String
  /// Human-readable box name.
  public let name: String
  /// Physical transport reported for the box.
  public let transport: AudioTransport
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
  /// Whether the box owns the configured audio device.
  public let ownsDevice: Bool
  /// Indices into ``AudioDeviceConfiguration/clockDevices`` that the box owns.
  public let clockDevices: [UInt32]

  /// Creates static box metadata.
  public init(
    uid: String,
    name: String,
    transport: AudioTransport = .unknown,
    isAcquirable: Bool = false,
    isAcquired: Bool = true,
    hasAudio: Bool = true,
    hasMIDI: Bool = false,
    hasVideo: Bool = false,
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

/// Static metadata for one `IOUserAudioClockDevice`, a device that publishes a clock but no
/// streams.
public struct AudioClockDeviceConfiguration: Sendable, Hashable {
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
  /// Clock domain shared by devices that run from one clock; zero means none.
  public let clockDomain: UInt32
  /// The timestamp smoothing algorithm.
  public let clockAlgorithm: AudioClockAlgorithm
  /// Whether the clock is stable.
  public let clockIsStable: Bool
  /// Whether the device is hidden from device lists.
  public let isHidden: Bool
  /// Input latency in frames.
  public let inputLatency: UInt32
  /// Output latency in frames.
  public let outputLatency: UInt32
  /// Whether the host saves and restores the device's controls, or `nil` for the framework
  /// default. Applied only when the extension is built with the DriverKit 25.5 SDK or newer.
  public let wantsControlsRestored: Bool?

  /// Creates static clock-device metadata.
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
    clockDomain: UInt32 = 0,
    clockAlgorithm: AudioClockAlgorithm = .simpleIIR,
    clockIsStable: Bool = true,
    isHidden: Bool = false,
    inputLatency: UInt32 = 0,
    outputLatency: UInt32 = 0,
    wantsControlsRestored: Bool? = nil
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
    self.clockDomain = clockDomain
    self.clockAlgorithm = clockAlgorithm
    self.clockIsStable = clockIsStable
    self.isHidden = isHidden
    self.inputLatency = inputLatency
    self.outputLatency = outputLatency
    self.wantsControlsRestored = wantsControlsRestored
  }
}

/// A snapshot of an `IOUserAudioBox`'s state.
public struct AudioBoxState: Sendable, Hashable {
  /// The box's object identifier.
  public let objectID: UInt32
  /// The reported transport.
  public let transport: AudioTransport
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
    guard runtimePayload.count == 16 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    transport = AudioTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 4))
    let flags: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    guard flags & ~0x3F == 0 else { throw AudioRuntimeError.invalidPayload }
    hasAudio = flags & 0x1 != 0
    hasMIDI = flags & 0x2 != 0
    hasVideo = flags & 0x4 != 0
    isAcquirable = flags & 0x8 != 0
    isAcquired = flags & 0x10 != 0
    isProtected = flags & 0x20 != 0
    acquisitionFailure = try runtimePayload.readRuntimeInteger(at: 12)
  }
}

/// A box property Swift can change.
public enum AudioBoxProperty: Sendable, Hashable {
  case transport(AudioTransport)
  case hasAudio(Bool)
  case hasMIDI(Bool)
  case hasVideo(Bool)
  case isAcquirable(Bool)
  case isAcquired(Bool)
  case isProtected(Bool)
  /// A `kern_return_t` the host reports when acquisition fails.
  case acquisitionFailure(Int32)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .transport(let value): (1, UInt64(value.rawValue))
    case .hasAudio(let value): (2, value ? 1 : 0)
    case .hasMIDI(let value): (3, value ? 1 : 0)
    case .hasVideo(let value): (4, value ? 1 : 0)
    case .isAcquirable(let value): (5, value ? 1 : 0)
    case .isAcquired(let value): (6, value ? 1 : 0)
    case .isProtected(let value): (7, value ? 1 : 0)
    case .acquisitionFailure(let value): (8, UInt64(UInt32(bitPattern: value)))
    }
  }
}

/// A snapshot of an `IOUserAudioClockDevice`'s clock, timing, and I/O state.
public struct AudioClockDeviceState: Sendable, Hashable {
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
  public let clockAlgorithm: AudioClockAlgorithm
  /// The reported transport.
  public let transport: AudioTransport
  /// The I/O transport state.
  public let transportState: AudioDeviceTransportState
  /// `GetClockIsStable()`.
  public let clockIsStable: Bool
  /// `GetDeviceIsAlive()`.
  public let isAlive: Bool
  /// `GetDeviceIsRunning()`.
  public let isRunning: Bool
  /// `GetIsHidden()`.
  public let isHidden: Bool
  /// `GetSupportsPrewarming()`.
  public let supportsPrewarming: Bool
  /// Input latency in frames.
  public let inputLatency: UInt32
  /// Output latency in frames.
  public let outputLatency: UInt32
  /// Sample frames between zero-timestamp updates.
  public let zeroTimestampPeriod: UInt32

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 80 else { throw AudioRuntimeError.invalidPayload }
    sampleRate = Double(bitPattern: try runtimePayload.readRuntimeInteger(at: 0))
    zeroSampleTime = try runtimePayload.readRuntimeInteger(at: 8)
    zeroHostTime = try runtimePayload.readRuntimeInteger(at: 16)
    clientInputSampleTime = try runtimePayload.readRuntimeInteger(at: 24)
    clientOutputSampleTime = try runtimePayload.readRuntimeInteger(at: 32)
    objectID = try runtimePayload.readRuntimeInteger(at: 40)
    clockDomain = try runtimePayload.readRuntimeInteger(at: 44)
    clockAlgorithm = AudioClockAlgorithm(rawValue: try runtimePayload.readRuntimeInteger(at: 48))
    transport = AudioTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 52))
    let rawState: UInt32 = try runtimePayload.readRuntimeInteger(at: 56)
    let flags: UInt32 = try runtimePayload.readRuntimeInteger(at: 60)
    inputLatency = try runtimePayload.readRuntimeInteger(at: 64)
    outputLatency = try runtimePayload.readRuntimeInteger(at: 68)
    zeroTimestampPeriod = try runtimePayload.readRuntimeInteger(at: 72)
    let count = Int(try runtimePayload.readRuntimeInteger(at: 76) as UInt32)
    guard let transportState = AudioDeviceTransportState(rawValue: rawState), flags & ~0x1F == 0,
      count <= 64, runtimePayload.count == 80 + count * 8
    else { throw AudioRuntimeError.invalidPayload }
    self.transportState = transportState
    clockIsStable = flags & 0x1 != 0
    isAlive = flags & 0x2 != 0
    isRunning = flags & 0x4 != 0
    isHidden = flags & 0x8 != 0
    supportsPrewarming = flags & 0x10 != 0
    availableSampleRates = try (0..<count).map {
      Double(bitPattern: try runtimePayload.readRuntimeInteger(at: 80 + $0 * 8))
    }
  }
}

/// A clock-device property Swift can change.
public enum AudioClockDeviceProperty: Sendable, Hashable {
  case clockDomain(UInt32)
  case clockAlgorithm(AudioClockAlgorithm)
  case clockIsStable(Bool)
  case isAlive(Bool)
  case isHidden(Bool)
  case inputLatency(UInt32)
  case outputLatency(UInt32)
  case transport(AudioTransport)
  /// Sample frames between zero-timestamp updates, 16 through 1,048,576.
  case zeroTimestampPeriod(UInt32)
  /// `SetWantsControlsRestored`; the extension answers `kIOReturnUnsupported` when built with
  /// an SDK older than DriverKit 25.5 or run on an older system.
  case wantsControlsRestored(Bool)

  var runtimeFields: (selector: UInt32, value: UInt64) {
    switch self {
    case .clockDomain(let value): (1, UInt64(value))
    case .clockAlgorithm(let value): (2, UInt64(value.rawValue))
    case .clockIsStable(let value): (3, value ? 1 : 0)
    case .isAlive(let value): (4, value ? 1 : 0)
    case .isHidden(let value): (5, value ? 1 : 0)
    case .inputLatency(let value): (6, UInt64(value))
    case .outputLatency(let value): (7, UInt64(value))
    case .transport(let value): (8, UInt64(value.rawValue))
    case .zeroTimestampPeriod(let value): (9, UInt64(value))
    case .wantsControlsRestored(let value): (10, value ? 1 : 0)
    }
  }
}
