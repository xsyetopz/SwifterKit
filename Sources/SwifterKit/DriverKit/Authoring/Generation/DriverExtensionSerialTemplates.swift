import Foundation

extension DriverExtensionGenerator {
  /// The terminal metadata of an `IOUserSerial` or `IOUserUSBSerial` service.
  static func serialTerminal(
    _ configuration: DriverConfiguration
  ) -> (baseName: String, suffix: String, modem: SerialModemStatus)? {
    if let serial = configuration.serialPort {
      return (serial.baseName, serial.suffix, serial.initialModemStatus)
    }
    guard let usbSerial = configuration.usbSerialPort else { return nil }
    return (usbSerial.baseName ?? "", usbSerial.suffix ?? "", usbSerial.initialModemStatus)
  }

  static func usbSerialConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let usbSerial = configuration.usbSerialPort
    let overridesName = usbSerial?.baseName != nil && usbSerial?.suffix != nil
    return """
      #define SWIFTERKIT_USB_SERIAL \(usbSerial == nil ? 0 : 1)
      static constexpr bool kSwifterKitUSBSerialOverridesName = \(overridesName);
      static constexpr bool kSwifterKitUSBSerialDeliversReceivedPackets =
          \(usbSerial?.deliversReceivedPackets == true);
      static constexpr bool kSwifterKitUSBSerialDeliversInterruptPackets =
          \(usbSerial?.deliversInterruptPackets == true);
      """
  }

  static func serialServiceMethods(_ configuration: DriverConfiguration) -> String {
    guard configuration.capabilities.contains(.serial) else { return "" }
    // IOUserUSBSerial moves queue data itself: RxFreeSpaceAvailable and TxDataAvailable are final,
    // and its packet hooks replace them.
    let dataPath =
      configuration.usbSerialPort == nil
      ? """
          virtual void RxFreeSpaceAvailable() LOCAL override;
          virtual void TxDataAvailable() LOCAL override;
      """
      : """
          virtual void handleRxPacket(uint8_t*& packet, uint32_t& size) LOCALONLY override;
          virtual void handleInterruptPacket(
              const uint8_t* packet,
              uint32_t size) LOCALONLY override;
      """
    return """
          kern_return_t StartSerial() LOCALONLY;
          void StopSerial() LOCALONLY;
          kern_return_t SerialCommand(
              uint32_t opcode,
              const uint8_t* payload,
              uint32_t payloadLength,
              OSData** response) LOCALONLY;

      protected:
      \(dataPath)
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
      """
  }
}
