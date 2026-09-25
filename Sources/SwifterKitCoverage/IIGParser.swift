import Foundation

/// A class declared in a DriverKit `.iig` header.
struct IIGClass: Equatable {
  let name: String
  let superclass: String?
  let isKernel: Bool
  /// Whether the class is a private `class EXTENDS (Base) Name` extension of `superclass`.
  let isExtension: Bool
  let methods: [IIGMethod]
}

/// A member function declared in a DriverKit class.
struct IIGMethod: Equatable {
  enum Access: String, Codable { case `public`, protected, `private` }

  let name: String
  /// The declaration with parameter names removed, used to tell overloads apart.
  let signature: String
  let access: Access
  let isStatic: Bool
  /// IIG annotations such as `LOCAL`, `LOCALONLY`, or `QUEUENAME(Default)`.
  let annotations: [String]
  /// Preprocessor conditions enclosing the declaration.
  let conditions: [String]
}

/// Extracts classes and member functions from `.iig` header text.
enum IIGParser {
  /// Reduces a parameter list to its types, as used in member signatures.
  static func normalizedParameters(_ parameters: String) -> String {
    Scanner.normalized(parameters)
  }

  static func parse(_ text: String) -> [IIGClass] {
    let source = IIGSource(text)
    let scanner = Scanner(source: source)
    return scanner.classes()
  }

  private struct Scanner {
    let characters: [Character]
    let lineOfOffset: [Int]
    let source: IIGSource

    init(source: IIGSource) {
      self.source = source
      var characters: [Character] = []
      var lineOfOffset: [Int] = []
      for (line, text) in source.lines.enumerated() {
        for character in text {
          characters.append(character)
          lineOfOffset.append(line)
        }
        characters.append("\n")
        lineOfOffset.append(line)
      }
      self.characters = characters
      self.lineOfOffset = lineOfOffset
    }

    func classes() -> [IIGClass] {
      var result: [IIGClass] = []
      var index = 0
      while let start = nextKeyword("class", from: index) {
        guard !isTemplateOrEnumClass(at: start), let brace = declarationBrace(from: start) else {
          index = start + 5
          continue
        }
        let head = String(characters[(start + 5)..<brace])
        guard let end = matchingBrace(from: brace) else { break }
        if let declared = Self.classHead(head) {
          let body = members(from: brace + 1, to: end)
          result.append(
            IIGClass(
              name: declared.name,
              superclass: declared.superclass,
              isKernel: declared.isKernel,
              isExtension: declared.isExtension,
              methods: body
            )
          )
        }
        index = end + 1
      }
      return result
    }

    /// Returns whether `class` at `start` is an `enum class` or a template parameter.
    private func isTemplateOrEnumClass(at start: Int) -> Bool {
      var index = start - 1
      while index >= 0, characters[index].isWhitespace { index -= 1 }
      guard index >= 0 else { return false }
      if characters[index] == "<" || characters[index] == "," { return true }
      let end = index + 1
      while index >= 0, characters[index].isIdentifier { index -= 1 }
      return String(characters[(index + 1)..<end]) == "enum"
    }

    /// Returns the `{` that opens a class body, or nil for a forward declaration.
    private func declarationBrace(from start: Int) -> Int? {
      var index = start
      while index < characters.count {
        switch characters[index] {
        case "{": return index
        case ";": return nil
        default: index += 1
        }
      }
      return nil
    }

    private func matchingBrace(from open: Int) -> Int? {
      var depth = 0
      for index in open..<characters.count {
        if characters[index] == "{" { depth += 1 }
        if characters[index] == "}" {
          depth -= 1
          if depth == 0 { return index }
        }
      }
      return nil
    }

    private func nextKeyword(_ keyword: String, from start: Int) -> Int? {
      let pattern = Array(keyword)
      var index = start
      while index + pattern.count <= characters.count {
        if characters[index..<(index + pattern.count)].elementsEqual(pattern),
          index == 0 || !characters[index - 1].isIdentifier,
          index + pattern.count == characters.count
            || !characters[index + pattern.count].isIdentifier
        {
          return index
        }
        index += 1
      }
      return nil
    }

    private static func classHead(
      _ head: String
    ) -> (name: String, superclass: String?, isKernel: Bool, isExtension: Bool)? {
      let text = head.trimmed
      if text.hasPrefix("EXTENDS"), let open = text.firstIndex(of: "("),
        let close = text.firstIndex(of: ")")
      {
        let base = text[text.index(after: open)..<close].trimmed
        let name = text[text.index(after: close)...].trimmed
        guard name.allSatisfy(\.isIdentifier), !name.isEmpty else { return nil }
        return (name, base, false, true)
      }
      let parts = head.split(separator: ":", maxSplits: 1).map(\.trimmed)
      var nameTokens = parts[0].split(whereSeparator: \.isWhitespace).map(String.init)
      nameTokens.removeAll { $0 == "final" }
      let isKernel = nameTokens.first == "KERNEL"
      guard let name = nameTokens.last, name.allSatisfy(\.isIdentifier) else { return nil }
      let superclass =
        parts.count > 1 ? parts[1].split(whereSeparator: \.isWhitespace).last.map(String.init) : nil
      return (name, superclass, isKernel, false)
    }

