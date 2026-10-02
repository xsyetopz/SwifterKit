import Foundation
import Testing

@testable import SwifterKitCoverage

@Suite
struct CoverageArticleTests {
  private let header = """
    class KERNEL IOExample : public IOService
    {
    public:
        virtual bool init() override;
        virtual kern_return_t Start(IOService * provider) override;
        virtual kern_return_t Legacy(uint32_t value);
        virtual void Reset();
    private:
        virtual void _Plumbing();
    };
    """

  private func article(exclusions: Set<Coverage.Exclusion>) -> String {
    let coverage = Coverage([surface("24.4", header), surface("27.0", header)])
    let native = NativeEvidence(
      uses: [use("IOExample", "Start", nil, kind: .override, in: "Runtime::Start_Impl")],
      bases: [:]
    )
    return CoverageArticle.render(
      coverage.applying(
        CoverageEvidence(coverage: coverage, native: native),
        documented: [.init("IOExample", "kern_return_t Start(IOService*)")],
        exclusions: exclusions
      )
    )
  }

  private let reset = Coverage.Exclusion(
    className: "IOExample",
    signature: "void Reset()",
    reason: "The runtime resets the device"
  )

  @Test
  func countsEveryStatusAndListsMembersADriverCannotReach() {
    let text = article(exclusions: [reset])

    #expect(text.hasPrefix("# DriverKit Coverage\n"))
    #expect(text.contains("headers of the DriverKit 24.4, 27.0 SDKs,"))
    #expect(text.contains("| ExampleKit | 4 | 1 | 0 | 2 | 1 | 1 |"))
    #expect(text.contains("| **Total** | 4 | 1 | 0 | 2 | 1 | 1 |"))
    #expect(text.contains("\n- `IOExample` `void Reset()`: The runtime resets the device\n"))
    #expect(text.contains("- `IOExample`: `bool init()`; `kern_return_t Legacy(uint32_t)`"))
    #expect(text.contains("- `IOExample`: `void _Plumbing()` (declared private in the SDK header)"))
    #expect(!text.contains("Start(IOService*)"))
    #expect(article(exclusions: []).contains("from Swift.\n\nNone.\n"))
  }

  @Test
  func readsBackTheExclusionsAndSDKsItWrites() {
    let text = article(exclusions: [reset])

    #expect(CoverageArticle.exclusions(in: text, article: true) == [reset])
    #expect(CoverageArticle.sdks(in: text) == ["24.4", "27.0"])
    #expect(CoverageArticle.missingSDKs(in: text, from: ["24.4"]) == ["27.0"])
    #expect(CoverageArticle.missingSDKs(in: text, from: ["24.4", "25.5", "27.0"]).isEmpty)
    // Gap and Apple lines have the same prefix but sit outside the exclusions section.
    #expect(CoverageArticle.exclusions(in: article(exclusions: []), article: true).isEmpty)
    let mapping = "- `IOExample` `void Reset()`: The runtime resets the device\nnot a line\n"
    #expect(CoverageArticle.exclusions(in: mapping, article: false) == [reset])
  }
}
