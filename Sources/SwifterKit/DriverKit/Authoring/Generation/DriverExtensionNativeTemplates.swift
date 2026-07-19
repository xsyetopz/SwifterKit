import Foundation

extension DriverExtensionGenerator {
  static func runtimeConfigurationHeader(_ configuration: DriverConfiguration) -> String {
    let hid = configuration.hidDevice
    let descriptor = hid?.reportDescriptor.map(String.init).joined(separator: ", ") ?? "0"
    let interruptsEnabled = configuration.capabilities.contains(.interrupts) ? 1 : 0
    let encodedInterruptIndices = interruptIndices(configuration)
    let memory = configuration.memoryPool
    let serial = configuration.serialPort
    let block = configuration.blockStorageDevice
    let midi = configuration.midiDevice
    let ethernet = configuration.ethernetDevice
    let audio = configuration.audioDevice
    let video = configuration.videoDevice
    let scsiController = configuration.scsiController
    let scsiPeripheral = configuration.scsiPeripheral
    return """
      #ifndef SwifterKitRuntimeConfiguration_h
      #define SwifterKitRuntimeConfiguration_h

      #include <stdint.h>

      \(audioConfigurationDeclarations(configuration))
      \(videoConfigurationDeclarations(configuration))
      \(scsiConfigurationDeclarations(configuration))

      #define SWIFTERKIT_ENABLE_HID \(hid == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_NETWORKING \(ethernet == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_AUDIO \(audio == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_VIDEO \(video == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SCSI_CONTROLLER \(scsiController == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SCSI_PERIPHERAL \(scsiPeripheral == nil ? 0 : 1)
      #define SWIFTERKIT_SCSI_PERIPHERAL_TYPE \(scsiPeripheral?.deviceType.rawValue ?? 0)
      #define SWIFTERKIT_ENABLE_USB \(configuration.capabilities.contains(.usb) ? 1 : 0)
      #define SWIFTERKIT_ENABLE_MIDI \(midi == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_BLOCK_STORAGE \(block == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SERIAL \(serial == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_PCI \(configuration.capabilities.contains(.pci) ? 1 : 0)
      #define SWIFTERKIT_ENABLE_INTERRUPTS \(interruptsEnabled)
      #define SWIFTERKIT_ENABLE_MEMORY \(memory == nil ? 0 : 1)

      static constexpr uint8_t kSwifterKitEthernetAddress[] = {\(ethernetAddress(ethernet))};
      static constexpr uint32_t kSwifterKitEthernetMTU = \(ethernet?.maximumTransferUnit ?? 0);
      static constexpr uint32_t kSwifterKitEthernetPacketBufferSize =
          \(ethernet?.packetBufferSize ?? 0);
      static constexpr uint32_t kSwifterKitEthernetPacketCount = \(ethernet?.packetCount ?? 0);
      static constexpr uint32_t kSwifterKitEthernetQueueCapacity = \(ethernet?.queueCapacity ?? 0);
      static constexpr uint32_t kSwifterKitEthernetHardwareAssists =
          \(ethernet?.hardwareAssists ?? 0);
      static constexpr uint32_t kSwifterKitEthernetMedia[] = {\(ethernetMedia(ethernet))};
      static constexpr uint32_t kSwifterKitEthernetMediaCount = \(ethernet?.media.count ?? 0);
      static constexpr uint32_t kSwifterKitEthernetInitialMedia =
          \(ethernet?.initialMedia.rawValue ?? 0);
      static constexpr bool kSwifterKitEthernetWakeOnMagicPacket =
          \(ethernet?.supportsWakeOnMagicPacket == true ? "true" : "false");

      static constexpr uint32_t kSwifterKitMaximumMemoryBuffers = \(memory?.maximumBuffers ?? 0);
      static constexpr uint64_t kSwifterKitMaximumMemoryBufferSize =
          \(memory?.maximumBufferSize ?? 0);
      static constexpr uint64_t kSwifterKitMaximumMemoryTotalSize =
          \(memory?.maximumTotalSize ?? 0);

      static constexpr uint32_t kSwifterKitMIDIProtocol = \(midi?.protocol.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitMIDISourceCount = \(midi?.sourceCount ?? 0);
      static constexpr uint32_t kSwifterKitMIDIDestinationCount =
          \(midi?.destinationCount ?? 0);
      static constexpr char kSwifterKitMIDIDriverName[] =
          \(cString(midi?.driverName ?? "SwifterKit MIDI"));
      static constexpr char kSwifterKitMIDIDeviceIdentifier[] =
          \(cString(midi?.deviceIdentifier ?? "SwifterKit.Device"));
      static constexpr char kSwifterKitMIDIModelIdentifier[] =
          \(cString(midi?.modelIdentifier ?? "SwifterKit.Model"));
      static constexpr char kSwifterKitMIDIManufacturerIdentifier[] =
          \(cString(midi?.manufacturerIdentifier ?? "SwifterKit"));
      static constexpr char kSwifterKitMIDIEntityName[] =
          \(cString(midi?.entityName ?? "SwifterKit Entity"));

      static constexpr uint64_t kSwifterKitBlockCount = \(block?.blockCount ?? 0);
      static constexpr uint32_t kSwifterKitBlockSize = \(block?.blockSize ?? 0);
      static constexpr uint32_t kSwifterKitBlockMaximumIOSize =
          \(block?.maximumIOSize ?? 0);
      static constexpr uint32_t kSwifterKitBlockMaximumOutstandingIOCount =
          \(block?.maximumOutstandingIOCount ?? 0);
      static constexpr uint32_t kSwifterKitBlockMaximumUnmapRegionCount =
          \(block?.maximumUnmapRegionCount ?? 0);
      static constexpr uint32_t kSwifterKitBlockMinimumSegmentAlignment =
          \(block?.minimumSegmentAlignment ?? 0);
      static constexpr uint8_t kSwifterKitBlockAddressBitCount =
          \(block?.addressBitCount ?? 0);
      static constexpr bool kSwifterKitBlockSupportsUnmap =
          \(block?.supportsUnmap == true ? "true" : "false");
      static constexpr bool kSwifterKitBlockSupportsFUA =
          \(block?.supportsForceUnitAccess == true ? "true" : "false");
      static constexpr bool kSwifterKitBlockIsEjectable =
          \(block?.isEjectable == true ? "true" : "false");
      static constexpr bool kSwifterKitBlockIsRemovable =
          \(block?.isRemovable == true ? "true" : "false");
      static constexpr bool kSwifterKitBlockIsWriteProtected =
          \(block?.isWriteProtected == true ? "true" : "false");
      static constexpr char kSwifterKitBlockVendor[] =
          \(cString(block?.vendor ?? "SwifterKit"));
      static constexpr char kSwifterKitBlockProduct[] =
          \(cString(block?.product ?? "Block Device"));
      static constexpr char kSwifterKitBlockRevision[] =
          \(cString(block?.revision ?? "1.0"));
      static constexpr char kSwifterKitBlockAdditionalInfo[] =
          \(cString(block?.additionalInfo ?? ""));

      static constexpr char kSwifterKitSerialBaseName[] =
          \(cString(serial?.baseName ?? "SwifterKit"));
      static constexpr char kSwifterKitSerialSuffix[] =
          \(cString(serial?.suffix ?? "Serial"));
      static constexpr bool kSwifterKitSerialInitialCTS =
          \(serial?.initialModemStatus.clearToSend == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialDSR =
          \(serial?.initialModemStatus.dataSetReady == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialRI =
          \(serial?.initialModemStatus.ringIndicator == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialDCD =
          \(serial?.initialModemStatus.dataCarrierDetect == true ? "true" : "false");

      static constexpr uint32_t kSwifterKitInterruptIndices[] = {\(encodedInterruptIndices)};
      static constexpr uint32_t kSwifterKitInterruptSourceCount =
          \(configuration.interruptSources.count);

      static constexpr uint8_t kSwifterKitHIDReportDescriptor[] = {\(descriptor)};
      static constexpr uint32_t kSwifterKitHIDReportDescriptorLength =
          \(hid?.reportDescriptor.count ?? 0);
      static constexpr char kSwifterKitHIDTransport[] = \(cString(hid?.transport ?? "Virtual"));
      static constexpr uint32_t kSwifterKitHIDVendorID = \(hid?.vendorID ?? 0);
      static constexpr uint32_t kSwifterKitHIDProductID = \(hid?.productID ?? 0);
      static constexpr uint32_t kSwifterKitHIDVersionNumber = \(hid?.versionNumber ?? 1);
      static constexpr uint32_t kSwifterKitHIDCountryCode = \(hid?.countryCode ?? 0);
      static constexpr uint32_t kSwifterKitHIDLocationID = \(hid?.locationID ?? 0);
      static constexpr char kSwifterKitHIDManufacturer[] =
          \(cString(hid?.manufacturer ?? "SwifterKit"));
      static constexpr char kSwifterKitHIDProduct[] =
          \(cString(hid?.product ?? "SwifterKit Runtime"));
      static constexpr char kSwifterKitHIDSerialNumber[] =
          \(cString(hid?.serialNumber ?? "SwifterKit"));
      static constexpr uint32_t kSwifterKitHIDPrimaryUsagePage = \(hid?.primaryUsagePage ?? 0);
      static constexpr uint32_t kSwifterKitHIDPrimaryUsage = \(hid?.primaryUsage ?? 0);
      static constexpr uint32_t kSwifterKitHIDHostReportOutput = 1U << 0;
      static constexpr uint32_t kSwifterKitHIDHostReportFeature = 1U << 1;
      static constexpr uint32_t kSwifterKitHIDAcceptedHostReportTypes =
          \(hid?.acceptedHostReportTypes.rawValue ?? 0);

      #endif
      """
  }

