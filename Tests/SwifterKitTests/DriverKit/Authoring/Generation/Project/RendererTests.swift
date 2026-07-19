import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverExtensionProjectTests {
  @Test func selectsExactFrameworksForCapabilities() {
    let cases: [(RuntimeCapabilities, Set<String>)] = [
      (.hid, ["HIDDriverKit.framework"]), (.usb, ["USBDriverKit.framework"]),
      (.pci, ["PCIDriverKit.framework"]), (.serial, ["SerialDriverKit.framework"]),
      (.blockStorage, ["BlockStorageDeviceDriverKit.framework"]),
      (.midi, ["MIDIDriverKit.framework"]), (.networking, ["NetworkingDriverKit.framework"]),
      (.audio, ["AudioDriverKit.framework"]), (.video, ["VideoDriverKit.framework"]),
      (.interrupts, []), (.memory, []), ([.interrupts, .memory], []),
      (
        [.hid, .usb, .pci, .serial, .blockStorage, .midi, .networking, .audio, .video],
        [
          "HIDDriverKit.framework", "USBDriverKit.framework", "PCIDriverKit.framework",
          "SerialDriverKit.framework", "BlockStorageDeviceDriverKit.framework",
          "MIDIDriverKit.framework", "NetworkingDriverKit.framework", "AudioDriverKit.framework",
          "VideoDriverKit.framework",
        ]
      ),
    ]

    for (capabilities, expected) in cases {
      #expect(
        DriverExtensionProject.frameworkNames(for: configuration(capabilities: capabilities))
          == expected
      )
    }
  }

  @Test func selectsEachSCSIFrameworkFromItsConfiguration() {
    let controller = configuration(
      capabilities: .scsi,
      scsiController: SCSIControllerConfiguration(
        initiatorIdentifier: 7,
        highestTargetIdentifier: 15
      )
    )
    let peripheral = configuration(
      capabilities: .scsi,
      scsiPeripheral: SCSIPeripheralConfiguration(deviceType: .blockCommands)
    )

    #expect(
      DriverExtensionProject.frameworkNames(for: controller) == [
        "SCSIControllerDriverKit.framework"
      ]
    )
    #expect(
      DriverExtensionProject.frameworkNames(for: peripheral) == [
        "SCSIPeripheralsDriverKit.framework"
      ]
    )
  }

  @Test func rendersCombinedFrameworkUnion() throws {
    let configuration = configuration(
      capabilities: [.hid, .usb, .interrupts, .memory],
      scsiController: SCSIControllerConfiguration(
        initiatorIdentifier: 7,
        highestTargetIdentifier: 15
      )
    )
    let rendered = try DriverExtensionProject.render(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(),
      template: projectTemplate()
    )
    let frameworkLines = rendered.split(separator: "\n").filter {
      $0.contains("DriverKit.framework")
    }

    #expect(frameworkLines.count == 9)
    for framework in [
      "HIDDriverKit.framework", "USBDriverKit.framework", "SCSIControllerDriverKit.framework",
    ] { #expect(frameworkLines.filter { $0.contains(framework) }.count == 3) }
    for framework in [
      "PCIDriverKit.framework", "SerialDriverKit.framework",
      "BlockStorageDeviceDriverKit.framework", "MIDIDriverKit.framework",
      "NetworkingDriverKit.framework", "AudioDriverKit.framework", "VideoDriverKit.framework",
      "SCSIPeripheralsDriverKit.framework",
    ] { #expect(!rendered.contains(framework)) }
  }

  @Test func generatedHIDProjectContainsNoUnrelatedFamilyFrameworks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("HIDDriver", isDirectory: true)

    try DriverExtensionGenerator.generate(configuration: hidConfiguration(), at: output)

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    let frameworkLines = project.split(separator: "\n").filter {
      $0.contains("DriverKit.framework")
    }
    #expect(frameworkLines.count == 3)
    #expect(frameworkLines.allSatisfy { $0.contains("HIDDriverKit.framework") })

    let derivedData = root.appendingPathComponent("DerivedData", isDirectory: true)
    let build = try run(
      executable: "/usr/bin/xcrun",
      arguments: [
        "xcodebuild", "-quiet", "-project", "SwifterKitRuntime.xcodeproj", "-scheme",
        "SwifterKitRuntime", "-configuration", "Debug", "-sdk", "driverkit", "-derivedDataPath",
        derivedData.path, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        "DEVELOPMENT_TEAM=", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO",
        "GCC_TREAT_WARNINGS_AS_ERRORS=YES", "build",
      ],
      currentDirectory: output
    )
    #expect(build.status == 0, Comment(rawValue: build.output))

    let binary = derivedData.appendingPathComponent(
      "Build/Products/Debug-driverkit/SwifterKitRuntime.dext/SwifterKitRuntime"
    )
    let linkedLibraries = try run(executable: "/usr/bin/otool", arguments: ["-L", binary.path])
    #expect(linkedLibraries.status == 0, Comment(rawValue: linkedLibraries.output))
    #expect(linkedLibraries.output.contains("HIDDriverKit.framework/HIDDriverKit"))
    for unrelated in [
      "USBDriverKit", "PCIDriverKit", "SerialDriverKit", "BlockStorageDeviceDriverKit",
      "MIDIDriverKit", "NetworkingDriverKit", "AudioDriverKit", "VideoDriverKit",
      "SCSIControllerDriverKit", "SCSIPeripheralsDriverKit",
    ] { #expect(!linkedLibraries.output.contains("\(unrelated).framework")) }
  }

  @Test func rejectsUnexpectedOrIncompleteTemplateFrameworkRecords() {
    let configuration = configuration(capabilities: .hid)
    let validTemplate = projectTemplate()
    let incomplete = validTemplate.replacingOccurrences(
      of: frameworkLine("HIDDriverKit.framework", kind: .buildFile),
      with: ""
    )
    let unexpected =
      validTemplate + frameworkLine("UnknownDriverKit.framework", kind: .fileReference)

    #expect(throws: DriverExtensionGenerationError.self) {
      try DriverExtensionProject.render(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(),
        template: incomplete
      )
    }
    #expect(throws: DriverExtensionGenerationError.self) {
      try DriverExtensionProject.render(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(),
        template: unexpected
      )
    }
  }

  private enum FrameworkLineKind {
    case buildFile
    case fileReference
    case buildPhase
  }

  private func projectTemplate() -> String {
    let frameworks = [
      "HIDDriverKit.framework", "USBDriverKit.framework", "PCIDriverKit.framework",
      "SerialDriverKit.framework", "BlockStorageDeviceDriverKit.framework",
      "MIDIDriverKit.framework", "NetworkingDriverKit.framework", "AudioDriverKit.framework",
      "VideoDriverKit.framework", "SCSIControllerDriverKit.framework",
      "SCSIPeripheralsDriverKit.framework",
    ]
    let records = frameworks.flatMap { framework in
      [
        frameworkLine(framework, kind: .buildFile), frameworkLine(framework, kind: .fileReference),
        frameworkLine(framework, kind: .buildPhase),
      ]
    }
    return
      ([
        "com.swifterkit.Runtime", "DRIVERKIT_DEPLOYMENT_TARGET = 19.0;",
        "DEVELOPMENT_TEAM = 9PQP6CDMQT;",
      ] + records).joined(separator: "\n")
  }

  private func frameworkLine(_ framework: String, kind: FrameworkLineKind) -> String {
    switch kind {
    case .buildFile: "build \(framework) in Frameworks"
    case .fileReference: "reference \(framework)"
    case .buildPhase: "phase \(framework) in Frameworks"
    }
  }

  private func configuration(
    capabilities: RuntimeCapabilities,
    scsiController: SCSIControllerConfiguration? = nil,
    scsiPeripheral: SCSIPeripheralConfiguration? = nil
  ) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.framework-selection",
      providerClass: "IOService",
      capabilities: capabilities,
      scsiController: scsiController,
      scsiPeripheral: scsiPeripheral
    )
  }

  private func hidConfiguration() -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.hid-framework-selection",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .hid,
      hidDevice: HIDDeviceConfiguration(
        reportDescriptor: [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0xC0],
        vendorID: 0x1234,
        productID: 0x5678,
        manufacturer: "Example",
        product: "Framework selection",
        serialNumber: "framework-selection-1",
        primaryUsagePage: 1,
        primaryUsage: 5
      )
    )
  }

  private func run(executable: String, arguments: [String], currentDirectory: URL? = nil) throws
    -> (status: Int32, output: String)
  {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return (
      process.terminationStatus,
      String(bytes: data, encoding: .utf8) ?? "process emitted non-UTF-8 output"
    )
  }
}
