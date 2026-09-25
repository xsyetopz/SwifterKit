import Foundation

extension DriverCommand {
  /// Creates a device reset through `IOPCIDevice::Reset`.
  public static func pciReset(type: PCIResetType, options: PCIResetOptions = []) throws -> Self {
    guard options.subtracting(.all).isEmpty else { throw PCIRuntimeError.invalidOptions }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(type.rawValue)
    payload.appendRuntimeInteger(options.rawValue)
    return pciControl(.pciReset, payload: payload)
  }

  /// Creates a configuration-space save through `IOPCIDevice::SaveDeviceState`.
  public static func pciSaveDeviceState(options: PCISaveStateOptions = []) throws -> Self {
    guard options.subtracting(.all).isEmpty else { throw PCIRuntimeError.invalidOptions }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(options.rawValue)
    return pciControl(.pciSaveDeviceState, payload: payload)
  }

  /// Creates a configuration-space restore through `IOPCIDevice::RestoreDeviceState`.
  public static let pciRestoreDeviceState = pciControl(.pciRestoreDeviceState, payload: Data())

  /// Creates a PCI Bus Power Management support query.
  public static func pciHasPowerManagement(support: PCIPowerManagementSupport = []) throws -> Self {
    guard support.subtracting(.all).isEmpty else { throw PCIRuntimeError.invalidOptions }
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(support.rawValue)
    return pciControl(.pciHasPowerManagement, payload: payload, responseSize: 4)
  }

  /// Creates a sleep power-state selection through `IOPCIDevice::EnablePCIPowerManagement`.
  public static func pciEnablePowerManagement(state: PCIPowerManagementState) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(state.rawValue)
    return pciControl(.pciEnablePowerManagement, payload: payload)
  }

  /// Creates a link-speed query through `IOPCIDevice::GetLinkSpeed`.
  public static let pciLinkSpeed = pciControl(.pciGetLinkSpeed, payload: Data(), responseSize: 4)

  /// Creates a link-speed limit change through `IOPCIDevice::SetLinkSpeed`.
  public static func pciSetLinkSpeed(_ speed: PCILinkSpeed, retrain: Bool) -> Self {
    var payload = Data(capacity: 8)
    payload.appendRuntimeInteger(speed.rawValue)
    payload.append(contentsOf: [retrain ? 1 : 0, 0, 0, 0])
    return pciControl(.pciSetLinkSpeed, payload: payload)
  }

  /// Creates an ASPM change through `IOPCIDevice::SetASPMState`.
  public static func pciSetASPMState(_ state: PCIASPMState) throws -> Self {
    guard state.subtracting(.all).isEmpty else { throw PCIRuntimeError.invalidOptions }
    var payload = Data(capacity: 4)
    payload.appendRuntimeInteger(state.rawValue)
    return pciControl(.pciSetASPMState, payload: payload)
  }

  /// Creates a registry property update through `IOPCIDevice::SetProperties`.
  public static func pciSetProperties(_ properties: PCIDeviceProperties) throws -> Self {
    guard !properties.isEmpty else { throw PCIRuntimeError.emptyPropertyUpdate }
    func encode(_ value: Bool?) -> UInt8 { value.map { $0 ? 2 : 1 } ?? 0 }
    let payload = Data([
      encode(properties.configSpaceVolatile), encode(properties.sleepLinkDisable),
      encode(properties.sleepReset), 0,
    ])
    return pciControl(.pciSetProperties, payload: payload)
  }

  private static func pciControl(
    _ opcode: RuntimeOpcode,
    payload: Data,
    responseSize: Int = 0
  ) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: .pci,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + responseSize
    )
  }
}

extension DriverContext {
  /// Resets the PCI device.
  ///
  /// Resetting disturbs the device: a multifunction device resets every function, and nothing
  /// may access the device until the call returns. DriverKit saves configuration state before the
  /// reset and restores it afterwards. The call blocks until the link is up again, except for
  /// ``PCIResetType/warmDisable``, which leaves the device unusable until a
  /// ``PCIResetType/warmEnable`` reset. With ``PCIResetOptions/terminate``, DriverKit terminates
  /// the device and this extension, so the response may never arrive.
  public func pciReset(type: PCIResetType, options: PCIResetOptions = []) async throws {
    _ = try await execute(.pciReset(type: type, options: options))
  }

  /// Saves the device's configuration space for a later ``pciRestoreDeviceState()``.
  public func pciSaveDeviceState(options: PCISaveStateOptions = []) async throws {
    _ = try await execute(.pciSaveDeviceState(options: options))
  }

  /// Restores the configuration space saved by ``pciSaveDeviceState(options:)``.
  ///
  /// Restoring rewrites the device's configuration registers.
  public func pciRestoreDeviceState() async throws { _ = try await execute(.pciRestoreDeviceState) }

  /// Returns whether the device supports every requested PCI Bus Power Management capability.
  ///
  /// With an empty set, returns whether the registry names the state the hardware expects during
  /// sleep. The runtime reports `true` when DriverKit returns `kIOReturnSuccess` and `false` for
  /// any other result.
  public func pciHasPowerManagement(support: PCIPowerManagementSupport = []) async throws -> Bool {
    let payload = try await execute(.pciHasPowerManagement(support: support))
    guard payload.count == 4 else { throw PCIRuntimeError.invalidResponse }
    let value: UInt32 = try payload.readRuntimeInteger(at: 0)
    guard value <= 1 else { throw PCIRuntimeError.invalidResponse }
    return value == 1
  }

  /// Selects the power state the device enters during system sleep.
  ///
  /// ``PCIPowerManagementState/disabled`` turns PCI power management off.
  public func pciEnablePowerManagement(state: PCIPowerManagementState) async throws {
    _ = try await execute(.pciEnablePowerManagement(state: state))
  }

  /// Returns the endpoint's current PCI Express link speed.
  public func pciLinkSpeed() async throws -> PCILinkSpeed {
    let payload = try await execute(.pciLinkSpeed)
    guard payload.count == 4,
      let speed = PCILinkSpeed(rawValue: try payload.readRuntimeInteger(at: 0))
    else { throw PCIRuntimeError.invalidResponse }
    return speed
  }

  /// Sets the upstream bridge's target link speed.
  ///
  /// The limit applies to later reset-initiated link training. With `retrain`, the link retrains
  /// immediately, which interrupts traffic, and the call returns after training completes.
  /// Success does not mean the link reached `speed`; call ``pciLinkSpeed()`` to read the result.
  public func pciSetLinkSpeed(_ speed: PCILinkSpeed, retrain: Bool = false) async throws {
    _ = try await execute(.pciSetLinkSpeed(speed, retrain: retrain))
  }

  /// Enables the given ASPM levels on the device and its upstream bridge, or disables ASPM.
  ///
  /// DriverKit enables only levels both link partners support. Enabling ASPM also enables the
  /// L1 substates both partners support; an empty set disables ASPM and L1 substates. ASPM adds
  /// exit latency to device accesses.
  public func pciSetASPMState(_ state: PCIASPMState) async throws {
    _ = try await execute(try .pciSetASPMState(state))
  }

  /// Sets Boolean IOPCIDevice registry properties that control sleep behavior.
  ///
  /// DriverKit reports success when at least one property is accepted.
  public func pciSetProperties(_ properties: PCIDeviceProperties) async throws {
    _ = try await execute(try .pciSetProperties(properties))
  }
}
