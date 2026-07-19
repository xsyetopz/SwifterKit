import Foundation
import Testing

@testable import SwifterKit

@Suite struct HIDGeneratorTests {
  @Test func generatesHostReportAllowlist() throws {
    let defaultHeader = DriverExtensionGenerator.runtimeConfigurationHeader(
      configuration(acceptedHostReportTypes: .all)
    )
    #expect(defaultHeader.contains("kSwifterKitHIDAcceptedHostReportTypes =\n    3;"))

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("OutputOnlyHID", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: configuration(acceptedHostReportTypes: .output),
      at: output
    )

    let header = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeConfiguration.h"),
      encoding: .utf8
    )
    #expect(header.contains("kSwifterKitHIDAcceptedHostReportTypes =\n    1;"))

    let build = try buildGeneratedExtension(
      at: output,
      derivedData: root.appendingPathComponent("DerivedData")
    )
    #expect(build.status == 0, Comment(rawValue: build.output))
  }

  @Test func rejectsUnknownHostReportBits() {
    let configuration = configuration(
      acceptedHostReportTypes: HIDHostReportTypes(rawValue: 1 << 10)
    )

    #expect(throws: DriverExtensionGenerationError.invalidHIDConfiguration) {
      try DriverExtensionGenerator.generate(
        configuration: configuration,
        at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      )
    }
  }

  @Test func nativeGuardRejectsBeforeReadingOrEnqueueing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("NativeContract", isDirectory: true)
    try DriverExtensionGenerator.generate(
      configuration: configuration(acceptedHostReportTypes: .output),
      at: output
    )

    let source = try String(
      contentsOf: output.appendingPathComponent("Sources/SwifterKitRuntimeHID.cpp"),
      encoding: .utf8
    )
    let guardIndex = try #require(
      source.range(of: "if (!AcceptsHostReportType(reportType))")?.lowerBound
    )
    let unsupportedIndex = try #require(
      source.range(of: "return kIOReturnUnsupported;", range: guardIndex..<source.endIndex)?
        .lowerBound
    )
    let lengthIndex = try #require(source.range(of: "report->GetLength")?.lowerBound)
    let allocationIndex = try #require(
      source.range(of: "OSData* payload = OSData::withCapacity")?.lowerBound
    )
    let enqueueIndex = try #require(
      source.range(of: "EnqueueEvent(", range: guardIndex..<source.endIndex)?.lowerBound
    )

    #expect(source.contains("case kIOHIDReportTypeOutput:"))
    #expect(source.contains("case kIOHIDReportTypeFeature:"))
    #expect(guardIndex < unsupportedIndex)
    #expect(unsupportedIndex < lengthIndex)
    #expect(lengthIndex < allocationIndex)
    #expect(allocationIndex < enqueueIndex)
  }

  private func configuration(acceptedHostReportTypes: HIDHostReportTypes) -> DriverConfiguration {
    DriverConfiguration(
      bundleIdentifier: "com.example.hid-policy",
      providerClass: "IOUserResources",
      matchingProperties: ["IOResourceMatch": .string("IOKit")],
      capabilities: .hid,
      hidDevice: HIDDeviceConfiguration(
        reportDescriptor: [
          0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95,
          0x01, 0x09, 0x02, 0x91, 0x02, 0xC0,
        ],
        vendorID: 0x1234,
        productID: 0x5678,
        manufacturer: "Example",
        product: "HID policy",
        serialNumber: "policy-1",
        primaryUsagePage: 0xFF00,
        primaryUsage: 1,
        acceptedHostReportTypes: acceptedHostReportTypes
      )
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
