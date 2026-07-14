import Foundation
import Testing

@testable import SwifterKit

@Suite struct MIDIGeneratorTests {
  @Test func generatesMIDIRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("MIDIDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.midi-driver",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .midi,
      midiDevice: deviceConfiguration
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "24.0"),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    let midiClient = try #require(
      personality["IOUserMIDIDriverUserClientProperties"] as? [String: Any]
    )
    #expect(midiClient["IOUserClass"] as? String == "IOUserMIDIDriverUserClient")

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit.family.midi"] as? Bool == true)

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("SWIFTERKIT_ENABLE_MIDI 1"))
    #expect(header.contains("kSwifterKitMIDISourceCount = 2"))
    #expect(header.contains("kSwifterKitMIDIDestinationCount =\n    3"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserMIDIDriver"))
    #expect(service.contains("MIDICommand"))
    #expect(service.contains("MIDIReceived"))

    let midiRuntime = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeMIDI.cpp"),
      encoding: .utf8
    )
    #expect(midiRuntime.contains("result = AddObject(device.get())"))
    #expect(!midiRuntime.contains("AddObject(entity.get())"))
    #expect(midiRuntime.contains("ivars->midiDevice->StartIO()"))
    #expect(midiRuntime.contains("ivars->midiDevice->StopIO()"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsMissingInvalidAndConflictingConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.midi",
      providerClass: "IOUserResources",
      capabilities: .midi
    )
    #expect(throws: DriverExtensionGenerationError.invalidMIDIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = DriverConfiguration(
      bundleIdentifier: "com.example.midi",
      providerClass: "IOUserResources",
      capabilities: .midi,
      midiDevice: MIDIDeviceConfiguration(
        driverName: "MIDI",
        deviceIdentifier: "Device",
        modelIdentifier: "Model",
        manufacturerIdentifier: "Maker",
        entityName: "Entity",
        protocol: .midi1,
        sourceCount: 0,
        destinationCount: 0
      )
    )
    #expect(throws: DriverExtensionGenerationError.invalidMIDIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalid,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let conflicting = DriverConfiguration(
      bundleIdentifier: "com.example.midi",
      providerClass: "IOUserResources",
      capabilities: [.midi, .blockStorage],
      blockStorageDevice: blockConfiguration,
      midiDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidMIDIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflicting,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func rejectsDeploymentTargetBeforeMIDIDriverKit() {
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.midi",
      providerClass: "IOUserResources",
      capabilities: .midi,
      midiDevice: deviceConfiguration
    )

    #expect(throws: DriverExtensionGenerationError.invalidMIDIConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "23.9"),
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private func buildGeneratedExtension(at directory: URL, derivedData: URL) throws -> (
    status: Int32, output: String
  ) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
      "xcodebuild", "-quiet", "-project", "SwifterKitRuntime.xcodeproj", "-scheme",
      "SwifterKitRuntime", "-configuration", "Debug", "-sdk", "driverkit", "-derivedDataPath",
      derivedData.path, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
      "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "GCC_TREAT_WARNINGS_AS_ERRORS=YES", "build",
    ]
    process.currentDirectoryURL = directory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return (
      process.terminationStatus,
      String(bytes: data, encoding: .utf8) ?? "xcodebuild emitted non-UTF-8 output"
    )
  }

  private var deviceConfiguration: MIDIDeviceConfiguration {
    MIDIDeviceConfiguration(
      driverName: "Swift MIDI",
      deviceIdentifier: "com.example.device",
      modelIdentifier: "com.example.model",
      manufacturerIdentifier: "com.example",
      entityName: "Swift Entity",
      protocol: .midi2,
      sourceCount: 2,
      destinationCount: 3
    )
  }

  private var blockConfiguration: BlockStorageDeviceConfiguration {
    BlockStorageDeviceConfiguration(
      blockCount: 1,
      blockSize: 512,
      maximumIOSize: 512,
      vendor: "V",
      product: "P",
      revision: "1"
    )
  }
}
