extension DriverExtensionGenerator {
  /// IOService registry, power, and system-state methods every generated service declares.
  ///
  /// They follow the event-client methods so they stay public for every superclass. The
  /// `SetPowerState` override matches `IOService` and `IOUserNetworkEthernet` alike.
  static let serviceControlMethods = """
        virtual kern_return_t SetPowerState(uint32_t powerFlags) override;
        virtual void PowerStateTimerOccurred(
            OSAction* action,
            uint64_t time) TYPE(IOTimerDispatchSource::TimerOccurred);
        kern_return_t AnswerPowerState(uint32_t requestID) LOCALONLY;
        void StopPower() LOCALONLY;
        kern_return_t ServiceCommand(
            uint32_t opcode,
            const uint8_t* payload,
            uint32_t payloadLength,
            OSData** response) LOCALONLY;
        kern_return_t ServiceSystemCommand(
            uint32_t opcode,
            const uint8_t* payload,
            uint32_t payloadLength,
            OSData** response) LOCALONLY;
        kern_return_t ServicePowerCommand(
            uint32_t opcode,
            const uint8_t* payload,
            uint32_t payloadLength,
            OSData** response) LOCALONLY;
    """
}
