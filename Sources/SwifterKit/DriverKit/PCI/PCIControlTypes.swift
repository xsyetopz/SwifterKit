/// Options for PCI aperture accesses, `tIOPCIAccessOptions`.
///
/// Configuration-space accesses accept no options.
public struct PCIAccessOptions: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates access options from `tIOPCIAccessOptions` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Allows DriverKit to offload the access, trading latency for CPU time,
  /// `kIOPCIAccessLatencyTolerantHint`.
  public static let latencyTolerant = Self(rawValue: 1 << 0)

  /// Every option the runtime accepts.
  public static let all: Self = [.latencyTolerant]
}

/// The reset that `IOPCIDevice::Reset` performs, `tIOPCIDeviceResetTypes`.
public enum PCIResetType: UInt32, Sendable, Hashable, CaseIterable {
  /// A hot reset through the upstream bridge's secondary bus reset bit, without removing power.
  case hot = 0x01
  /// A platform warm reset without removing power, when the platform supports one.
  case warm = 0x02
  /// The first half of a warm reset, such as asserting PERST#.
  ///
  /// The device stays unusable until a later ``warmEnable`` reset.
  case warmDisable = 0x04
  /// Completes a warm reset started with ``warmDisable``.
  case warmEnable = 0x08
  /// A function-level reset, when the function supports one.
  case functionLevel = 0x10
}

/// Options for `IOPCIDevice::Reset`, `tIOPCIDeviceResetOptions`.
public struct PCIResetOptions: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates reset options from `tIOPCIDeviceResetOptions` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Terminates the reset devices and re-probes the bus, stopping attached drivers including
  /// this extension, `kIOPCIDeviceResetOptionTerminate`.
  public static let terminate = Self(rawValue: 1 << 0)

  /// Every option the runtime accepts.
  public static let all: Self = [.terminate]
}

/// Options for `IOPCIDevice::SaveDeviceState`, `IOPCISaveDeviceStateOptions`.
public struct PCISaveStateOptions: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates save options from `IOPCISaveDeviceStateOptions` bits.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Reuses this saved state for every later restore until the next permanent save,
  /// `kPCIConfigShadowPermanent`.
  public static let permanent = Self(rawValue: 0x8000_0000)

  /// Every option the runtime accepts.
  public static let all: Self = [.permanent]
}

/// PCI Bus Power Management capability bits checked by `IOPCIDevice::HasPCIPowerManagement`.
///
/// An empty set asks whether the registry names the state the hardware expects during sleep.
public struct PCIPowerManagementSupport: OptionSet, Sendable, Hashable {
  public let rawValue: UInt64

  /// Creates capability bits from the PCI power-management capabilities register.
  public init(rawValue: UInt64) { self.rawValue = rawValue }

  /// The function supports D3, `kPCIPMCD3Support`.
  public static let d3 = Self(rawValue: 0x0001)
  /// The function supports D1, `kPCIPMCD1Support`.
  public static let d1 = Self(rawValue: 0x0200)
  /// The function supports D2, `kPCIPMCD2Support`.
  public static let d2 = Self(rawValue: 0x0400)
  /// The function can signal PME from D0, `kPCIPMCPMESupportFromD0`.
  public static let pmeFromD0 = Self(rawValue: 0x0800)
  /// The function can signal PME from D1, `kPCIPMCPMESupportFromD1`.
  public static let pmeFromD1 = Self(rawValue: 0x1000)
  /// The function can signal PME from D2, `kPCIPMCPMESupportFromD2`.
  public static let pmeFromD2 = Self(rawValue: 0x2000)
  /// The function can signal PME from D3hot, `kPCIPMCPMESupportFromD3Hot`.
  public static let pmeFromD3Hot = Self(rawValue: 0x4000)
  /// The function can signal PME from D3cold, `kPCIPMCPMESupportFromD3Cold`.
  public static let pmeFromD3Cold = Self(rawValue: 0x8000)

  /// Every capability bit the runtime accepts.
  public static let all: Self = [
    .d3, .d1, .d2, .pmeFromD0, .pmeFromD1, .pmeFromD2, .pmeFromD3Hot, .pmeFromD3Cold,
  ]
}

/// The sleep power state that `IOPCIDevice::EnablePCIPowerManagement` selects.
public enum PCIPowerManagementState: UInt64, Sendable, Hashable, CaseIterable {
  /// Disables PCI power management, `kPCIPMCSPowerStateD0`.
  case disabled = 0
  /// Places the function in D1 during sleep, `kPCIPMCSPowerStateD1`.
  case d1 = 1
  /// Places the function in D2 during sleep, `kPCIPMCSPowerStateD2`.
  case d2 = 2
  /// Places the function in D3 during sleep, `kPCIPMCSPowerStateD3`.
  case d3 = 3
  /// Lets `IOPCIDevice` choose the state, `kPCIPMCSDefaultEnableBits`.
  case automatic = 0xFFFF_FFFF
}

/// A PCI Express link speed, `IOPCILinkSpeed`.
public enum PCILinkSpeed: UInt32, Sendable, Hashable, CaseIterable {
  /// 2.5 GT/s, PCIe generation 1.
  case gen1 = 1
  /// 5 GT/s, PCIe generation 2.
  case gen2 = 2
  /// 8 GT/s, PCIe generation 3.
  case gen3 = 3
  /// 16 GT/s, PCIe generation 4.
  case gen4 = 4
  /// 32 GT/s, PCIe generation 5.
  case gen5 = 5
}

/// Active State Power Management levels, `tIOPCILinkControlASPMBits`.
///
/// An empty set disables ASPM and L1 substates on the link.
public struct PCIASPMState: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32

  /// Creates ASPM levels from `tIOPCILinkControlASPMBits`.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// L0s entry, `kIOPCILinkControlASPMBitsL0s`.
  public static let l0s = Self(rawValue: 1 << 0)
  /// L1 entry, `kIOPCILinkControlASPMBitsL1`.
  public static let l1 = Self(rawValue: 1 << 1)

  /// Every level the runtime accepts.
  public static let all: Self = [.l0s, .l1]
}

/// Boolean `IOPCIDevice` registry properties that `IOPCIDevice::SetProperties` accepts.
///
/// A `nil` field leaves that property unchanged. SwifterKit exposes only the settable keys whose
/// SDK description makes the value a Boolean; numeric or undocumented keys such as
/// `IOPCIRetrainLinkMask`, `wait-for-link-up`, `IOPCIDeviceCrashResetType`, and
/// `IOPCIKernelMemoryAccess` are not accepted.
public struct PCIDeviceProperties: Sendable, Hashable {
  /// `IOPMPCIConfigSpaceVolatile`; `false` stops configuration-space save and restore on power
  /// state transitions.
  public var configSpaceVolatile: Bool?
  /// `IOPMPCISleepLinkDisable`; `true` disables the PCI Express link on sleep.
  public var sleepLinkDisable: Bool?
  /// `IOPMPCISleepReset`; `true` issues a secondary bus reset on sleep.
  public var sleepReset: Bool?

  /// Creates a property update.
  public init(
    configSpaceVolatile: Bool? = nil,
    sleepLinkDisable: Bool? = nil,
    sleepReset: Bool? = nil
  ) {
    self.configSpaceVolatile = configSpaceVolatile
    self.sleepLinkDisable = sleepLinkDisable
    self.sleepReset = sleepReset
  }

  /// Returns whether the update sets no property.
  public var isEmpty: Bool {
    configSpaceVolatile == nil && sleepLinkDisable == nil && sleepReset == nil
  }
}
