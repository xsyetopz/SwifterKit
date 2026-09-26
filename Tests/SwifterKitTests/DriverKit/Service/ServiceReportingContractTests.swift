import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceReportingContractTests {
  @Test
  func generatesReporterTablesAndBuilds() throws {
    try withGeneratedExtension(ServiceReportingCommandsTests.reporting) { output, root in
      let configuration = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(configuration.contains("kSwifterKitReporterCount = 3;"))
      #expect(configuration.contains("kSwifterKitReportLegendPublic = true;"))
      #expect(configuration.contains("kSwifterKitReportChannels[4] = {"))
      #expect(configuration.contains("{21592ULL, \"\\x54\"\"\\x58\"}"))
      #expect(configuration.contains("kSwifterKitReportStates[2] = {20302ULL, 5195334ULL};"))
      #expect(configuration.contains("{10, 0, 4},\n    {2, 1, 8}"))
      #expect(configuration.contains("{1, 4, \(ReportUnit.bytes.rawValue)ULL, "))
      #expect(configuration.contains(", 0, 2, 0, 0, 0, 0}"))
      #expect(configuration.contains("{2, 2, \(ReportUnit.hardwareTicks.rawValue)ULL, "))
      #expect(configuration.contains("nullptr, 2, 1, 0, 2, 0, 0}"))
      #expect(configuration.contains("nullptr, 3, 1, 2, 0, 0, 2}"))
      try expectGeneratedExtensionBuilds(
        at: output,
        derivedData: root.appendingPathComponent("DerivedData")
      )
    }
  }

  @Test
  func rejectsInvalidReportingAtGeneration() throws {
    let reporting = ReportingConfiguration(reporters: [
      ReporterConfiguration(
        kind: .state(states: []),
        group: "G",
        channels: [ReportChannel(id: 1, name: "C")],
        categories: .power
      )
    ])
    #expect(throws: DriverExtensionGenerationError.invalidReportingConfiguration) {
      try withGeneratedExtension(reporting) { _, _ in }
    }
  }

  @Test
  func nativeLimitsAndLayoutsMatchSwift() throws {
    try withGeneratedExtension(nil) { output, _ in
      let header = try source(RuntimeSchemaHeader.fileName, in: output)
      for (name, value) in [
        ("Reporters", ReportingLimits.maximumReporters),
        ("ReportChannels", ReportingLimits.maximumChannels),
        ("ReportStates", ReportingLimits.maximumStates),
        ("HistogramSegments", ReportingLimits.maximumSegments),
        ("HistogramBuckets", ReportingLimits.maximumBuckets),
      ] { #expect(header.contains("kSwifterKitMaximum\(name) = \(value);")) }
      let operations: [(String, DriverCommand.ReporterOperation)] = [
        ("SetValue", .setValue), ("IncrementValue", .incrementValue), ("SetState", .setState),
        ("OverrideState", .overrideState), ("IncrementState", .incrementState),
        ("TallyValue", .tallyValue), ("OverrideBucket", .overrideBucket),
      ]
      for (name, operation) in operations {
        #expect(header.contains("    \(name) = \(operation.rawValue),"))
      }
      let layouts = try source("SwifterKitRuntimeReportingProtocol.h", in: output)
      #expect(layouts.contains("#include \"SwifterKitRuntimeSchema.h\""))
      #expect(layouts.contains("static_assert(sizeof(SwifterKitReporterUpdate) == 56);"))
      #expect(layouts.contains("static_assert(sizeof(SwifterKitReporterRead) == 24);"))

      let defaults = try source("SwifterKitRuntimeConfiguration.h", in: output)
      #expect(defaults.contains("kSwifterKitReporterCount = 0;"))
      #expect(defaults.contains("kSwifterKitReporters[1] = {};"))
    }
  }

  @Test
  func runtimeServesIOReportClientsAndValidatesUpdates() throws {
    try withGeneratedExtension(nil) { output, _ in
      let service = try source("SwifterKitRuntimeService.iig", in: output)
      #expect(service.contains("virtual IOReturn ConfigureReport("))
      #expect(service.contains("virtual IOReturn UpdateReport("))

      let reporting = try source("SwifterKitRuntimeReporting.cpp", in: output)
      #expect(reporting.contains("IOReporter::configureAllReports(reporters, channels, action"))
      #expect(reporting.contains("IOReporter::updateAllReports("))
      #expect(
        reporting.contains("return ConfigureReport(channels, action, outCount, SUPERDISPATCH);")
      )
      #expect(
        reporting.contains("legend->addReporterLegend(reporter, config.group, config.subgroup)")
      )
      #expect(reporting.contains("SetLegend(legend->getLegend(), kSwifterKitReportLegendPublic)"))
      #expect(reporting.contains("stateReporter->setStateID("))
      #expect(reporting.contains("!HasChannel(kSwifterKitReporters[index], channelID)"))
      #expect(reporting.contains("config.kind != kState || !HasState(config, state)"))
      #expect(reporting.contains("static_cast<uint64_t>(values[0]) >= BucketCount(config)"))
      #expect(reporting.contains("payloadLength != expected"))

      let control = try source("SwifterKitRuntimeServiceControl.cpp", in: output)
      #expect(control.contains("return ReporterCommand(opcode, payload, payloadLength, response);"))
      let userClient = try source("SwifterKitRuntimeCommandDispatch.cpp", in: output)
      #expect(userClient.contains("case SwifterKitRuntimeOpcode::ReporterUpdate:"))
      #expect(userClient.contains("case SwifterKitRuntimeOpcode::ReporterRead:"))

      // Reporters exist before the service registers and outlive host connections.
      let start = try source("SwifterKitRuntimeService.cpp", in: output)
      let reportingStart = try #require(start.range(of: "result = StartReporting();")?.lowerBound)
      let register = try #require(start.range(of: "result = RegisterService();")?.lowerBound)
      #expect(reportingStart < register)
      let events = try source("SwifterKitRuntimeEvents.cpp", in: output)
      #expect(!events.contains("StopReporting"))
    }
  }

  private func withGeneratedExtension(
    _ reporting: ReportingConfiguration?,
    _ body: (URL, URL) throws -> Void
  ) throws {
    try withTemporaryExtension(
      named: "ReportingDriver",
      configuration: DriverConfiguration(
        bundleIdentifier: "com.example.contract-reporting",
        providerClass: "IOUserResources",
        matchingProperties: ["IOResourceMatch": .string("IOKit")],
        capabilities: [],
        reporting: reporting
      ),
      options: DriverExtensionGenerationOptions(deploymentTarget: "21.0")
    ) { output, root in try body(output, root) }
  }
}
