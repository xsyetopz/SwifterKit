import Foundation
import Testing

@testable import SwifterKit

@Suite
struct DriverExtensionPCIGeneratorTests {
  private func configuration(
    interrupts: PCIInterruptConfiguration?,
    sources: [InterruptSourceConfiguration] = [InterruptSourceConfiguration(index: 0)],
    capabilities: RuntimeCapabilities = [.pci, .interrupts]
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.msi-driver",
      providerClass: "IOPCIDevice",
      capabilities: capabilities,
      pciDevice: PCIDeviceConfiguration(
        vendorID: 0x1011,
        deviceIDs: [0x0026],
        interrupts: interrupts
      ),
      interruptSources: capabilities.contains(.interrupts) ? sources : []
    )
  }

  @Test
  func generatesMSIRuntimeThatBuilds() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("MSIDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: configuration(
        interrupts: PCIInterruptConfiguration(
          type: .msi,
          requiredVectorCount: 2,
          requestedVectorCount: 4
        ),
        sources: [
          InterruptSourceConfiguration(index: 0),
          InterruptSourceConfiguration(index: 1, clock: .continuous),
        ]
      ),
      at: output
    )

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("kSwifterKitPCIConfigureInterrupts = true;"))
    #expect(header.contains("kSwifterKitPCIInterruptType = 65536;"))
    #expect(header.contains("kSwifterKitPCIInterruptRequiredVectors =\n    2;"))
    #expect(header.contains("kSwifterKitPCIInterruptRequestedVectors =\n    4;"))

    let service = try source("SwifterKitRuntimeService.iig", in: output)
    #expect(service.contains("PCIControl("))

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func omitsInterruptAllocationByDefault() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("PlainPCIDriver", isDirectory: true)
    try DriverExtensionGenerator.generate(configuration: configuration(interrupts: nil), at: output)

    let header = try source("SwifterKitRuntimeConfiguration.h", in: output)
    #expect(header.contains("kSwifterKitPCIConfigureInterrupts = false;"))
  }

  @Test
  func rejectsInvalidInterruptAllocation() {
    let invalid: [DriverConfiguration] = [
      configuration(interrupts: PCIInterruptConfiguration(type: .msi), capabilities: .pci),
      configuration(interrupts: PCIInterruptConfiguration(type: .msi, requestedVectorCount: 64)),
      configuration(interrupts: PCIInterruptConfiguration(type: .msiX, requiredVectorCount: 0)),
      configuration(interrupts: PCIInterruptConfiguration(type: .legacy, requestedVectorCount: 2)),
      configuration(
        interrupts: PCIInterruptConfiguration(type: .legacy),
        sources: [InterruptSourceConfiguration(index: 1)]
      ),
      configuration(
        interrupts: PCIInterruptConfiguration(
          type: .msiX,
          requiredVectorCount: 2,
          requestedVectorCount: 8
        ),
        sources: [InterruptSourceConfiguration(index: 2)]
      ),
    ]
    for configuration in invalid {
      #expect(throws: DriverExtensionGenerationError.invalidInterruptConfiguration) {
        try DriverExtensionGenerator.generate(
          configuration: configuration,
          at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
      }
    }
  }

  @Test
  func nativeRuntimeAllocatesVectorsBeforeCreatingSources() throws {
    let interrupts = try packagedSource("SwifterKitRuntimeInterrupts.cpp")
    let start = try section(of: interrupts, from: "::StartInterrupts(", to: "::StopInterrupts(")
    let configure = try #require(
      start.range(of: "ConfigurePCIInterrupts(ivars->pciDevice)")?.lowerBound
    )
    let create = try #require(start.range(of: "IOInterruptDispatchSource::Create(")?.lowerBound)
    #expect(configure < create)
    let helper = try section(
      of: interrupts,
      from: "kern_return_t ConfigurePCIInterrupts(",
      to: "int32_t FindInterruptSlot("
    )
    let validation = try #require(
      helper.range(of: "IsValidPCIInterruptConfiguration()")?.lowerBound
    )
    let call = try #require(helper.range(of: "device->ConfigureInterrupts(")?.lowerBound)
    #expect(validation < call)
    #expect(interrupts.contains("index >= kSwifterKitPCIInterruptRequiredVectors"))
    #expect(interrupts.contains("maximum = 2048;"))
  }

  @Test
  func nativeRuntimeBoundsApertureAccessesAndControlArguments() throws {
    let pci = try packagedSource("SwifterKitRuntimePCI.cpp")
    let access = try section(
      of: pci,
      from: "SwifterKitRuntimeService::PCIAccess(",
      to: "SwifterKitRuntimeService::PCIGetBARInfo("
    )
    let bounds = try #require(access.range(of: "ApertureContains(")?.lowerBound)
    let firstWrite = try #require(access.range(of: "WriteMemory(")?.lowerBound)
    let firstRead = try #require(access.range(of: "ReadMemory(")?.lowerBound)
    #expect(bounds < firstWrite && bounds < firstRead)
    #expect(pci.contains("return size >= width && offset <= size - width;"))
    #expect(pci.contains("(header->options & ~kAccessOptionMask) == 0"))

    let control = try section(
      of: pci,
      from: "SwifterKitRuntimeService::PCIControl(",
      to: "SwifterKitRuntimeService::PCICommand("
    )
    #expect(control.contains("!IsResetType(header.type)"))
    #expect(control.contains("(header.options & ~kResetOptionMask) != 0"))
    #expect(control.contains("(options & ~kSaveStateOptionMask) != 0"))
    #expect(control.contains("(support & ~kPowerManagementSupportMask) != 0"))
    #expect(control.contains("!IsPowerManagementState(state)"))
    #expect(control.contains("!IsLinkSpeed(header.speed)"))
    #expect(control.contains("(state & ~kASPMMask) != 0"))

    // A terminating reset returns without waiting for termination, so Swift gets its result.
    let reset = try section(
      of: String(control),
      from: "case SwifterKitRuntimeOpcode::PCIReset:",
      to: "case SwifterKitRuntimeOpcode::PCISaveDeviceState:"
    )
    let retain = try #require(reset.range(of: "device->retain();")?.lowerBound)
    let call = try #require(
      reset.range(of: "device->Reset(header.type, header.options)")?.lowerBound
    )
    let release = try #require(reset.range(of: "device->release();")?.lowerBound)
    #expect(retain < call && call < release)
    #expect(reset.contains("return result;"))
  }

  private func packagedSource(_ name: String) throws -> String {
    try withTemporaryExtension(
      named: "ContractPCIDriver",
      configuration: configuration(interrupts: PCIInterruptConfiguration(type: .msiX))
    ) { output, _ in try source(name, in: output) }
  }
}
