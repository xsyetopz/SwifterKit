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
  private static let usbSerialFramework = "USBSerialDriverKit.framework"

  static func frameworkNames(for configuration: DriverConfiguration) -> Set<String> {
    var names = Set(
      frameworksByCapability.compactMap { capability, framework in
        configuration.capabilities.contains(capability) ? framework : nil
      }
    )
    if configuration.scsiController != nil { names.insert(scsiControllerFramework) }
    if configuration.scsiPeripheral != nil { names.insert(scsiPeripheralFramework) }
    if configuration.usbSerialPort != nil { names.insert(usbSerialFramework) }
    return names
  }

  static func render(
    configuration: DriverConfiguration,
    options: DriverExtensionGenerationOptions,
    template: String
  ) throws -> String {
    try render(
      frameworks: frameworkNames(for: configuration),
      bundleIdentifier: configuration.bundleIdentifier,
      personalities: [],
      options: options,
      template: template
    )
  }

  /// Renders the project for an extension that links `frameworks`.
  ///
  /// When `personalities` is not empty, each runtime source record is replaced by one record per
  /// personality that names the personality's renamed file and uses its own object identifiers.
  static func render(
    frameworks selectedFrameworks: Set<String>,
    bundleIdentifier: String,
    personalities: [String],
    options: DriverExtensionGenerationOptions,
    template: String
  ) throws -> String {
    let allFrameworks = Set(frameworksByCapability.map { $0.1 }).union([
      scsiControllerFramework, scsiPeripheralFramework, usbSerialFramework,
    ])
    var occurrenceCounts: [String: Int] = [:]

    for line in template.split(separator: "\n", omittingEmptySubsequences: false) {
      for framework in frameworkNames(in: line) { occurrenceCounts[framework, default: 0] += 1 }
    }

    guard Set(occurrenceCounts.keys) == allFrameworks,
      occurrenceCounts.values.allSatisfy({ $0 == 3 })
    else { throw DriverExtensionGenerationError.templateInvariant("project.pbxproj frameworks") }

    let renderedLines = template.split(separator: "\n", omittingEmptySubsequences: false).filter {
      line in
      !frameworkNames(in: line).contains { framework in !selectedFrameworks.contains(framework) }
    }
    var rendered = try renderedLines.flatMap { line in
      try personalityLines(for: line, personalities: personalities)
    }.joined(separator: "\n")
    rendered = try replacing("com.swifterkit.Runtime", with: bundleIdentifier, in: rendered)
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

  private static func replacing(
    _ source: String,
    with replacement: String,
    in value: String
  ) throws -> String {
    guard value.contains(source) else {
      throw DriverExtensionGenerationError.templateInvariant("project.pbxproj")
    }
    return value.replacingOccurrences(of: source, with: replacement)
  }

  /// Object identifiers in the template share this segment, which the clones replace.
  private static let identifierSegment = "2AAAAAAA"

  /// `line` once per personality when it records a runtime source file, otherwise `line`.
  private static func personalityLines(
    for line: Substring,
    personalities: [String]
  ) throws -> [String] {
    guard !personalities.isEmpty, recordsRuntimeSource(line) else { return [String(line)] }
    guard line.contains(identifierSegment) else {
      throw DriverExtensionGenerationError.templateInvariant("project.pbxproj source identifiers")
    }
    return personalities.enumerated().map { index, personality in
      let tag = String(index + 1, radix: 16, uppercase: true)
      let segment = "F" + String(repeating: "0", count: max(0, 7 - tag.count)) + tag
      return DriverExtensionPersonalityRenaming.renamed(String(line), personality: personality)
        .replacingOccurrences(of: identifierSegment, with: segment)
    }
  }

  private static func recordsRuntimeSource(_ line: Substring) -> Bool {
    line.split { character in !(character.isLetter || character.isNumber || character == ".") }
      .contains { token in
        token.hasPrefix("SwifterKit") && [".cpp", ".iig", ".h"].contains { token.hasSuffix($0) }
      }
  }

  private static func frameworkNames(in line: Substring) -> Set<String> {
    Set(
      line.split { character in !(character.isLetter || character.isNumber || character == ".") }
        .lazy.map(String.init).filter { $0.hasSuffix("DriverKit.framework") }
    )
  }
}
