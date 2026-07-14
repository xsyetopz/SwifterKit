// swift-tools-version: 6.2

import Foundation
import PackageDescription

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
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .testTarget(
      name: "SwifterKitTests",
      dependencies: ["SwifterKit"],
      swiftSettings: [.unsafeFlags(["-F", testingFrameworks])],
      linkerSettings: [
        .unsafeFlags(["-F", testingFrameworks, "-Xlinker", "-rpath", "-Xlinker", testingRuntime])
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
