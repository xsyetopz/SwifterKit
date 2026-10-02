import Foundation

/// Assigns clang-resolved native uses to the members the SDK headers declare.
struct CoverageEvidence {
  /// The evidence for each member, keyed by `MemberKey`.
  private(set) var members: [MemberKey: Set<String>] = [:]
  /// Uses of DriverKit classes that match no member, such as calls the IIG headers do not
  /// declare. SwifterKit's own classes are not listed.
  private(set) var unresolved: Set<NativeUse> = []

  struct MemberKey: Hashable, Comparable {
    let className: String
    let signature: String

    init(_ className: String, _ signature: String) {
      self.className = className
      self.signature = signature
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.className, lhs.signature) < (rhs.className, rhs.signature)
    }
  }

  init(coverage: Coverage, native: NativeEvidence) {
    let classes = Dictionary(coverage.classes.map { ($0.name, $0) }) { first, _ in first }
    // The DriverKit classes whose objects the runtime holds: those it calls members of or
    // through, and the bases of the classes it defines.
    let held = Set(native.uses.flatMap { [$0.className] + ($0.receiver.map { [$0] } ?? []) })
    for use in native.uses {
      let receiver = use.receiver.flatMap { classes[$0] == nil ? nil : $0 }
      let starts =
        (receiver.map { [$0] } ?? []) + Self.declaringClasses(use.className, classes: classes)
      let key = starts.lazy.compactMap {
        Self.resolve(use, from: $0, classes: classes, bases: native.bases)
      }.first
      if let key {
        members[key, default: []].insert(use.evidence)
        if use.kind == .override {
          for overridden in Self.overridden(key, named: use.method, classes: classes) {
            members[overridden, default: []].insert(use.evidence)
          }
        }
        if use.dispatched, let receiver {
          let overrides = Self.overrides(
            of: key,
            named: use.method,
            below: receiver,
            held: held,
            classes: classes
          )
          for override in overrides { members[override, default: []].insert(use.evidence) }
        }
      } else if classes[use.className] != nil || use.kind == .override {
        unresolved.insert(use)
      }
    }
  }

  /// The overrides of `key` that classes below `receiver` declare, for the classes in `held`.
  /// A call through a `receiver` pointer reaches the override of the object's class.
  private static func overrides(
    of key: MemberKey,
    named name: String,
    below receiver: String,
    held: Set<String>,
    classes: [String: Coverage.Class]
  ) -> [MemberKey] {
    let parameters = ClangAST.parameters(ofType: key.signature)
    return held.sorted().flatMap { className -> [MemberKey] in
      guard className != receiver, let entry = classes[className] else { return [] }
      var ancestor = entry.superclass
      var visited: Set<String> = []
      while let current = ancestor, current != receiver, visited.insert(current).inserted {
        ancestor = classes[current]?.superclass
      }
      guard ancestor == receiver else { return [] }
      return entry.methods.filter {
        $0.name == name && ClangAST.parameters(ofType: $0.signature) == parameters
      }.map { MemberKey(className, $0.signature) }
    }
  }

  /// The declarations above `key` that it overrides: the members of its superclasses with its
  /// name and parameters. An override of `key` overrides each of them, as an override of
  /// `IOUserHIDEventService::SetProperties` overrides `IOHIDEventService::SetProperties`.
  private static func overridden(
    _ key: MemberKey,
    named name: String,
    classes: [String: Coverage.Class]
  ) -> [MemberKey] {
    let parameters = ClangAST.parameters(ofType: key.signature)
    var result: [MemberKey] = []
    var className = classes[key.className]?.superclass
    var visited: Set<String> = [key.className]
    while let current = className, visited.insert(current).inserted {
      for method in classes[current]?.methods ?? []
      where method.name == name && ClangAST.parameters(ofType: method.signature) == parameters {
        result.append(MemberKey(current, method.signature))
      }
      className = classes[current]?.superclass
    }
    return result
  }

  /// The classes to resolve a use attributed to `name` from. IIG declares the methods of a
  /// `LOCALONLY` class again on a generated `<Class>Interface` base, and clang resolves calls
  /// through a pointer to the class to that declaration, so `<Class>` follows `name`.
  private static func declaringClasses(
    _ name: String,
    classes: [String: Coverage.Class]
  ) -> [String] {
    guard name.hasSuffix("Interface") else { return [name] }
    let declaring = String(name.dropLast("Interface".count))
    return classes[declaring] == nil ? [name] : [name, declaring]
  }

  /// The member `use` reaches: the nearest class, starting at `start`, that declares the
  /// method, and the overload whose parameters match.
  private static func resolve(
    _ use: NativeUse,
    from start: String,
    classes: [String: Coverage.Class],
    bases: [String: String]
  ) -> MemberKey? {
    var className: String? = start
    var visited: Set<String> = []
    while let name = className, visited.insert(name).inserted {
      let candidates = classes[name]?.methods.filter { $0.name == use.method } ?? []
      if !candidates.isEmpty {
        return overload(of: use, in: candidates).map { MemberKey(name, $0.signature) }
      }
      className = classes[name]?.superclass ?? bases[name]
    }
    return nil
  }

  /// The candidate whose parameters match `use`, or the only candidate with as many parameters.
  /// An IIG override has no C++ parameters to compare, so it needs a single candidate.
  private static func overload(
    of use: NativeUse,
    in candidates: [Coverage.Method]
  ) -> Coverage.Method? {
    guard let parameters = use.parameters else {
      return candidates.count == 1 ? candidates[0] : nil
    }
    let typed = candidates.map { ($0, ClangAST.parameters(ofType: $0.signature)) }
    let exact = typed.filter { $0.1 == parameters }
    if exact.count == 1 { return exact[0].0 }
    let counted = typed.filter { $0.1.count == parameters.count }
    return counted.count == 1 ? counted[0].0 : nil
  }
}
