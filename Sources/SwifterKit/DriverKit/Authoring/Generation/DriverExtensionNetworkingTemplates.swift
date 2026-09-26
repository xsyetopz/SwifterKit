import Foundation

extension DriverExtensionGenerator {
  /// Returns whether the offload, naming, pool, and polling metadata is internally consistent.
  static func isValid(ethernetCapabilities value: EthernetDeviceConfiguration) -> Bool {
    let assists = value.assists
    let tso = assists.contains(.tso4) || assists.contains(.tso6)
    let reserved =
      UInt32(value.transmitHeadroom) + UInt32(value.transmitTailroom)
      + UInt32(value.transmitDataOffset)
    let pool = value.poolOptions
    let largestPool = max(value.packetCount, value.receivePacketCount ?? 0)
    return value.minimumTransferUnit >= 68 && value.minimumTransferUnit <= value.maximumTransferUnit
      && EthernetHardwareAssists.all.isSuperset(of: assists)
      && EthernetFeatureFlags.all.isSuperset(of: value.featureFlags)
      && isValid(tso: value.tsoOptions, assists: assists) && (tso == (value.tsoOptions != nil))
      && reserved + value.maximumTransferUnit + 64 <= value.packetBufferSize
      && isValid(bsdNamePrefix: value.bsdNamePrefix)
      && (value.bsdUnitNumber.map { (0...9_999).contains($0) } ?? true)
      && (pool.bufferCount.map { $0 >= largestPool && $0 <= 4_096 } ?? true)
      && (pool.memorySegmentSize == 0 || pool.memorySegmentSize >= value.packetBufferSize)
      && EthernetPacketPoolFlags.all.isSuperset(of: pool.flags)
      && (32...64).contains(pool.maximumAddressBits)
      && (value.receivePacketCount.map { (8...1_024).contains($0) && $0 >= value.queueCapacity }
        ?? true)
      && (value.packetPolling?.isValid ?? true)
      && (value.transmitServiceClass.map { EthernetServiceClass.all.contains($0) } ?? true)
  }

  private static func isValid(tso: EthernetTSOOptions?, assists: EthernetHardwareAssists) -> Bool {
    guard let tso else { return true }
    let ipv4 = !assists.contains(.tso4) || (1...65_535).contains(tso.maximumSegmentSizeIPv4)
    let ipv6 = !assists.contains(.tso6) || (1...65_535).contains(tso.maximumSegmentSizeIPv6)
    return ipv4 && ipv6
  }

