import Foundation

/// Identifiers used by SwifterKit's sources, as evidence for coverage claims.
struct SourceIndex {
  /// Identifiers anywhere in the sources.
  private(set) var words: Set<String> = []
  /// Identifiers called or defined as functions, including `Name_Impl` overrides as `Name`.
  private(set) var functions: Set<String> = []

  init(directories: [URL], extensions: Set<String>) throws {
    let fileManager = FileManager.default
    for directory in directories {
      guard let files = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
      else { continue }
      for case let file as URL in files where extensions.contains(file.pathExtension) {
        index(try String(contentsOf: file, encoding: .utf8))
      }
    }
  }

  init(text: String) { index(text) }

  private mutating func index(_ text: String) {
    let characters = Array(text.unicodeScalars)
    var index = 0
    while index < characters.count {
      guard characters[index].isIdentifierStart else {
        index += 1
        continue
      }
      let start = index
      while index < characters.count, characters[index].isIdentifierPart { index += 1 }
      let word = String(String.UnicodeScalarView(characters[start..<index]))
      words.insert(word)
      var next = index
      while next < characters.count, characters[next] == " " { next += 1 }
      if next < characters.count, characters[next] == "(" { functions.insert(word) }
      if word.hasSuffix("_Impl") { functions.insert(String(word.dropLast("_Impl".count))) }
    }
  }

  /// Returns whether the sources name `className` and call or implement `method`.
  func references(className: String, method: String) -> Bool {
    words.contains(className) && functions.contains(method)
  }
}

/// Compares the manifest with SDK surfaces and SwifterKit's sources.
struct CoverageAudit {
  let manifest: CoverageManifest
  let native: SourceIndex
  let swift: SourceIndex

  /// Marks gaps that the generated runtime already references as `generated`.
  ///
  /// Overloaded names stay gaps because a name match cannot tell which overload is used.
  func inferringGenerated() -> CoverageManifest {
    var result = manifest
    for classIndex in result.classes.indices {
      let className = result.classes[classIndex].name
      let names = result.classes[classIndex].methods.map(\.name)
      for methodIndex in result.classes[classIndex].methods.indices {
        let method = result.classes[classIndex].methods[methodIndex]
        let isOverloaded = names.filter { $0 == method.name }.count > 1
        if method.status == .gap, !isOverloaded,
          native.references(className: className, method: method.name)
        {
          result.classes[classIndex].methods[methodIndex].status = .generated
          result.classes[classIndex].methods[methodIndex].note =
            "referenced by the generated runtime"
        }
      }
    }
    return result
  }

  /// Returns claims that the sources do not support.
  func problems() -> [String] {
    var problems: [String] = []
    for entry in manifest.classes {
      for method in entry.methods {
        let symbol = "\(entry.framework)/\(entry.name)::\(method.signature)"
        switch method.status {
        case .gap: break
        case .generated:
          if !native.references(className: entry.name, method: method.name) {
            problems.append("\(symbol) is marked generated but the runtime does not reference it")
          }
        case .swiftAPI:
          if let swiftSymbol = method.swiftSymbol, swift.words.contains(swiftSymbol) { break }
          problems.append("\(symbol) is marked swift-api without a Swift symbol in Sources")
        case .fastPath, .excluded:
          if method.note?.trimmed.isEmpty ?? true {
            problems.append("\(symbol) is marked \(method.status.rawValue) without a note")
          }
        }
      }
    }
    return problems
  }

  /// Describes members that `merging` would add or remove.
  static func drift(from manifest: CoverageManifest, to merged: CoverageManifest) -> [String] {
    func symbols(_ manifest: CoverageManifest) -> [String: [String]] {
      var result: [String: [String]] = [:]
      for entry in manifest.classes {
        for method in entry.methods {
          result["\(entry.framework)/\(entry.name)::\(method.signature)"] = method.sdks
        }
      }
      return result
    }
    let before = symbols(manifest)
    let after = symbols(merged)
    var drift: [String] = []
    for (symbol, sdks) in after.sorted(by: { $0.key < $1.key }) where before[symbol] != sdks {
      drift.append(before[symbol] == nil ? "new: \(symbol)" : "changed SDKs: \(symbol)")
    }
    for symbol in before.keys.sorted() where after[symbol] == nil {
      drift.append("removed: \(symbol)")
    }
    return drift
  }

  /// Per-framework counts of each status.
  static func summary(_ manifest: CoverageManifest) -> String {
    var counts: [String: [CoverageStatus: Int]] = [:]
    for entry in manifest.classes {
      for method in entry.methods {
        counts[entry.framework, default: [:]][method.status, default: 0] += 1
      }
    }
    let statuses = CoverageStatus.allCases
    var lines = ["framework | " + statuses.map(\.rawValue).joined(separator: " | ") + " | covered"]
    var totals: [CoverageStatus: Int] = [:]
    for framework in counts.keys.sorted() {
      let row = counts[framework, default: [:]]
      for (status, count) in row { totals[status, default: 0] += count }
      lines.append(line(framework, row, statuses))
    }
    lines.append(line("total", totals, statuses))
    return lines.joined(separator: "\n")
  }

  private static func line(
    _ name: String,
    _ row: [CoverageStatus: Int],
    _ statuses: [CoverageStatus]
  ) -> String {
    let inScope = statuses.filter { $0 != .excluded }.reduce(0) { $0 + row[$1, default: 0] }
    let covered = inScope - row[.gap, default: 0]
    let percent = inScope == 0 ? 100 : covered * 100 / inScope
    let counts = statuses.map { String(row[$0, default: 0]) }.joined(separator: " | ")
    return "\(name) | \(counts) | \(covered)/\(inScope) (\(percent)%)"
  }
}

private extension Unicode.Scalar {
  var isIdentifierStart: Bool { properties.isAlphabetic && isASCII || self == "_" }

  var isIdentifierPart: Bool { isIdentifierStart || ("0"..."9").contains(self) }
}
