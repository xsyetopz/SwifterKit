/// The interrupt mechanism that `IOPCIDevice::ConfigureInterrupts` allocates.
public enum PCIInterruptType: UInt32, Sendable, Hashable, CaseIterable {
  /// A level-triggered legacy INTx interrupt, `kIOInterruptTypeLevel`.
  ///
  /// DriverKit documents that `IOInterruptDispatchSource` supports only MSI sources for
  /// `IOPCIDevice` providers, so creating a dispatch source for a legacy interrupt can fail.
  case legacy = 0x0000_0001
  /// Message-signaled interrupts, `kIOInterruptTypePCIMessaged`.
  case msi = 0x0001_0000
  /// Extended message-signaled interrupts, `kIOInterruptTypePCIMessagedX`.
  case msiX = 0x0002_0000

  /// Classifies the flags that ``DriverContext/interruptType(index:)`` returns.
  ///
  /// Returns `nil` for an edge-triggered source without PCI message flags.
  public init?(interruptTypeFlags flags: UInt64) {
    if flags & UInt64(Self.msiX.rawValue) != 0 {
      self = .msiX
    } else if flags & UInt64(Self.msi.rawValue) != 0 {
      self = .msi
    } else if flags & UInt64(Self.legacy.rawValue) != 0 {
      self = .legacy
    } else {
      return nil
    }
  }

  /// The largest vector count the PCI specification allows for this interrupt type.
  public var maximumVectorCount: UInt32 {
    switch self {
    case .legacy: 1
    case .msi: 32
    case .msiX: 2_048
    }
  }
}

/// Interrupt vectors that the generated extension allocates on its PCI provider.
///
/// The extension calls `IOPCIDevice::ConfigureInterrupts` once while starting, after it opens
/// the provider and before it creates the `IOInterruptDispatchSource` for each
/// ``InterruptSourceConfiguration``. Starting fails when DriverKit cannot allocate at least
/// ``requiredVectorCount`` vectors.
///
/// Interrupt source indices are provider interrupt indices after allocation. Only the required
/// vectors are guaranteed, so every configured source index must be below
/// ``requiredVectorCount``. Use ``DriverContext/interruptType(index:)`` to confirm the type
/// DriverKit assigned to a source.
public struct PCIInterruptConfiguration: Sendable, Hashable {
  /// The interrupt mechanism to allocate.
  public let type: PCIInterruptType
  /// The minimum number of vectors for allocation to succeed.
  public let requiredVectorCount: UInt32
  /// The number of vectors to request; DriverKit may allocate fewer, but not fewer than required.
  public let requestedVectorCount: UInt32

  /// Creates an interrupt allocation request.
  public init(
    type: PCIInterruptType,
    requiredVectorCount: UInt32 = 1,
    requestedVectorCount: UInt32? = nil
  ) {
    self.type = type
    self.requiredVectorCount = requiredVectorCount
    self.requestedVectorCount = requestedVectorCount ?? requiredVectorCount
  }

  /// Returns whether the vector counts fit the interrupt type's limits.
  public var hasValidVectorCounts: Bool {
    requiredVectorCount >= 1 && requiredVectorCount <= requestedVectorCount
      && requestedVectorCount <= type.maximumVectorCount
  }

  /// Returns whether an interrupt source index can refer to a guaranteed vector.
  public func canDeliver(sourceIndex: UInt32) -> Bool { sourceIndex < requiredVectorCount }
}
