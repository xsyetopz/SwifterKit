import Foundation
import Testing

@testable import SwifterKitCoverage

@Suite
struct CoverageAuditTests {
  private let header = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual kern_return_t Start(IOService * provider) override;
        virtual void Notify(uint32_t value);
        virtual void Notify(uint64_t value);
        virtual kern_return_t Legacy(uint32_t value);
    private:
        virtual void _Plumbing();
    };
    class KERNEL IOExampleChild : public IOExample
    {
    public:
        virtual void Reset();
    };
    """

  @Test
  func readsMentionsFromDocumentationCommentsOnly() {
    let source = """
      /// Starts the device through `IOExample::Start` and `IOExampleChild::Reset`.
      // `IOExample::Legacy` is not documentation.
      let value = "`IOExample::Notify`"
          /// Indented: `IOExample::Notify`, not `IOExample` or `Notify`.
      """
    let mentions = DocumentedMembers(text: source, file: "Example.swift").mentions

    #expect(
      mentions.sorted().map { "\($0.className)::\($0.member) \($0.location)" } == [
        "IOExample::Notify Example.swift:4", "IOExample::Start Example.swift:1",
        "IOExampleChild::Reset Example.swift:1",
      ]
    )
  }

  @Test
  func resolvesMentionsThroughSuperclassesToEveryOverload() {
    let coverage = Coverage([surface("24.4", header)])
    let source = """
      /// `IOExampleChild::Notify`, `IOExampleChild::Missing`, and `OSString::length`.
      """
    let resolved = DocumentedMembers(text: source).resolved(in: coverage)

    #expect(resolved.count == 2)
    #expect(
      resolved.first { $0.key.member == "Notify" }?.value.map(\.signature).sorted() == [
        "void Notify(uint32_t)", "void Notify(uint64_t)",
      ]
    )
    #expect(resolved.first { $0.key.member == "Missing" }?.value.isEmpty == true)
  }

  @Test
  func reportsMentionsAndExclusionsTheHeadersOrEvidenceDoNotSupport() {
    let coverage = Coverage([surface("24.4", header)])
    let evidence = CoverageEvidence(
      coverage: coverage,
      native: NativeEvidence(
        uses: [use("IOExample", "Start", nil, kind: .override, in: "Runtime::Start_Impl")],
        bases: [:]
      )
    )
    let documented = DocumentedMembers(
      text: "/// `IOExample::Start`, `IOExample::Legacy`, `IOExample::Gone`.",
      file: "A.swift"
    ).resolved(in: coverage)
    func exclusion(
      _ signature: String,
      _ reason: String = "The runtime owns it"
    ) -> Coverage.Exclusion {
      Coverage.Exclusion(className: "IOExample", signature: signature, reason: reason)
    }
    let exclusions: Set = [
      exclusion("void Notify(uint32_t)"), exclusion("void Gone()"), exclusion("void _Plumbing()"),
      exclusion("kern_return_t Start(IOService*)"), exclusion("void Notify(uint64_t)", "Not yet"),
    ]

    #expect(
      CoverageAudit.problems(
        coverage,
        documented: documented,
        exclusions: exclusions,
        evidence: evidence
      ) == [
        "`IOExample::Gone` at A.swift:1 names no member the SDK headers declare",
        "`IOExample::Legacy` at A.swift:1 is documented but the runtime does not reach it",
        "excluded `IOExample` `kern_return_t Start(IOService*)` is reached by the runtime",
        "excluded `IOExample` `void Gone()` names no member the SDK headers declare",
        "excluded `IOExample` `void Notify(uint64_t)` says \"Not yet\"; "
          + "describe what SwifterKit does now",
        "excluded `IOExample` `void _Plumbing()` is already kept from DriverKit clients: "
          + "declared private in the SDK header",
      ]
    )
    // Without evidence, only the header facts are checked.
    #expect(
      CoverageAudit.problems(
        coverage,
        documented: documented,
        exclusions: [exclusion("void Notify(uint32_t)")],
        evidence: nil
      ) == ["`IOExample::Gone` at A.swift:1 names no member the SDK headers declare"]
    )
  }

  @Test
  func provisionalWordsAreWholeWords() {
    for word in ["deferred", "Planned", "not yet", "HARD", "today", "TODO"] {
      #expect(CoverageAudit.provisionalWord(in: "Support is \(word) here") == word)
    }
    #expect(CoverageAudit.provisionalWord(in: "Hardcoded and undated notes stay valid") == nil)
  }
}
