import Foundation

/// A service-matching or system-state watch the extension runs, returned by
/// ``DriverContext/watchServices(matching:)`` or ``DriverContext/watchSystemState(items:)``.
public struct ServiceWatch: Sendable, Hashable {
  /// The identifier that the watch's notifications repeat.
  public let id: UInt32

  /// Wraps an identifier the extension returned.
  public init(id: UInt32) { self.id = id }
}

/// Limits the extension enforces on watches.
public enum ServiceWatchLimits {
  /// The most service and system-state watches that run at once, together.
  public static let maximumWatches = RuntimeDispatchLimits.maximumServiceWatches
  /// The most items one system-state watch names.
  public static let maximumStateItems = RuntimeDispatchLimits.maximumWatchedStateItems
}

/// A service that started or stopped matching a ``ServiceWatch``, from
/// `IOServiceNotificationDispatchSource`.
///
/// A driver extension sees another service only for the duration of the notification, so the
/// event carries its registry entry ID and name; look the service up from the host with
/// ``DriverClient`` when more is needed.
public struct ServiceMatchNotification: Sendable, Hashable {
  /// Whether the service matched or terminated.
  public enum Kind: UInt32, Sendable, Hashable {
    /// The service stopped matching, `kIOServiceNotificationTypeTerminated`.
    case terminated = 0
    /// The service matched, `kIOServiceNotificationTypeMatched`.
    case matched = 1
  }

  /// The watch that observed the service.
  public let watch: ServiceWatch
  /// Whether the service matched or terminated.
  public let kind: Kind
  /// The watch's notification count, from 1; a gap means lossy events were dropped.
  public let sequence: UInt64
  /// The service's `IORegistryEntry` identifier.
  public let registryEntryID: UInt64
  /// The service's registry name, or an empty string when it has none.
  public let name: String

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 32 else { throw ServiceRuntimeError.invalidPayload }
    let id: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let rawKind: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    let nameLength: UInt32 = try runtimePayload.readRuntimeInteger(at: 24)
    guard id != 0, let kind = Kind(rawValue: rawKind),
      try runtimePayload.readRuntimeInteger(at: 28) as UInt32 == 0,
      nameLength <= ServicePropertyCoding.maximumNameLength,
      runtimePayload.count == 32 + Int(nameLength),
      let name = String(bytes: runtimePayload.dropFirst(32), encoding: .utf8)
    else { throw ServiceRuntimeError.invalidPayload }
    watch = ServiceWatch(id: id)
    self.kind = kind
    sequence = try runtimePayload.readRuntimeInteger(at: 8)
    registryEntryID = try runtimePayload.readRuntimeInteger(at: 16)
    self.name = name
    guard sequence != 0 else { throw ServiceRuntimeError.invalidPayload }
  }
}

/// A system state item that changed, from `IOServiceStateNotificationDispatchSource`.
public struct SystemStateNotification: Sendable, Hashable {
  /// The watch that observed the item.
  public let watch: ServiceWatch
  /// The watch's notification count, from 1; a gap means lossy events were dropped.
  public let sequence: UInt64
  /// The item's name.
  public let item: String
  /// The item's value from `StateNotificationItemCopy`, or `nil` when the item has no value or
  /// the value does not fit one event.
  public let value: [String: DriverProperty]?

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 16 else { throw ServiceRuntimeError.invalidPayload }
    let id: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let nameLength = Int(try runtimePayload.readRuntimeInteger(at: 4) as UInt32)
    guard id != 0, (1...ServicePropertyCoding.maximumNameLength).contains(nameLength),
      runtimePayload.count >= 16 + nameLength
    else { throw ServiceRuntimeError.invalidPayload }
    let start = runtimePayload.startIndex
    let nameBytes = runtimePayload[(start + 16)..<(start + 16 + nameLength)]
    guard !nameBytes.contains(0), let item = String(bytes: nameBytes, encoding: .utf8) else {
      throw ServiceRuntimeError.invalidPayload
    }
    let rest = runtimePayload[(start + 16 + nameLength)...]
    if rest.isEmpty {
      value = nil
    } else {
      guard case .dictionary(let dictionary) = try ServicePropertyCoding.decode(Data(rest)) else {
        throw ServiceRuntimeError.invalidPayload
      }
      value = dictionary
    }
    watch = ServiceWatch(id: id)
    sequence = try runtimePayload.readRuntimeInteger(at: 8)
    self.item = item
    guard sequence != 0 else { throw ServiceRuntimeError.invalidPayload }
  }
}

