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
  func fastPathClaimsNeedANoteASwiftSymbolAndARuntimeReference() throws {
    var manifest = CoverageManifest().merging([surface("24.4", older)])
    let start = try #require(manifest.classes[0].methods.firstIndex { $0.name == "Start" })
    manifest.classes[0].methods[start].status = .fastPath
    let native = SourceIndex(text: "IOExample* provider; provider->Start(nullptr);")
    let swift = SourceIndex(text: "enum FastPathOp {}")
    func problems(note: String?, symbol: String?, native: SourceIndex = native) -> [String] {
      var claimed = manifest
      claimed.classes[0].methods[start].note = note
      claimed.classes[0].methods[start].swiftSymbol = symbol
      return CoverageAudit(manifest: claimed, native: native, swift: swift).problems()
    }
    let member = "ExampleKit/IOExample::kern_return_t Start(IOService*)"

    #expect(problems(note: "Started by a start program", symbol: "FastPathOp").isEmpty)
    #expect(
      problems(note: nil, symbol: "FastPathOp") == ["\(member) is marked fast-path without a note"]
    )
    let missingSymbol = ["\(member) is marked fast-path without a Swift symbol in Sources"]
    #expect(problems(note: "Runs", symbol: nil) == missingSymbol)
    #expect(problems(note: "Runs", symbol: "FastPathRing") == missingSymbol)
    #expect(
      problems(note: "Runs", symbol: "FastPathOp", native: SourceIndex(text: "IOExample")) == [
        "\(member) is marked fast-path but the runtime does not reference it"
      ]
    )
  }

  @Test
  func coveredNotesDescribeWhatTheSourcesDo() throws {
    var manifest = CoverageManifest().merging([surface("24.4", older)])
    let plumbing = try #require(manifest.classes[0].methods.firstIndex { $0.name == "_Plumbing" })
    func problems(_ note: String, status: CoverageStatus = .excluded) -> [String] {
      manifest.classes[0].methods[plumbing].status = status
      manifest.classes[0].methods[plumbing].note = note
      return CoverageAudit(
        manifest: manifest,
        native: SourceIndex(text: ""),
        swift: SourceIndex(text: "")
      ).problems()
    }
    let member = "ExampleKit/IOExample::void _Plumbing()"

    for word in ["deferred", "Planned", "not yet", "HARD", "today", "TODO"] {
      #expect(
        problems("Support is \(word) here") == [
          "\(member) note says \"\(word)\"; describe what SwifterKit does now"
        ]
      )
    }
    #expect(problems("Private hardware plumbing that DriverKit calls itself").isEmpty)
    #expect(problems("Hardcoded and undated notes stay valid").isEmpty)
    #expect(problems("TODO", status: .gap).isEmpty)
  }

  @Test
  func summarizesCoveredMembers() {
    let summary = CoverageAudit.summary(CoverageManifest().merging([surface("24.4", older)]))
    #expect(summary.contains("ExampleKit | 2 | 0 | 0 | 0 | 2 | 0/2 (0%)"))
  }
}
