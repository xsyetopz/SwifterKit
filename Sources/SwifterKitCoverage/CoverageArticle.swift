import Foundation

/// Renders the DocC article that tells driver authors how much of Apple's DriverKit surface a
/// Swift driver controls.
enum CoverageArticle {
  static let exclusionsTitle = "### Members SwifterKit does not expose"

  static func render(_ coverage: Coverage) -> String {
    let sdks = coverage.sdks.joined(separator: ", ")
    var lines: [String] = [
      "# DriverKit Coverage", "",
      "How much of the DriverKit API that Apple's SDK headers declare a Swift driver reaches.", "",
      "## Overview", "",
      "`SwifterKitCoverage docc` generates this article from the `.iig` headers of the "
        + "DriverKit \(sdks) SDKs, clang's AST of the generated extension runtime, and the "
        + "Swift documentation. Edit only the reasons under \"Members SwifterKit does not "
        + "expose\".", "",
      "- term Swift API: A typed Swift API reaches the member through the runtime, and its "
        + "documentation names the member.",
      "- term Runtime: The generated extension runtime calls or overrides the member for you. "
        + "Clang's AST of the generated sources is the evidence.",
      "- term Gap: The header makes the member public to DriverKit clients and SwifterKit does "
        + "not reach it.",
      "- term Not exposed: The header makes the member public and SwifterKit chose not to "
        + "expose it, for the reason given.",
      "- term Apple only: The header keeps the member from DriverKit clients: it is private, in "
        + "a private class extension, or compiled only for the kernel or under a private "
        + "condition. No DriverKit driver can use it.", "", "### Counts", "",
      "| Framework | Public | Swift API | Runtime | Gap | Not exposed | Apple only |",
      "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    var totals = Counts()
    for framework in Set(coverage.classes.map(\.framework)).sorted() {
      let counts = Counts(coverage.classes.filter { $0.framework == framework })
      totals.add(counts)
      lines.append(counts.row(framework))
    }
    lines.append(totals.row("**Total**"))

    lines += [
      "", exclusionsTitle, "", "Public members that SwifterKit chose not to reach from Swift.",
    ]
    lines += listing(coverage, .excluded, by: .swifterkit) { entry, methods in
      methods.map { "- `\(entry.name)` `\($0.signature)`: \($0.note ?? "")" }
    }
    lines += ["", "### Gaps", "", "Public members that a Swift driver cannot reach."]
    lines += listing(coverage, .gap) { entry, methods in
      ["- `\(entry.name)`: " + methods.map { "`\($0.signature)`" }.joined(separator: "; ")]
    }
    lines += [
      "", "### Members Apple keeps from DriverKit clients", "",
      "Members that no DriverKit driver can use, with the header fact that says so.",
    ]
    lines += listing(coverage, .excluded, by: .apple) { entry, methods in
      [
        "- `\(entry.name)`: "
          + methods.map { "`\($0.signature)` (\($0.note ?? ""))" }.joined(separator: "; ")
      ]
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Reads the exclusion lines `` - `Class` `signature`: reason `` from `text`. In an article,
  /// only the lines under "Members SwifterKit does not expose" count.
  static func exclusions(in text: String, article: Bool) -> Set<Coverage.Exclusion> {
    var result: Set<Coverage.Exclusion> = []
    var inSection = !article
    for line in text.split(separator: "\n") {
      if article, line.hasPrefix("### ") {
        inSection = line == exclusionsTitle
        continue
      }
      guard inSection, line.hasPrefix("- `") else { continue }
      let parts = line.dropFirst(3).components(separatedBy: "` `")
      guard parts.count == 2, let end = parts[1].range(of: "`: ") else { continue }
      result.insert(
        Coverage.Exclusion(
          className: parts[0],
          signature: String(parts[1][..<end.lowerBound]),
          reason: String(parts[1][end.upperBound...])
        )
      )
    }
    return result
  }

  /// The SDK versions an article names, or `nil` when it names none.
  static func sdks(in text: String) -> [String]? {
    guard let start = text.range(of: "headers of the DriverKit "),
      let end = text[start.upperBound...].range(of: " SDKs")
    else { return nil }
    return text[start.upperBound..<end.lowerBound].components(separatedBy: ", ")
  }

  private struct Counts {
    var values: [Int] = Array(repeating: 0, count: 6)

    init() {}

    init(_ classes: [Coverage.Class]) {
      for method in classes.flatMap(\.methods) {
        switch (method.status, method.excludedBy) {
        case (.swiftAPI, _): values[1] += 1
        case (.generated, _): values[2] += 1
        case (.gap, _): values[3] += 1
        case (.excluded, .apple): values[5] += 1
        case (.excluded, _): values[4] += 1
        }
      }
      values[0] = values[1...4].reduce(0, +)
    }

    mutating func add(_ other: Self) { values = zip(values, other.values).map(+) }

    func row(_ name: String) -> String {
      "| \(name) | " + values.map(String.init).joined(separator: " | ") + " |"
    }
  }

  /// One subsection per framework listing, through `format`, each class's members with `status`
  /// and, for exclusions, `source`.
  private static func listing(
    _ coverage: Coverage,
    _ status: CoverageStatus,
    by source: ExclusionSource? = nil,
    format: (Coverage.Class, [Coverage.Method]) -> [String]
  ) -> [String] {
    var lines: [String] = []
    var framework = ""
    for entry in coverage.classes {
      let methods = entry.methods.filter { $0.status == status && $0.excludedBy == source }
      guard !methods.isEmpty else { continue }
      if entry.framework != framework {
        framework = entry.framework
        lines += ["", "#### \(framework)", ""]
      }
      lines += format(entry, methods)
    }
    return framework.isEmpty ? ["", "None."] : lines
  }
}
