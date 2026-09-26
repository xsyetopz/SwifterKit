import Foundation

/// The HIDDriverKit role a generated runtime plays.
enum HIDRuntimeMode: Equatable {
  /// No HID behavior.
  case none
  /// `IOUserHIDDevice` with a report descriptor from ``HIDDeviceConfiguration``.
  case device
  /// `IOUserUSBHostHIDDevice` on a USB HID interface.
  case usbDevice
  /// `IOUserHIDEventService` on an `IOHIDInterface`.
  case eventService
  /// `IOUserHIDEventDriver` on an `IOHIDInterface`.
  case eventDriver

  init(_ configuration: DriverConfiguration) {
    guard configuration.capabilities.contains(.hid) else {
      self = .none
      return
    }
    if configuration.usbHIDDevice != nil {
      self = .usbDevice
    } else if let service = configuration.hidEventService {
      if case .eventDriver = service.serviceClass {
        self = .eventDriver
      } else {
        self = .eventService
      }
    } else {
      self = .device
    }
  }

  var isEventService: Bool { self == .eventService || self == .eventDriver }

  var superclass: String? {
    switch self {
    case .none: nil
    case .device: "IOUserHIDDevice"
    case .usbDevice: "IOUserUSBHostHIDDevice"
    case .eventService: "IOUserHIDEventService"
    case .eventDriver: "IOUserHIDEventDriver"
    }
  }

  /// The kernel class that hosts the generated service, from Apple's own HID personalities.
  var kernelClass: String? {
    switch self {
    case .none: nil
    case .device, .usbDevice: "AppleUserHIDDevice"
    case .eventService, .eventDriver: "AppleUserHIDEventService"
    }
  }
}

