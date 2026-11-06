import Testing

@testable import SwifterKit

@Suite
struct DriverKitDeploymentVersionTests {
  @Test
  func parsesAndComparesVersions() throws {
    let v21 = try #require(DriverKitDeploymentVersion("21"))
    let v21Point4 = try #require(DriverKitDeploymentVersion("21.4"))

    #expect(v21 == .v21)
    #expect(v21 < v21Point4)
    #expect(v21Point4 < .v22)
    #expect(try #require(DriverKitDeploymentVersion("24.00")) == .v24)
  }

  @Test(arguments: ["", ".", ".19", "19.", "19..0", "19.0.0", "nineteen", "１９.０"])
  func rejectsMalformedVersion(value: String) { #expect(DriverKitDeploymentVersion(value) == nil) }
}
