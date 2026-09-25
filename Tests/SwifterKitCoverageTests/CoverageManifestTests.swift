import Foundation
import Testing

@testable import SwifterKitCoverage

@Suite
struct CoverageManifestTests {
  private func surface(_ version: String, _ header: String) -> SDKSurface {
    SDKSurface(
      version: version,
      classes: IIGParser.parse(header).map {
        SDKSurface.DeclaredClass(framework: "ExampleKit", declaration: $0)
      }
    )
  }

  private let older = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual bool init() override;
        virtual kern_return_t Start(IOService * provider) override;
        virtual kern_return_t Legacy(uint32_t value);
    private:
        virtual void _Plumbing();
    };
    """

  private let newer = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual bool init() override;
        virtual kern_return_t Start(IOService * provider) override;
        virtual kern_return_t Added(uint64_t value);
    private:
        virtual void _Plumbing();
    };
    """

  @Test
  func mergesSDKPresenceAndAppliesExclusions() throws {
    let manifest = CoverageManifest().merging([surface("24.4", older), surface("27.0", newer)])
    let methods = try #require(manifest.classes.first).methods

    #expect(manifest.sdks == ["24.4", "27.0"])
    #expect(methods.map(\.signature) == methods.map(\.signature).sorted())
    #expect(methods.count == 5)
    let byName = Dictionary(uniqueKeysWithValues: methods.map { ($0.name, $0) })
    #expect(byName["Start"]?.sdks == ["24.4", "27.0"])
    #expect(byName["Legacy"]?.sdks == ["24.4"])
    #expect(byName["Added"]?.sdks == ["27.0"])
    #expect(byName["Start"]?.status == .gap)
    #expect(byName["_Plumbing"]?.status == .excluded)
    #expect(byName["init"]?.status == .excluded)
  }

  @Test
  func keepsStatusesAndDropsMembersNoSDKDeclares() throws {
    var manifest = CoverageManifest().merging([surface("24.4", older)])
    let index = try #require(manifest.classes[0].methods.firstIndex { $0.name == "Start" })
    manifest.classes[0].methods[index].status = .generated

    let updated = manifest.merging([surface("24.4", newer)])
    let names = updated.classes[0].methods.map(\.name)

    #expect(names.contains("Added"))
    #expect(!names.contains("Legacy"))
    #expect(updated.classes[0].methods.first { $0.name == "Start" }?.status == .generated)
    #expect(
      CoverageAudit.drift(from: manifest, to: updated) == [
        "new: ExampleKit/IOExample::kern_return_t Added(uint64_t)",
        "removed: ExampleKit/IOExample::kern_return_t Legacy(uint32_t)",
      ]
    )
    #expect(
      CoverageAudit.drift(from: updated, to: updated.merging([surface("24.4", newer)])).isEmpty
    )
  }

  @Test
  func encodesDeterministically() throws {
    let manifest = CoverageManifest().merging([surface("24.4", older)])
    let data = try manifest.encoded()
    #expect(try CoverageManifest.decoded(data) == manifest)
    #expect(try manifest.encoded() == data)
  }

  @Test
  func auditsClaimsAgainstSources() throws {
    var manifest = CoverageManifest().merging([surface("24.4", older)])
    let native = SourceIndex(
      text: "class Runtime : public IOExample {}; kern_return_t Start_Impl(IOService*);"
    )
    let audit = CoverageAudit(
      manifest: manifest,
      native: native,
      swift: SourceIndex(text: "func legacy()")
    )

    let inferred = audit.inferringGenerated()
    let statuses = Dictionary(
      uniqueKeysWithValues: inferred.classes[0].methods.map { ($0.name, $0.status) }
    )
    #expect(statuses["Start"] == .generated)
    #expect(statuses["Legacy"] == .gap)

    let legacy = try #require(manifest.classes[0].methods.firstIndex { $0.name == "Legacy" })
    manifest.classes[0].methods[legacy].status = .generated
    manifest.classes[0].methods[legacy].swiftSymbol = nil
    let problems = CoverageAudit(manifest: manifest, native: native, swift: SourceIndex(text: ""))
      .problems()
    #expect(
      problems == [
        "ExampleKit/IOExample::kern_return_t Legacy(uint32_t) is marked generated "
          + "but the runtime does not reference it"
      ]
    )
  }

  @Test
  func summarizesCoveredMembers() {
    let summary = CoverageAudit.summary(CoverageManifest().merging([surface("24.4", older)]))
    #expect(summary.contains("ExampleKit | 2 | 0 | 0 | 0 | 2 | 0/2 (0%)"))
  }
}
