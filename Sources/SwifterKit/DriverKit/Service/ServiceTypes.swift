import Foundation

/// Power capability flags that DriverKit passes to `IOService::SetPowerState` and accepts in
/// `IOService::ChangePowerState`.
public struct ServicePowerCapability: RawRepresentable, Sendable, Hashable {
  /// The system is entering sleep, `kIOServicePowerCapabilityOff`.
  public static let off = Self(rawValue: 0)
  /// The device and system are fully powered, `kIOServicePowerCapabilityOn`.
  public static let on = Self(rawValue: 0x2)
  /// The device is in a reduced power state while the system runs, `kIOServicePowerCapabilityLow`.
  public static let low = Self(rawValue: 0x1_0000)
  /// The system is in a low-power wake, `kIOServicePowerCapabilityLPW`.
  public static let lowPowerWake = Self(rawValue: 0x2_0000)

  /// The DriverKit power flags.
  public let rawValue: UInt32
  /// Creates a capability from DriverKit power flags.
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// A power change DriverKit announced through `IOService::SetPowerState`.
///
/// Make the device safe for ``capability``, then call
/// ``DriverContext/completePowerState(requestID:)``. DriverKit changes power only after the
/// change is acknowledged. The extension acknowledges on the driver's behalf when the driver
/// does not answer within ten seconds, when the host disconnects or stops delivering events
/// because ``SwiftDriver/handle(event:context:)`` threw, or when a newer change arrives. A change
/// that arrives while no host is connected is acknowledged at once and never delivered.
public struct ServicePowerStateRequest: Sendable, Hashable {
  /// The identifier to pass to ``DriverContext/completePowerState(requestID:)``.
  public let requestID: UInt32
  /// The power state the system is changing to.
  public let capability: ServicePowerCapability

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 8 else { throw ServiceRuntimeError.invalidPayload }
    requestID = try runtimePayload.readRuntimeInteger(at: 0)
    capability = ServicePowerCapability(rawValue: try runtimePayload.readRuntimeInteger(at: 4))
    guard requestID != 0 else { throw ServiceRuntimeError.invalidPayload }
  }
}

/// Kinds of power-management assertion, the `CreatePMAssertion` bits.
public struct ServicePMAssertionOptions: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates options from `CreatePMAssertion` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Keeps the CPU and core hardware in dark wake instead of sleep,
  /// `kIOServicePMAssertionCPUBit`.
  public static let cpu = Self(rawValue: 0x001)
  /// Wakes the system fully right after it sleeps, `kIOServicePMAssertionForceFullWakeupBit`.
  public static let forceFullWakeup = Self(rawValue: 0x800)

  /// Every option the runtime accepts.
  public static let all: Self = [.cpu, .forceFullWakeup]
}

/// A power-management assertion held until ``DriverContext/releasePMAssertion(_:)``.
public struct ServicePMAssertion: Sendable, Hashable {
  /// The identifier `CreatePMAssertion` returned.
  public let id: UInt64

  /// Wraps an identifier from `CreatePMAssertion`.
  public init(id: UInt64) { self.id = id }
}

/// The longest memory-access latency a driver tolerates, the `kIOMaxBusStall*` values.
public enum ServiceBusStall: UInt64, Sendable, CaseIterable {
  /// No constraint, `kIOMaxBusStallNone`.
  case none = 0
  /// 5 µs, `kIOMaxBusStall5usec`.
  case microseconds5 = 5_000
  /// 10 µs, `kIOMaxBusStall10usec`.
  case microseconds10 = 10_000
  /// 20 µs, `kIOMaxBusStall20usec`.
  case microseconds20 = 20_000
  /// 25 µs, `kIOMaxBusStall25usec`.
  case microseconds25 = 25_000
  /// 30 µs, `kIOMaxBusStall30usec`.
  case microseconds30 = 30_000
  /// 40 µs, `kIOMaxBusStall40usec`.
  case microseconds40 = 40_000
}

/// Options for ``DriverContext/searchServiceProperty(named:options:plane:)``.
public struct ServicePropertySearchOptions: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates options from `IOService::SearchProperty` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Searches the service and then its parents, `kIOServiceSearchPropertyParents`.
  public static let parents = Self(rawValue: 0x1)

  /// Every option the runtime accepts.
  public static let all: Self = [.parents]
}

/// An invalid IOService request or malformed runtime reply.
public enum ServiceRuntimeError: Error, Sendable, Equatable {
  /// A registry or item name is empty, longer than 127 UTF-8 bytes, or contains NUL.
  case invalidName(String)
  /// The value is `.real`, or a string contains NUL; DriverKit registries cannot hold it.
  case unsupportedProperty
  /// Values nest deeper than eight levels.
  case propertyTooDeep
  /// The encoded request does not fit one runtime message.
  case payloadTooLarge
  /// A property update or key list is empty.
  case emptyRequest
  /// Options outside the documented set, or a synced assertion that is not only
  /// ``ServicePMAssertionOptions/cpu``.
  case invalidOptions
  /// A zero busy-state delta, assertion identifier, or request identifier.
  case invalidValue
  /// The extension replied with a malformed payload.
  case invalidPayload
}
