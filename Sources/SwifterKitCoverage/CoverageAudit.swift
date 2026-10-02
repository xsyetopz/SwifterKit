import Foundation

/// The DriverKit members SwifterKit's documentation names, written `` `Class::member` `` in a
/// `///` comment. Naming a member there claims that the documented Swift API reaches it.
struct DocumentedMembers {
  struct Mention: Hashable, Comparable {
    let className: String
    let member: String
    /// `File.swift:line`.
    let location: String

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.className, lhs.member, lhs.location) < (rhs.className, rhs.member, rhs.location)
    }
  }

  private(set) var mentions: Set<Mention> = []

  init(directories: [URL]) throws {
    for directory in directories {
      guard
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
      else { continue }
      for case let file as URL in files where file.pathExtension == "swift" {
        index(try String(contentsOf: file, encoding: .utf8), file: file.lastPathComponent)
      }
    }
  }

  init(text: String, file: String = "Source.swift") { index(text, file: file) }

  private static let pattern = "`[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*`"

  private mutating func index(_ text: String, file: String) {
    for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
    where line.trimmingCharacters(in: .whitespaces).hasPrefix("///") {
      var rest = line[...]
      while let range = rest.range(of: Self.pattern, options: .regularExpression) {
        let parts = rest[range].dropFirst().dropLast().components(separatedBy: "::")
        mentions.insert(
          Mention(className: parts[0], member: parts[1], location: "\(file):\(offset + 1)")
        )
        rest = rest[range.upperBound...]
      }
    }
  }

  /// The members each mention names: every overload of the member in the nearest class, from
  /// the named one up, that declares it. Mentions of classes no SDK declares are ignored.
  func resolved(in coverage: Coverage) -> [Mention: [CoverageEvidence.MemberKey]] {
    let classes = Dictionary(coverage.classes.map { ($0.name, $0) }) { first, _ in first }
    var result: [Mention: [CoverageEvidence.MemberKey]] = [:]
    for mention in mentions where classes[mention.className] != nil {
      var name: String? = mention.className
      var visited: Set<String> = []
      var keys: [CoverageEvidence.MemberKey] = []
      while let current = name, keys.isEmpty, visited.insert(current).inserted {
        keys =
          classes[current]?.methods.filter { $0.name == mention.member }.map {
            CoverageEvidence.MemberKey(current, $0.signature)
          } ?? []
        name = classes[current]?.superclass
      }
      result[mention] = keys
    }
    return result
  }
}

/// Checks SwifterKit's claims about DriverKit members against Apple's headers and clang's
/// evidence.
enum CoverageAudit {
  /// Returns documentation mentions and exclusions that the headers or the evidence do not
  /// support. Without `evidence`, only the header facts are checked.
  static func problems(
    _ coverage: Coverage,
    documented: [DocumentedMembers.Mention: [CoverageEvidence.MemberKey]],
    exclusions: Set<Coverage.Exclusion>,
    evidence: CoverageEvidence?
  ) -> [String] {
    var methods: [CoverageEvidence.MemberKey: Coverage.Method] = [:]
    for entry in coverage.classes {
      for method in entry.methods {
        methods[CoverageEvidence.MemberKey(entry.name, method.signature)] = method
      }
    }
    var problems: [String] = []
    for (mention, keys) in documented.sorted(by: { $0.key < $1.key }) {
      let name = "`\(mention.className)::\(mention.member)` at \(mention.location)"
      if keys.isEmpty {
        problems.append("\(name) names no member the SDK headers declare")
      } else if let evidence, !keys.contains(where: { evidence.members[$0] != nil }) {
        problems.append("\(name) is documented but the runtime does not reach it")
      }
    }
    for exclusion in exclusions.sorted(by: {
      ($0.className, $0.signature) < ($1.className, $1.signature)
    }) {
      let key = CoverageEvidence.MemberKey(exclusion.className, exclusion.signature)
      let name = "excluded `\(exclusion.className)` `\(exclusion.signature)`"
      guard let method = methods[key] else {
        problems.append("\(name) names no member the SDK headers declare")
        continue
      }
      if method.excludedBy == .apple {
        problems.append("\(name) is already kept from DriverKit clients: \(method.note ?? "")")
      }
      if let evidence, evidence.members[key] != nil {
        problems.append("\(name) is reached by the runtime")
      }
      if let word = provisionalWord(in: exclusion.reason) {
        problems.append("\(name) says \"\(word)\"; describe what SwifterKit does now")
      }
    }
    return problems
  }

  /// Words that describe intent rather than what the sources do, which an exclusion reason
  /// must not use.
  private static let provisionalPattern = #"\b(deferred|planned|not yet|hard|today|TODO)\b"#

  /// Returns the first provisional word in `note`, if any.
  static func provisionalWord(in note: String) -> String? {
    note.range(of: provisionalPattern, options: [.regularExpression, .caseInsensitive]).map {
      String(note[$0])
    }
  }
}
