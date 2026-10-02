import Foundation

/// The DriverKit members that SwifterKit's native runtime calls or overrides, read from clang's
/// AST of every generated extension tree the build tests capture.
struct NativeEvidence {
  private(set) var uses: Set<NativeUse> = []
  /// The first base class of every class the trees define or include.
  private(set) var bases: [String: String] = [:]

  enum Failure: Error, CustomStringConvertible {
    case noTrees(String)
    case clang(String, String)

    var description: String {
      switch self {
      case .noTrees(let path):
        "no generated trees under \(path); run the tests with SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE"
      case .clang(let file, let message): "clang failed on \(file): \(message)"
      }
    }
  }

  /// Compiles each `.cpp` file of each tree in `trees` with the selected Xcode's clang.
  ///
  /// A tree holds `Sources`, `DerivedSources`, and `DeploymentTarget`, as the build tests write
  /// them under `SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE`. Trees of multi-personality extensions
  /// rename the runtime classes and files, so they are skipped; they compile the same sources.
  init(trees: URL) throws {
    let fileManager = FileManager.default
    var pending: [(sources: URL, derived: URL, target: String, file: URL)] = []
    var actions: [String: Action] = [:]
    for tree in try fileManager.contentsOfDirectory(at: trees, includingPropertiesForKeys: nil) {
      let sources = tree.appendingPathComponent("Sources")
      guard
        fileManager.fileExists(
          atPath: sources.appendingPathComponent("SwifterKitRuntimeConfiguration.h").path
        ),
        let target = try? String(
          contentsOf: tree.appendingPathComponent("DeploymentTarget"),
          encoding: .utf8
        )
      else { continue }
      let derived = tree.appendingPathComponent("DerivedSources")
      for file in try fileManager.contentsOfDirectory(atPath: sources.path).sorted() {
        let url = sources.appendingPathComponent(file)
        if file.hasSuffix(".cpp") { pending.append((sources, derived, target.trimmed, url)) }
        if file.hasSuffix(".iig") {
          actions.merge(Self.actions(inIIG: try String(contentsOf: url, encoding: .utf8))) {
            current,
            _ in current
          }
        }
      }
    }
    let jobs = pending
    guard !jobs.isEmpty else { throw Failure.noTrees(trees.path) }

    let sdkPath = try Self.run(["--sdk", "driverkit", "--show-sdk-path"])
    let sdk = (String(data: sdkPath, encoding: .utf8) ?? "").trimmed
    let results = Results()
    DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
      let job = jobs[index]
      do {
        let json = try Self.run([
          "clang++", "-x", "c++", "-std=c++20", "-fblocks", "-fno-exceptions", "-fno-rtti",
          "-target", "arm64-apple-driverkit\(job.target)", "-isysroot", sdk, "-I", job.sources.path,
          "-I", job.derived.path, "-fsyntax-only", "-Xclang", "-ast-dump=json", job.file.path,
        ])
        results.add(
          try Self.parse(
            json,
            treePrefix: job.sources.deletingLastPathComponent().path + "/",
            sourcePrefix: job.sources.path + "/"
          )
        )
      } catch { results.fail(error) }
    }
    if let failure = results.failure { throw failure }
    uses = Self.resolvingActions(results.uses, actions)
    bases = results.bases
  }

  init(uses: Set<NativeUse>, bases: [String: String]) {
    self.uses = uses
    self.bases = bases
  }

  /// The DriverKit member an IIG action method implements, as its `TYPE(Class::Method)` names it.
  struct Action: Equatable {
    let className: String
    let method: String
  }

  /// The action methods that `.iig` text declares with `TYPE(Class::Method)`, keyed
  /// `Class::action`. Clang compiles `TYPE` to nothing, so the AST reads an action's `_Impl` as
  /// an override of a member that the class's base does not declare.
  static func actions(inIIG text: String) -> [String: Action] {
    var actions: [String: Action] = [:]
    for declared in IIGParser.parse(text) {
      for method in declared.methods {
        for annotation in method.annotations
        where annotation.hasPrefix("TYPE(") && annotation.hasSuffix(")") {
          let target = annotation.dropFirst("TYPE(".count).dropLast().components(separatedBy: "::")
          guard target.count == 2 else { continue }
          actions["\(declared.name)::\(method.name)"] = Action(
            className: target[0],
            method: target[1]
          )
        }
      }
    }
    return actions
  }

  /// `uses` with each action's `_Impl` attributed to the member that the action's `TYPE` names.
  static func resolvingActions(
    _ uses: Set<NativeUse>,
    _ actions: [String: Action]
  ) -> Set<NativeUse> {
    Set(
      uses.map { use in
        guard use.kind == .override, use.parameters == nil, use.function.hasSuffix("_Impl"),
          let action = actions[String(use.function.dropLast("_Impl".count))]
        else { return use }
        return NativeUse(
          className: action.className,
          method: action.method,
          parameters: nil,
          kind: .override,
          file: use.file,
          function: use.function
        )
      }
    )
  }

  /// Parses `json`, keeping uses in files under `sourcePrefix` and taking the classes defined
  /// under `treePrefix` as SwifterKit's own.
  ///
  /// `ClangAST` recurses once per AST level, and a function's nested statements overflow the
  /// 512 KB stack of a dispatch worker or test thread, so the parse runs on its own thread.
  static func parse(_ json: Data, treePrefix: String, sourcePrefix: String) throws -> ClangAST {
    let parsed = Parsed()
    let thread = Thread {
      parsed.result = Result {
        try ClangAST(
          json: json,
          isTree: { $0.hasPrefix(treePrefix) },
          isSource: { $0.hasPrefix(sourcePrefix) }
        )
      }
      parsed.done.signal()
    }
    thread.stackSize = 64 << 20
    thread.start()
    parsed.done.wait()
    return try parsed.result.get()
  }

  /// Hands a parse result from its thread to the waiting caller, which reads it only after
  /// `done` is signaled.
  private final class Parsed: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var result: Result<ClangAST, Error> = .failure(CocoaError(.coderReadCorrupt))
  }

  /// Collects the translation units' results across `concurrentPerform` iterations.
  private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var uses: Set<NativeUse> = []
    private(set) var bases: [String: String] = [:]
    private(set) var failure: Error?

    func add(_ ast: ClangAST) {
      lock.lock()
      defer { lock.unlock() }
      uses.formUnion(ast.uses)
      bases.merge(ast.bases) { current, _ in current }
    }

    func fail(_ error: Error) {
      lock.lock()
      defer { lock.unlock() }
      if failure == nil { failure = error }
    }
  }

  /// Runs `xcrun` with `arguments` and returns its standard output. Standard error goes to a
  /// file, because a full pipe would stall the process while its output is read.
  private static func run(_ arguments: [String]) throws -> Data {
    let errorFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "swifterkit-coverage-\(UUID().uuidString).log"
    )
    FileManager.default.createFile(atPath: errorFile.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: errorFile) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = try FileHandle(forWritingTo: errorFile)
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let message = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
      throw Failure.clang(arguments.last ?? "", message)
    }
    return data
  }
}
