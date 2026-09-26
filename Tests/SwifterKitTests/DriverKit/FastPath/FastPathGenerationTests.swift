import Foundation
import Testing

@testable import SwifterKit

@Suite
struct FastPathGenerationTests {
  static let small = FastPathConfiguration(
    programs: [
      FastPathProgram(
        trigger: .interrupt(sourceIndex: 2, delivery: .whenProgramEmits),
        operations: [
          .read(FastPathRegister(bar: 2, offset: 0x40, width: .bits32), into: .v1),
          .skip(count: 1, if: FastPathCondition(.v1, mask: 0x8000_0000, is: .zero)),
          .emit([.v1, .v0]),
          .write(FastPathRegister(bar: 2, offset: 0x40, width: .bits32), .value(.v1)),
        ]
      ),
      FastPathProgram(
        trigger: .command,
        argumentCount: 2,
        operations: [
          .compute(.v0, .shiftLeft, .constant(8)),
          .modify(FastPathRegister(bar: 0, offset: 8, width: .bits16), clear: 0xFF00, set: 0x0100),
          .poll(
            FastPathRegister(bar: 0, offset: 0, width: .bits8),
            mask: 0x80,
            equals: 0,
            maxIterations: 20,
            intervalMicroseconds: 50
          ), .delay(microseconds: 10), .fail(status: Int32(bitPattern: 0xE000_02D6)),
        ]
      ),
    ],
    barSizes: [2: 0x100, 0: 0x10]
  )

