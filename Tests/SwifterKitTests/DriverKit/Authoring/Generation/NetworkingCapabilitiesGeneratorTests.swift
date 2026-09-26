import Foundation
import Testing

@testable import SwifterKit

/// Checks the generated Ethernet capability constants, overrides, and native rules.
@Suite
struct NetworkingCapabilitiesGeneratorTests {
  @Test
  func generatesFullCapabilityNetworkingRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("FullEthernetDriver")
    try DriverExtensionGenerator.generate(
      configuration: configuration(fullDevice),
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
      at: output
    )

    let config = try source("SwifterKitRuntimeConfiguration.h", in: output)
    for constant in [
      "kSwifterKitEthernetMinimumMTU =\n    1280;", "kSwifterKitEthernetRxPacketCount =\n    128;",
      "kSwifterKitEthernetBufferCount = 256;", "kSwifterKitEthernetPoolFlags = 2;",
      "kSwifterKitEthernetDMAAddressBits =\n    40;", "kSwifterKitEthernetTSOMSS4 =\n    9000;",
      "kSwifterKitEthernetSoftwareVLAN =\n    true;", "kSwifterKitEthernetTxHeadroom = 16;",
      "kSwifterKitEthernetSubFamily =\n    1;",
      "kSwifterKitEthernetBSDNamePrefix[] =\n    \(DriverExtensionGenerator.cString("sk"));",
      "kSwifterKitEthernetBSDUnitNumber = 7;", "kSwifterKitEthernetPacketTap =\n    true;",
      "kSwifterKitEthernetPolling = true;", "kSwifterKitEthernetPollDataRate = 1000000000;",
      "kSwifterKitEthernetFeatureFlags =\n    201326592;",
    ] { #expect(config.contains(constant), "\(constant)") }
    let service = try source("SwifterKitRuntimeService.iig", in: output)
    for member in [
      "setHardwareAssists(\n        uint32_t assists,\n        uint32_t mask) LOCALONLY override;",
      "getTSOOptions(IOUserNetworkTSOOptions* options) LOCALONLY override;",
      "getBSDNamePrefix() LOCALONLY override;", "bpfTap(uint32_t dataLinkType, uint32_t mode)",
      "hwConfigNicProxyData(nicproxy_info_t* handoff) LOCALONLY override;",
      "void DrainNetworkTransmits() LOCALONLY;", "kern_return_t NetworkPollerCommand(",
    ] { #expect(service.contains(member), "\(member)") }

    try expectGeneratedExtensionBuilds(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
  }

  @Test
  func nativeNetworkingRulesMatchSwift() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("EthernetContract")
    try DriverExtensionGenerator.generate(
      configuration: configuration(fullDevice),
      options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
      at: output
    )
    let setup = try source("SwifterKitRuntimeNetworkSetup.cpp", in: output)
    // Registration uses the two-pool form, and each pool is checked against its size.
    #expect(
      setup.contains(
        "registerEthernetInterface(queues, 4, ivars->networkPool, ivars->networkRxPool)"
      )
    )
    #expect(setup.contains("options.poolFlags = kSwifterKitEthernetPoolFlags | PoolFlagMapToDext;"))
    #expect(setup.contains("result = (*pool)->GetPacketCount(&count);"))
    #expect(setup.contains("result = (*pool)->GetBufferCount(&count);"))
    #expect(setup.contains("(void)state->networkPool->deallocatePackets(packets, count);"))
    // The poller is disabled before the lock its poll callback takes.
    let stop = try #require(setup.range(of: "void SwifterKitRuntimeService::StopNetwork()"))
    let rest = setup[stop.upperBound...]
    let disable = try #require(rest.range(of: "ivars->networkPoller->disable();"))
    let queues = try #require(rest.range(of: "networkTxCompletion->setEnable(false)"))
    #expect(disable.lowerBound < queues.lowerBound)
    #expect(setup.contains("mtu >= kSwifterKitEthernetMinimumMTU && mtu <= kSwifterKitEthernetMTU"))
    #expect(setup.contains("NetworkControlEvent(12, changed, &mask, sizeof(mask))"))
    // supportsWakeOnMagicPacket alone lets the stack toggle WOMP through the assist mask.
    #expect(
      setup.contains("| (kSwifterKitEthernetWakeOnMagicPacket ? kIOUserNetworkHWAssistWOMP : 0U);")
    )
    #expect(setup.contains("if ((mask & ~kAdvertisedHardwareAssists) != 0)"))
    #expect(setup.contains("return kAdvertisedHardwareAssists;"))
    #expect(setup.contains("NetworkControlEvent(6, (changed & kIOUserNetworkHWAssistWOMP) != 0"))
    #expect(
      setup.contains(
        "> kSwifterKitMaximumEventPayloadLength - sizeof(SwifterKitNetworkEventHeader)"
      )
    )

    let packets = try source("SwifterKitRuntimeNetworkPackets.cpp", in: output)
    #expect(packets.contains("(void)ivars->networkRxPool->deallocatePacket(packet);"))
    #expect(packets.contains("input->pollInterval <= kSwifterKitEthernetMaximumPollInterval"))
    #expect(packets.contains("quality >= kIOUserNetworkLinkQualityOff"))
    #expect(packets.contains("rates->effectiveInput <= rates->maximumInput"))
    // Counters reach the poller only after networkLock is dropped.
    let unlock = try #require(packets.range(of: "IOLockUnlock(ivars->networkLock);\n    // The"))
    let update = try #require(packets.range(of: "poller->updatePacketCounters(1, receivedLength)"))
    #expect(unlock.lowerBound < update.lowerBound)

    let protocolHeader = try source("SwifterKitRuntimeProtocol.h", in: output)
    #expect(
      protocolHeader.contains("static_assert(sizeof(SwifterKitNetworkHardwareCounts) == 88);")
    )
    #expect(
      protocolHeader.contains(
        "kSwifterKitEthernetMaximumPollInterval = \(EthernetPacketPolling.maximumPollInterval);"
      )
    )
    let client = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
    for opcode in RuntimeOpcode.allCases where (0x0910...0x0915).contains(opcode.rawValue) {
      let name = String(describing: opcode)
      let native = name.prefix(1).uppercased() + name.dropFirst()
      #expect(client.contains("case SwifterKitRuntimeOpcode::\(native):"), "\(native)")
    }
  }

  @Test
  func rejectsInconsistentCapabilities() {
    let address = EthernetAddress(2, 3, 4, 5, 6, 7)
    let invalid: [EthernetDeviceConfiguration] = [
      EthernetDeviceConfiguration(hardwareAddress: address, minimumTransferUnit: 1_600),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        hardwareAssists: EthernetHardwareAssists.tso4.rawValue
      ),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        tsoOptions: EthernetTSOOptions(maximumSegmentSizeIPv4: 9_000, maximumSegmentSizeIPv6: 0)
      ), EthernetDeviceConfiguration(hardwareAddress: address, hardwareAssists: 0x0000_0008),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        featureFlags: EthernetFeatureFlags(rawValue: 1)
      ), EthernetDeviceConfiguration(hardwareAddress: address, transmitHeadroom: 16_000),
      EthernetDeviceConfiguration(hardwareAddress: address, bsdNamePrefix: "En"),
      EthernetDeviceConfiguration(hardwareAddress: address, bsdNamePrefix: "abcdefgh"),
      EthernetDeviceConfiguration(hardwareAddress: address, bsdUnitNumber: -2),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        poolOptions: EthernetPacketPoolOptions(bufferCount: 8)
      ),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        poolOptions: EthernetPacketPoolOptions(
          flags: EthernetPacketPoolFlags(rawValue: 0x1000_0000)
        )
      ),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        poolOptions: EthernetPacketPoolOptions(maximumAddressBits: 16)
      ), EthernetDeviceConfiguration(hardwareAddress: address, receivePacketCount: 4),
      EthernetDeviceConfiguration(
        hardwareAddress: address,
        packetPolling: EthernetPacketPolling(dataRate: 0)
      ),
    ]
    for device in invalid {
      #expect(throws: DriverExtensionGenerationError.invalidEthernetConfiguration) {
        try DriverExtensionGenerator.generate(
          configuration: configuration(device),
          options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
          at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
      }
    }
  }

  private var fullDevice: EthernetDeviceConfiguration {
    let assists: EthernetHardwareAssists = [
      .transmitIPv4HeaderChecksum, .transmitTCPChecksum, .transmitUDPChecksum, .tso4, .tso6, .lro,
      .receiveChecksum, .wakeOnMagicPacket, .softwareVLAN, .nicProxy,
    ]
    return EthernetDeviceConfiguration(
      hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7),
      maximumTransferUnit: 9_000,
      packetBufferSize: 16_384,
      packetCount: 256,
      queueCapacity: 64,
      hardwareAssists: assists.rawValue,
      media: [.automatic, .base1000T, .base10GT],
      supportsWakeOnMagicPacket: true,
      minimumTransferUnit: 1_280,
      featureFlags: [.wakeOnMagicPacket, .nicProxy],
      tsoOptions: EthernetTSOOptions(maximumSegmentSizeIPv4: 9_000, maximumSegmentSizeIPv6: 8_980),
      supportsSoftwareVLAN: true,
      transmitHeadroom: 16,
      transmitTailroom: 8,
      transmitDataOffset: 2,
      interfaceSubFamily: .usb,
      bsdNamePrefix: "sk",
      bsdUnitNumber: 7,
      packetTap: true,
      poolOptions: EthernetPacketPoolOptions(
        bufferCount: 256,
        flags: .singleMemorySegment,
        maximumAddressBits: 40
      ),
      receivePacketCount: 128,
      packetPolling: EthernetPacketPolling(dataRate: 1_000_000_000, pollInterval: 100_000)
    )
  }

  private func configuration(_ device: EthernetDeviceConfiguration) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.full-ethernet",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .networking,
      ethernetDevice: device
    )
  }

  private func source(_ name: String, in output: URL) throws -> String {
    try String(contentsOf: output.appendingPathComponent("Sources/\(name)"), encoding: .utf8)
  }
}
