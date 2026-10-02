import Foundation

/// Renames the native runtime for one personality of a multi-personality extension.
///
/// Every personality compiles its own copy of the runtime, so each copy prefixes the identifiers
/// and file names that start with `SwifterKit` with the personality name:
/// `SwifterKitRuntimeService` becomes `SwifterKit<Name>RuntimeService`. String and character
/// literals keep their text, except `#include` paths, which name renamed files.
enum DriverExtensionPersonalityRenaming {
  private static let prefix = Array("SwifterKit".utf8)

  /// The runtime class or file name `name` takes in `personality`'s copy of the runtime.
  static func renamed(_ name: String, personality: String) -> String {
    let bytes = Array(name.utf8)
    let offsets = bytes.indices.filter { startsIdentifier(bytes, at: $0) }
    return inserting(personality, after: offsets, in: name)
  }

  /// `source` with every `SwifterKit` identifier outside string and character literals renamed.
  static func renamedSource(_ source: String, personality: String) -> String {
    let bytes = Array(source.utf8)
    var offsets: [Int] = []
    var state = State.code
    var renamesLiterals = isInclude(bytes, lineStart: 0)
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if state.renames(includeLine: renamesLiterals), startsIdentifier(bytes, at: index) {
        offsets.append(index)
        index += prefix.count
        continue
      }
      let next = index + 1 < bytes.count ? bytes[index + 1] : 0
      var width = 1
      switch (state, byte) {
      case (_, newline):
        if state != .blockComment { state = .code }
        renamesLiterals = isInclude(bytes, lineStart: index + 1)
      case (.code, quote): state = .string
      case (.code, apostrophe) where index == 0 || !isAlphanumeric(bytes[index - 1]):
        state = .character
      case (.code, slash) where next == slash: state = .lineComment
      case (.code, slash) where next == star:
        state = .blockComment
        width = 2
      case (.string, backslash), (.character, backslash): width = 2
      case (.string, quote), (.character, apostrophe): state = .code
      case (.blockComment, star) where next == slash:
        state = .code
        width = 2
      default: break
      }
      index += width
    }
    return inserting(personality, after: offsets, in: source)
  }

  /// Writes `personality`'s renamed copy of every file in `sources` into `destination`.
  static func renameSources(at sources: URL, into destination: URL, personality: String) throws {
    let fileManager = FileManager.default
    for name in try fileManager.contentsOfDirectory(atPath: sources.path).sorted() {
      let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
      let target = destination.appendingPathComponent(renamed(name, personality: personality))
      guard !fileManager.fileExists(atPath: target.path) else {
        throw DriverExtensionGenerationError.invalidPersonalityName(personality)
      }
      try renamedSource(text, personality: personality).write(
        to: target,
        atomically: true,
        encoding: .utf8
      )
    }
  }

  private enum State {
    case code, string, character, lineComment, blockComment

    func renames(includeLine: Bool) -> Bool {
      switch self {
      case .code, .lineComment, .blockComment: true
      case .string, .character: includeLine
      }
    }
  }

  private static let newline = UInt8(ascii: "\n")
  private static let quote = UInt8(ascii: "\"")
  private static let apostrophe = UInt8(ascii: "'")
  private static let slash = UInt8(ascii: "/")
  private static let star = UInt8(ascii: "*")
  private static let backslash = UInt8(ascii: "\\")
  private static let underscore = UInt8(ascii: "_")

  /// `text` with `personality` inserted after the `SwifterKit` that starts at each UTF-8 offset in
  /// ascending `offsets`. The insertion points follow ASCII, so they are character boundaries.
  private static func inserting(
    _ personality: String,
    after offsets: [Int],
    in text: String
  ) -> String {
    var result = ""
    var copied = text.startIndex
    var position = (index: text.startIndex, offset: 0)
    for offset in offsets.map({ $0 + prefix.count }) {
      position.index = text.utf8.index(position.index, offsetBy: offset - position.offset)
      position.offset = offset
      result += text[copied..<position.index]
      result += personality
      copied = position.index
    }
    return result + text[copied...]
  }

  /// Whether `SwifterKit` starts an identifier or file name at `index`. Text after `/` is part
  /// of a package path, such as the generated-header comments' Swift source paths.
  private static func startsIdentifier(_ bytes: [UInt8], at index: Int) -> Bool {
    guard index + prefix.count <= bytes.count, bytes[index] == prefix[0] else { return false }
    if index > 0,
      isAlphanumeric(bytes[index - 1]) || [underscore, slash].contains(bytes[index - 1])
    {
      return false
    }
    return bytes[index..<index + prefix.count].elementsEqual(prefix)
  }

  /// Whether the line starting at `lineStart` is an `#include` or `#import` directive.
  private static func isInclude(_ bytes: [UInt8], lineStart: Int) -> Bool {
    var index = lineStart
    while index < bytes.count, bytes[index] == UInt8(ascii: " ") || bytes[index] == 9 { index += 1 }
    return ["#include", "#import"].contains { directive in
      let directive = Array(directive.utf8)
      return index + directive.count <= bytes.count
        && bytes[index..<index + directive.count].elementsEqual(directive)
    }
  }

  private static func isAlphanumeric(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
      || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
      || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
  }
}