extension DriverCommand {
  /// Creates a service watch through `IOServiceNotificationDispatchSource::Create`.
  ///
  /// The matching dictionary holds `IOProviderClass`, `IONameMatch` for a ``DriverServiceMatch``
  /// name, and `IOPropertyMatch` for its registry properties.
  public static func watchServices(matching criteria: DriverServiceMatch) throws -> Self {
    _ = try ServicePropertyCoding.nameBytes(criteria.serviceClass)
    var matching: [String: DriverProperty] = ["IOProviderClass": .string(criteria.serviceClass)]
    if let name = criteria.name {
      _ = try ServicePropertyCoding.nameBytes(name)
      matching["IONameMatch"] = .string(name)
    }
    if !criteria.registryProperties.isEmpty {
      for key in criteria.registryProperties.keys { _ = try ServicePropertyCoding.nameBytes(key) }
      matching["IOPropertyMatch"] = .dictionary(criteria.registryProperties)
    }
    let payload = try ServicePropertyCoding.encode(.dictionary(matching))
    guard payload.count <= ServicePropertyCoding.maximumPayloadSize else {
      throw ServiceRuntimeError.payloadTooLarge
    }
    return service(.watchServices, payload: payload, responseSize: 8)
  }

  /// Creates a system-state watch through `IOServiceStateNotificationDispatchSource::Create` on
  /// the system state notification service.
  public static func watchSystemState(items: [String]) throws -> Self {
    guard !items.isEmpty else { throw ServiceRuntimeError.emptyRequest }
    guard items.count <= ServiceWatchLimits.maximumStateItems else {
      throw ServiceRuntimeError.payloadTooLarge
    }
    for item in items { _ = try ServicePropertyCoding.nameBytes(item) }
    let payload = try ServicePropertyCoding.encode(.array(items.map(DriverProperty.string)))
    return service(.watchSystemState, payload: payload, responseSize: 8)
  }

  /// Creates a watch cancellation through the watch's dispatch source `Cancel`.
  public static func cancelWatch(_ watch: ServiceWatch) throws -> Self {
    service(.watchCancel, payload: try identifierPayload(watch.id))
  }
}

extension DriverContext {
  /// Watches for services that match `criteria`; each match and termination arrives as an event
  /// that ``DriverEvent/serviceMatchNotification()`` decodes, starting with services that
  /// already match.
  ///
  /// At most ``ServiceWatchLimits/maximumWatches`` watches run at once; more fail with
  /// `kIOReturnNoResources`. Watches end when the host disconnects.
  public func watchServices(matching criteria: DriverServiceMatch) async throws -> ServiceWatch {
    let reply = try await execute(try .watchServices(matching: criteria))
    return ServiceWatch(id: try Self.identifier(from: reply))
  }

  /// Watches system state items such as those ``createSystemStateItem(named:value:)`` creates;
  /// each change arrives as an event that ``DriverEvent/systemStateNotification()`` decodes.
  public func watchSystemState(items: [String]) async throws -> ServiceWatch {
    let reply = try await execute(try .watchSystemState(items: items))
    return ServiceWatch(id: try Self.identifier(from: reply))
  }

  /// Cancels a watch from ``watchServices(matching:)`` or ``watchSystemState(items:)``.
  public func cancelWatch(_ watch: ServiceWatch) async throws {
    _ = try await execute(try .cancelWatch(watch))
  }
}

extension DriverEvent {
  /// Decodes a service match or termination from a ``ServiceWatch``.
  public func serviceMatchNotification() throws -> ServiceMatchNotification? {
    guard type == RuntimeEventType.watchServices.rawValue else { return nil }
    return try ServiceMatchNotification(runtimePayload: Data(payload))
  }

  /// Decodes a system state item change from a ``ServiceWatch``.
  public func systemStateNotification() throws -> SystemStateNotification? {
    guard type == RuntimeEventType.watchSystemState.rawValue else { return nil }
    return try SystemStateNotification(runtimePayload: Data(payload))
  }
}
