import Foundation

/// A VideoDriverKit object addressed by a runtime command.
public enum VideoObjectTarget: Sendable, Hashable {
  /// The `IOUserVideoDriver` service itself.
  case driver
  /// The configured `IOUserVideoDevice`.
  case device
  /// A configured `IOUserVideoBox`, by its index in ``VideoDeviceConfiguration/boxes``.
  case box(UInt32)
  /// A configured `IOUserVideoClockDevice`, by its index in
  /// ``VideoDeviceConfiguration/clockDevices``.
  case clockDevice(UInt32)
  /// Any object the driver publishes, resolved through `GetVideoObjectForObjectID`.
  case object(UInt32)

  /// The largest number of boxes or clock devices one driver declares.
  public static let maximumTableCount: UInt32 = 4

  var runtimeFields: (kind: UInt32, index: UInt32) {
    switch self {
    case .driver: (0, 0)
    case .device: (1, 0)
    case .box(let index): (2, index)
    case .clockDevice(let index): (3, index)
    case .object(let objectID): (4, objectID)
    }
  }

  func validated() throws -> Self {
    switch self {
    case .driver, .device: return self
    case .box(let index), .clockDevice(let index):
      guard index < Self.maximumTableCount else { throw VideoRuntimeError.invalidObjectTarget }
      return self
    case .object(let objectID):
      guard objectID != 0 else { throw VideoRuntimeError.invalidObjectTarget }
      return self
    }
  }
}

/// A VideoDriverKit object class identifier.
public struct VideoClassID: RawRepresentable, Sendable, Hashable {
  /// The unmodified VideoDriverKit value.
  public let rawValue: UInt32
  /// Preserves a raw VideoDriverKit class identifier.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// `IOUserVideoObject`.
  public static let object = Self(rawValue: 0x616F_626A)
  /// `IOUserVideoDriver`.
  public static let driver = Self(rawValue: 0x6170_6C67)
  /// `IOUserVideoBox`.
  public static let box = Self(rawValue: 0x6162_6F78)
  /// `IOUserVideoDevice`.
  public static let device = Self(rawValue: 0x6164_6576)
  /// `IOUserVideoClockDevice`.
  public static let clock = Self(rawValue: 0x6163_6C6B)
  /// `IOUserVideoStream`.
  public static let stream = Self(rawValue: 0x6173_7472)
}

/// The smoothing algorithm the host applies to a clock device's timestamps.
public struct VideoClockAlgorithm: RawRepresentable, Sendable, Hashable {
  /// The unmodified `IOUserVideoClockAlgorithm` value.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserVideoClockAlgorithm` value.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Timestamps are used unfiltered.
  public static let raw = Self(rawValue: 0x7261_7777)
  /// A simple infinite-impulse-response filter.
  public static let simpleIIR = Self(rawValue: 0x6969_7266)
  /// A twelve-point moving-window average.
  public static let twelvePointMovingWindowAverage = Self(rawValue: 0x6D61_7667)
}

/// The I/O transport state VideoDriverKit reports for a clock device.
public enum VideoDeviceTransportState: UInt32, Sendable, Hashable {
  case stopped = 0
  case prewarmed = 1
  case running = 2
}

/// Which per-element string an object publishes.
public enum VideoElementNameKind: UInt32, Sendable, Hashable {
  /// `SetElementName` / `GetElementName`.
  case name = 0
  /// `SetElementCategoryName` / `GetElementCategoryName`.
  case category = 1
  /// `SetElementNumberName` / `GetElementNumberName`.
  case number = 2
}

/// The object that holds a configured custom property.
public enum VideoCustomPropertyOwner: UInt32, Sendable, Hashable {
  /// Removed from its owner; configuration and values are kept.
  case detached = 0
  /// Added to the `IOUserVideoDevice`, where the runtime places it at start.
  case device = 1
  /// Added to the `IOUserVideoDriver`.
  case driver = 2
}

/// A stream-queue notification the driver sends to the host.
public enum VideoBufferQueueNotification: UInt32, Sendable, Hashable {
  /// `IOUserVideoDriver::BufferQueueChange`.
  case bufferQueueChange = 1
  /// `IOUserVideoDriver::OutputBufferNotification`.
  case outputBufferNotification = 2
  /// The stream's own `IOUserVideoStream::SendBufferQueueChange`; `changeAction` must be zero.
  case streamBufferQueueChange = 3
}