  private static func ethernetAddress(_ value: EthernetDeviceConfiguration?) -> String {
    value?.hardwareAddress.bytes.map(String.init).joined(separator: ", ") ?? "0, 0, 0, 0, 0, 0"
  }

  private static func ethernetMedia(_ value: EthernetDeviceConfiguration?) -> String {
    value?.media.map { String($0.rawValue) }.joined(separator: ", ") ?? "0"
  }

  private static func interruptIndices(_ configuration: DriverConfiguration) -> String {
    let indices = configuration.interruptSources.map { String($0.nativeIndex) }.joined(
      separator: ", "
    )
    return indices.isEmpty ? "0" : indices + ", 0"
  }

  static func cString(_ value: String) -> String {
    let literals = value.utf8.map { String(format: "\"\\x%02X\"", $0) }.joined()
    return literals.isEmpty ? "\"\"" : literals
  }

  static func serviceInterface(_ configuration: DriverConfiguration) -> String {
    let hid = configuration.capabilities.contains(.hid)
    let usb = configuration.capabilities.contains(.usb)
    let pci = configuration.capabilities.contains(.pci)
    let serial = configuration.capabilities.contains(.serial)
    let blockStorage = configuration.capabilities.contains(.blockStorage)
    let midi = configuration.capabilities.contains(.midi)
    let networking = configuration.capabilities.contains(.networking)
    let audio = configuration.capabilities.contains(.audio)
    let video = configuration.capabilities.contains(.video)
    let scsiController = configuration.scsiController != nil
    let scsiPeripheralClass = scsiPeripheralSuperclass(configuration.scsiPeripheral)
    let scsiPeripheralInclude = scsiPeripheralSuperclassInclude(configuration.scsiPeripheral)
    let interrupts = configuration.capabilities.contains(.interrupts)
    let memory = configuration.capabilities.contains(.memory)
    let superclass =
      hid
      ? "IOUserHIDDevice"
      : serial
        ? "IOUserSerial"
        : blockStorage
          ? "IOUserBlockStorageDevice"
          : midi
            ? "IOUserMIDIDriver"
            : networking
              ? "IOUserNetworkEthernet"
              : audio
                ? "IOUserAudioDriver"
                : video
                  ? "IOUserVideoDriver"
                  : scsiController
                    ? "IOUserSCSIParallelInterfaceController" : scsiPeripheralClass ?? "IOService"
    let superclassInclude =
      hid
      ? "#include <HIDDriverKit/IOUserHIDDevice.iig>"
      : serial
        ? "#include <SerialDriverKit/IOUserSerial.iig>"
        : blockStorage
          ? "#include <BlockStorageDeviceDriverKit/IOUserBlockStorageDevice.iig>"
          : midi
            ? "#include <MIDIDriverKit/IOUserMIDIDriver.iig>"
            : networking
              ? "#include <NetworkingDriverKit/IOUserNetworkEthernet.iig>"
              : audio
                ? "#include <AudioDriverKit/IOUserAudioDriver.iig>"
                : video
                  ? "#include <VideoDriverKit/IOUserVideoDriver.iig>"
                  : scsiController
                    ? "#include <SCSIControllerDriverKit/IOUserSCSIParallelInterfaceController.iig>"
                    : scsiPeripheralInclude ?? "#include <DriverKit/IOService.iig>"
    let lifecycle =
      hid
      ? """
          virtual kern_return_t Stop(IOService* provider) override;
      """
      : """
          virtual kern_return_t Start(IOService* provider) override;
          virtual kern_return_t Stop(IOService* provider) override;
      """
    let audioMethods = audioServiceMethods(enabled: audio)
    let videoMethods = videoServiceMethods(enabled: video)
    let scsiMethods = scsiServiceMethods(enabled: scsiController)
    let scsiPeripheralMethods = scsiPeripheralServiceMethods(configuration.scsiPeripheral)
    let usbMethods =
      usb
      ? """
          kern_return_t USBControlTransfer(
              const SwifterKitUSBControlTransferHeader* header,
              const uint8_t* bytes,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t USBPipeTransfer(
              const SwifterKitUSBPipeTransferHeader* header,
              const uint8_t* bytes,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t USBClearStall(uint8_t endpoint, bool withRequest) LOCALONLY;
          kern_return_t USBSelectAlternateSetting(uint8_t alternateSetting) LOCALONLY;
      """ : ""
    let pciMethods =
      pci
      ? """
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
      """ : ""
    let midiMethods =
      midi
      ? """
          kern_return_t StartMIDI() LOCALONLY;
          void StopMIDI() LOCALONLY;
          kern_return_t MIDICommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t MIDIReceived(
              uint32_t destinationIndex,
              const uint32_t* words,
              uint32_t wordCount) LOCALONLY;

      protected:
          virtual kern_return_t StartIO(OSArray* deviceList) LOCALONLY override;
          virtual kern_return_t StopIO() LOCALONLY override;
      """ : ""
    let networkingMethods =
      networking
      ? """
          kern_return_t StartNetwork() LOCALONLY;
          void StopNetwork() LOCALONLY;
          kern_return_t NetworkCommand(
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
          virtual uint32_t getHardwareAssists() LOCALONLY override;
          virtual MediaWord getInitialMedia() LOCALONLY override;
          virtual kern_return_t getHardwareAddress(
              ether_addr_t* address) LOCALONLY override;
          virtual kern_return_t setHardwareAddress(
              ether_addr_t* address) LOCALONLY override;
      """ : ""
    let blockStorageMethods =
      blockStorage
      ? """
          void StopBlockStorage() LOCALONLY;
          kern_return_t BlockStorageCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength) LOCALONLY;

      protected:
          virtual kern_return_t DoAsyncEjectMedia(uint32_t requestID) override;
          virtual kern_return_t DoAsyncSynchronize(
              uint32_t requestID,
              uint64_t lba,
              uint64_t blockCount) override;
          virtual kern_return_t DoAsyncReadWrite(
              bool isRead,
              uint32_t requestID,
              uint64_t dmaAddress,
              uint64_t byteCount,
              uint64_t lba,
              uint64_t blockCount,
              IOUserStorageOptions options) override;
          virtual kern_return_t GetDeviceParams(struct DeviceParams* parameters) override;
          virtual kern_return_t GetVendorString(struct DeviceString* value) override;
          virtual kern_return_t GetProductString(struct DeviceString* value) override;
          virtual kern_return_t GetRevisionString(struct DeviceString* value) override;
          virtual kern_return_t GetAdditionalInfoString(struct DeviceString* value) override;
          virtual kern_return_t ReportEjectability(bool* value) override;
          virtual kern_return_t ReportRemovability(bool* value) override;
          virtual kern_return_t ReportWriteProtection(bool* value) override;

      private:
          virtual kern_return_t DoAsyncUnmapPriv(
              uint32_t requestID,
              struct BlockRange* ranges,
              uint32_t rangeCount) LOCALONLY override;
      """ : ""
    let serialMethods =
      serial
      ? """
          kern_return_t StartSerial() LOCALONLY;
          void StopSerial() LOCALONLY;
          kern_return_t SerialCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;

      protected:
          virtual void RxFreeSpaceAvailable() LOCAL override;
          virtual void TxDataAvailable() LOCAL override;
          virtual kern_return_t HwActivate() LOCAL override;
          virtual kern_return_t HwDeactivate() LOCAL override;
          virtual kern_return_t HwResetFIFO(bool tx, bool rx) LOCAL override;
          virtual kern_return_t HwSendBreak(bool sendBreak) LOCAL override;
          virtual kern_return_t HwProgramUART(
              uint32_t baudRate,
              uint8_t dataBits,
              uint8_t halfStopBits,
              uint8_t parity) LOCAL override;
          virtual kern_return_t HwProgramBaudRate(uint32_t baudRate) LOCAL override;
          virtual kern_return_t HwProgramMCR(bool dtr, bool rts) LOCAL override;
          virtual kern_return_t HwGetModemStatus(
              bool* cts,
              bool* dsr,
              bool* ri,
              bool* dcd) LOCAL override;
          virtual kern_return_t HwProgramLatencyTimer(uint32_t latency) LOCAL override;
          virtual kern_return_t HwProgramFlowControl(
              uint32_t flags,
              uint8_t xon,
              uint8_t xoff) LOCAL override;
      """ : ""
    let memoryMethods =
      memory
      ? """
          kern_return_t StartMemory(IOService* provider) LOCALONLY;
          void StopMemory() LOCALONLY;
          kern_return_t MemoryCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
      """ : ""
    let interruptMethods =
      interrupts
      ? """
          kern_return_t StartInterrupts(IOService* provider) LOCALONLY;
          void StopInterrupts() LOCALONLY;
          kern_return_t InterruptCommand(
              uint32_t opcode,
              const SwifterKitInterruptCommandHeader* header,
              OSData** response) LOCALONLY;
          virtual void InterruptOccurred(
              OSAction* action,
              uint64_t count,
              uint64_t time) TYPE(IOInterruptDispatchSource::InterruptOccurred);
      """ : ""
    let interruptInclude = interrupts ? "#include <DriverKit/IOInterruptDispatchSource.iig>" : ""
    let hidMethods =
      hid
      ? """
          kern_return_t SubmitHIDInputReport(
              const SwifterKitHIDReportHeader* header,
              const uint8_t* bytes) LOCALONLY;
          kern_return_t CopyHIDRuntimeStatistics(
              SwifterKitHIDRuntimeStatistics* statistics) LOCALONLY;

      protected:
          virtual bool handleStart(IOService* provider) LOCALONLY override;
          virtual OSDictionary* newDeviceDescription() LOCALONLY override;
          virtual OSData* newReportDescriptor() LOCALONLY override;
          virtual kern_return_t setReport(
              IOMemoryDescriptor* report,
              IOHIDReportType reportType,
              IOOptionBits options,
              uint32_t completionTimeout,
              OSAction* action) LOCALONLY override;
      """ : ""

    return """
      #ifndef SwifterKitRuntimeService_h
      #define SwifterKitRuntimeService_h

      #include <Availability.h>

      #include <DriverKit/OSData.iig>
      \(superclassInclude)
      \(interruptInclude)
      \(networking ? "#include <DriverKit/IODataQueueDispatchSource.iig>" : "")

      #include "SwifterKitRuntimeProtocol.h"

      class SwifterKitRuntimeService : public \(superclass) {
      public:
          virtual bool init() override;
          virtual void free() override;
      \(lifecycle)
          virtual kern_return_t NewUserClient(uint32_t type, IOUserClient** userClient) override;

          kern_return_t CopyNextEvent(OSData** event) LOCALONLY;
          kern_return_t EnqueueEvent(
              uint32_t type,
              const void* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t EnqueueRequiredEvent(
              uint32_t type,
              const void* payload,
              uint32_t payloadLength) LOCALONLY;
      \(memoryMethods)
      \(audioMethods)
      \(videoMethods)
      \(scsiMethods)
      \(scsiPeripheralMethods)
      \(networkingMethods)
      \(midiMethods)
      \(blockStorageMethods)
      \(serialMethods)
      \(interruptMethods)
      \(usbMethods)
      \(pciMethods)
      \(hidMethods)
      };

      #endif
      """
  }

}
