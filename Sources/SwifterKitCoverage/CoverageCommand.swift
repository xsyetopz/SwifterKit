import Foundation

/// Maintains the DriverKit coverage manifest.
///
///     swifterkit-coverage update --manifest FILE --sdk DIR... [--infer-generated]
///     swifterkit-coverage check --manifest FILE [--sdk DIR...]
///     swifterkit-coverage summary --manifest FILE
///
/// `--sdk` names a `DriverKit.sdk` directory. `update` and `check` read native evidence from
/// `--runtime` directories and Swift evidence from `--swift` directories, defaulting to the
/// package's runtime resources and `Sources/SwifterKit`.
@main
enum CoverageCommand {
  struct Options {
    var command = ""
    var manifest: URL?
    var sdks: [URL] = []
    var runtime: [URL] = []
    var swift: [URL] = []
    var inferGenerated = false
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
    guard let manifestURL = options.manifest else { throw Failure.usage("--manifest is required") }
    let manifest = try CoverageManifest.load(from: manifestURL)
    let surfaces = try options.sdks.map { try SDKSurface(sdk: $0) }

    switch options.command {
    case "update":
      guard !surfaces.isEmpty else { throw Failure.usage("update needs at least one --sdk") }
      var updated = manifest.merging(surfaces)
      if options.inferGenerated { updated = try audit(updated, options).inferringGenerated() }
      try updated.encoded().write(to: manifestURL, options: .atomic)
      print(CoverageAudit.summary(updated))
    case "check":
      var problems = try audit(manifest, options).problems()
      if !surfaces.isEmpty {
        problems += CoverageAudit.drift(from: manifest, to: manifest.merging(surfaces)).map {
          "manifest is out of date (\($0)); run swifterkit-coverage update"
        }
      }
      print(CoverageAudit.summary(manifest))
      guard problems.isEmpty else { throw Failure.check(problems) }
    case "summary": print(CoverageAudit.summary(manifest))
    default:
      throw Failure.usage("unknown command '\(options.command)'; use update, check, or summary")
    }
  }

  private static func audit(
    _ manifest: CoverageManifest,
    _ options: Options
  ) throws -> CoverageAudit {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    // The service `.iig` overrides are rendered from the generator's Swift templates.
    let runtime =
      options.runtime.isEmpty
      ? [
        root.appendingPathComponent("Sources/SwifterKit/Resources/DriverKitExtension/Sources"),
        root.appendingPathComponent("Sources/SwifterKit/DriverKit/Authoring/Generation"),
      ] : options.runtime
    let swift =
      options.swift.isEmpty ? [root.appendingPathComponent("Sources/SwifterKit")] : options.swift
    return CoverageAudit(
      manifest: manifest,
      native: try SourceIndex(directories: runtime, extensions: ["cpp", "h", "iig", "swift"]),
      swift: try SourceIndex(directories: swift, extensions: ["swift"])
    )
  }

  static func parse(_ arguments: [String]) throws -> Options {
    var options = Options()
    var remaining = arguments[...]
    guard let command = remaining.popFirst() else {
      throw Failure.usage("usage: swifterkit-coverage update|check|summary --manifest FILE")
    }
    options.command = command
    while let flag = remaining.popFirst() {
      if flag == "--infer-generated" {
        options.inferGenerated = true
        continue
      }
      guard let value = remaining.popFirst() else { throw Failure.usage("\(flag) needs a value") }
      let url = URL(fileURLWithPath: value)
      switch flag {
      case "--manifest": options.manifest = url
      case "--sdk": options.sdks.append(url)
      case "--runtime": options.runtime.append(url)
      case "--swift": options.swift.append(url)
      default: throw Failure.usage("unknown option \(flag)")
      }
    }
    return options
  }
}
