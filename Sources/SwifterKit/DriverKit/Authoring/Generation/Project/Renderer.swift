import Foundation

enum DriverExtensionProject {
  private static let frameworksByCapability: [(RuntimeCapabilities, String)] = [
    (.hid, "HIDDriverKit.framework"), (.usb, "USBDriverKit.framework"),
    (.pci, "PCIDriverKit.framework"), (.serial, "SerialDriverKit.framework"),
    (.blockStorage, "BlockStorageDeviceDriverKit.framework"), (.midi, "MIDIDriverKit.framework"),
    (.networking, "NetworkingDriverKit.framework"), (.audio, "AudioDriverKit.framework"),
    (.video, "VideoDriverKit.framework"),
  ]

  private static let scsiControllerFramework = "SCSIControllerDriverKit.framework"
  private static let scsiPeripheralFramework = "SCSIPeripheralsDriverKit.framework"

  static func frameworkNames(for configuration: DriverConfiguration) -> Set<String> {
    var names = Set(
      frameworksByCapability.compactMap { capability, framework in
        configuration.capabilities.contains(capability) ? framework : nil
      }
    )
    if configuration.scsiController != nil { names.insert(scsiControllerFramework) }
    if configuration.scsiPeripheral != nil { names.insert(scsiPeripheralFramework) }
    return names
  }

  static func render(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions,
    template: String
  ) throws -> String {
    let allFrameworks = Set(frameworksByCapability.map { $0.1 }).union([
      scsiControllerFramework, scsiPeripheralFramework,
    ])
    var occurrenceCounts: [String: Int] = [:]

    for line in template.split(separator: "\n", omittingEmptySubsequences: false) {
      for framework in frameworkNames(in: line) { occurrenceCounts[framework, default: 0] += 1 }
    }

    guard Set(occurrenceCounts.keys) == allFrameworks,
      occurrenceCounts.values.allSatisfy({ $0 == 3 })
    else { throw DriverExtensionGenerationError.templateInvariant("project.pbxproj frameworks") }

    let selectedFrameworks = frameworkNames(for: configuration)
    let renderedLines = template.split(separator: "\n", omittingEmptySubsequences: false).filter {
      line in
      !frameworkNames(in: line).contains { framework in !selectedFrameworks.contains(framework) }
    }
    var rendered = renderedLines.joined(separator: "\n")
    rendered = try replacing(
      "com.swifterkit.Runtime",
      with: configuration.bundleIdentifier,
      in: rendered
    )
    rendered = try replacing(
      "DRIVERKIT_DEPLOYMENT_TARGET = 19.0;",
      with: "DRIVERKIT_DEPLOYMENT_TARGET = \(options.deploymentTarget);",
      in: rendered
    )
    rendered = try replacing(
      "DEVELOPMENT_TEAM = 9PQP6CDMQT;",
      with: "DEVELOPMENT_TEAM = \"\";",
      in: rendered
    )
    return rendered
  }

  private static func replacing(_ source: String, with replacement: String, in value: String) throws
    -> String
  {
    guard value.contains(source) else {
      throw DriverExtensionGenerationError.templateInvariant("project.pbxproj")
    }
    return value.replacingOccurrences(of: source, with: replacement)
  }

  private static func frameworkNames(in line: Substring) -> Set<String> {
    Set(
      line.split { character in !(character.isLetter || character.isNumber || character == ".") }
        .lazy.map(String.init).filter { $0.hasSuffix("DriverKit.framework") }
    )
  }
}