  @Test
  func emitsProgramOperationTriggerAndBARTables() {
    #expect(
      DriverExtensionGenerator.fastPathDeclarations(Self.small) == """
        static constexpr SwifterKitFastPathProgram kSwifterKitFastPathPrograms[2] = {
            {0, 4, 0, 0},
            {4, 5, 2, 1010}
        };
        static constexpr uint32_t kSwifterKitFastPathProgramCount = 2;
        static constexpr SwifterKitFastPathOperation kSwifterKitFastPathOperations[9] = {
            {1, 1026, 1, 0, 64ULL, 0ULL, 0ULL},
            {7, 1, 1, 0, 0ULL, 2147483648ULL, 0ULL},
            {8, 0, 2, 0, 0ULL, 1ULL, 0ULL},
            {2, 1026, 0, 1, 64ULL, 1ULL, 0ULL},
            {4, 0, 4, 0, 0ULL, 8ULL, 0ULL},
            {3, 512, 0, 0, 8ULL, 65280ULL, 256ULL},
            {5, 256, 20, 50, 0ULL, 128ULL, 0ULL},
            {6, 0, 10, 0, 0ULL, 0ULL, 0ULL},
            {9, 0, 0xE00002D6, 0, 0ULL, 0ULL, 0ULL}
        };
        static constexpr uint32_t kSwifterKitFastPathOperationCount = 9;
        static constexpr SwifterKitFastPathTrigger kSwifterKitFastPathTriggers[2] = {
            {3, 2, 3, 0},
            {4, 0, 0, 1}
        };
        static constexpr uint32_t kSwifterKitFastPathTriggerCount = 2;
        static constexpr SwifterKitFastPathBAR kSwifterKitFastPathBARSizes[2] = {
            {0, 0, 16ULL},
            {2, 0, 256ULL}
        };
        static constexpr uint32_t kSwifterKitFastPathBARSizeCount = 2;
        """
    )
  }

  @Test
  func emitsOneElementTablesWithoutAFastPath() {
    let declarations = DriverExtensionGenerator.fastPathDeclarations(nil)
    #expect(declarations.contains("kSwifterKitFastPathOperations[1] = {};"))
    #expect(declarations.contains("kSwifterKitFastPathProgramCount = 0;"))
    #expect(declarations.contains("kSwifterKitFastPathBARSizes[1] = {};"))
  }

  @Test
  func nativeSchemaCarriesTheLimitsAndCodes() {
    let header = RuntimeSchemaHeader.renderFastPath()
    for (name, value) in [
      ("MaximumPrograms", FastPathLimits.maximumPrograms),
      ("MaximumOperations", FastPathLimits.maximumOperations),
      ("MaximumArguments", FastPathLimits.maximumArguments),
      ("MaximumPollIterations", FastPathLimits.maximumPollIterations),
      ("MaximumPollIntervalMicroseconds", FastPathLimits.maximumPollIntervalMicroseconds),
      ("MaximumDelayMicroseconds", FastPathLimits.maximumDelayMicroseconds),
      ("MaximumDelayBudgetMicroseconds", FastPathLimits.maximumDelayBudgetMicroseconds),
      ("BARCount", Int(FastPathLimits.maximumBAR) + 1), ("SlotCount", FastPathSlot.allCases.count),
    ] { #expect(header.contains("kSwifterKitFastPath\(name) = \(value);")) }
    #expect(header.contains("    Fail = 9,\n"))
    #expect(header.contains("static_assert(sizeof(SwifterKitFastPathOperation) == 40);"))
    #expect(Set(RuntimeFastPathOpcode.allCases.map(\.rawValue)).count == 9)
  }

  /// Every operation kind, register width, operand kind, and condition, repeated to fill a program.
  private static let everyOperation: [FastPathOp] = [
    .read(FastPathRegister(bar: 0, offset: 0, width: .bits32), into: .v0),
    .write(FastPathRegister(bar: 0, offset: 4, width: .bits8), .constant(0xFF)),
    .write(FastPathRegister(bar: 2, offset: 8, width: .bits16), .value(.v1)),
    .modify(FastPathRegister(bar: 5, offset: 0x18, width: .bits64), clear: 0xF0, set: .max),
    .compute(.v1, .and, .constant(0xFFFF)), .compute(.v2, .or, .value(.v1)),
    .compute(.v3, .xor, .constant(.max)), .compute(.v4, .shiftLeft, .constant(63)),
    .compute(.v5, .shiftRight, .value(.v4)), .compute(.v6, .add, .constant(1)),
    .compute(.v7, .subtract, .value(.v6)),
    .poll(
      FastPathRegister(bar: 0, offset: 0x0FFC, width: .bits32),
      mask: 1,
      equals: 1,
      maxIterations: 10,
      intervalMicroseconds: 100
    ), .delay(microseconds: 100),
    .skip(count: 1, if: FastPathCondition(.v0, mask: 1, is: .nonzero)),
    .fail(status: Int32(bitPattern: 0xE000_02BC)),
    .skip(count: 1, if: FastPathCondition(.v2, is: .zero)), .emit(FastPathSlot.allCases),
  ]

  /// The most programs, each with the most operations, over every trigger and delivery.
  static let maximal: FastPathConfiguration = {
    let triggers: [(Int) -> FastPathTrigger] = [
      { _ in .start }, { _ in .stop }, { _ in .command },
      { .interrupt(sourceIndex: UInt32($0), delivery: .always) },
      { .interrupt(sourceIndex: UInt32($0), delivery: .never) },
      { .interrupt(sourceIndex: UInt32($0), delivery: .whenProgramEmits) },
    ]
    let operations = (0..<FastPathLimits.maximumOperations).map {
      everyOperation[$0 % everyOperation.count]
    }
    return FastPathConfiguration(
      programs: (0..<FastPathLimits.maximumPrograms).map { index in
        let trigger = triggers[index % triggers.count](index)
        return FastPathProgram(
          trigger: trigger,
          argumentCount: trigger == .command ? FastPathLimits.maximumArguments : 0,
          operations: operations
        )
      },
      barSizes: [0: 0x1000, 2: 0x100, 5: 0x20]
    )
  }()

  @Test
  func maximalFastPathGeneratesAndBuilds() throws {
    #expect(Self.maximal.programs.allSatisfy { $0.operations.last.map(\.isSkip) == false })
    try withTemporaryExtension(
      named: "FastPathDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.fast-path",
        providerClass: "IOPCIDevice",
        capabilities: [.pci, .interrupts],
        pciDevice: PCIDeviceConfiguration(vendorID: 0x1011, deviceIDs: [0x0026]),
        interruptSources: (0..<32).map { InterruptSourceConfiguration(index: $0) },
        fastPath: Self.maximal
      )
    ) { output, root in
      let configuration = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(configuration.contains("#define SWIFTERKIT_ENABLE_FAST_PATH 1"))
      #expect(configuration.contains("#include \"SwifterKitRuntimeFastPathSchema.h\""))
      #expect(configuration.contains("kSwifterKitFastPathProgramCount = 32;"))
      #expect(configuration.contains("kSwifterKitFastPathOperationCount = 2048;"))
      #expect(configuration.contains("kSwifterKitFastPathTriggerCount = 32;"))
      #expect(configuration.contains("kSwifterKitFastPathBARSizeCount = 3;"))
      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }
}

private extension FastPathOp { var isSkip: Bool { if case .skip = self { true } else { false } } }
