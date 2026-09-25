import Foundation

extension DriverExtensionGenerator {
  static func usesUSBDeviceProvider(_ configuration: DriverConfiguration) -> Bool {
    configuration.usbDevice != nil
      && configuration.providerClass == USBDeviceConfiguration.deviceProviderClass
  }

  static func isValidUSB(_ configuration: DriverConfiguration) -> Bool {
    guard let usb = configuration.usbDevice, usb.vendorID != 0,
      Set(usb.productIDs).count == usb.productIDs.count,
      usb.productIDMask == nil || usb.productIDs.count == 1
    else { return false }
    switch configuration.providerClass {
    case USBDeviceConfiguration.interfaceProviderClass: return true
    case USBDeviceConfiguration.deviceProviderClass:
      // IOUSBHostDevice matching has no configuration or interface keys.
      return usb.configurationValue == nil && usb.interfaceNumber == nil
        && usb.interfaceClass == nil && usb.interfaceSubclass == nil && usb.interfaceProtocol == nil
    default: return false
    }
  }

  static func usbServiceMethods(enabled: Bool) -> String {
    guard enabled else { return "" }
    return """
          kern_return_t StartUSB(IOService* provider) LOCALONLY;
          void StopUSB() LOCALONLY;
          void ReleaseUSBTransfers() LOCALONLY;
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
          kern_return_t USBCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          kern_return_t USBPipeCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;
          void DeliverUSBCompletions() LOCALONLY;
          virtual void USBPipeIOComplete(
              OSAction* action,
              IOReturn status,
              uint32_t actualByteCount,
              uint64_t completionTimestamp) TYPE(IOUSBHostPipe::CompleteAsyncIO);
          virtual void USBPipeIsochIOComplete(
              OSAction* action,
              IOReturn status) TYPE(IOUSBHostPipe::CompleteAsyncIsochIO);
      """
  }
}
