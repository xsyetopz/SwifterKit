import Foundation

/// A DriverKit member that SwifterKit's native sources call or override, as clang resolved it.
struct NativeUse: Hashable, Comparable {
  enum Kind: String { case call, override }

  /// The class that declares the called member, or the base class of the SwifterKit class that
  /// overrides it. The base is read per translation unit, because a renamed runtime class's base
  /// depends on the extension's role.
  let className: String
  let method: String
  /// Normalized parameter types, or `nil` for an IIG `Name_Impl` override, whose parameters are
  /// the IIG argument structure.
  let parameters: [String]?
  let kind: Kind
  /// The source file name, without directories.
  let file: String
  /// The function whose body contains the use.
  let function: String
  /// The class of the object a call goes through, with SwifterKit's classes replaced by their
  /// DriverKit base, or `nil` when the call names no object. IIG declares an override only as
  /// `Name_Impl`, so clang names the base's declaration even when the object's class overrides it.
  var receiver: String?
  /// Whether the call goes through a pointer whose class is a DriverKit class, so the object can
  /// be of any subclass and the call reaches that subclass's override.
  var dispatched = false

  /// Where the use is, as `File: Class::function`.
  var evidence: String { "\(file): \(function)" }

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.className, lhs.method, lhs.file, lhs.function, lhs.kind.rawValue) < (
      rhs.className, rhs.method, rhs.file, rhs.function, rhs.kind.rawValue
    )
  }
}

/// Reads the uses of DriverKit members from clang's JSON AST dump of one translation unit.
///
/// Clang omits a location's file and line when they match the previously written location, so
/// locations are read in the order clang writes them: `loc`, `range.begin`, `range.end`, then
/// `inner`, with a macro location's spelling before its expansion.
struct ClangAST {
  private(set) var uses: [NativeUse] = []
  /// The first base class of every class definition in the translation unit.
  private(set) var bases: [String: String] = [:]

  private struct MethodDecl {
    let owner: String
    let name: String
    let type: String
    /// Whether a call reaches the object's override: the member is virtual, or IIG declares it
    /// with a trailing `OSDispatchMethod` and sends it to the object's implementation.
    let dispatches: Bool
  }

  private struct Reference {
    let declaration: String
    /// The type of the object the call goes through, resolved once the whole unit is read,
    /// because a template can name a class's member alias declared after it.
    let receiverType: String?
    let file: String
    let function: String
  }

  private let isSource: (String) -> Bool
  private let isTree: (String) -> Bool
  private var file = ""
  private var records: [String: String] = [:]
  /// The classes defined, not only declared, in the tree.
  private var sourceRecords: Set<String> = []
  /// Type aliases declared in classes, keyed `Class::Alias`, and the types they name.
  private var aliases: [String: String] = [:]
  private var methods: [String: MethodDecl] = [:]
  private var overriding: Set<String> = []
  private var references: [Reference] = []

