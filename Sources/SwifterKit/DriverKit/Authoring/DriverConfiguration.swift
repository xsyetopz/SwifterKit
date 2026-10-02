/// Static metadata used to generate and connect a DriverKit extension.
public struct DriverConfiguration: Sendable, Hashable {
  /// The internal service class implemented by SwifterKit's native runtime.
  public static let runtimeServiceClass = "SwifterKitRuntimeService"

  /// The driver extension bundle identifier.
  public let bundleIdentifier: String
  /// The DriverKit provider class matched by the extension.
  public let providerClass: String
  /// Additional IOKit personality matching properties for the provider.
  public let matchingProperties: [String: DriverProperty]
  /// Runtime capabilities required by the Swift driver.
  public let capabilities: RuntimeCapabilities
  /// Virtual HID metadata when the generated runtime provides HIDDriverKit behavior.
  public let hidDevice: HIDDeviceConfiguration?
  /// Event-service metadata when the runtime matches an `IOHIDInterface` and dispatches events.
  public let hidEventService: HIDEventServiceConfiguration?
  /// USB HID metadata when the runtime derives from `IOUserUSBHostHIDDevice`.
  public let usbHIDDevice: USBHIDDeviceConfiguration?
  /// Factory limits when the runtime creates virtual HID devices at run time.
  public let hidDeviceFactory: HIDDeviceFactoryConfiguration?
  /// USB hardware matching when the generated runtime provides USBDriverKit behavior.
  public let usbDevice: USBDeviceConfiguration?
  /// PCI matching when the generated runtime provides PCIDriverKit behavior.
  public let pciDevice: PCIDeviceConfiguration?
  /// Terminal metadata when the generated runtime provides SerialDriverKit behavior.
  public let serialPort: SerialPortConfiguration?
  /// USB serial-port metadata when the runtime derives from `IOUserUSBSerial`.
  public let usbSerialPort: USBSerialPortConfiguration?
  /// Device metadata when the runtime provides BlockStorageDeviceDriverKit behavior.
  public let blockStorageDevice: BlockStorageDeviceConfiguration?
  /// Device and endpoint topology when the runtime provides MIDIDriverKit behavior.
  public let midiDevice: MIDIDeviceConfiguration?
  /// Ethernet interface metadata when the runtime provides NetworkingDriverKit behavior.
  public let ethernetDevice: EthernetDeviceConfiguration?
  /// Device and stream topology when the runtime provides AudioDriverKit behavior.
  public let audioDevice: AudioDeviceConfiguration?
  /// Device, stream, and buffer topology when the runtime provides VideoDriverKit behavior.
  public let videoDevice: VideoDeviceConfiguration?
  /// HBA policy when the runtime provides SCSIControllerDriverKit behavior.
  public let scsiController: SCSIControllerConfiguration?
  /// Logical-unit policy when the runtime provides SCSIPeripheralsDriverKit behavior.
  public let scsiPeripheral: SCSIPeripheralConfiguration?
  /// Hardware interrupt sources managed by the generated native runtime.
  public let interruptSources: [InterruptSourceConfiguration]
  /// Native memory-pool limits when raw memory operations are enabled.
  public let memoryPool: MemoryPoolConfiguration?
  /// IOReporting channels the generated service publishes, if any.
  public let reporting: ReportingConfiguration?
  /// Register programs the generated extension runs natively, if any.
  public let fastPath: FastPathConfiguration?
  /// The IOKit personality this configuration describes inside a multi-personality extension.
  ///
  /// `nil` for a single-configuration extension. ``DriverExtensionConfiguration/personality(_:)``
  /// returns configurations with this set, which names the personality's own ``serviceClass``.
  public internal(set) var personalityName: String?

  /// The native class of the service this configuration's extension starts.
  ///
  /// ``runtimeServiceClass`` for a single-configuration extension. Each personality of a
  /// ``DriverExtensionConfiguration`` runs its own class, which inserts the personality name:
  /// `SwifterKit<Name>RuntimeService`.
  public var serviceClass: String {
    guard let personalityName else { return Self.runtimeServiceClass }
    return DriverExtensionPersonalityRenaming.renamed(
      Self.runtimeServiceClass,
      personality: personalityName
    )
  }

  /// Creates driver metadata consumed by the extension generator.
  public init(
    bundleIdentifier: String,
    providerClass: String,
    matchingProperties: [String: DriverProperty] = [:],
    capabilities: RuntimeCapabilities,
    hidDevice: HIDDeviceConfiguration? = nil,
    hidEventService: HIDEventServiceConfiguration? = nil,
    usbHIDDevice: USBHIDDeviceConfiguration? = nil,
    hidDeviceFactory: HIDDeviceFactoryConfiguration? = nil,
    usbDevice: USBDeviceConfiguration? = nil,
    pciDevice: PCIDeviceConfiguration? = nil,
    serialPort: SerialPortConfiguration? = nil,
    usbSerialPort: USBSerialPortConfiguration? = nil,
    blockStorageDevice: BlockStorageDeviceConfiguration? = nil,
    midiDevice: MIDIDeviceConfiguration? = nil,
    ethernetDevice: EthernetDeviceConfiguration? = nil,
    audioDevice: AudioDeviceConfiguration? = nil,
    videoDevice: VideoDeviceConfiguration? = nil,
    scsiController: SCSIControllerConfiguration? = nil,
    scsiPeripheral: SCSIPeripheralConfiguration? = nil,
    interruptSources: [InterruptSourceConfiguration] = [],
    memoryPool: MemoryPoolConfiguration? = nil,
    reporting: ReportingConfiguration? = nil,
    fastPath: FastPathConfiguration? = nil
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.providerClass = providerClass
    self.matchingProperties = matchingProperties
    self.capabilities = capabilities
    self.hidDevice = hidDevice
    self.hidEventService = hidEventService
    self.usbHIDDevice = usbHIDDevice
    self.hidDeviceFactory = hidDeviceFactory
    self.usbDevice = usbDevice
    self.pciDevice = pciDevice
    self.serialPort = serialPort
    self.usbSerialPort = usbSerialPort
    self.blockStorageDevice = blockStorageDevice
    self.midiDevice = midiDevice
    self.ethernetDevice = ethernetDevice
    self.audioDevice = audioDevice
    self.videoDevice = videoDevice
    self.scsiController = scsiController
    self.scsiPeripheral = scsiPeripheral
    self.interruptSources = interruptSources
    self.memoryPool = memoryPool
    self.reporting = reporting
    self.fastPath = fastPath
  }

  /// The criteria used to discover this generated extension.
  public var serviceMatch: DriverServiceMatch {
    DriverServiceMatch(
      serviceClass: "IOService",
      registryProperties: [
        "CFBundleIdentifier": .string(bundleIdentifier), "IOUserClass": .string(serviceClass),
      ]
    )
  }
}