  private static func isValid(bsdNamePrefix: String?) -> Bool {
    guard let bsdNamePrefix else { return true }
    return (1...7).contains(bsdNamePrefix.utf8.count)
      && bsdNamePrefix.utf8.allSatisfy { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) }
  }

  /// Native constants for the Ethernet interface, packet pools, and poller.
  static func ethernetConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let ethernet = configuration.ethernetDevice
    let pool = ethernet?.poolOptions
    let polling = ethernet?.packetPolling
    return """
      static constexpr uint8_t kSwifterKitEthernetAddress[] = {\(ethernetAddress(ethernet))};
      static constexpr uint32_t kSwifterKitEthernetMTU = \(ethernet?.maximumTransferUnit ?? 0);
      static constexpr uint32_t kSwifterKitEthernetMinimumMTU =
          \(ethernet?.minimumTransferUnit ?? 0);
      static constexpr uint32_t kSwifterKitEthernetPacketBufferSize =
          \(ethernet?.packetBufferSize ?? 0);
      static constexpr uint32_t kSwifterKitEthernetPacketCount = \(ethernet?.packetCount ?? 0);
      static constexpr uint32_t kSwifterKitEthernetRxPacketCount =
          \(ethernet?.receivePacketCount ?? 0);
      static constexpr uint32_t kSwifterKitEthernetBufferCount = \(pool?.bufferCount ?? 0);
      static constexpr uint32_t kSwifterKitEthernetMemorySegmentSize =
          \(pool?.memorySegmentSize ?? 0);
      static constexpr uint32_t kSwifterKitEthernetPoolFlags = \(pool?.flags.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitEthernetDMAAddressBits =
          \(pool?.maximumAddressBits ?? 64);
      static constexpr uint32_t kSwifterKitEthernetQueueCapacity = \(ethernet?.queueCapacity ?? 0);
      static constexpr uint32_t kSwifterKitEthernetHardwareAssists =
          \(ethernet?.hardwareAssists ?? 0);
      static constexpr uint32_t kSwifterKitEthernetFeatureFlags =
          \(ethernet?.featureFlags.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitEthernetTSOMSS4 =
          \(ethernet?.tsoOptions?.maximumSegmentSizeIPv4 ?? 0);
      static constexpr uint32_t kSwifterKitEthernetTSOMSS6 =
          \(ethernet?.tsoOptions?.maximumSegmentSizeIPv6 ?? 0);
      static constexpr bool kSwifterKitEthernetSoftwareVLAN =
          \(ethernet?.supportsSoftwareVLAN == true ? "true" : "false");
      static constexpr uint16_t kSwifterKitEthernetTxHeadroom = \(ethernet?.transmitHeadroom ?? 0);
      static constexpr uint16_t kSwifterKitEthernetTxTailroom = \(ethernet?.transmitTailroom ?? 0);
      static constexpr uint16_t kSwifterKitEthernetTxDataOffset =
          \(ethernet?.transmitDataOffset ?? 0);
      static constexpr uint32_t kSwifterKitEthernetTxServiceClass =
          \(ethernet?.transmitServiceClass?.rawValue ?? 0xFFFF_FFFF);
      static constexpr uint32_t kSwifterKitEthernetSubFamily =
          \(ethernet?.interfaceSubFamily.rawValue ?? 0);
      static constexpr char kSwifterKitEthernetBSDNamePrefix[] =
          \(cString(ethernet?.bsdNamePrefix ?? ""));
      static constexpr int32_t kSwifterKitEthernetBSDUnitNumber = \(ethernet?.bsdUnitNumber ?? -1);
      static constexpr bool kSwifterKitEthernetPacketTap =
          \(ethernet?.packetTap == true ? "true" : "false");
      static constexpr uint32_t kSwifterKitEthernetMedia[] = {\(ethernetMedia(ethernet))};
      static constexpr uint32_t kSwifterKitEthernetMediaCount = \(ethernet?.media.count ?? 0);
      static constexpr uint32_t kSwifterKitEthernetInitialMedia =
          \(ethernet?.initialMedia.rawValue ?? 0);
      static constexpr bool kSwifterKitEthernetWakeOnMagicPacket =
          \(ethernet?.supportsWakeOnMagicPacket == true ? "true" : "false");
      static constexpr bool kSwifterKitEthernetPolling = \(polling == nil ? "false" : "true");
      static constexpr bool kSwifterKitEthernetPollingEnabled =
          \(polling?.enabled == true ? "true" : "false");
      static constexpr uint64_t kSwifterKitEthernetPollDataRate = \(polling?.dataRate ?? 0);
      static constexpr uint64_t kSwifterKitEthernetPollInterval = \(polling?.pollInterval ?? 0);
      """
  }

  private static func ethernetAddress(_ value: EthernetDeviceConfiguration?) -> String {
    value?.hardwareAddress.bytes.map(String.init).joined(separator: ", ") ?? "0, 0, 0, 0, 0, 0"
  }

  private static func ethernetMedia(_ value: EthernetDeviceConfiguration?) -> String {
    value?.media.map { String($0.rawValue) }.joined(separator: ", ") ?? "0"
  }

  /// `IOUserNetworkEthernet` members the generated service declares.
  static func networkingServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
      public:
          kern_return_t StartNetwork() LOCALONLY;
          void StopNetwork() LOCALONLY;
          void AbortNetworkTransmits() LOCALONLY;
          void DrainNetworkTransmits() LOCALONLY;
          kern_return_t CopyPacketPoolMemory(uint32_t pool, IOMemoryDescriptor** memory) LOCALONLY;
          kern_return_t NetworkCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t NetworkPacketCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t NetworkReceivePackets(
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t NetworkCompleteTransmits(
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t NetworkPollerCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t NetworkControlEvent(
              uint32_t kind,
              uint32_t value,
              const void* bytes = nullptr,
              uint32_t byteCount = 0) LOCALONLY;
          virtual void NetworkTxPacketAvailable(
              OSAction* action) TYPE(IODataQueueDispatchSource::DataAvailable);

      protected:
          virtual kern_return_t setPowerState(
              unsigned long state,
              IOService* device) LOCALONLY override;
          virtual kern_return_t getSupportedMediaArray(
              MediaWord* media,
              uint32_t* count) LOCALONLY override;
          virtual kern_return_t setInterfaceEnable(bool enable) LOCALONLY override;
          virtual kern_return_t setPromiscuousModeEnable(bool enable) LOCALONLY override;
          virtual kern_return_t setMulticastAddresses(
              const ether_addr_t* addresses,
              uint32_t count) LOCALONLY override;
          virtual kern_return_t setAllMulticastModeEnable(bool enable) LOCALONLY override;
          virtual kern_return_t handleChosenMedia(MediaWord media) LOCALONLY override;
          virtual kern_return_t setMaxTransferUnit(uint32_t mtu) LOCALONLY override;
          virtual uint32_t getMaxTransferUnit() LOCALONLY override;
          virtual kern_return_t setHardwareAssists(uint32_t assists) LOCALONLY override;
          virtual kern_return_t setHardwareAssists(
              uint32_t assists,
              uint32_t mask) LOCALONLY override;
          virtual uint32_t getHardwareAssists() LOCALONLY override;
          virtual uint32_t getFeatureFlags() LOCALONLY override;
          virtual kern_return_t getTSOOptions(IOUserNetworkTSOOptions* options) LOCALONLY override;
          virtual uint32_t getInterfaceSubFamily() LOCALONLY override;
          virtual const char* getBSDNamePrefix() LOCALONLY override;
          virtual int32_t getBSDUnitNumber() LOCALONLY override;
          virtual uint16_t getTxDataOffset() LOCALONLY override;
          virtual int bpfTap(uint32_t dataLinkType, uint32_t mode) LOCALONLY override;
          virtual void hwConfigNicProxyData(nicproxy_info_t* handoff) LOCALONLY override;
          virtual MediaWord getInitialMedia() LOCALONLY override;
          virtual kern_return_t getHardwareAddress(
              ether_addr_t* address) LOCALONLY override;
          virtual kern_return_t setHardwareAddress(
              ether_addr_t* address) LOCALONLY override;
          virtual kern_return_t processInterfaceCommand(ifdrv_t* command) LOCALONLY override;
      """
  }
}
