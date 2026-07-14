import Testing

@testable import SwifterKit

@Suite struct DriverKitDeploymentVersionTests {
  @Test func parsesAndComparesVersions() throws {
    let v19 = try #require(DriverKitDeploymentVersion("19"))
    let v20 = try #require(DriverKitDeploymentVersion("20.0"))
    let v20Point4 = try #require(DriverKitDeploymentVersion("20.4"))

    #expect(v19 == .v19)
    #expect(v20 < v20Point4)
    #expect(v20Point4 == .v20Point4)
    #expect(try #require(DriverKitDeploymentVersion("24.00")) == .v24)
  }

  @Test(arguments: ["", ".", ".19", "19.", "19..0", "19.0.0", "nineteen", "１９.０"])
  func rejectsMalformedVersion(value: String) { #expect(DriverKitDeploymentVersion(value) == nil) }
}
