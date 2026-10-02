import Foundation

/// Generates and checks the DocC article on SwifterKit's DriverKit coverage.
///
///     swifterkit-coverage docc --sdk DIR... --trees DIR --article FILE [--exclusions FILE]
///         [--swift DIR...]
///     swifterkit-coverage check --sdk DIR... [--trees DIR] --article FILE [--swift DIR...]
///     swifterkit-coverage evidence --sdk DIR... --trees DIR
///
/// `--sdk` names a `DriverKit.sdk` directory, whose `.iig` headers declare the members. `--trees`
/// names the directory of generated extension trees that `SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE`
/// collects during `swift test`; clang reads which members those trees call or override.
/// `--swift` names the directories whose `///` comments name `` `Class::member` ``, by default
/// `Sources/SwifterKit`. SwifterKit's exclusions come from the article's "Members SwifterKit does
/// not expose" section and, for `docc`, from `--exclusions`, a file of lines in the same format
/// whose reasons replace the article's.
///
/// `docc` writes the article. `check` fails on documentation mentions and exclusions that the
/// headers or the evidence do not support, and, when it has the trees and the article names the
/// same SDKs, on an article that differs from what `docc` would write. When `--sdk` lacks an SDK
/// the article names, `check` does not report members the given headers do not declare.
@main
enum CoverageCommand {
  struct Options {
    var command = ""
    var sdks: [URL] = []
    var swift: [URL] = []
    var trees: URL?
    var article: URL?
    var exclusions: URL?
  }

  enum Failure: Error, CustomStringConvertible {
    case usage(String)
    case check([String])

    var description: String {
      switch self {
      case .usage(let message): message
      case .check(let problems): problems.joined(separator: "\n")
      }
    }
  }

  static func main() {
    do { try run(Array(CommandLine.arguments.dropFirst())) } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }

  static func run(_ arguments: [String]) throws {
    let options = try parse(arguments)
    guard !options.sdks.isEmpty else { throw Failure.usage("--sdk is required") }
    let coverage = Coverage(try options.sdks.map { try SDKSurface(sdk: $0) })
    let evidence = try options.trees.map {
      CoverageEvidence(coverage: coverage, native: try NativeEvidence(trees: $0))
    }

    switch options.command {
    case "docc":
      guard let evidence else { throw Failure.usage("docc needs --trees") }
      guard let article = options.article else { throw Failure.usage("docc needs --article") }
      var exclusions = try existingExclusions(article)
      if let file = options.exclusions {
        let mapped = CoverageArticle.exclusions(
          in: try String(contentsOf: file, encoding: .utf8),
          article: false
        )
        let keys = Set(mapped.map { CoverageEvidence.MemberKey($0.className, $0.signature) })
        exclusions = mapped.union(
          exclusions.filter {
            !keys.contains(CoverageEvidence.MemberKey($0.className, $0.signature))
          }
        )
      }
      let (rendered, problems) = try audit(coverage, evidence, exclusions, options.swift)
      try Data(CoverageArticle.render(rendered).utf8).write(to: article, options: .atomic)
      for problem in problems { FileHandle.standardError.write(Data("warning: \(problem)\n".utf8)) }
    case "check":
      guard let article = options.article else { throw Failure.usage("check needs --article") }
      let text = try String(contentsOf: article, encoding: .utf8)
      let exclusions = CoverageArticle.exclusions(in: text, article: true)
      let missing = CoverageArticle.missingSDKs(in: text, from: coverage.sdks)
      if !missing.isEmpty {
        print(
          "note: --sdk lacks the DriverKit \(missing.joined(separator: ", ")) SDKs that "
            + "\(article.lastPathComponent) names, so members the given headers do not declare "
            + "are not reported"
        )
      }
      var (rendered, problems) = try audit(
        coverage,
        evidence,
        exclusions,
        options.swift,
        requireDeclared: missing.isEmpty
      )
      if evidence == nil {
        print("note: without --trees, \(article.lastPathComponent) is not compared")
      } else if CoverageArticle.sdks(in: text) != coverage.sdks {
        let named = CoverageArticle.sdks(in: text)?.joined(separator: ", ") ?? "no"
        print(
          "note: \(article.lastPathComponent) names \(named) SDKs, not "
            + "\(coverage.sdks.joined(separator: ", ")), so it is not compared"
        )
      } else if text != CoverageArticle.render(rendered) {
        problems.append("\(article.lastPathComponent) is out of date; run swifterkit-coverage docc")
      }
      guard problems.isEmpty else { throw Failure.check(problems) }
    case "evidence":
      guard let evidence else { throw Failure.usage("evidence needs --trees") }
      for (key, uses) in evidence.members.sorted(by: { $0.key < $1.key }) {
        print("\(key.className)::\(key.signature)")
        for use in uses.sorted() { print("  \(use)") }
      }
      for use in evidence.unresolved.sorted() {
        let parameters = use.parameters?.joined(separator: ", ") ?? "IIG"
        let member = "\(use.className)::\(use.method)(\(parameters))"
        print("unresolved \(use.kind.rawValue) \(member) \(use.evidence)")
      }
    default:
      throw Failure.usage("unknown command '\(options.command)'; use docc, check, or evidence")
    }
  }

  /// The coverage with the evidence, documentation, and exclusions applied, and the problems the
  /// audit finds in them.
  private static func audit(
    _ coverage: Coverage,
    _ evidence: CoverageEvidence?,
    _ exclusions: Set<Coverage.Exclusion>,
    _ swift: [URL],
    requireDeclared: Bool = true
  ) throws -> (Coverage, [String]) {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let documented = try DocumentedMembers(
      directories: swift.isEmpty ? [root.appendingPathComponent("Sources/SwifterKit")] : swift
    ).resolved(in: coverage)
    let problems = CoverageAudit.problems(
      coverage,
      documented: documented,
      exclusions: exclusions,
      evidence: evidence,
      requireDeclared: requireDeclared
    )
    guard let evidence else { return (coverage, problems) }
    let applied = coverage.applying(
      evidence,
      documented: Set(documented.values.joined()),
      exclusions: exclusions
    )
    return (applied, problems)
  }

  /// The exclusions an existing article lists, or none when there is no article yet.
  private static func existingExclusions(_ article: URL) throws -> Set<Coverage.Exclusion> {
    guard FileManager.default.fileExists(atPath: article.path) else { return [] }
    return CoverageArticle.exclusions(
      in: try String(contentsOf: article, encoding: .utf8),
      article: true
    )
  }

  static func parse(_ arguments: [String]) throws -> Options {
    var options = Options()
    var remaining = arguments[...]
    guard let command = remaining.popFirst() else {
      throw Failure.usage("usage: swifterkit-coverage docc|check|evidence --sdk DIR...")
    }
    options.command = command
    while let flag = remaining.popFirst() {
      guard let value = remaining.popFirst() else { throw Failure.usage("\(flag) needs a value") }
      let url = URL(fileURLWithPath: value)
      switch flag {
      case "--sdk": options.sdks.append(url)
      case "--swift": options.swift.append(url)
      case "--trees": options.trees = url
      case "--article": options.article = url
      case "--exclusions": options.exclusions = url
      default: throw Failure.usage("unknown option \(flag)")
      }
    }
    return options
  }
}
