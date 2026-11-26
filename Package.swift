// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SwifterKit",
  platforms: [.macOS(.v13)],
  products: [.library(name: "SwifterKit", targets: ["SwifterKit"])],
  targets: [
    .target(
      name: "SwifterKit",
      resources: [.copy("Resources/DriverKitExtension")],
      linkerSettings: [.linkedFramework("IOKit", .when(platforms: [.macOS]))]
    ),
    .executableTarget(name: "SwifterKitCoverage"),
    .testTarget(name: "SwifterKitCoverageTests", dependencies: ["SwifterKitCoverage"]),
    .testTarget(name: "SwifterKitTests", dependencies: ["SwifterKit"])
  ],
  swiftLanguageModes: [.v6]
)

// >>> swift-bedrock
// Managed by swift-bedrock: Swift 6, the upcoming features, strict memory safety,
// and warnings as errors, for every target.
package.swiftLanguageModes = [.v6]
for target in package.targets where ![.system, .binary, .plugin].contains(target.type) {
  target.swiftSettings =
    (target.swiftSettings ?? []) + [
      .enableUpcomingFeature("ExistentialAny"),
      .enableUpcomingFeature("InternalImportsByDefault"),
      .enableUpcomingFeature("MemberImportVisibility"),
      .enableUpcomingFeature("InferIsolatedConformances"),
      .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
      .enableUpcomingFeature("ImmutableWeakCaptures"),
      .strictMemorySafety(),
      .treatAllWarnings(as: .error)
    ]
}
// <<< swift-bedrock
