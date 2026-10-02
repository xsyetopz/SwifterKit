import Foundation

/// How SwifterKit handles one DriverKit member function.
enum CoverageStatus: CaseIterable, Comparable {
  /// Public in the header and not reachable from Swift.
  case gap
  /// Called or overridden by the generated extension runtime.
  case generated
  /// Reached by the runtime on behalf of a Swift API whose documentation names the member.
  case swiftAPI
  /// Not reachable from Swift. `excludedBy` says whose decision that is and `note` gives the
  /// reason.
  case excluded
}

/// Who keeps an excluded member out of Swift's reach.
enum ExclusionSource {
  /// Apple's header keeps the member from DriverKit clients, as the note quotes.
  case apple
  /// SwifterKit chose not to expose a member that DriverKit clients can use.
  case swifterkit
}

/// Every DriverKit class and member function that the given SDKs declare, and how SwifterKit
/// handles each one. Built anew on every run from Apple's headers, clang's evidence, and the
/// Swift sources; nothing here is stored.
struct Coverage: Equatable {
  struct Method: Equatable {
    var signature: String
    var name: String
    var access: IIGMethod.Access
    var conditions: [String]
    /// SDK versions that declare this member.
    var sdks: [String]
    var status: CoverageStatus = .gap
    var note: String?
    /// `File: Class::function` for each runtime function that clang shows calling or
    /// overriding the member.
    var evidence: [String]?
    var excludedBy: ExclusionSource?
  }

  struct Class: Equatable {
    var framework: String
    var name: String
    var superclass: String?
    var isExtension: Bool
    var methods: [Method]
  }

  /// A member that SwifterKit chose not to expose, and why.
  struct Exclusion: Hashable {
    let className: String
    let signature: String
    let reason: String
  }

  /// The SDK versions the coverage was read from, oldest first.
  var sdks: [String] = []
  var classes: [Class] = []

  /// Reads the members every surface declares. Members a header keeps from DriverKit clients
  /// start excluded by Apple and all others start as gaps.
  init(_ surfaces: [SDKSurface]) {
    var byClass: [String: Class] = [:]
    for surface in surfaces.sorted(by: { compareVersions($0.version, $1.version) }) {
      for declared in surface.classes {
        let declaration = declared.declaration
        let classKey = "\(declared.framework)/\(declaration.name)"
        var entry =
          byClass[classKey]
          ?? Class(
            framework: declared.framework,
            name: declaration.name,
            superclass: nil,
            isExtension: declaration.isExtension,
            methods: []
          )
        entry.superclass = declaration.superclass
        for method in declaration.methods {
          if let index = entry.methods.firstIndex(where: { $0.signature == method.signature }) {
            entry.methods[index].sdks.append(surface.version)
            // Surfaces are read oldest first, so the newest SDK's declaration wins.
            entry.methods[index].access = method.access
            entry.methods[index].conditions = method.conditions
          } else {
            entry.methods.append(
              Method(
                signature: method.signature,
                name: method.name,
                access: method.access,
                conditions: method.conditions,
                sdks: [surface.version]
              )
            )
          }
        }
        byClass[classKey] = entry
      }
    }
    sdks = Set(surfaces.map(\.version)).sorted(by: compareVersions)
    classes = byClass.values.map { entry in
      var entry = entry
      entry.methods = entry.methods.map { method in
        var method = method
        let reason =
          entry.isExtension
          ? "private class extension in the SDK header" : Self.headerReason(method)
        if let reason {
          method.status = .excluded
          method.excludedBy = .apple
          method.note = reason
        }
        return method
      }.sorted { $0.signature < $1.signature }
      return entry
    }.sorted { ($0.framework, $0.name) < ($1.framework, $1.name) }
  }

  /// The header text that keeps a declaration from DriverKit clients, if any.
  static func headerReason(_ method: Method) -> String? {
    if method.access == .private { return "declared private in the SDK header" }
    let excluded: Set = [
      "KERNEL", "defined(KERNEL)", "0", "!(TARGET_OS_DRIVERKIT)", "!defined(TARGET_OS_DRIVERKIT)",
    ]
    for condition in method.conditions
    where excluded.contains(condition)
      || (condition.contains("PRIVATE") && !condition.hasPrefix("!"))
    { return "compiled only under #if \(condition) in the SDK header" }
    return nil
  }

  /// The coverage with each public member's status decided by `evidence`, the `Class::member`
  /// names in Swift documentation, and SwifterKit's exclusions.
  ///
  /// A member the runtime reaches is `swiftAPI` when the documentation names it and `generated`
  /// otherwise. An exclusion applies only to a public member the runtime does not reach.
  func applying(
    _ evidence: CoverageEvidence,
    documented: Set<CoverageEvidence.MemberKey> = [],
    exclusions: Set<Exclusion> = []
  ) -> Self {
    let reasons = Dictionary(
      exclusions.map { (CoverageEvidence.MemberKey($0.className, $0.signature), $0.reason) }
    ) { first, _ in first }
    var result = self
    for classIndex in result.classes.indices {
      let className = result.classes[classIndex].name
      for methodIndex in result.classes[classIndex].methods.indices {
        var method = result.classes[classIndex].methods[methodIndex]
        guard method.excludedBy != .apple else { continue }
        let key = CoverageEvidence.MemberKey(className, method.signature)
        method.evidence = evidence.members[key].map { $0.sorted() }
        method.note = nil
        method.excludedBy = nil
        if method.evidence != nil {
          method.status = documented.contains(key) ? .swiftAPI : .generated
        } else if let reason = reasons[key] {
          method.status = .excluded
          method.excludedBy = .swifterkit
          method.note = reason
        } else {
          method.status = .gap
        }
        result.classes[classIndex].methods[methodIndex] = method
      }
    }
    return result
  }
}

/// Orders SDK versions numerically, such as 24.4 before 25.5.
func compareVersions(_ lhs: String, _ rhs: String) -> Bool {
  let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
  let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
  return left.lexicographicallyPrecedes(right)
}
