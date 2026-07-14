import Foundation
import Testing

@testable import SwifterKit

@Suite struct AudioGeneratorTests {
  @Test func generatesAudioRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("AudioDriver")
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .audio,
      audioDevice: deviceConfiguration
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    let audioClient = try #require(
      personality["IOUserAudioDriverUserClientProperties"] as? [String: Any]
    )
    #expect(audioClient["IOUserClass"] as? String == "IOUserAudioDriverUserClient")

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(entitlements["com.apple.developer.driverkit.family.audio"] as? Bool == true)
    #expect(
      entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] as? Bool == true
    )

    let config = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(config.contains("SWIFTERKIT_ENABLE_AUDIO 1"))
    #expect(config.contains("kSwifterKitAudioSampleRateCount = 2"))
    #expect(config.contains("kSwifterKitAudioStreamCount = 2"))
    #expect(config.contains("kSwifterKitAudioControlCount = 5"))
    #expect(config.contains("kSwifterKitAudioCustomPropertyCount ="))
    #expect(config.contains("kSwifterKitAudioCustomProperties[] ="))
    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserAudioDriver"))
    #expect(service.contains("StartAudio()"))
    let userClient = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeUserClient.cpp"),
      encoding: .utf8
    )
    #expect(userClient.contains("CopyClientEntitlements"))
    #expect(userClient.contains("kSwifterKitBundleIdentifier"))
    let audioDevice = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeAudioDevice.cpp"),
      encoding: .utf8
    )
    #expect(audioDevice.contains("__atomic_add_fetch"))
    #expect(!audioDevice.contains("EnqueueEvent(0x0A00"))
    let audioRuntime = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeAudio.cpp"),
      encoding: .utf8
    )
    #expect(audioRuntime.contains("AudioControlValueEvent"))
    #expect(audioRuntime.contains("EnqueueRequiredEvent"))
    let callbacks = try String(
      contentsOf: output.appendingPathComponent(
        "Sources/SwifterKitRuntimeAudioControlCallbacks.cpp"
      ),
      encoding: .utf8
    )
    #expect(callbacks.contains("HandleChangeSelectedValues"))
    #expect(callbacks.contains("HandleChangeCustomPropertyDataValueWithQualifier"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func generatesUSBBackedAudioRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("USBAudioDriver")
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.usb-audio",
      providerClass: "IOUSBHostInterface",
      capabilities: [.audio, .usb],
      usbDevice: USBDeviceConfiguration(vendorID: 0x1234, productIDs: [0x5678], interfaceClass: 1),
      audioDevice: deviceConfiguration
    )
    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
      at: output
    )
    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsMissingInvalidOldAndConflictingConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      capabilities: .audio
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalid = AudioDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Audio",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: []
    )
    let invalidConfiguration = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      capabilities: .audio,
      audioDevice: invalid
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalidConfiguration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let invalidStream = AudioStreamConfiguration(
      direction: .output,
      name: "Output",
      formats: [.linearPCM(sampleRate: 48_000, channels: 2)]
    )
    let invalidControl = AudioControlConfiguration.slider(
      AudioSliderControlConfiguration(
        metadata: AudioControlMetadata(identifier: 0, name: "Invalid", controlClass: .slider),
        initialValue: 2,
        minimumValue: 0,
        maximumValue: 1
      )
    )
    let invalidControlDevice = AudioDeviceConfiguration(
      deviceUID: "Device",
      modelUID: "Model",
      manufacturerUID: "Maker",
      name: "Audio",
      sampleRates: [48_000],
      initialSampleRate: 48_000,
      streams: [invalidStream],
      controls: [invalidControl]
    )
    let invalidControlConfiguration = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      capabilities: .audio,
      audioDevice: invalidControlDevice
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: invalidControlConfiguration,
        options: DriverExtensionGenerationOptions(deploymentTarget: "21.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let valid = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      capabilities: .audio,
      audioDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: valid,
        options: DriverExtensionGenerationOptions(deploymentTarget: "20.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let conflict = DriverConfiguration(
      bundleIdentifier: "com.example.audio",
      providerClass: "IOUserResources",
      capabilities: [.audio, .networking],
      ethernetDevice: EthernetDeviceConfiguration(
        hardwareAddress: EthernetAddress(2, 3, 4, 5, 6, 7)
      ),
      audioDevice: deviceConfiguration
    )
    #expect(throws: DriverExtensionGenerationError.invalidAudioConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: conflict,
        options: DriverExtensionGenerationOptions(deploymentTarget: "22.0"),
        at: root.appendingPathComponent(UUID().uuidString)
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
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "non-UTF-8 output")
  }

  private var deviceConfiguration: AudioDeviceConfiguration {
    let formats = [
      AudioStreamFormat.linearPCM(sampleRate: 44_100, channels: 2),
      AudioStreamFormat.linearPCM(sampleRate: 48_000, channels: 2),
    ]
    let property = AudioCustomPropertyConfiguration(
      identifier: 20,
      selector: 0x7377_6B70,
      values: ["Mode": "Studio"]
    )
    return AudioDeviceConfiguration(
      deviceUID: "SwifterKit.Audio",
      modelUID: "SwifterKit.Model",
      manufacturerUID: "SwifterKit",
      name: "Swift Audio",
      transport: .usb,
      sampleRates: [44_100, 48_000],
      initialSampleRate: 48_000,
      streams: [
        AudioStreamConfiguration(direction: .output, name: "Output", formats: formats),
        AudioStreamConfiguration(direction: .input, name: "Input", formats: formats),
      ],
      controls: audioControls,
      customProperties: [property]
    )
  }

  private var audioControls: [AudioControlConfiguration] {
    let mute = AudioControlMetadata(
      identifier: 1,
      name: "Mute",
      scope: .output,
      controlClass: .mute
    )
    return [
      .boolean(AudioBooleanControlConfiguration(metadata: mute, initialValue: false)),
      .level(
        AudioLevelControlConfiguration(
          metadata: AudioControlMetadata(
            identifier: 2,
            name: "Volume",
            scope: .output,
            controlClass: .volume
          ),
          initialDecibels: -6,
          minimumDecibels: -96,
          maximumDecibels: 0
        )
      ),
      .selector(
        AudioSelectorControlConfiguration(
          metadata: AudioControlMetadata(
            identifier: 3,
            name: "Input",
            scope: .input,
            controlClass: .dataSource
          ),
          values: [
            AudioSelectorValue(value: 1, name: "Line"), AudioSelectorValue(value: 2, name: "Mic"),
          ],
          initialValues: [1]
        )
      ),
      .slider(
        AudioSliderControlConfiguration(
          metadata: AudioControlMetadata(identifier: 4, name: "Blend", controlClass: .slider),
          initialValue: 50,
          minimumValue: 0,
          maximumValue: 100
        )
      ),
      .stereoPan(
        AudioStereoPanControlConfiguration(
          metadata: AudioControlMetadata(
            identifier: 5,
            name: "Pan",
            scope: .output,
            controlClass: .stereoPan
          ),
          leftChannel: 1,
          rightChannel: 2
        )
      ),
    ]
  }
}