  /// Parses `json`, keeping uses located in files for which `isSource` returns `true`. Classes
  /// defined in files for which `isTree` returns `true` are SwifterKit's own, as are those in
  /// source files; IIG writes a class's definition outside the sources.
  init(json: Data, isTree: ((String) -> Bool)? = nil, isSource: @escaping (String) -> Bool) throws {
    self.isSource = isSource
    self.isTree = isTree ?? isSource
    guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
      throw CocoaError(.coderReadCorrupt)
    }
    visit(root, record: nil, function: nil)
    for reference in references {
      guard let method = methods[reference.declaration] else { continue }
      let receiver = reference.receiverType.flatMap { className(ofType: $0) }
      var use = NativeUse(
        className: method.owner,
        method: method.name,
        parameters: Self.parameters(ofType: method.type),
        kind: .call,
        file: URL(fileURLWithPath: reference.file).lastPathComponent,
        function: reference.function,
        receiver: receiver.map(driverKitClass)
      )
      use.dispatched = method.dispatches && receiver.map { !sourceRecords.contains($0) } == true
      uses.append(use)
    }
  }

  /// `name`, or for a class defined in a source file, its nearest base that is not.
  private func driverKitClass(_ name: String) -> String {
    var name = name
    var visited: Set<String> = []
    while sourceRecords.contains(name), visited.insert(name).inserted, let base = bases[name] {
      name = base
    }
    return name
  }

  private mutating func visit(_ node: [String: Any], record: String?, function: String?) {
    let kind = node["kind"] as? String ?? ""
    let location = (node["loc"] as? [String: Any]).map { consume($0) }
    var end: String?
    if let range = node["range"] as? [String: Any] {
      if let begin = range["begin"] as? [String: Any] { consume(begin) }
      if let last = range["end"] as? [String: Any] { end = consume(last) }
    }
    // Clang writes the elements of an array initializer with a filler under `array_filler`.
    let inner = (node["inner"] ?? node["array_filler"]) as? [[String: Any]] ?? []
    let id = node["id"] as? String ?? ""
    var record = record
    var function = function
    switch kind {
    case "CXXRecordDecl":
      guard let name = node["name"] as? String else { break }
      records[id] = name
      record = name
      // The sources forward-declare DriverKit classes; only a definition makes a class theirs.
      if let location, isTree(location), node["completeDefinition"] as? Bool == true {
        sourceRecords.insert(name)
      }
      let base = (node["bases"] as? [[String: Any]])?.first?["type"] as? [String: Any]
      if let base = base?["qualType"] as? String { bases[name] = base }
    case "TypeAliasDecl", "TypedefDecl":
      if let record, let name = node["name"] as? String,
        let type = (node["type"] as? [String: Any])?["qualType"] as? String
      {
        aliases["\(record)::\(name)"] = type
      }
    case "CXXMethodDecl", "CXXConstructorDecl", "CXXDestructorDecl", "FunctionDecl":
      let name = node["name"] as? String ?? ""
      let owner = (node["parentDeclContextId"] as? String).flatMap { records[$0] } ?? record
      let type = (node["type"] as? [String: Any])?["qualType"] as? String ?? ""
      if kind != "FunctionDecl", let owner {
        let overrides = inner.contains { $0["kind"] as? String == "OverrideAttr" }
        let virtual = node["virtual"] as? Bool == true || overrides
        methods[id] = MethodDecl(
          owner: owner,
          name: name,
          type: type,
          dispatches: virtual || Self.isIIGMethod(type)
        )
        if overrides { overriding.insert(id) }
      }
      guard let location, isSource(location),
        inner.contains(where: { $0["kind"] as? String == "CompoundStmt" })
      else { break }
      let body = owner.map { "\($0)::\(name)" } ?? name
      function = body
      guard kind == "CXXMethodDecl", let owner else { break }
      let previous = node["previousDecl"] as? String
      if name.hasSuffix("_Impl") {
        appendOverride(owner, String(name.dropLast("_Impl".count)), nil, location, body)
      } else if overriding.contains(id) || previous.map(overriding.contains) == true {
        appendOverride(owner, name, Self.parameters(ofType: type), location, body)
      }
    case "MemberExpr", "DeclRefExpr":
      let declaration =
        node["referencedMemberDecl"] as? String ?? (node["referencedDecl"] as? [String: Any])?["id"]
        as? String
      if let declaration, let end, isSource(end), let function {
        // Clang converts a derived receiver to the declaring base before the call; the object's
        // own class sits beneath that conversion.
        var receiver = inner.first
        while let cast = receiver, cast["castKind"] as? String == "UncheckedDerivedToBase" {
          receiver = (cast["inner"] as? [[String: Any]])?.first
        }
        let object = (receiver?["type"] as? [String: Any])?["qualType"] as? String
        references.append(
          Reference(
            declaration: declaration,
            receiverType: kind == "MemberExpr" ? object : nil,
            file: end,
            function: function
          )
        )
      }
    default: break
    }
    for child in inner { visit(child, record: record, function: function) }
  }

  private mutating func appendOverride(
    _ owner: String,
    _ method: String,
    _ parameters: [String]?,
    _ file: String,
    _ function: String
  ) {
    uses.append(
      NativeUse(
        className: bases[owner] ?? owner,
        method: method,
        parameters: parameters,
        kind: .override,
        file: URL(fileURLWithPath: file).lastPathComponent,
        function: function
      )
    )
  }

  /// Reads one source location and returns the file of its expansion. Only the file matters,
  /// because evidence names functions rather than lines that move with every edit.
  @discardableResult
  private mutating func consume(_ location: [String: Any]) -> String {
    if let spelling = location["spellingLoc"] as? [String: Any] { consume(spelling) }
    if let expansion = location["expansionLoc"] as? [String: Any] { return consume(expansion) }
    if let file = location["file"] as? String { self.file = file }
    return file
  }

  /// The class an object or pointer type names, as in `const IOTimerDispatchSource *`, or as a
  /// template's `typename Family::Object *` names through the class's member alias.
  /// A template's alias can name itself, as `typename Family::State` does, so `visited` stops at
  /// an alias already followed.
  private func className(ofType type: String, visited: Set<String> = []) -> String? {
    let words = type.split { $0.isWhitespace || $0 == "*" || $0 == "&" }.filter {
      !["const", "volatile", "struct", "class"].contains($0)
    }
    if words.count == 2, words[0] == "typename" {
      let path = words[1].components(separatedBy: "::").suffix(2).joined(separator: "::")
      guard !visited.contains(path), let alias = aliases[path] else { return nil }
      return className(ofType: alias, visited: visited.union([path]))
    }
    guard words.count == 1, let name = words[0].split(separator: ":").last,
      name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
    else { return nil }
    return String(name)
  }

  /// The normalized parameter types of a function type or member signature, without IIG's
  /// trailing `OSDispatchMethod` dispatch parameter.
  static func parameters(ofType type: String) -> [String] {
    var text = Substring(type.trimmingCharacters(in: .whitespaces))
    // A trailing return type, as in `auto (uint64_t) -> kern_return_t`, follows the parameters.
    var level = 0
    for index in text.indices {
      if text[index] == "(" { level += 1 }
      if text[index] == ")" { level -= 1 }
      if level == 0, text[index...].hasPrefix(" -> ") {
        text = text[..<index]
        break
      }
    }
    for suffix in [" const", " noexcept", " override"] where text.hasSuffix(suffix) {
      text = text.dropLast(suffix.count)
    }
    guard text.last == ")" else { return [] }
    var depth = 0
    var open = text.endIndex
    for index in text.indices.reversed() {
      if text[index] == ")" { depth += 1 }
      if text[index] == "(" { depth -= 1 }
      if depth == 0 {
        open = index
        break
      }
    }
    guard open < text.endIndex else { return [] }
    var parameters: [String] = []
    var current = ""
    depth = 0
    for character in text[text.index(after: open)..<text.index(before: text.endIndex)] {
      if "(<[".contains(character) { depth += 1 }
      if ")>]".contains(character) { depth -= 1 }
      if character == ",", depth == 0 {
        parameters.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    parameters.append(current)
    let normalized = parameters.map(normalized).filter { !$0.isEmpty && $0 != "void" }
    return normalized.last == "OSDispatchMethod" ? normalized.dropLast() : normalized
  }

  /// Whether a member's function type ends with IIG's `OSDispatchMethod` dispatch parameter.
  private static func isIIGMethod(_ type: String) -> Bool {
    var parameters = type
    if let close = parameters.lastIndex(of: ")") { parameters = String(parameters[..<close]) }
    return parameters.hasSuffix("OSDispatchMethod")
  }

  private static func normalized(_ parameter: String) -> String {
    var words = parameter.split(whereSeparator: \.isWhitespace).map(String.init)
    words.removeAll { ["struct", "class", "enum"].contains($0) }
    return words.joined()
  }
}
