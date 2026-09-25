import Foundation

/// How SwifterKit handles one DriverKit member function.
enum CoverageStatus: String, Codable, CaseIterable, Comparable {
  /// Not yet reachable from Swift.
  case gap
  /// Called or overridden by the generated extension runtime.
  case generated
  /// Exposed through a typed Swift API, named by `swiftSymbol`.
  case swiftAPI = "swift-api"
  /// Declarable through the native fast path.
  case fastPath = "fast-path"
  /// Deliberately out of scope; `note` gives the reason.
  case excluded

  static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

/// The checked-in record of every DriverKit class and member function and its coverage.
struct CoverageManifest: Codable, Equatable {
  struct Method: Codable, Equatable {
    var signature: String
    var name: String
    var access: IIGMethod.Access
    var annotations: [String]
    var conditions: [String]
    /// The DriverKit version from the header's availability attribute, when it has one.
    var introduced: String?
    /// The DriverKit version that deprecated the member, when the header says so.
    var deprecated: String?
    /// SDK versions that declare this member.
    var sdks: [String]
    var status: CoverageStatus
    var swiftSymbol: String?
    var note: String?
  }

  struct Class: Codable, Equatable {
    var framework: String
    var name: String
    var superclass: String?
    var kernel: Bool
    var isExtension: Bool
    var sdks: [String]
    var methods: [Method]
  }

  var schemaVersion = 1
  /// SDK versions the manifest has been reconciled against.
  var sdks: [String] = []
  var classes: [Class] = []

  /// Reconciles the manifest with the surfaces of the given SDKs.
  ///
  /// Members keep their status. New members start as gaps unless an exclusion rule applies, and
  /// members no longer declared by any SDK are removed.
  func merging(_ surfaces: [SDKSurface]) -> Self {
    let versions = Set(surfaces.map(\.version))
    var byClass: [String: Class] = [:]
    for var entry in classes {
      entry.sdks.removeAll(where: versions.contains)
      entry.methods = entry.methods.map { method in
        var method = method
        method.sdks.removeAll(where: versions.contains)
        return method
      }
      byClass[key(entry.framework, entry.name)] = entry
    }

    for surface in surfaces.sorted(by: { compareVersions($0.version, $1.version) }) {
      for declared in surface.classes {
        let classKey = key(declared.framework, declared.declaration.name)
        var entry =
          byClass[classKey]
          ?? Class(
            framework: declared.framework,
            name: declared.declaration.name,
            superclass: declared.declaration.superclass,
            kernel: declared.declaration.isKernel,
            isExtension: declared.declaration.isExtension,
            sdks: [],
            methods: []
          )
        entry.superclass = declared.declaration.superclass
        entry.kernel = declared.declaration.isKernel
        entry.sdks = Self.adding(surface.version, to: entry.sdks)
        for method in declared.declaration.methods {
          if let index = entry.methods.firstIndex(where: { $0.signature == method.signature }) {
            entry.methods[index].sdks = Self.adding(surface.version, to: entry.methods[index].sdks)
            // Surfaces are merged oldest first, so the newest SDK's declaration wins.
            entry.methods[index].access = method.access
            entry.methods[index].annotations = method.annotations
            entry.methods[index].conditions = method.conditions
            entry.methods[index].introduced = method.introduced
            entry.methods[index].deprecated = method.deprecated
          } else {
            entry.methods.append(
              Self.newEntry(method, isExtension: entry.isExtension, version: surface.version)
            )
          }
        }
        byClass[classKey] = entry
      }
    }

    var merged = self
    merged.sdks = sdks.reduce(into: Array(versions)) { result, version in
      if !result.contains(version) { result.append(version) }
    }.sorted(by: compareVersions)
    merged.classes = byClass.values.compactMap { entry in
      var entry = entry
      entry.methods = entry.methods.filter { !$0.sdks.isEmpty }.sorted {
        $0.signature < $1.signature
      }
      return entry.sdks.isEmpty ? nil : entry
    }.sorted { key($0.framework, $0.name) < key($1.framework, $1.name) }
    return merged
  }

  private func key(_ framework: String, _ name: String) -> String { "\(framework)/\(name)" }

  private static func adding(_ version: String, to versions: [String]) -> [String] {
    (versions.contains(version) ? versions : versions + [version]).sorted(by: compareVersions)
  }

  private static func newEntry(_ method: IIGMethod, isExtension: Bool, version: String) -> Method {
    let reason =
      isExtension
      ? "private class extension; framework implementation detail" : exclusionReason(method)
    return Method(
      signature: method.signature,
      name: method.name,
      access: method.access,
      annotations: method.annotations,
      conditions: method.conditions,
      introduced: method.introduced,
      deprecated: method.deprecated,
      sdks: [version],
      status: reason == nil ? .gap : .excluded,
      swiftSymbol: nil,
      note: reason
    )
  }

  /// Declarations that DriverKit clients cannot call or override.
  static func exclusionReason(_ method: IIGMethod) -> String? {
    if method.access == .private { return "private member" }
    if method.signature.hasSuffix(" init()") || method.signature.hasSuffix(" free()") {
      return "OSObject lifecycle hook; the generated runtime owns object lifetime"
    }
    let excluded: Set = [
      "KERNEL", "defined(KERNEL)", "0", "!(TARGET_OS_DRIVERKIT)", "!defined(TARGET_OS_DRIVERKIT)",
    ]
    for condition in method.conditions
    where excluded.contains(condition)
      || (condition.contains("PRIVATE") && !condition.hasPrefix("!"))
    { return "compiled only under #if \(condition)" }
    return nil
  }
}

extension CoverageManifest {
  static func load(from url: URL) throws -> Self {
    guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
    return try decoded(Data(contentsOf: url))
  }

  static func decoded(_ data: Data) throws -> Self {
    try JSONDecoder().decode(Self.self, from: data)
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(self)
    data.append(0x0A)
    return data
  }
}