/// Identity metadata read from a VideoDriverKit object.
public struct VideoObjectInfo: Sendable, Hashable {
  /// The object's `IOUserVideoObjectID`; zero for the driver.
  public let objectID: UInt32
  /// The concrete class identifier.
  public let classID: VideoClassID
  /// The base class identifier.
  public let baseClassID: VideoClassID
  /// The reported transport, or ``VideoTransport/unknown`` for objects without one.
  public let transport: VideoTransport
  /// The object name, or an empty string when none is set.
  public let name: String
  /// The box or device UID, or an empty string for objects without one.
  public let uid: String

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 32 else { throw VideoRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    let reserved0: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    classID = VideoClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 8))
    baseClassID = VideoClassID(rawValue: try runtimePayload.readRuntimeInteger(at: 12))
    transport = VideoTransport(rawValue: try runtimePayload.readRuntimeInteger(at: 16))
    let nameLength = Int(try runtimePayload.readRuntimeInteger(at: 20) as UInt32)
    let uidLength = Int(try runtimePayload.readRuntimeInteger(at: 24) as UInt32)
    let reserved1: UInt32 = try runtimePayload.readRuntimeInteger(at: 28)
    let base = runtimePayload.startIndex
    guard reserved0 == 0, reserved1 == 0, nameLength <= 255, uidLength <= 255,
      runtimePayload.count == 32 + nameLength + uidLength,
      let name = String(
        data: runtimePayload[(base + 32)..<(base + 32 + nameLength)],
        encoding: .utf8
      ), let uid = String(data: runtimePayload.suffix(uidLength), encoding: .utf8)
    else { throw VideoRuntimeError.invalidPayload }
    self.name = name
    self.uid = uid
  }
}

/// A driver, box, or clock-device notification or request from VideoDriverKit.
///
/// `boxAcquisitionRequested` and `clockDeviceSampleRateRequested` are required events. Answer
/// each with ``DriverContext/videoCompleteRequest(requestID:accept:failure:)`` within ten
/// seconds; after that the extension rejects the request.
public enum VideoObjectEvent: Sendable, Hashable {
  /// `IOUserVideoDriver::StartDevice` started I/O on the object.
  case deviceStarted(objectID: UInt32, flags: UInt64)
  /// `IOUserVideoDriver::StopDevice` stopped I/O on the object.
  case deviceStopped(objectID: UInt32, flags: UInt64)
  /// A clock device's `StartIO` succeeded.
  case clockDeviceStarted(index: UInt32, flags: UInt64)
  /// A clock device's `StopIO` ran.
  case clockDeviceStopped(index: UInt32, flags: UInt64)
  /// A clock device applied a new sample rate.
  case clockDeviceSampleRateChanged(index: UInt32, sampleRate: Double)
  /// The host asked to acquire or release a box through `HandleChangeAcquireBox`.
  case boxAcquisitionRequested(requestID: UInt32, box: UInt32, acquire: Bool)
  /// The host asked a clock device to change sample rate through `HandleChangeSampleRate`.
  case clockDeviceSampleRateRequested(requestID: UInt32, index: UInt32, sampleRate: Double)
  /// VideoDriverKit called a clock device's `StreamFormatChanged` for a stream object.
  case clockDeviceStreamFormatChanged(index: UInt32, streamObjectID: UInt32)
  /// The video device's `StreamFormatChanged` ran for a stream.
  case deviceStreamFormatChanged(streamObjectID: UInt32)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 24 else { throw VideoRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let index: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let requestID: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    let value: UInt64 = try runtimePayload.readRuntimeInteger(at: 16)
    guard reserved == 0 else { throw VideoRuntimeError.invalidPayload }
    let requested = kind == 6 || kind == 7
    guard requested == (requestID != 0) else { throw VideoRuntimeError.invalidPayload }
    switch kind {
    case 1: self = .deviceStarted(objectID: index, flags: value)
    case 2: self = .deviceStopped(objectID: index, flags: value)
    case 3: self = .clockDeviceStarted(index: index, flags: value)
    case 4: self = .clockDeviceStopped(index: index, flags: value)
    case 5: self = .clockDeviceSampleRateChanged(index: index, sampleRate: .init(bitPattern: value))
    case 6:
      guard value <= 1 else { throw VideoRuntimeError.invalidPayload }
      self = .boxAcquisitionRequested(requestID: requestID, box: index, acquire: value == 1)
    case 7:
      self = .clockDeviceSampleRateRequested(
        requestID: requestID,
        index: index,
        sampleRate: Double(bitPattern: value)
      )
    case 8:
      guard value <= UInt64(UInt32.max) else { throw VideoRuntimeError.invalidPayload }
      self = .clockDeviceStreamFormatChanged(index: index, streamObjectID: UInt32(value))
    case 9:
      guard index == 0, value <= UInt64(UInt32.max) else { throw VideoRuntimeError.invalidPayload }
      self = .deviceStreamFormatChanged(streamObjectID: UInt32(value))
    default: throw VideoRuntimeError.invalidEventKind(kind)
    }
  }
}
