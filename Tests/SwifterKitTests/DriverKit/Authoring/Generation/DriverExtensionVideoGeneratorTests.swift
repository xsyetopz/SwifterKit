import Foundation
import Testing

@testable import SwifterKit

@Suite struct VideoGeneratorTests {
  @Test func generatesVideoRuntime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("VideoDriver", isDirectory: true)
    let configuration = DriverConfiguration(
      bundleIdentifier: "com.example.video",
      providerClass: "IOService",
      capabilities: .video,
      videoDevice: sampleDevice()
    )

    try DriverExtensionGenerator.generate(
      configuration: configuration,
      options: DriverExtensionGenerationOptions(deploymentTarget: "27.0"),
      at: output
    )

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("SWIFTERKIT_ENABLE_VIDEO 1"))
    #expect(header.contains("kSwifterKitVideoStreamCount = 2"))
    #expect(header.contains("1920, 1080"))
    #expect(header.contains("kSwifterKitVideoControlCount = 3"))
    #expect(header.contains("kSwifterKitVideoCustomPropertyCount =\n    1"))
    let selector = try #require(header.split(separator: "\n").first { $0.contains("{3, 7,") })
    #expect(selector.split(separator: ",").count == 16)
    #expect(selector.hasSuffix(", 0, 2, 0, 1}"))

    let service = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeService.iig"),
      encoding: .utf8
    )
    #expect(service.contains("public IOUserVideoDriver"))
    #expect(service.contains("StartVideo"))
    #expect(service.contains("VideoCommand"))

    let info = try loadPropertyList(at: output.appendingPathComponent("Info.plist"))
    let personalities = try #require(info["IOKitPersonalities"] as? [String: Any])
    let personality = try #require(personalities["SwiftDriver"] as? [String: Any])
    #expect(personality["IOUserVideoDriverUserClientProperties"] != nil)

    let entitlements = try loadPropertyList(
      at: output.appendingPathComponent("SwifterKitRuntime.entitlements")
    )
    #expect(
      entitlements["com.apple.developer.driverkit.allow-any-userclient-access"] as? Bool == true
    )

    let project = try String(
      contentsOf: output.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("VideoDriverKit.framework"))
    #expect(project.contains("SwifterKitRuntimeVideoDevice.iig in Sources"))
    #expect(project.contains("SwifterKitRuntimeVideoControls.cpp in Sources"))
    #expect(project.contains("SwifterKitRuntimeVideoDirectionControl.iig in Sources"))
    #expect(project.contains("SwifterKitRuntimeVideoStream.iig in Sources"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsMissingOldAndMalformedConfiguration() {
    let root = FileManager.default.temporaryDirectory
    let missing = DriverConfiguration(
      bundleIdentifier: "com.example.video",
      providerClass: "IOService",
      capabilities: .video
    )
    #expect(throws: DriverExtensionGenerationError.invalidVideoConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: missing,
        options: DriverExtensionGenerationOptions(deploymentTarget: "27.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let valid = DriverConfiguration(
      bundleIdentifier: "com.example.video",
      providerClass: "IOService",
      capabilities: .video,
      videoDevice: sampleDevice()
    )
    #expect(throws: DriverExtensionGenerationError.invalidVideoConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: valid,
        options: DriverExtensionGenerationOptions(deploymentTarget: "26.0"),
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }

    let detached = DriverConfiguration(
      bundleIdentifier: "com.example.video",
      providerClass: "IOService",
      capabilities: [],
      videoDevice: sampleDevice()
    )
    #expect(throws: DriverExtensionGenerationError.capabilityConfigurationMismatch(.video)) {
      try DriverExtensionGenerator.generate(
        configuration: detached,
        at: root.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  private func sampleDevice() -> VideoDeviceConfiguration {
    let format = VideoStreamFormat(
      frameRate: 60,
      frameTimeScale: 60,
      codec: .bgra32,
      width: 1_920,
      height: 1_080
    )
    let property = VideoCustomPropertyConfiguration(
      identifier: 3,
      selector: 0x7377_6B70,
      values: ["Mode": "Studio"]
    )
    return VideoDeviceConfiguration(
      deviceUID: "Video.Device",
      modelUID: "Video.Model",
      manufacturerUID: "Example",
      name: "Video Device",
      transport: .usb,
      sampleRates: [60],
      initialSampleRate: 60,
      streams: [
        VideoStreamConfiguration(
          identifier: "Video.Output",
          direction: .output,
          formats: [format],
          bufferCount: 4,
          dataBufferCapacity: 8_294_400
        ),
        VideoStreamConfiguration(
          identifier: "Video.Input",
          direction: .input,
          formats: [format],
          bufferCount: 2,
          dataBufferCapacity: 8_294_400
        ),
      ],
      controls: [
        .boolean(
          VideoBooleanControlConfiguration(
            metadata: VideoControlMetadata(identifier: 1, name: "Enabled", controlClass: .boolean),
            initialValue: true
          )
        ),
        .direction(
          VideoDirectionControlConfiguration(
            metadata: VideoControlMetadata(
              identifier: 2,
              name: "Direction",
              controlClass: .direction
            ),
            initialValue: false
          )
        ),
        .selector(
          VideoSelectorControlConfiguration(
            metadata: VideoControlMetadata(identifier: 7, name: "Mode", controlClass: .selector),
            values: [
              VideoSelectorValue(value: 10, name: "A"), VideoSelectorValue(value: 20, name: "B"),
            ],
            initialValues: [20]
          )
        ),
      ],
      customProperties: [property]
    )
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
}