extension DriverExtensionGenerator {
  static func validateHID(
    _ configuration: DriverConfiguration,
    deploymentVersion: DriverKitDeploymentVersion
  ) throws {
    let capabilities = configuration.capabilities
    let roles = [
      configuration.hidDevice != nil, configuration.hidEventService != nil,
      configuration.usbHIDDevice != nil,
    ].filter { $0 }.count
    guard capabilities.contains(.hid) else {
      if roles > 0 { throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.hid) }
      return
    }
    guard roles == 1 else { throw DriverExtensionGenerationError.invalidHIDConfiguration }
    if let hid = configuration.hidDevice {
      guard isValid(hid: hid) else { throw DriverExtensionGenerationError.invalidHIDConfiguration }
    }
    if let service = configuration.hidEventService {
      guard service.isValid,
        configuration.providerClass == HIDEventServiceConfiguration.providerClass,
        deploymentVersion >= .v21, capabilities.isDisjoint(with: [.usb, .pci, .interrupts])
      else { throw DriverExtensionGenerationError.invalidHIDConfiguration }
    }
    if let device = configuration.usbHIDDevice {
      guard device.isValid, capabilities.contains(.usb),
        configuration.providerClass == USBDeviceConfiguration.interfaceProviderClass,
        capabilities.isDisjoint(with: [.pci, .interrupts])
      else { throw DriverExtensionGenerationError.invalidHIDConfiguration }
    }
  }

  private static func isValid(hid: HIDDeviceConfiguration) -> Bool {
    let strings = [hid.transport, hid.manufacturer, hid.product, hid.serialNumber]
    return !hid.reportDescriptor.isEmpty && hid.reportDescriptor.count <= 65_488
      && hid.acceptedHostReportTypes.subtracting(.all).isEmpty
      && hid.answeredReportTypes.subtracting(.all).isEmpty
      && strings.allSatisfy { !$0.isEmpty && !$0.contains("\0") }
  }

  /// Registry keys an event service's typed matching writes into the personality.
  static func hidReservedKeys(_ configuration: DriverConfiguration) -> Set<String> {
    configuration.hidEventService == nil ? [] : ["DeviceUsagePairs", "VendorID", "ProductID"]
  }

  static func addHIDPersonality(
    _ configuration: DriverConfiguration,
    to personality: inout [String: Any]
  ) {
    let mode = HIDRuntimeMode(configuration)
    guard let kernelClass = mode.kernelClass else { return }
    personality["IOClass"] = kernelClass
    if mode != .device { personality["CFBundleIdentifierKernel"] = "com.apple.iokit.IOHIDFamily" }
    if let hid = configuration.hidDevice {
      personality["PrimaryUsagePage"] = hid.primaryUsagePage
      personality["PrimaryUsage"] = hid.primaryUsage
    }
    guard let service = configuration.hidEventService else { return }
    if !service.usagePairs.isEmpty {
      personality["DeviceUsagePairs"] = service.usagePairs.map { pair -> [String: Any] in
        var entry: [String: Any] = ["DeviceUsagePage": pair.usagePage]
        if let usage = pair.usage { entry["DeviceUsage"] = usage }
        return entry
      }
    }
    if let vendorID = service.vendorID { personality["VendorID"] = vendorID }
    if let productID = service.productID { personality["ProductID"] = productID }
  }

  static func hidConfigurationDeclarations(_ configuration: DriverConfiguration) -> String {
    let mode = HIDRuntimeMode(configuration)
    let hid = configuration.hidDevice
    let usb = configuration.usbHIDDevice
    let service = configuration.hidEventService
    let descriptorBytes = hid?.reportDescriptor ?? usb?.reportDescriptor ?? []
    let descriptor =
      descriptorBytes.isEmpty ? "0" : descriptorBytes.map(String.init).joined(separator: ", ")
    let properties = usb?.encodedDeviceProperties ?? []
    let encodedProperties =
      properties.isEmpty ? "0" : properties.map(String.init).joined(separator: ", ")
    let accepted =
      hid?.acceptedHostReportTypes.rawValue ?? usb?.acceptedHostReportTypes.rawValue ?? 0
    let answered = hid?.answeredReportTypes.rawValue ?? usb?.answeredReportTypes.rawValue ?? 0
    return """
      #define SWIFTERKIT_HID_DEVICE \(mode == .device || mode == .usbDevice ? 1 : 0)
      #define SWIFTERKIT_HID_USB_DEVICE \(mode == .usbDevice ? 1 : 0)
      #define SWIFTERKIT_HID_EVENT_SERVICE \(mode.isEventService ? 1 : 0)
      #define SWIFTERKIT_HID_EVENT_DRIVER \(mode == .eventDriver ? 1 : 0)

      static constexpr uint8_t kSwifterKitHIDReportDescriptor[] = {\(descriptor)};
      static constexpr uint32_t kSwifterKitHIDReportDescriptorLength = \(descriptorBytes.count);
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
      static constexpr uint32_t kSwifterKitHIDAcceptedHostReportTypes =
          \(accepted);
      static constexpr uint32_t kSwifterKitHIDAnsweredReportTypes = \(answered);
      static constexpr uint8_t kSwifterKitHIDDeviceProperties[] = {\(encodedProperties)};
      static constexpr uint32_t kSwifterKitHIDDevicePropertiesLength = \(properties.count);
      static constexpr bool kSwifterKitHIDDeliversDeviceInputReports =
          \(usb?.deliversInputReports == true ? "true" : "false");
      static constexpr uint32_t kSwifterKitHIDEventDelivery = \(service?.delivery.rawValue ?? 0);
      static constexpr uint32_t kSwifterKitHIDEventDriverCategories =
          \(service?.eventDriverCategories.rawValue ?? 0);
      """
  }

  static func hidSuperclassInclude(_ mode: HIDRuntimeMode) -> String? {
    mode.superclass.map { "#include <HIDDriverKit/\($0).iig>" }
  }

  static func hidServiceMethods(_ mode: HIDRuntimeMode) -> String {
    switch mode {
    case .none: return ""
    case .device, .usbDevice:
      let handleReport =
        mode == .usbDevice
        ? """
            virtual kern_return_t handleReport(
                uint64_t timestamp,
                IOMemoryDescriptor* report,
                uint32_t reportLength,
                IOHIDReportType reportType,
                IOOptionBits options) LOCALONLY override;
        """ : ""
      return """
        \(hidCommonMethods)
            kern_return_t SubmitHIDInputReport(
                const SwifterKitHIDReportHeader* header,
                const uint8_t* bytes) LOCALONLY;
            kern_return_t CopyHIDRuntimeStatistics(
                SwifterKitHIDRuntimeStatistics* statistics) LOCALONLY;
            kern_return_t CompleteHIDGetReport(
                const uint8_t* payload,
                uint32_t payloadLength) LOCALONLY;

        protected:
            virtual bool handleStart(IOService* provider) LOCALONLY override;
            virtual OSDictionary* newDeviceDescription() LOCALONLY override;
            virtual OSData* newReportDescriptor() LOCALONLY override;
            virtual kern_return_t getReport(
                IOMemoryDescriptor* report,
                IOHIDReportType reportType,
                IOOptionBits options,
                uint32_t completionTimeout,
                OSAction* action) LOCALONLY override;
            virtual kern_return_t setReport(
                IOMemoryDescriptor* report,
                IOHIDReportType reportType,
                IOOptionBits options,
                uint32_t completionTimeout,
                OSAction* action) LOCALONLY override;
            virtual void setProperty(OSObject* key, OSObject* value) LOCALONLY override;
        \(handleReport)
        """
    case .eventService, .eventDriver:
      return """
        \(hidCommonMethods)
            kern_return_t HIDElementCommand(
                uint32_t opcode,
                const uint8_t* payload,
                uint32_t payloadLength,
                OSData** response) LOCALONLY;
            kern_return_t HIDDispatchCommand(
                uint32_t opcode,
                const uint8_t* payload,
                uint32_t payloadLength,
                OSData** response) LOCALONLY;
            kern_return_t DispatchHIDDigitizerCollection(
                const uint8_t* payload,
                uint32_t payloadLength) LOCALONLY;

        protected:
            virtual bool handleStart(IOService* provider) LOCALONLY override;
            virtual void handleReport(
                uint64_t timestamp,
                uint8_t* report,
                uint32_t reportLength,
                IOHIDReportType type,
                uint32_t reportID) LOCALONLY override;
            virtual kern_return_t processReport(
                uint64_t timestamp,
                uint64_t report,
                uint32_t reportLength,
                IOHIDReportType type,
                uint32_t reportID) override;
            virtual kern_return_t SetLEDState(uint32_t usagePage, uint32_t usage, bool on) override;
            virtual kern_return_t SetProperties(OSDictionary* properties) override;
        \(mode == .eventDriver ? hidEventDriverMethods : "")
        """
    }
  }

  private static let hidCommonMethods = """
        kern_return_t HIDCommand(
            uint32_t opcode,
            const uint8_t* payload,
            uint32_t payloadLength,
            OSData** response) LOCALONLY;
        void StopHID() LOCALONLY;
        void AbortHIDRequests() LOCALONLY;
    """

  private static let hidEventDriverMethods = """
        virtual bool parseKeyboardElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parsePointerElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseScrollElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseLEDElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseDigitizerElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseProximityElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseGameControllerElement(IOHIDElement* element) LOCALONLY override;
        virtual bool parseRemainingElement(IOHIDElement* element) LOCALONLY override;
        virtual void handleKeyboardReport(uint64_t timestamp, uint32_t reportID) LOCALONLY override;
        virtual void handleRelativePointerReport(
            uint64_t timestamp,
            uint32_t reportID) LOCALONLY override;
        virtual void handleAbsolutePointerReport(
            uint64_t timestamp,
            uint32_t reportID) LOCALONLY override;
        virtual void handleScrollReport(uint64_t timestamp, uint32_t reportID) LOCALONLY override;
        virtual void handleDigitizerReport(
            uint64_t timestamp,
            uint32_t reportID) LOCALONLY override;
        virtual void handleProximityReport(
            uint64_t timestamp,
            uint32_t reportID) LOCALONLY override;
        virtual void handleGameControllerReport(
            uint64_t timestamp,
            uint32_t reportID) LOCALONLY override;
    """
}
