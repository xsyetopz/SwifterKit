import Foundation

/// An AudioDriverKit object addressed by a runtime command.
public enum AudioObjectTarget: Sendable, Hashable {
  /// The `IOUserAudioDriver` service itself.
  case driver
  /// The configured `IOUserAudioDevice`.
  case device
  /// A configured `IOUserAudioBox`, by its index in ``AudioDeviceConfiguration/boxes``.
  case box(UInt32)
  /// A configured `IOUserAudioClockDevice`, by its index in
  /// ``AudioDeviceConfiguration/clockDevices``.
  case clockDevice(UInt32)
  /// Any object the driver publishes, resolved through `GetAudioObjectForObjectID`.
  case object(UInt32)

  /// The largest number of boxes or clock devices one driver declares.
  public static let maximumTableCount: UInt32 = 4

  var runtimeFields: (kind: UInt32, index: UInt32) {
    switch self {
    case .driver: (RuntimeAudioTargetKind.driver.rawValue, 0)
    case .device: (RuntimeAudioTargetKind.device.rawValue, 0)
    case .box(let index): (RuntimeAudioTargetKind.box.rawValue, index)
    case .clockDevice(let index): (RuntimeAudioTargetKind.clock.rawValue, index)
    case .object(let objectID): (RuntimeAudioTargetKind.object.rawValue, objectID)
    }
  }

  func validated() throws -> Self {
    switch self {
    case .driver, .device: return self
    case .box(let index), .clockDevice(let index):
      guard index < Self.maximumTableCount else { throw AudioRuntimeError.invalidObjectTarget }
      return self
    case .object(let objectID):
      guard objectID != 0 else { throw AudioRuntimeError.invalidObjectTarget }
      return self
    }
  }
}

/// An AudioDriverKit object class identifier.
public struct AudioClassID: RawRepresentable, Sendable, Hashable {
  /// The unmodified AudioDriverKit value.
  public let rawValue: UInt32
  /// Preserves a raw AudioDriverKit class identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// `IOUserAudioObject`.
  public static let object = Self(rawValue: 0x616F_626A)
  /// `IOUserAudioDriver`.
  public static let driver = Self(rawValue: 0x6170_6C67)
  /// `IOUserAudioBox`.
  public static let box = Self(rawValue: 0x6162_6F78)
  /// `IOUserAudioDevice`.
  public static let device = Self(rawValue: 0x6164_6576)
  /// `IOUserAudioClockDevice`.
  public static let clock = Self(rawValue: 0x6163_6C6B)
}

/// The smoothing algorithm the host applies to a clock device's timestamps.
public struct AudioClockAlgorithm: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IOUserAudioClockAlgorithm` value.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserAudioClockAlgorithm` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Timestamps are used unfiltered.
  public static let raw = Self(rawValue: 0x7261_7777)
  /// A simple infinite-impulse-response filter.
  public static let simpleIIR = Self(rawValue: 0x6969_7266)
  /// A twelve-point moving-window average.
  public static let twelvePointMovingWindowAverage = Self(rawValue: 0x6D61_7667)
}

/// The I/O transport state AudioDriverKit reports for a clock device.
public enum AudioDeviceTransportState: UInt32, Sendable, Hashable {
  /// AudioDriverKit reports stopped clock-device I/O.
  case stopped = 0
  /// AudioDriverKit reports a clock device prepared for I/O.
  case prewarmed = 1
  /// AudioDriverKit reports that the clock device I/O is running.
  case running = 2
}

/// Which per-element string an object publishes.
public enum AudioElementNameKind: UInt32, Sendable, Hashable {
  /// `SetElementName` / `GetElementName`.
  case name = 0
  /// `SetElementCategoryName` / `GetElementCategoryName`.
  case category = 1
  /// `SetElementNumberName` / `GetElementNumberName`.
  case number = 2
}

