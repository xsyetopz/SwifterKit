import Foundation

/// The classes and member functions one DriverKit SDK declares in its `.iig` headers.
struct SDKSurface {
  struct DeclaredClass {
    let framework: String
    let declaration: IIGClass
  }

  let version: String
  let classes: [DeclaredClass]

  enum Failure: Error, CustomStringConvertible {
    case unreadableSettings(String)
    case missingFrameworks(String)

    var description: String {
      switch self {
      case .unreadableSettings(let path): "cannot read the SDK version from \(path)"
      case .missingFrameworks(let path): "no DriverKit frameworks under \(path)"
      }
    }
  }

  /// Reads every framework header under a `DriverKit.sdk` directory.
  init(sdk: URL) throws {
    let settingsURL = sdk.appendingPathComponent("SDKSettings.json")
    guard let data = try? Data(contentsOf: settingsURL),
      let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let version = settings["Version"] as? String
    else { throw Failure.unreadableSettings(settingsURL.path) }

    let frameworks = sdk.appendingPathComponent("System/DriverKit/System/Library/Frameworks")
    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: frameworks.path) else {
      throw Failure.missingFrameworks(frameworks.path)
    }
    var classes: [DeclaredClass] = []
    for name in names.sorted() where name.hasSuffix(".framework") {
      let framework = String(name.dropLast(".framework".count))
      let headers = frameworks.appendingPathComponent(name).appendingPathComponent("Headers")
      let files = (try? fileManager.contentsOfDirectory(atPath: headers.path)) ?? []
      for file in files.sorted() where file.hasSuffix(".iig") {
        let text = try String(contentsOf: headers.appendingPathComponent(file), encoding: .utf8)
        classes += IIGParser.parse(text).map {
          DeclaredClass(framework: framework, declaration: $0)
        }
      }
    }
    self.init(version: version, classes: classes)
  }

  init(version: String, classes: [DeclaredClass]) {
    self.version = version
    self.classes = classes
  }
}

/// Orders SDK versions numerically, such as 24.4 before 25.5.
func compareVersions(_ lhs: String, _ rhs: String) -> Bool {
  let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
  let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
  return left.lexicographicallyPrecedes(right)
}
