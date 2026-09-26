import Foundation
import Testing

@testable import SwifterKit

/// The DriverKit SDK used for generated-extension builds, when one is installed.
///
/// `SWIFTERKIT_DRIVERKIT_DEVELOPER_DIR` selects an older Xcode, such as Xcode 16.3 whose
/// DriverKit 24.4 SDK still accepts the 19.0 default; otherwise `DEVELOPER_DIR` applies.
struct DriverKitSDK: Sendable {
  let minimumDeploymentTarget: DriverKitDeploymentVersion
  let maximumDeploymentTarget: DriverKitDeploymentVersion

  static let current: Self? = locate()

  /// Returns whether the selected SDK can build a project with `deploymentTarget`.
  static func supports(deploymentTarget: String) -> Bool {
    guard let sdk = current, let target = DriverKitDeploymentVersion(deploymentTarget) else {
      return false
    }
    return target <= sdk.maximumDeploymentTarget
  }

  private static func locate() -> Self? {
    guard let path = run("/usr/bin/xcrun", ["--sdk", "driverkit", "--show-sdk-path"]).map(trimmed),
      let settings = try? Data(
        contentsOf: URL(fileURLWithPath: path).appendingPathComponent("SDKSettings.json")
      ), let json = try? JSONSerialization.jsonObject(with: settings) as? [String: Any],
      let targets = json["SupportedTargets"] as? [String: Any],
      let driverKit = targets["driverkit"] as? [String: Any],
      let minimum = version(driverKit["MinimumDeploymentTarget"]),
      let maximum = version(driverKit["DefaultDeploymentTarget"])
    else { return nil }
    return Self(minimumDeploymentTarget: minimum, maximumDeploymentTarget: maximum)
  }

  private static func version(_ value: Any?) -> DriverKitDeploymentVersion? {
    (value as? String).flatMap(DriverKitDeploymentVersion.init)
  }

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Builds a generated extension unsigned for arm64 and x86_64 when the selected SDK can.
///
/// Projects older than the SDK minimum build at that minimum so the generated sources still
/// compile against the installed SDK. A project newer than the SDK records an issue; gate such
/// tests with ``DriverKitSDK/supports(deploymentTarget:)`` so they report as skipped. CI sets
/// `SWIFTERKIT_REQUIRE_DRIVERKIT` so a missing SDK fails ``DriverKitSDKTests``.
@discardableResult
func expectGeneratedExtensionBuilds(
  at directory: URL,
  derivedData: URL,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Bool {
  guard let sdk = DriverKitSDK.current else { return false }
  let target = try generatedDeploymentTarget(at: directory)
  if let target, target > sdk.maximumDeploymentTarget {
    Issue.record(
      "The selected DriverKit SDK is older than the project",
      sourceLocation: sourceLocation
    )
    return false
  }
  var arguments = [
    "xcodebuild", "-quiet", "-project", "SwifterKitRuntime.xcodeproj", "-scheme",
    "SwifterKitRuntime", "-configuration", "Debug", "-sdk", "driverkit", "-derivedDataPath",
    derivedData.path, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
    "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "GCC_TREAT_WARNINGS_AS_ERRORS=YES",
  ]
  let builtTarget = max(target ?? sdk.minimumDeploymentTarget, sdk.minimumDeploymentTarget)
  if let target, target < builtTarget {
    arguments.append("DRIVERKIT_DEPLOYMENT_TARGET=\(builtTarget.major).\(builtTarget.minor)")
  }
  arguments.append("build")
  let build = try runTool("/usr/bin/xcrun", arguments, currentDirectory: directory)
  #expect(build.status == 0, Comment(rawValue: build.output), sourceLocation: sourceLocation)
  if build.status == 0,
    let capture = ProcessInfo.processInfo.environment["SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE"]
  {
    try captureForNativeAnalysis(
      directory,
      derivedData: derivedData,
      target: builtTarget,
      into: URL(fileURLWithPath: capture)
    )
  }
  return build.status == 0
}

/// Copies a built tree's sources, IIG-generated headers, and deployment target so
/// `scripts/ci/validate-native.sh` can analyze every family configuration the build tests cover.
private func captureForNativeAnalysis(
  _ directory: URL,
  derivedData: URL,
  target: DriverKitDeploymentVersion,
  into capture: URL
) throws {
  let generated = try #require(
    FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: nil)?.compactMap {
      $0 as? URL
    }.first { $0.path.hasSuffix("/DerivedSources/SwifterKitRuntime") }
  )
  let tree = capture.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
  try FileManager.default.copyItem(
    at: directory.appendingPathComponent("Sources"),
    to: tree.appendingPathComponent("Sources")
  )
  try FileManager.default.copyItem(at: generated, to: tree.appendingPathComponent("DerivedSources"))
  try Data("\(target.major).\(target.minor)\n".utf8).write(
    to: tree.appendingPathComponent("DeploymentTarget")
  )
}

/// Runs a tool with the DriverKit Xcode and without the caller's `TOOLCHAINS` override, so
/// Xcode uses its own compilers. Host builds pass `driverKitXcode: false` to keep the selected
/// Xcode, because an older Xcode's host runtimes, such as its sanitizers, may not run on a newer
/// macOS.
func runTool(
  _ executable: String,
  _ arguments: [String],
  currentDirectory: URL? = nil,
  driverKitXcode: Bool = true
) throws -> (status: Int32, output: String) {
  #if os(macOS)
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "TOOLCHAINS")
    if driverKitXcode, let developerDirectory = environment["SWIFTERKIT_DRIVERKIT_DEVELOPER_DIR"] {
      environment["DEVELOPER_DIR"] = developerDirectory
    }
    process.environment = environment
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
      process.terminationStatus,
      String(bytes: data, encoding: .utf8) ?? "\(executable) emitted non-UTF-8 output"
    )
  #else
    return (-1, "\(executable) requires macOS")
  #endif
}

private func run(_ executable: String, _ arguments: [String]) -> String? {
  guard let result = try? runTool(executable, arguments), result.status == 0 else { return nil }
  return result.output
}

private func generatedDeploymentTarget(at directory: URL) throws -> DriverKitDeploymentVersion? {
  let project = try String(
    contentsOf: directory.appendingPathComponent("SwifterKitRuntime.xcodeproj/project.pbxproj"),
    encoding: .utf8
  )
  let prefix = "DRIVERKIT_DEPLOYMENT_TARGET = "
  guard let line = project.split(separator: "\n").first(where: { $0.contains(prefix) }),
    let range = line.range(of: prefix)
  else { return nil }
  return DriverKitDeploymentVersion(String(line[range.upperBound...].prefix { $0 != ";" }))
}

@Suite
struct DriverKitSDKTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTERKIT_REQUIRE_DRIVERKIT"] != nil))
  func requiredSDKIsInstalled() {
    #expect(DriverKitSDK.current != nil, "DEVELOPER_DIR does not contain a DriverKit SDK")
  }
}
