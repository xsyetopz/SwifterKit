import Foundation

extension DriverCommand {
  /// Creates a power-state request through `IOService::ChangePowerState`.
  public static func changePowerState(_ capability: ServicePowerCapability) throws -> Self {
    guard [.off, .on, .low].contains(capability) else { throw ServiceRuntimeError.invalidValue }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(capability.rawValue)
    return service(.serviceChangePowerState, payload: payload)
  }

  /// Creates a power-override change through `IOService::SetPowerOverride`.
  public static func setPowerOverride(_ enabled: Bool) -> Self {
    service(.serviceSetPowerOverride, payload: Data([enabled ? 1 : 0, 0, 0, 0]))
  }

  /// Creates a power-management assertion through `IOService::CreatePMAssertion`.
  ///
  /// A `synced` assertion may only be ``ServicePMAssertionOptions/cpu``.
  public static func createPMAssertion(
    _ options: ServicePMAssertionOptions,
    synced: Bool = false
  ) throws -> Self {
    guard !options.isEmpty, options.subtracting(.all).isEmpty, !synced || options == .cpu else {
      throw ServiceRuntimeError.invalidOptions
    }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(options.rawValue)
    payload.append(contentsOf: [synced ? 1 : 0, 0, 0, 0])
    return service(.serviceCreatePMAssertion, payload: payload, responseSize: 8)
  }

  /// Creates an assertion release through `IOService::ReleasePMAssertion`.
  public static func releasePMAssertion(_ assertion: ServicePMAssertion) throws -> Self {
    guard assertion.id != 0 else { throw ServiceRuntimeError.invalidValue }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(assertion.id)
    return service(.serviceReleasePMAssertion, payload: payload)
  }

  /// Acknowledges a ``ServicePowerStateRequest``.
  public static func completePowerState(requestID: UInt32) throws -> Self {
    guard requestID != 0 else { throw ServiceRuntimeError.invalidValue }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(requestID)
    payload.appendRuntimeInteger(UInt32(0))
    return service(.serviceCompletePowerState, payload: payload)
  }

  /// Creates a busy-state change through `IOService::AdjustBusy`.
  public static func adjustBusy(by delta: Int32) throws -> Self {
    guard delta != 0 else { throw ServiceRuntimeError.invalidValue }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(delta)
    return service(.serviceAdjustBusy, payload: payload)
  }

  /// Creates a busy-state read through `IOService::GetBusyState`.
  public static let busyState = service(.serviceGetBusyState, responseSize: 4)

  /// Creates a bus-stall limit through `IOService::RequireMaxBusStall`.
  public static func requireMaxBusStall(_ stall: ServiceBusStall) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(stall.rawValue)
    return service(.serviceRequireMaxBusStall, payload: payload)
  }

  /// Creates a termination of the generated service through `IOService::Terminate`.
  public static let terminateService = service(.serviceTerminate)
}

extension DriverContext {
  /// Asks DriverKit to move the generated service to `capability`: ``ServicePowerCapability/on``,
  /// ``ServicePowerCapability/low``, or ``ServicePowerCapability/off``.
  public func changePowerState(_ capability: ServicePowerCapability) async throws {
    _ = try await execute(try .changePowerState(capability))
  }

  /// Makes the service's power state follow only ``changePowerState(_:)``, ignoring its
  /// children's power desires.
  public func setPowerOverride(_ enabled: Bool) async throws {
    _ = try await execute(.setPowerOverride(enabled))
  }

  /// Creates a power-management assertion.
  ///
  /// With `synced`, the call fails with `kIOReturnBusy` when sleep is already irreversible.
  /// Requires the DriverKit 25.5 SDK or later; older builds report `kIOReturnUnsupported`.
  public func createPMAssertion(
    _ options: ServicePMAssertionOptions,
    synced: Bool = false
  ) async throws -> ServicePMAssertion {
    let reply = try await execute(try .createPMAssertion(options, synced: synced))
    guard reply.count == 8 else { throw ServiceRuntimeError.invalidPayload }
    return ServicePMAssertion(id: try reply.readRuntimeInteger(at: 0))
  }

  /// Releases an assertion from ``createPMAssertion(_:synced:)``.
  public func releasePMAssertion(_ assertion: ServicePMAssertion) async throws {
    _ = try await execute(try .releasePMAssertion(assertion))
  }

  /// Acknowledges a ``ServicePowerStateRequest`` once the device is safe for the new state.
  ///
  /// Fails with `kIOReturnNotFound` when the extension already acknowledged the request, after
  /// its ten-second timeout or a newer change. Rethrowing that error from
  /// ``SwiftDriver/handle(event:context:)`` ends event delivery.
  public func completePowerState(requestID: UInt32) async throws {
    _ = try await execute(try .completePowerState(requestID: requestID))
  }

  /// Adds `delta` to the service's busy state; moving to or from zero also changes the
  /// provider's busy state by one.
  public func adjustBusy(by delta: Int32) async throws {
    _ = try await execute(try .adjustBusy(by: delta))
  }

  /// Returns the service's busy state.
  public func busyState() async throws -> UInt32 {
    let reply = try await execute(.busyState)
    guard reply.count == 4 else { throw ServiceRuntimeError.invalidPayload }
    return try reply.readRuntimeInteger(at: 0)
  }

  /// Limits system power saving so memory accesses stall no longer than `stall`; pass
  /// ``ServiceBusStall/none`` when the time-critical transfer ends.
  public func requireMaxBusStall(_ stall: ServiceBusStall) async throws {
    _ = try await execute(.requireMaxBusStall(stall))
  }

  /// Starts asynchronous termination of the generated service; DriverKit then stops it and
  /// closes this connection.
  public func terminateService() async throws { _ = try await execute(.terminateService) }
}

extension DriverEvent {
  /// Decodes a power change announced by `IOService::SetPowerState`.
  public func servicePowerState() throws -> ServicePowerStateRequest? {
    guard type == RuntimeEventType.servicePowerState.rawValue else { return nil }
    return try ServicePowerStateRequest(runtimePayload: Data(payload))
  }
}
