import Foundation

/// A header reduced to declaration text, with the preprocessor conditions active on each line.
///
/// Comments and `@iig implementation` blocks are removed, and preprocessor directives are
/// replaced by empty lines, so line numbers match the original header.
struct IIGSource: Equatable {
  /// Declaration text without comments or directives.
  let lines: [String]
  /// The conditions enclosing each line, outermost first; include guards are omitted.
  let conditions: [[String]]

  init(_ text: String) {
    let stripped = Self.removingIIGBlocks(Self.removingComments(text))
    var lines: [String] = []
    var conditions: [[String]] = []
    var stack: [String?] = []
    let rawLines = stripped.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init
    )
    for (index, raw) in rawLines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      conditions.append(stack.compactMap { $0 })
      guard line.hasPrefix("#") else {
        lines.append(raw)
        continue
      }
      lines.append("")
      Self.apply(directive: line, next: Self.nextDirective(after: index, in: rawLines), to: &stack)
    }
    self.lines = lines
    self.conditions = conditions
  }

  private static func apply(directive: String, next: String?, to stack: inout [String?]) {
    let body = directive.dropFirst().trimmingCharacters(in: .whitespaces)
    let (keyword, argument) = split(body)
    switch keyword {
    case "if": stack.append(argument)
    case "ifdef": stack.append("defined(\(argument))")
    case "ifndef":
      let isGuard = next.map { split(String($0.dropFirst()).trimmed).1 == argument } ?? false
      stack.append(isGuard ? nil : "!defined(\(argument))")
    case "elif": if !stack.isEmpty { stack[stack.count - 1] = argument }
    case "else":
      if let last = stack.last, let condition = last { stack[stack.count - 1] = "!(\(condition))" }
    case "endif": if !stack.isEmpty { stack.removeLast() }
    default: break
    }
  }

  private static func nextDirective(after index: Int, in lines: [String]) -> String? {
    guard index + 1 < lines.count else { return nil }
    let line = lines[index + 1].trimmed
    return line.hasPrefix("#") ? line : nil
  }

  private static func split(_ body: String) -> (String, String) {
    guard let space = body.firstIndex(where: \.isWhitespace) else { return (body, "") }
    return (String(body[..<space]), body[space...].trimmed)
  }

  /// Removes `/* */` and `//` comments, keeping newlines so line numbers stay stable.
  static func removingComments(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    var iterator = Array(text.unicodeScalars)[...]
    var inBlock = false
    var inLine = false
    var inString = false
    while let scalar = iterator.popFirst() {
      let next = iterator.first
      if inBlock {
        if scalar == "*", next == "/" {
          iterator.removeFirst()
          inBlock = false
        } else if scalar == "\n" {
          result.unicodeScalars.append(scalar)
        }
      } else if inLine {
        if scalar == "\n" {
          inLine = false
          result.unicodeScalars.append(scalar)
        }
      } else if inString {
        result.unicodeScalars.append(scalar)
        if scalar == "\\", let escaped = iterator.popFirst() {
          result.unicodeScalars.append(escaped)
        } else if scalar == "\"" {
          inString = false
        }
      } else if scalar == "/", next == "*" {
        iterator.removeFirst()
        inBlock = true
      } else if scalar == "/", next == "/" {
        iterator.removeFirst()
        inLine = true
      } else {
        if scalar == "\"" { inString = true }
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  /// Blanks `@iig implementation` … `@iig end` blocks, which hold kernel-side includes.
  static func removingIIGBlocks(_ text: String) -> String {
    var inBlock = false
    return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      let trimmed = line.trimmed
      if trimmed.hasPrefix("@iig implementation") {
        inBlock = true
        return ""
      }
      if inBlock {
        if trimmed.hasPrefix("@iig end") { inBlock = false }
        return ""
      }
      return String(line)
    }.joined(separator: "\n")
  }
}

extension StringProtocol { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
