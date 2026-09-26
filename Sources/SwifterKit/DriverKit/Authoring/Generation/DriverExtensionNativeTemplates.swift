import Foundation

extension DriverExtensionGenerator {
  static func runtimeConfigurationHeader(_ configuration: DriverConfiguration) -> String {
    let interruptsEnabled = configuration.capabilities.contains(.interrupts) ? 1 : 0
    let encodedInterruptIndices = interruptIndices(configuration)
    let memory = configuration.memoryPool
    let serial = serialTerminal(configuration)
    let block = configuration.blockStorageDevice
    let midi = configuration.midiDevice
    let audio = configuration.audioDevice
    let video = configuration.videoDevice
    let scsiController = configuration.scsiController
    let scsiPeripheral = configuration.scsiPeripheral
    return """
      #ifndef SwifterKitRuntimeConfiguration_h
      #define SwifterKitRuntimeConfiguration_h

      #include <stdint.h>

      #include "SwifterKitRuntimeFastPathSchema.h"

      static constexpr char kSwifterKitBundleIdentifier[] =
          \(cString(configuration.bundleIdentifier));

      \(audioConfigurationDeclarations(configuration))
      \(videoConfigurationDeclarations(configuration))
      \(scsiConfigurationDeclarations(configuration))

      #define SWIFTERKIT_ENABLE_HID \(configuration.capabilities.contains(.hid) ? 1 : 0)
      \(hidConfigurationDeclarations(configuration))
      #define SWIFTERKIT_ENABLE_NETWORKING \(configuration.ethernetDevice == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_AUDIO \(audio == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_VIDEO \(video == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SCSI_CONTROLLER \(scsiController == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SCSI_PERIPHERAL \(scsiPeripheral == nil ? 0 : 1)
      #define SWIFTERKIT_SCSI_PERIPHERAL_TYPE \(scsiPeripheral?.deviceType.rawValue ?? 0)
      #define SWIFTERKIT_ENABLE_USB \(configuration.capabilities.contains(.usb) ? 1 : 0)
      #define SWIFTERKIT_ENABLE_MIDI \(midi == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_BLOCK_STORAGE \(block == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_SERIAL \(serial == nil ? 0 : 1)
      \(usbSerialConfigurationDeclarations(configuration))
      #define SWIFTERKIT_ENABLE_PCI \(configuration.capabilities.contains(.pci) ? 1 : 0)
      #define SWIFTERKIT_ENABLE_INTERRUPTS \(interruptsEnabled)
      #define SWIFTERKIT_ENABLE_MEMORY \(memory == nil ? 0 : 1)
      #define SWIFTERKIT_ENABLE_FAST_PATH \(configuration.fastPath == nil ? 0 : 1)

      static constexpr bool kSwifterKitUSBDeviceProvider =
          \(usesUSBDeviceProvider(configuration));

      \(ethernetConfigurationDeclarations(configuration))

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
          \(serial?.modem.clearToSend == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialDSR =
          \(serial?.modem.dataSetReady == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialRI =
          \(serial?.modem.ringIndicator == true ? "true" : "false");
      static constexpr bool kSwifterKitSerialInitialDCD =
          \(serial?.modem.dataCarrierDetect == true ? "true" : "false");

      static constexpr uint32_t kSwifterKitInterruptIndices[] = {\(encodedInterruptIndices)};
      static constexpr uint32_t kSwifterKitInterruptSourceCount =
          \(configuration.interruptSources.count);
      \(pciInterruptDeclarations(configuration))
      \(reportingDeclarations(configuration.reporting))
      \(fastPathDeclarations(configuration.fastPath))


      #endif
      """
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
    let hidMode = HIDRuntimeMode(configuration)
    let hid = hidMode != .none
    let usb = configuration.capabilities.contains(.usb)
    let pci = configuration.capabilities.contains(.pci)
    let serial = configuration.capabilities.contains(.serial)
    let usbSerial = configuration.usbSerialPort != nil
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
      hidMode.superclass
      ?? (usbSerial
        ? "IOUserUSBSerial"
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
                      ? "IOUserSCSIParallelInterfaceController"
                      : scsiPeripheralClass ?? "IOService")
    let scsiControllerInclude =
      "#include <SCSIControllerDriverKit/IOUserSCSIParallelInterfaceController.iig>"
    let superclassInclude =
      hidSuperclassInclude(hidMode)
      ?? (usbSerial
        ? "#include <USBSerialDriverKit/IOUserUSBSerial.iig>"
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
                      ? scsiControllerInclude
                      : scsiPeripheralInclude ?? "#include <DriverKit/IOService.iig>")
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
    let usbMethods = usbServiceMethods(enabled: usb)
    let pciMethods = pciServiceMethods(enabled: pci)
    let midiMethods =
      midi
      ? """
          kern_return_t StartMIDI() LOCALONLY;
          void StopMIDI() LOCALONLY;
          kern_return_t MIDICommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t MIDIObjectCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          IOUserMIDIDevice* CopyMIDIDevice() LOCALONLY;
          kern_return_t MIDIReceived(
              uint32_t destinationIndex,
              const uint32_t* words,
              uint32_t wordCount) LOCALONLY;

      protected:
          virtual kern_return_t StartIO(OSArray* deviceList) LOCALONLY override;
          virtual kern_return_t StopIO() LOCALONLY override;
      """ : ""
    let networkingMethods = networkingServiceMethods(enabled: networking)
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
    let serialMethods = serialServiceMethods(configuration)
    let memoryMethods =
      memory
      ? """
          kern_return_t StartMemory(IOService* provider) LOCALONLY;
          void StopMemory() LOCALONLY;
          kern_return_t MemoryCommand(
              const IOService* client,
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t CopyMemoryForClient(
              IOService* client,
              uint64_t handle,
              IOMemoryDescriptor** memory) LOCALONLY;
          void ReleaseClientMemory(IOService* client) LOCALONLY;
          kern_return_t WrapClientMemory(
              IOUserClient* client,
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
    let fastPathMethods =
      configuration.fastPath == nil
      ? ""
      : """
          void StartFastPath() LOCALONLY;
          void StopFastPath() LOCALONLY;
          void InvalidateFastPathBARs() LOCALONLY;
          bool RunFastPathInterrupt(uint32_t sourceIndex) LOCALONLY;
          kern_return_t CopyFastPathRingMemory(
              uint32_t identifier,
              IOMemoryDescriptor** memory) LOCALONLY;
          kern_return_t FastPathCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
      """
    let interruptInclude = interrupts ? "#include <DriverKit/IOInterruptDispatchSource.iig>" : ""
    let hidMethods = hidServiceMethods(hidMode)

    return """
      #ifndef SwifterKitRuntimeService_h
      #define SwifterKitRuntimeService_h

      #include <Availability.h>

      #include <DriverKit/IOServiceNotificationDispatchSource.iig>
      #include <DriverKit/IOServiceStateNotificationDispatchSource.iig>
      #include <DriverKit/IOTimerDispatchSource.iig>
      #include <DriverKit/OSData.iig>
      \(superclassInclude)
      \(interruptInclude)
      \(usb ? "#include <USBDriverKit/IOUSBHostDevice.iig>" : "")
      \(usb ? "#include <USBDriverKit/IOUSBHostPipe.iig>" : "")
      \(networking ? "#include <DriverKit/IODataQueueDispatchSource.iig>" : "")

      #include "SwifterKitRuntimeProtocol.h"

      class SwifterKitRuntimeService : public \(superclass) {
      public:
          virtual bool init() override;
          virtual void free() override;
      \(lifecycle)
          virtual kern_return_t NewUserClient(uint32_t type, IOUserClient** userClient) override;
          virtual kern_return_t ClientCrashed(IOService* client, uint64_t options) override;

          kern_return_t CopyNextEvent(OSData** event) LOCALONLY;
          kern_return_t EnqueueEvent(
              uint32_t type,
              const void* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t EnqueueRequiredEvent(
              uint32_t type,
              const void* payload,
              uint32_t payloadLength) LOCALONLY;
          kern_return_t AttachEventClient(IOService* client) LOCALONLY;
          void DetachEventClient(IOService* client) LOCALONLY;
          kern_return_t CopyClientMemory(
              IOService* client,
              uint64_t type,
              uint64_t* options,
              IOMemoryDescriptor** memory) LOCALONLY;
      \(serviceControlMethods)
      \(reportingMethods)
      \(fastPathMethods)
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
