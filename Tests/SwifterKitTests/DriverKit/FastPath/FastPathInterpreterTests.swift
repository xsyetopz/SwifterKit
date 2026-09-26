import Foundation
import Testing

@testable import SwifterKit

/// Runs the native interpreter on the host: the generator emits these programs' tables, the host
/// `clang++` compiles `SwifterKitRuntimeFastPathInterpreter.h` with a fake register file and the
/// address and undefined-behavior sanitizers, and the test checks every transcript line.
@Suite
struct FastPathInterpreterTests {
  private static func bar0(_ offset: UInt64, _ width: FastPathRegister.Width) -> FastPathRegister {
    FastPathRegister(bar: 0, offset: offset, width: width)
  }
  private static func bar2(_ offset: UInt64, _ width: FastPathRegister.Width) -> FastPathRegister {
    FastPathRegister(bar: 2, offset: offset, width: width)
  }

  /// One program per behavior; the harness addresses them by index.
  static let programs = FastPathConfiguration(
    programs: [
      FastPathProgram(
        trigger: .command,
        argumentCount: 2,
        operations: [
          .read(bar0(0x08, .bits32), into: .v2), .write(bar0(0x0C, .bits16), .value(.v0)),
          .write(bar2(0x00, .bits8), .constant(0xAB)), .write(bar0(0x10, .bits64), .value(.v1)),
          .read(bar0(0x10, .bits64), into: .v3),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        operations: [
          .modify(bar0(0x20, .bits32), clear: 0xFF00, set: 0x42),
          .read(bar0(0x20, .bits32), into: .v0),
          .modify(bar2(0x04, .bits8), clear: 0x0F, set: 0xF0),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        argumentCount: 2,
        operations: [
          .compute(.v2, .add, .value(.v0)), .compute(.v2, .subtract, .constant(1)),
          .compute(.v3, .or, .value(.v1)), .compute(.v3, .and, .constant(0xFF)),
          .compute(.v4, .xor, .constant(.max)), .compute(.v5, .add, .constant(1)),
          .compute(.v5, .shiftLeft, .constant(63)), .compute(.v6, .add, .value(.v0)),
          .compute(.v6, .shiftRight, .value(.v1)), .compute(.v7, .subtract, .constant(1)),
          .compute(.v7, .shiftLeft, .value(.v1)),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        operations: [
          .poll(
            bar0(0x30, .bits32),
            mask: 1,
            equals: 1,
            maxIterations: 5,
            intervalMicroseconds: 100
          ), .read(bar0(0x30, .bits32), into: .v0),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        operations: [
          .poll(
            bar0(0x34, .bits32),
            mask: 3,
            equals: 2,
            maxIterations: 4,
            intervalMicroseconds: 50
          ), .write(bar0(0x38, .bits32), .constant(1)),
        ]
      ),
      FastPathProgram(
        trigger: .start,
        operations: [.delay(microseconds: 250), .delay(microseconds: 1_000)]
      ),
      FastPathProgram(
        trigger: .command,
        argumentCount: 1,
        operations: [
          .skip(count: 1, if: FastPathCondition(.v0, mask: 1, is: .nonzero)),
          .write(bar2(0x08, .bits8), .constant(0x11)),
          .skip(count: 1, if: FastPathCondition(.v0, mask: 1, is: .zero)),
          .write(bar2(0x09, .bits8), .constant(0x22)),
        ]
      ),
      FastPathProgram(
        trigger: .interrupt(sourceIndex: 3, delivery: .whenProgramEmits),
        operations: [
          .read(bar0(0x08, .bits32), into: .v1),
          .skip(count: 1, if: FastPathCondition(.v1, mask: 0x80, is: .zero)),
          .emit([.v1, .v0, .v7]), .compute(.v0, .add, .constant(5)), .emit([.v0]),
        ]
      ),
      FastPathProgram(
        trigger: .stop,
        operations: [
          .write(bar0(0x40, .bits32), .constant(7)), .fail(status: Int32(bitPattern: 0xE000_02BC)),
          .write(bar0(0x44, .bits32), .constant(8)),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        argumentCount: 4,
        operations: [.emit(FastPathSlot.allCases)]
      ),
    ],
    barSizes: [0: 0x100, 2: 0x10]
  )

  /// The transcript of each valid run: status, emit flag, slots, then accesses in order.
  static let runs = [
    "read-write status=0 emitted=0 slots=12345,1122334455667788,DEADBEEF,1122334455667788,0,0,0,0"
      + " log=R0+8/4=DEADBEEF W0+C/2=2345 W2+0/1=AB W0+10/8=1122334455667788"
      + " R0+10/8=1122334455667788",
    "modify status=0 emitted=0 slots=1234007A,0,0,0,0,0,0,0 log=R0+20/4=12345678"
      + " W0+20/4=1234007A R0+20/4=1234007A R2+4/1=3C W2+4/1=F0",
    "compute status=0 emitted=0 slots=1234,44,1233,44,FFFFFFFFFFFFFFFF,8000000000000000,123,"
      + "FFFFFFFFFFFFFFF0 log=",
    "poll-success status=0 emitted=0 slots=1,0,0,0,0,0,0,0 log=R0+30/4=0 D100 R0+30/4=0 D100"
      + " R0+30/4=1 R0+30/4=1",
    "poll-timeout status=E00002D6 emitted=0 slots=0,0,0,0,0,0,0,0 log=R0+34/4=0 D50 R0+34/4=0"
      + " D50 R0+34/4=0 D50 R0+34/4=0",
    "delay status=0 emitted=0 slots=0,0,0,0,0,0,0,0 log=D250 D1000",
    "skip-clear status=0 emitted=0 slots=0,0,0,0,0,0,0,0 log=W2+8/1=11",
    "skip-set status=0 emitted=0 slots=1,0,0,0,0,0,0,0 log=W2+9/1=22",
    "emit-bit status=0 emitted=1 slots=5,CAFE00FE,0,0,0,0,0,0 log=R0+8/4=CAFE00FE"
      + " E:CAFE00FE:0:0 E:5",
    "emit-clear status=0 emitted=1 slots=5,100,0,0,0,0,0,0 log=R0+8/4=100 E:5",
    "fail status=E00002BC emitted=0 slots=0,0,0,0,0,0,0,0 log=W0+40/4=7",
    "emit-all status=0 emitted=1 slots=1,2,3,4,0,0,0,0 log=E:1:2:3:4:0:0:0:0",
  ]

  static let rejections = [
    "opcode-zero", "opcode-unknown", "read-slot", "read-unused-c", "read-unused-immediate",
    "bar-undeclared", "bar-index", "width", "register-high-bits", "misaligned", "out-of-bounds",
    "end-of-bar", "write-wide-constant", "write-operand-kind", "write-slot", "write-unused",
    "budget-mismatch", "start-past-table", "count-zero", "count-over-limit", "arguments-over-limit",
    "argument-mismatch", "program-index", "modify-wide-mask", "modify-unused", "compute-op-zero",
    "compute-op-unknown", "compute-shift", "compute-slot", "compute-operand-kind", "compute-unused",
    "poll-iterations-zero", "poll-iterations-over", "poll-interval", "poll-outside-mask",
    "poll-wide-mask", "poll-budget", "delay-zero", "delay-over", "delay-unused", "skip-zero",
    "skip-past-end", "skip-test", "skip-slot", "emit-zero", "emit-over", "emit-slot",
    "emit-extra-byte", "emit-unused", "fail-zero", "fail-unused", "bar-smaller", "bar-missing",
  ]

  static let invalidConfigurations = [
    "no-source", "wrong-source", "delivery-zero", "delivery-unknown", "delivery-on-command",
    "source-on-start", "kind-zero", "kind-unknown", "program-mismatch", "duplicate-interrupt",
    "arguments-on-start", "trigger-count", "bar-duplicate", "bar-zero-size", "bar-index",
    "bar-reserved", "malformed-row",
  ]

  static let hostCompilerAvailable: Bool = {
    #if os(macOS)
      (try? runTool(
        "/usr/bin/xcrun",
        ["--sdk", "macosx", "--find", "clang++"],
        driverKitXcode: false
      ))?.status == 0
    #else
      false
    #endif
  }()

  @Test
  func programsAreValidInSwift() throws {
    try Self.programs.validate(interruptSources: [3], hasPCIDevice: true)
  }

  @Test(.enabled(if: hostCompilerAvailable))
  func interpreterRunsEveryOperationAndRejectsMalformedRows() throws {
    let lines = try Self.runHarness()
    for run in Self.runs {
      let name = String(run.prefix { $0 != " " })
      #expect(lines[name] == run, "\(name)")
    }
    for name in Self.rejections {
      let line = lines["reject-\(name)"]
      #expect(
        line?.hasSuffix("executed=0 status=E00002C2 accesses=0") == true,
        "\(name): \(line ?? "")"
      )
    }
    // A BAR declared smaller than a register it names still loads; the program is rejected.
    #expect(lines["reject-bar-smaller"]?.contains("loaded=1") == true)
    #expect(lines["config-valid"] == "config-valid valid=1")
    for name in Self.invalidConfigurations {
      #expect(lines["config-\(name)"] == "config-\(name) valid=0")
    }
    #expect(lines["interrupt-program"] == "interrupt-program source3=7 source4=10 count=10")
    #expect(lines["deliver"] == "deliver always=1 never=0 emitted=1 silent=0 not-run=1 unknown=1")
    #expect(lines["command"] == "command matching=1 count=0 start=0 interrupt=0 missing=0")
    #expect(
      lines.count == Self.runs.count + Self.rejections.count + Self.invalidConfigurations.count + 4
    )
  }

  /// Compiles and runs the harness, returning its lines keyed by their first word.
  private static func runHarness() throws -> [String: String] {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let tables = """
      #include "SwifterKitRuntimeFastPathSchema.h"

      \(DriverExtensionGenerator.fastPathDeclarations(programs))

      """
    try Data(tables.utf8).write(to: directory.appendingPathComponent("FastPathTables.h"))
    let harness = directory.appendingPathComponent("Harness.cpp")
    try Data(fastPathInterpreterHarness.utf8).write(to: harness)
    let executable = directory.appendingPathComponent("Harness")
    let build = try runTool(
      "/usr/bin/xcrun",
      [
        "--sdk", "macosx", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror",
        "-fno-exceptions", "-fno-rtti", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
        "-I", checkedInNativeSources.path, "-I", directory.path, harness.path, "-o",
        executable.path,
      ],
      driverKitXcode: false
    )
    try #require(build.status == 0, Comment(rawValue: build.output))
    let run = try runTool(executable.path, [], driverKitXcode: false)
    try #require(run.status == 0, Comment(rawValue: run.output))
    let lines = run.output.split(separator: "\n").map {
      (String($0.prefix { $0 != " " }), String($0))
    }
    return Dictionary(lines) { first, _ in first }
  }
}
