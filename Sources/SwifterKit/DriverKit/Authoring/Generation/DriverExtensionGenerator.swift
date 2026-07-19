import Foundation

/// Version and deployment settings for a generated DriverKit extension.
public struct DriverExtensionGenerationOptions: Sendable, Hashable {
  /// The extension's user-visible version.
  public let shortVersion: String
  /// The monotonically increasing bundle version.
  public let buildVersion: String
  /// The minimum DriverKit version.
  public let deploymentTarget: String

  /// Creates extension generation settings.
  public init(
    shortVersion: String = "0.1.0",
    buildVersion: String = "1",
    deploymentTarget: String = "19.0"
  ) {
    self.shortVersion = shortVersion
    self.buildVersion = buildVersion
    self.deploymentTarget = deploymentTarget
  }
}

/// Generates a buildable internal dext project from Swift driver metadata.
public enum DriverExtensionGenerator {
  /// Generates a new extension directory without overwriting existing data.
  public static func generate(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions = DriverExtensionGenerationOptions(),
    at outputDirectory: URL
  ) throws {
    try validate(configuration: configuration, options: options)

    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: outputDirectory.path) else {
      throw DriverExtensionGenerationError.destinationExists(outputDirectory.path)
    }
    guard let template = Bundle.module.url(forResource: "DriverKitExtension", withExtension: nil)
    else { throw DriverExtensionGenerationError.templateUnavailable }

    let parent = outputDirectory.deletingLastPathComponent()
    let staging = parent.appendingPathComponent(
      ".swifterkit-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? fileManager.removeItem(at: staging) }

    do {
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      try fileManager.copyItem(at: template, to: staging)
      try writeInfo(
        configuration: configuration,
        options: options,
        to: staging.appendingPathComponent("Info.plist")
      )
      try writeEntitlements(
        configuration: configuration,
        to: staging.appendingPathComponent("SwifterKitRuntime.entitlements")
      )
      try configureRuntime(configuration: configuration, options: options, in: staging)
      try fileManager.moveItem(at: staging, to: outputDirectory)
    } catch let error as DriverExtensionGenerationError { throw error } catch {
      throw DriverExtensionGenerationError.fileSystem(error.localizedDescription)
    }
  }

  private static func validate(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions
  ) throws {
    let bundleParts = configuration.bundleIdentifier.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    let validBundle =
      bundleParts.count >= 2
      && bundleParts.allSatisfy { part in
        !part.isEmpty
          && part.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
          }
      }
    guard validBundle else {
      throw DriverExtensionGenerationError.invalidBundleIdentifier(configuration.bundleIdentifier)
    }
    guard !configuration.providerClass.isEmpty else {
      throw DriverExtensionGenerationError.invalidProviderClass
    }
    guard !options.shortVersion.isEmpty, !options.buildVersion.isEmpty else {
      throw DriverExtensionGenerationError.invalidVersion
    }
    guard let deploymentVersion = DriverKitDeploymentVersion(options.deploymentTarget),
      deploymentVersion >= .v19
    else { throw DriverExtensionGenerationError.invalidDeploymentTarget }

