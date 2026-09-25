import Foundation

extension DriverExtensionGenerator {
  /// Returns whether PCI interrupt allocation fits the configured interrupt sources.
  static func isValid(
    pciInterrupts value: PCIInterruptConfiguration,
    configuration: DriverConfiguration
  ) -> Bool {
    configuration.capabilities.contains(.interrupts) && value.hasValidVectorCounts
      && configuration.interruptSources.allSatisfy { value.canDeliver(sourceIndex: $0.index) }
  }

  /// Native constants for `IOPCIDevice::ConfigureInterrupts`.
  static func pciInterruptDeclarations(_ configuration: DriverConfiguration) -> String {
    let interrupts = configuration.pciDevice?.interrupts
    let configure = interrupts == nil ? "false" : "true"
    return """
      static constexpr bool kSwifterKitPCIConfigureInterrupts = \(configure);
      static constexpr uint32_t kSwifterKitPCIInterruptType = \(interrupts?.type.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitPCIInterruptRequiredVectors =
          \(interrupts?.requiredVectorCount ?? 0);
      static constexpr uint32_t kSwifterKitPCIInterruptRequestedVectors =
          \(interrupts?.requestedVectorCount ?? 0);
      """
  }

  static func pciServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
          kern_return_t PCICommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t PCIAccess(
              const SwifterKitPCIAccessHeader* header,
              bool write,
              OSData** response) LOCALONLY;
          kern_return_t PCIGetBARInfo(uint8_t barIndex, OSData** response) LOCALONLY;
          kern_return_t PCIGetLocation(OSData** response) LOCALONLY;
          kern_return_t PCIFindCapability(
              const SwifterKitPCICapabilityHeader* header,
              OSData** response) LOCALONLY;
          kern_return_t PCIControl(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
      """
  }
}