/// Identity metadata read from an AudioDriverKit object.
public struct AudioObjectInfo: Sendable, Hashable {
  /// The object's `IOUserAudioObjectID`. Zero for the driver, which has none.
  public let objectID: UInt32
  /// The owning object's identifier. Zero for the driver.
  public let ownerObjectID: UInt32
  /// The concrete class identifier.
  public let classID: AudioClassID
  /// The base class identifier.
  public let baseClassID: AudioClassID
  /// The reported transport, or ``AudioTransport/unknown`` for objects without one.
  public let transport: AudioTransport
  /// The object name, or an empty string when none is set.
  public let name: String
  /// The box or device UID, or an empty string for objects without one.
  public let uid: String

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 32 else { throw AudioRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    ownerObjectID = try runtimePayload.readRuntimeInteger(at: 4)
    classID = AudioClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    baseClassID = AudioClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 12))
    transport = AudioTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 16))
    let nameLength = Int(try runtimePayload.readRuntimeInteger(at: 20) as UInt32)
    let uidLength = Int(try runtimePayload.readRuntimeInteger(at: 24) as UInt32)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    let base = runtimePayload.startIndex
    let maximum = RuntimeAudioLimits.nameMaximumLength
    guard reserved == 0, nameLength <= maximum, uidLength <= maximum,
      runtimePayload.count == 32 + nameLength + uidLength,
      let name = String(
        data: runtimePayload[(base + 32)..<(base + 32 + nameLength)],
        encoding: .utf8
      ), let uid = String(data: runtimePayload.suffix(uidLength), encoding: .utf8)
    else { throw AudioRuntimeError.invalidPayload }
    self.name = name
    self.uid = uid
  }
}

/// A driver, box, or clock-device notification or request from AudioDriverKit.
///
/// `boxAcquisitionRequested` and `clockDeviceSampleRateRequested` are required events. Answer
/// each with ``DriverContext/audioCompleteRequest(requestID:accept:failure:)`` within ten
/// seconds. After that, the extension rejects the request.
public enum AudioObjectEvent: Sendable, Hashable {
  /// `IOUserAudioDriver::StartDevice` started I/O on the object.
  case deviceStarted(objectID: UInt32, flags: UInt64)
  /// `IOUserAudioDriver::StopDevice` stopped I/O on the object.
  case deviceStopped(objectID: UInt32, flags: UInt64)
  /// A clock device's `StartIO` succeeded.
  /// Raised from `IOUserAudioClockDevice::StartIO`.
  case clockDeviceStarted(index: UInt32, flags: UInt64)
  /// A clock device's `StopIO` ran.
  /// Raised from `IOUserAudioClockDevice::StopIO`.
  case clockDeviceStopped(index: UInt32, flags: UInt64)
  /// A clock device applied a new sample rate.
  case clockDeviceSampleRateChanged(index: UInt32, sampleRate: Double)
  /// The host asked to acquire or release a box through `HandleChangeAcquireBox`.
  /// Raised from `IOUserAudioBox::HandleChangeAcquireBox`.
  case boxAcquisitionRequested(requestID: UInt32, box: UInt32, acquire: Bool)
  /// The host asked a clock device to change sample rate through `HandleChangeSampleRate`.
  /// Raised from `IOUserAudioClockDevice::HandleChangeSampleRate`.
  case clockDeviceSampleRateRequested(requestID: UInt32, index: UInt32, sampleRate: Double)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24 else { throw AudioRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let index: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let requestID: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    let value: UInt64 = try runtimePayload.readRuntimeInteger(at: 16)
    guard reserved == 0 else { throw AudioRuntimeError.invalidPayload }
    guard let eventKind = RuntimeAudioObjectEventKind(rawValue: kind) else {
      throw AudioRuntimeError.invalidEventKind(kind)
    }
    let requested = eventKind == .boxRequest || eventKind == .clockRequest
    guard requested == (requestID != 0) else { throw AudioRuntimeError.invalidPayload }
    switch eventKind {
    case .deviceStarted: self = .deviceStarted(objectID: index, flags: value)
    case .deviceStopped: self = .deviceStopped(objectID: index, flags: value)
    case .clockStarted: self = .clockDeviceStarted(index: index, flags: value)
    case .clockStopped: self = .clockDeviceStopped(index: index, flags: value)
    case .clockRateChanged:
      self = .clockDeviceSampleRateChanged(index: index, sampleRate: .init(bitPattern: value))
    case .boxRequest:
      guard value <= 1 else { throw AudioRuntimeError.invalidPayload }
      self = .boxAcquisitionRequested(requestID: requestID, box: index, acquire: value == 1)
    case .clockRequest:
      self = .clockDeviceSampleRateRequested(
        requestID: requestID,
        index: index,
        sampleRate: Double(bitPattern: value)
      )
    }
  }
}