    let supported = RuntimeCapabilities.hid.union(.usb).union(.pci).union(.serial).union(
      .blockStorage
    ).union(.midi).union(.networking).union(.audio).union(.scsi).union(.video).union(.interrupts)
      .union(.memory)
    let unsupported = configuration.capabilities.subtracting(supported)
    guard unsupported.isEmpty else {
      throw DriverExtensionGenerationError.unsupportedCapabilities(unsupported)
    }
    if configuration.capabilities.contains(.hid) {
      guard let hid = configuration.hidDevice, isValid(hid: hid) else {
        throw DriverExtensionGenerationError.invalidHIDConfiguration
      }
    } else if configuration.hidDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.hid)
    }
    if configuration.capabilities.contains(.usb) {
      guard let usb = configuration.usbDevice, usb.vendorID != 0,
        Set(usb.productIDs).count == usb.productIDs.count,
        usb.productIDMask == nil || usb.productIDs.count == 1,
        configuration.providerClass == "IOUSBHostInterface"
      else { throw DriverExtensionGenerationError.invalidUSBConfiguration }
    } else if configuration.usbDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.usb)
    }
    if configuration.capabilities.contains(.pci) {
      guard let pci = configuration.pciDevice, isValid(pci: pci),
        configuration.providerClass == "IOPCIDevice", !configuration.capabilities.contains(.usb)
      else { throw DriverExtensionGenerationError.invalidPCIConfiguration }
    } else if configuration.pciDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.pci)
    }
    if configuration.capabilities.contains(.serial) {
      guard let serial = configuration.serialPort, isValid(serial: serial),
        !configuration.capabilities.contains(.hid)
      else { throw DriverExtensionGenerationError.invalidSerialConfiguration }
    } else if configuration.serialPort != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.serial)
    }
    if configuration.capabilities.contains(.blockStorage) {
      guard let block = configuration.blockStorageDevice, isValid(blockStorage: block),
        !configuration.capabilities.contains(.hid), !configuration.capabilities.contains(.serial)
      else { throw DriverExtensionGenerationError.invalidBlockStorageConfiguration }
    } else if configuration.blockStorageDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.blockStorage)
    }
    if configuration.capabilities.contains(.midi) {
      guard let midi = configuration.midiDevice, isValid(midi: midi),
        !configuration.capabilities.contains(.hid), !configuration.capabilities.contains(.serial),
        !configuration.capabilities.contains(.blockStorage)
      else { throw DriverExtensionGenerationError.invalidMIDIConfiguration }
    } else if configuration.midiDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.midi)
    }
    if configuration.capabilities.contains(.networking) {
      guard let ethernet = configuration.ethernetDevice, isValid(ethernet: ethernet),
        deploymentVersion >= .v22, !configuration.capabilities.contains(.hid),
        !configuration.capabilities.contains(.serial),
        !configuration.capabilities.contains(.blockStorage),
        !configuration.capabilities.contains(.midi)
      else { throw DriverExtensionGenerationError.invalidEthernetConfiguration }
    } else if configuration.ethernetDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.networking)
    }
    if configuration.capabilities.contains(.audio) {
      guard let audio = configuration.audioDevice, isValid(audio: audio), deploymentVersion >= .v21,
        !configuration.capabilities.contains(.hid), !configuration.capabilities.contains(.serial),
        !configuration.capabilities.contains(.blockStorage),
        !configuration.capabilities.contains(.midi),
        !configuration.capabilities.contains(.networking)
      else { throw DriverExtensionGenerationError.invalidAudioConfiguration }
    } else if configuration.audioDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.audio)
    }
    if configuration.capabilities.contains(.video) {
      guard let video = configuration.videoDevice, isValid(video: video), deploymentVersion >= .v27,
        !configuration.capabilities.contains(.hid), !configuration.capabilities.contains(.serial),
        !configuration.capabilities.contains(.blockStorage),
        !configuration.capabilities.contains(.midi),
        !configuration.capabilities.contains(.networking),
        !configuration.capabilities.contains(.audio), !configuration.capabilities.contains(.scsi)
      else { throw DriverExtensionGenerationError.invalidVideoConfiguration }
    } else if configuration.videoDevice != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.video)
    }
    if configuration.capabilities.contains(.scsi) {
      let hasController = configuration.scsiController != nil
      let hasPeripheral = configuration.scsiPeripheral != nil
      guard hasController != hasPeripheral, !configuration.capabilities.contains(.hid),
        !configuration.capabilities.contains(.serial),
        !configuration.capabilities.contains(.blockStorage),
        !configuration.capabilities.contains(.midi),
        !configuration.capabilities.contains(.networking),
        !configuration.capabilities.contains(.audio), !configuration.capabilities.contains(.video)
      else { throw DriverExtensionGenerationError.invalidSCSIConfiguration }
      if let controller = configuration.scsiController {
        guard deploymentVersion >= .v20Point4, isValid(scsi: controller) else {
          throw DriverExtensionGenerationError.invalidSCSIConfiguration
        }
      } else if deploymentVersion < .v22 {
        throw DriverExtensionGenerationError.invalidSCSIConfiguration
      }
    } else if configuration.scsiController != nil || configuration.scsiPeripheral != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.scsi)
    }
    let interruptIndices = configuration.interruptSources.map(\.index)
    if configuration.capabilities.contains(.interrupts) {
      guard !interruptIndices.isEmpty, interruptIndices.allSatisfy({ $0 <= UInt16.max }),
        Set(interruptIndices).count == interruptIndices.count, interruptIndices.count <= 32
      else { throw DriverExtensionGenerationError.invalidInterruptConfiguration }
    } else if !interruptIndices.isEmpty {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.interrupts)
    }
    if configuration.capabilities.contains(.memory) {
      guard let memory = configuration.memoryPool, memory.maximumBuffers > 0,
        memory.maximumBuffers <= 64, memory.maximumBufferSize > 0,
        memory.maximumTotalSize >= memory.maximumBufferSize
      else { throw DriverExtensionGenerationError.invalidMemoryConfiguration }
    } else if configuration.memoryPool != nil {
      throw DriverExtensionGenerationError.capabilityConfigurationMismatch(.memory)
    }
    if configuration.capabilities.contains(.blockStorage), deploymentVersion < .v21 {
      throw DriverExtensionGenerationError.invalidBlockStorageConfiguration
    }
    if configuration.capabilities.contains(.midi), deploymentVersion < .v24 {
      throw DriverExtensionGenerationError.invalidMIDIConfiguration
    }

    var reservedKeys: Set<String> = [
      "CFBundleIdentifier", "CFBundleIdentifierKernel", "IOClass", "IOMatchCategory",
      "IOProviderClass", "IOTTYBaseName", "IOTTYSuffix", "IOUserClass", "IOUserServerName",
      "UserClientProperties",
    ]
    if let usb = configuration.usbDevice { reservedKeys.formUnion(usb.matchingProperties.keys) }
    if let pci = configuration.pciDevice { reservedKeys.formUnion(pci.matchingProperties.keys) }
    if let reserved = configuration.matchingProperties.keys.first(where: reservedKeys.contains) {
      throw DriverExtensionGenerationError.reservedMatchingProperty(reserved)
    }
  }

  private static func isValid(scsi value: SCSIControllerConfiguration) -> Bool {
    let validFeatureMask = SCSIParallelFeatures(
      rawValue: SCSIParallelFeatures.informationUnitTransfers.rawValue * 2 - 1
    )
    return (1...256).contains(value.maximumTaskCount) && value.maximumTransferSize > 0
      && value.minimumSegmentAlignment > 0
      && value.minimumSegmentAlignment & (value.minimumSegmentAlignment - 1) == 0
      && (1...64).contains(value.addressBitCount)
      && value.dmaSegmentType.rawValue <= SCSIDMASegmentType.littleEndian64.rawValue
      && value.supportedFeatures.subtracting(validFeatureMask).isEmpty
      && (value.taskManagementResponse == .functionComplete
        || value.taskManagementResponse == .functionRejected)
  }

  private static func isValid(ethernet value: EthernetDeviceConfiguration) -> Bool {
    let address = value.hardwareAddress.bytes
    return address.count == 6 && address.contains { $0 != 0 } && address[0] & 1 == 0
      && (576...16_000).contains(value.maximumTransferUnit)
      && value.packetBufferSize >= value.maximumTransferUnit + 64
      && value.packetBufferSize <= 65_480 && (8...1_024).contains(value.packetCount)
      && (1...1_024).contains(value.queueCapacity) && value.queueCapacity <= value.packetCount
      && !value.media.isEmpty && value.media.count <= 32
      && Set(value.media).count == value.media.count && value.media.contains(value.initialMedia)
  }

  private static func isValid(midi value: MIDIDeviceConfiguration) -> Bool {
    let strings = [
      value.driverName, value.deviceIdentifier, value.modelIdentifier, value.manufacturerIdentifier,
      value.entityName,
    ]
    return value.sourceCount <= 32 && value.destinationCount <= 32
      && value.sourceCount + value.destinationCount > 0
      && strings.allSatisfy { !$0.isEmpty && !$0.contains("\0") && $0.utf8.count < 256 }
  }

  private static func isValid(blockStorage value: BlockStorageDeviceConfiguration) -> Bool {
    let strings = [value.vendor, value.product, value.revision, value.additionalInfo]
    return value.blockCount > 0 && value.blockSize > 0
      && value.blockSize & (value.blockSize - 1) == 0 && value.maximumIOSize >= value.blockSize
      && value.maximumIOSize.isMultiple(of: value.blockSize)
      && (1...64).contains(value.maximumOutstandingIOCount)
      && value.maximumUnmapRegionCount <= 4_000
      && value.supportsUnmap == (value.maximumUnmapRegionCount > 0)
      && value.minimumSegmentAlignment > 0
      && value.minimumSegmentAlignment & (value.minimumSegmentAlignment - 1) == 0
      && (1...64).contains(value.addressBitCount)
      && strings.allSatisfy { $0.utf8.count < 256 && !$0.contains("\0") } && !value.vendor.isEmpty
      && !value.product.isEmpty && !value.revision.isEmpty
  }

  private static func isValid(serial: SerialPortConfiguration) -> Bool {
    let strings = [serial.baseName, serial.suffix]
    return strings.allSatisfy { !$0.isEmpty && !$0.contains("\0") }
  }

  private static func isValid(pci: PCIDeviceConfiguration) -> Bool {
    !pci.matches.isEmpty
      && pci.matches.values.allSatisfy { expression in
        !expression.isEmpty
          && expression.allSatisfy {
            $0.isHexDigit || $0 == "x" || $0 == "X" || $0 == "&" || $0 == " "
          }
      }
  }

  private static func isValid(hid: HIDDeviceConfiguration) -> Bool {
    let strings = [hid.transport, hid.manufacturer, hid.product, hid.serialNumber]
    return !hid.reportDescriptor.isEmpty && hid.reportDescriptor.count <= 65_488
      && hid.acceptedHostReportTypes.subtracting(.all).isEmpty
      && strings.allSatisfy { !$0.isEmpty && !$0.contains("\0") }
  }

  private static func writeInfo(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions,
    to destination: URL
  ) throws {
    let isHID = configuration.capabilities.contains(.hid)
    var personality: [String: Any] = [
      "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
      "CFBundleIdentifierKernel": configuration.capabilities.contains(.blockStorage)
        ? "com.apple.iokit.IOStorageFamily" : "com.apple.kpi.iokit",
      "IOClass": isHID ? "AppleUserHIDDevice" : "IOUserService",
      "IOMatchCategory": "$(PRODUCT_BUNDLE_IDENTIFIER)",
      "IOProviderClass": configuration.providerClass,
      "IOUserClass": DriverConfiguration.runtimeServiceClass,
      "IOUserServerName": "$(PRODUCT_BUNDLE_IDENTIFIER)",
      "UserClientProperties": [
        "IOClass": "IOUserUserClient", "IOUserClass": "SwifterKitRuntimeUserClient",
      ],
    ]
    if configuration.capabilities.contains(.midi) {
      personality["IOUserMIDIDriverUserClientProperties"] = [
        "IOClass": "IOUserUserClient", "IOUserClass": "IOUserMIDIDriverUserClient",
      ]
    }
    if configuration.capabilities.contains(.audio) {
      personality["IOUserAudioDriverUserClientProperties"] = [
        "IOClass": "IOUserUserClient", "IOUserClass": "IOUserAudioDriverUserClient",
      ]
    }
    if configuration.capabilities.contains(.video) {
      personality["IOUserVideoDriverUserClientProperties"] = [
        "IOClass": "IOUserUserClient", "IOUserClass": "IOUserVideoDriverUserClient",
      ]
    }
    if let hid = configuration.hidDevice {
      personality["PrimaryUsagePage"] = hid.primaryUsagePage
      personality["PrimaryUsage"] = hid.primaryUsage
    }
    if let usb = configuration.usbDevice {
      for (key, value) in usb.matchingProperties { personality[key] = value.foundationValue }
    }
    if let pci = configuration.pciDevice {
      for (key, value) in pci.matchingProperties { personality[key] = value.foundationValue }
    }
    if let serial = configuration.serialPort {
      personality["IOTTYBaseName"] = serial.baseName
      personality["IOTTYSuffix"] = serial.suffix
    }
    if let peripheral = configuration.scsiPeripheral {
      for (key, value) in peripheral.transferConstraints.registryProperties {
        personality[key] = value
      }
    }
    if configuration.capabilities.contains(.networking) {
      personality["CFBundleIdentifierKernel"] = "com.apple.iokit.IOSkywalkFamily"
    }
    for (key, value) in configuration.matchingProperties {
      personality[key] = value.foundationValue
    }

    let info: [String: Any] = [
      "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
      "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
      "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
      "CFBundleShortVersionString": options.shortVersion, "CFBundleVersion": options.buildVersion,
      "IOKitPersonalities": ["SwiftDriver": personality],
      "OSBundleUsageDescription": "Hosts DriverKit operations for Swift driver behavior.",
    ]
    try writePropertyList(info, to: destination)
  }

  private static func writeEntitlements(configuration: DriverConfiguration, to destination: URL)
    throws
  {
    var entitlements: [String: Any] = ["com.apple.developer.driverkit": true]
    if configuration.capabilities.contains(.hid) {
      entitlements["com.apple.developer.driverkit.family.hid.device"] = true
      entitlements["com.apple.developer.driverkit.transport.hid"] = true
      entitlements["com.apple.developer.driverkit.family.hid.eventservice"] = true
    }
    if let usb = configuration.usbDevice {
      entitlements["com.apple.developer.driverkit.transport.usb"] = [
        usb.matchingProperties.mapValues(\.foundationValue)
      ]
    }
    if configuration.capabilities.contains(.serial) {
      entitlements["com.apple.developer.driverkit.family.serial"] = true
    }
    if configuration.capabilities.contains(.blockStorage) {
      entitlements["com.apple.developer.driverkit.family.block-storage-device"] = true
    }
    if configuration.capabilities.contains(.midi) {
      entitlements["com.apple.developer.driverkit.family.midi"] = true
    }
    if configuration.capabilities.contains(.networking) {
      entitlements["com.apple.developer.driverkit.family.networking"] = true
    }
    if configuration.capabilities.contains(.audio) {
      entitlements["com.apple.developer.driverkit.family.audio"] = true
      entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] = true
    }
    if configuration.capabilities.contains(.video) {
      entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] = true
    }
    if configuration.scsiController != nil {
      entitlements["com.apple.developer.driverkit.family.scsicontroller"] = true
    }
    if let pci = configuration.pciDevice {
      entitlements["com.apple.developer.driverkit.transport.pci"] = [
        pci.matchingProperties.mapValues(\.foundationValue)
      ]
    }
    try writePropertyList(entitlements, to: destination)
  }

  private static func writePropertyList(_ value: Any, to destination: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: destination, options: .atomic)
  }

  private static func configureRuntime(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions,
    in directory: URL
  ) throws {
    let sources = directory.appendingPathComponent("Sources")
    let header = sources.appendingPathComponent("SwifterKitRuntimeProtocol.h")
    try replace(
      in: header,
      source: "static constexpr uint64_t kSwifterKitRuntimeCapabilities = 0;",
      with: "static constexpr uint64_t kSwifterKitRuntimeCapabilities = "
        + "\(configuration.capabilities.rawValue);"
    )

    try runtimeConfigurationHeader(configuration).write(
      to: sources.appendingPathComponent("SwifterKitRuntimeConfiguration.h"),
      atomically: true,
      encoding: .utf8
    )
    try serviceInterface(configuration).write(
      to: sources.appendingPathComponent("SwifterKitRuntimeService.iig"),
      atomically: true,
      encoding: .utf8
    )

    let project = directory.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj")
    let template = try String(contentsOf: project, encoding: .utf8)
    try DriverExtensionProject.render(
      configuration: configuration,
      options: options,
      template: template
    ).write(to: project, atomically: true, encoding: .utf8)
  }

  private static func replace(in file: URL, source: String, with replacement: String) throws {
    let contents = try String(contentsOf: file, encoding: .utf8)
    guard contents.contains(source) else {
      throw DriverExtensionGenerationError.templateInvariant(file.lastPathComponent)
    }
    try contents.replacingOccurrences(of: source, with: replacement).write(
      to: file,
      atomically: true,
      encoding: .utf8
    )
  }
}
