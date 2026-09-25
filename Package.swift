// swift-tools-version: 6.1

import Foundation
import PackageDescription

// Xcode's Swift Testing framework lives outside the default search paths of swift.org
// toolchains; point macOS test builds at the selected Xcode.
let developerDirectory =
  ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
  ?? "/Applications/Xcode.app/Contents/Developer"
let testingFrameworks =
  "\(developerDirectory)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
let testingRuntime = "\(developerDirectory)/Platforms/MacOSX.platform/Developer/usr/lib"

let package = Package(
  name: "SwifterKit",
  platforms: [.macOS(.v10_15)],
  products: [.library(name: "SwifterKit", targets: ["SwifterKit"])],
  targets: [
    .target(
      name: "SwifterKit",
      resources: [.copy("Resources/DriverKitExtension")],
      linkerSettings: [.linkedFramework("IOKit", .when(platforms: [.macOS]))]
    ), .executableTarget(name: "SwifterKitCoverage"),
    .testTarget(
      name: "SwifterKitCoverageTests",
      dependencies: ["SwifterKitCoverage"],
      swiftSettings: [.unsafeFlags(["-F", testingFrameworks], .when(platforms: [.macOS]))],
      linkerSettings: [
        .unsafeFlags(
          ["-F", testingFrameworks, "-Xlinker", "-rpath", "-Xlinker", testingRuntime],
          .when(platforms: [.macOS])
        )
      ]
    ),
    .testTarget(
      name: "SwifterKitTests",
      dependencies: ["SwifterKit"],
      swiftSettings: [.unsafeFlags(["-F", testingFrameworks], .when(platforms: [.macOS]))],
      linkerSettings: [
        .unsafeFlags(
          ["-F", testingFrameworks, "-Xlinker", "-rpath", "-Xlinker", testingRuntime],
          .when(platforms: [.macOS])
        )
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