    /// Splits a class body into top-level statements and keeps the member functions.
    private func members(from start: Int, to end: Int) -> [IIGMethod] {
      var methods: [IIGMethod] = []
      // IIG publishes methods declared before any access specifier through the generated
      // interface (for example IOUserSerial::RxError), so only explicit sections restrict them.
      var access = IIGMethod.Access.public
      var statement = ""
      var statementLine: Int?
      var index = start
      while index < end {
        let character = characters[index]
        if character == "{" {
          guard let close = matchingBrace(from: index) else { break }
          if let method = Self.method(
            statement,
            access: access,
            conditions: conditions(statementLine)
          ) {
            methods.append(method)
          }
          statement = ""
          statementLine = nil
          index = close + 1
          continue
        }
        if character == ";" {
          if let method = Self.method(
            statement,
            access: access,
            conditions: conditions(statementLine)
          ) {
            methods.append(method)
          }
          statement = ""
          statementLine = nil
        } else {
          statement.append(character)
          if statementLine == nil, !character.isWhitespace { statementLine = lineOfOffset[index] }
          if character == ":", let specifier = Self.accessSpecifier(statement) {
            access = specifier
            statement = ""
            statementLine = nil
          }
        }
        index += 1
      }
      return methods
    }

    private func conditions(_ line: Int?) -> [String] { line.map { source.conditions[$0] } ?? [] }

    private static func accessSpecifier(_ statement: String) -> IIGMethod.Access? {
      switch statement.trimmed {
      case "public:": .public
      case "protected:": .protected
      case "private:": .private
      default: nil
      }
    }

    static func method(
      _ statement: String,
      access: IIGMethod.Access,
      conditions: [String]
    ) -> IIGMethod? {
      let text = statement.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      guard let open = text.firstIndex(of: "("),
        !["typedef ", "using ", "friend ", "struct ", "enum ", "class ", "union "].contains(where: {
          text.hasPrefix($0)
        })
      else { return nil }
      let prefix = text[..<open].trimmed
      guard let name = prefix.split(separator: " ").last.map(String.init), let first = name.first,
        first.isLetter || first == "_", name.allSatisfy(\.isIdentifier),
        !name.hasPrefix("OSDeclare")
      else { return nil }
      guard let close = Self.closingParenthesis(in: text, from: open) else { return nil }
      let returnTokens = prefix.split(separator: " ").dropLast().map(String.init)
      let parameters = String(text[text.index(after: open)..<close])
      let trailing = String(text[text.index(after: close)...])
      let isStatic = returnTokens.contains("static")
      let returnType = returnTokens.filter { $0 != "virtual" && $0 != "static" }.joined(
        separator: " "
      ).replacingOccurrences(of: " *", with: "*")
      let signature =
        "\(returnType.isEmpty ? "" : returnType + " ")\(name)(\(normalized(parameters)))"
        + qualifiers(trailing)
      return IIGMethod(
        name: name,
        signature: signature,
        access: access,
        isStatic: isStatic,
        annotations: annotations(trailing),
        conditions: conditions
      )
    }

    private static func closingParenthesis(
      in text: String,
      from open: String.Index
    ) -> String.Index? {
      var depth = 0
      var index = open
      while index < text.endIndex {
        if text[index] == "(" { depth += 1 }
        if text[index] == ")" {
          depth -= 1
          if depth == 0 { return index }
        }
        index = text.index(after: index)
      }
      return nil
    }

    /// Normalizes parameters to their types so renamed parameters keep the same key.
    static func normalized(_ parameters: String) -> String {
      splitTopLevel(parameters).map(parameterType).filter { !$0.isEmpty && $0 != "void" }.joined(
        separator: ", "
      )
    }

    private static func parameterType(_ parameter: String) -> String {
      var text = parameter.trimmed
      if let equals = text.firstIndex(of: "=") { text = text[..<equals].trimmed }
      text = text.replacingOccurrences(of: "*", with: " * ").replacingOccurrences(
        of: "&",
        with: " & "
      )
      var tokens = text.split(separator: " ").map(String.init)
      tokens.removeAll { $0 == "TARGET" }
      tokens = tokens.filter { !($0.hasPrefix("TYPE(") || $0.hasPrefix("QUEUENAME(")) }
      var suffix = ""
      if let last = tokens.last, let bracket = last.firstIndex(of: "[") {
        suffix = String(last[bracket...])
        tokens[tokens.count - 1] = String(last[..<bracket])
      }
      let keywords: Set = ["const", "volatile", "unsigned", "signed", "long", "short", "struct"]
      if tokens.count > 1, let last = tokens.last, last.allSatisfy(\.isIdentifier),
        !keywords.contains(last), tokens[tokens.count - 2] != "struct"
      {
        tokens.removeLast()
      }
      return (tokens.joined(separator: " ") + suffix).replacingOccurrences(of: " * ", with: " *")
        .replacingOccurrences(of: " *", with: "*").trimmed
    }

    private static func splitTopLevel(_ text: String) -> [String] {
      var parts: [String] = []
      var current = ""
      var depth = 0
      for character in text {
        if character == "(" || character == "[" || character == "<" { depth += 1 }
        if character == ")" || character == "]" || character == ">" { depth -= 1 }
        if character == ",", depth == 0 {
          parts.append(current)
          current = ""
        } else {
          current.append(character)
        }
      }
      parts.append(current)
      return parts
    }

    private static func qualifiers(_ trailing: String) -> String {
      let tokens = trailing.split(separator: " ")
      return tokens.contains("const") ? " const" : ""
    }

    private static func annotations(_ trailing: String) -> [String] {
      let ignored: Set = ["const", "override", "final", "=", "0", "=0"]
      return trailing.replacingOccurrences(of: "= 0", with: "").split(separator: " ").map(
        String.init
      ).filter { !ignored.contains($0) }
    }
  }
}

private extension Character { var isIdentifier: Bool { isLetter || isNumber || self == "_" } }
