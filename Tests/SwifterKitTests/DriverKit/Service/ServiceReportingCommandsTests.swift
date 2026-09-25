import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceReportingCommandsTests {
  @Test
  func typedValuesMatchIOReportTypes() {
    #expect(ReportCategories.all.rawValue == 0x811E)
    #expect(
      [ReportUnit.none, .seconds, .milliseconds, .microseconds, .nanoseconds].map(\.rawValue) == [
        0, 0x0100_0000_0000_0000, 0x0100_007C_0000_0000, 0x0100_0079_0000_0000,
        0x0100_0076_0000_0000,
      ]
    )
    #expect(ReportUnit.hardwareTicks.rawValue == 0x0101_0000_0000_0000)
    #expect(ReportUnit.bytes.rawValue == 0x0900_8200_0000_0000)
    #expect(ReportUnit.events.rawValue == 0x6400_0000_0000_0000)
    #expect(HistogramSegment.Scale.exponential.rawValue == 1)
    let channel = [ReportChannel(id: 1, name: "C")]
    #expect(
      ReporterConfiguration(
        kind: .state(states: [1]),
        group: "G",
        channels: channel,
        categories: .power
      ).unit == .hardwareTicks
    )
    #expect(
      ReporterConfiguration(kind: .simple, group: "G", channels: channel, categories: .power).unit
        == .none
    )
  }

  @Test
  func encodesReporterUpdates() throws {
    let set = try DriverCommand.setReportValue(-5, reporter: 2, channel: 0x41)
    #expect(set.opcode == 0x0E20)
    #expect(set.requiredCapabilities.isEmpty)
    #expect(set.maximumResponseSize == RuntimeMessage.headerSize)
    #expect(set.payload.count == 56)
    #expect(try set.payload.readRuntimeInteger(at: 0) as UInt32 == 2)
    #expect(try set.payload.readRuntimeInteger(at: 4) as UInt32 == 1)
    #expect(try set.payload.readRuntimeInteger(at: 8) as UInt64 == 0x41)
    #expect(try set.payload.readRuntimeInteger(at: 16) as Int64 == -5)
    #expect(set.payload[24...].allSatisfy { $0 == 0 })

    let operations: [(DriverCommand, UInt32)] = [
      (try .incrementReportValue(by: 1, reporter: 0, channel: 1), 2),
      (try .setReportState(7, reporter: 0, channel: 1), 3),
      (try .adjustReportState(7, reporter: 0, channel: 1, residency: 10, transitions: 2), 4),
      (
        try .adjustReportState(
          7,
          reporter: 0,
          channel: 1,
          residency: 10,
          transitions: 2,
          accumulate: true
        ), 5
      ), (try .tallyReportValue(9, reporter: 0, channel: 1), 6),
      (
        try .overrideHistogramBucket(
          3,
          reporter: 0,
          channel: 1,
          hits: 4,
          minimum: 1,
          maximum: 8,
          sum: 20
        ), 7
      ),
    ]
    for (command, operation) in operations {
      #expect(try command.payload.readRuntimeInteger(at: 4) as UInt32 == operation)
    }
    let bucket = operations[5].0.payload
    #expect(try bucket.readRuntimeInteger(at: 16) as Int64 == 3)
    #expect(try bucket.readRuntimeInteger(at: 48) as Int64 == 20)
    let adjust = operations[2].0.payload
    #expect(try adjust.readRuntimeInteger(at: 24) as Int64 == 10)
    #expect(try adjust.readRuntimeInteger(at: 32) as Int64 == 2)
  }

  @Test
  func encodesReporterReads() throws {
    let value = try DriverCommand.reportValue(reporter: 1, channel: 9)
    #expect(value.opcode == 0x0E21)
    #expect(value.maximumResponseSize == RuntimeMessage.headerSize + 24)
    #expect(value.payload.count == 24)
    #expect(try value.payload.readRuntimeInteger(at: 16) as UInt64 == 0)
    let state = try DriverCommand.reportStateStatistics(4, reporter: 1, channel: 9)
    #expect(try state.payload.readRuntimeInteger(at: 16) as UInt64 == 4)
  }

  @Test
  func rejectsInvalidReporterRequests() {
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.setReportValue(1, reporter: 16, channel: 1)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.setReportValue(1, reporter: -1, channel: 1)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.reportValue(reporter: 0, channel: 0)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.adjustReportState(
        1,
        reporter: 0,
        channel: 1,
        residency: .max,
        transitions: 0
      )
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.overrideHistogramBucket(
        128,
        reporter: 0,
        channel: 1,
        hits: 0,
        minimum: 0,
        maximum: 0,
        sum: 0
      )
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.overrideHistogramBucket(
        0,
        reporter: 0,
        channel: 1,
        hits: 0,
        minimum: 2,
        maximum: 1,
        sum: 0
      )
    }
  }

  @Test
  func validatesReportingConfigurations() {
    #expect(Self.reporting.isValid)
    let invalid: [ReporterConfiguration] = [
      ReporterConfiguration(kind: .simple, group: "", channels: [channel(1)], categories: .traffic),
      ReporterConfiguration(
        kind: .simple,
        group: String(repeating: "g", count: 64),
        channels: [channel(1)],
        categories: .traffic
      ),
      ReporterConfiguration(
        kind: .simple,
        group: "G",
        subgroup: "a\0b",
        channels: [channel(1)],
        categories: .traffic
      ), ReporterConfiguration(kind: .simple, group: "G", channels: [], categories: .traffic),
      ReporterConfiguration(
        kind: .simple,
        group: "G",
        channels: [channel(0)],
        categories: .traffic
      ), ReporterConfiguration(kind: .simple, group: "G", channels: [channel(1)], categories: []),
      ReporterConfiguration(
        kind: .simple,
        group: "G",
        channels: [channel(1)],
        categories: ReportCategories(rawValue: 1)
      ),
      ReporterConfiguration(
        kind: .simple,
        group: "G",
        channels: (1...33).map { channel($0) },
        categories: .traffic
      ),
      ReporterConfiguration(
        kind: .state(states: []),
        group: "G",
        channels: [channel(1)],
        categories: .power
      ),
      ReporterConfiguration(
        kind: .state(states: [1, 1]),
        group: "G",
        channels: [channel(1)],
        categories: .power
      ),
      ReporterConfiguration(
        kind: .state(states: Array(1...17)),
        group: "G",
        channels: [channel(1)],
        categories: .power
      ),
      ReporterConfiguration(
        kind: .histogram(segments: [HistogramSegment(baseBucketWidth: 1, bucketCount: 4)]),
        group: "G",
        channels: [channel(1), channel(2)],
        categories: .performance
      ),
      ReporterConfiguration(
        kind: .histogram(segments: [HistogramSegment(baseBucketWidth: 1, bucketCount: 129)]),
        group: "G",
        channels: [channel(1)],
        categories: .performance
      ),
      ReporterConfiguration(
        kind: .histogram(segments: [
          HistogramSegment(baseBucketWidth: 1, scale: .exponential, bucketCount: 4)
        ]),
        group: "G",
        channels: [channel(1)],
        categories: .performance
      ),
      ReporterConfiguration(
        kind: .histogram(segments: []),
        group: "G",
        channels: [channel(1)],
        categories: .performance
      ),
    ]
    for reporter in invalid { #expect(!ReportingConfiguration(reporters: [reporter]).isValid) }
    #expect(!ReportingConfiguration(reporters: []).isValid)
    let simple = ReporterConfiguration(
      kind: .simple,
      group: "G",
      channels: [channel(1)],
      categories: .traffic
    )
    #expect(!ReportingConfiguration(reporters: [simple, simple]).isValid)
    #expect(!ReportingConfiguration(reporters: Array(repeating: simple, count: 17)).isValid)
  }

  static let reporting = ReportingConfiguration(reporters: [
    ReporterConfiguration(
      kind: .simple,
      group: "Traffic",
      subgroup: "Bytes",
      channels: [ReportChannel(id: 0x5458, name: "TX"), ReportChannel(id: 0x5258, name: "RX")],
      categories: .traffic,
      unit: .bytes
    ),
    ReporterConfiguration(
      kind: .state(states: [0x4F4E, 0x4F4646]),
      group: "Power",
      channels: [ReportChannel(id: 0x5057, name: "Link")],
      categories: .power,
      unit: .hardwareTicks
    ),
    ReporterConfiguration(
      kind: .histogram(segments: [
        HistogramSegment(baseBucketWidth: 10, bucketCount: 4),
        HistogramSegment(baseBucketWidth: 2, scale: .exponential, bucketCount: 8),
      ]),
      group: "Latency",
      channels: [ReportChannel(id: 0x4C54, name: "IO")],
      categories: [.performance, .field],
      unit: .microseconds
    ),
  ])

  private func channel(_ id: UInt64) -> ReportChannel { ReportChannel(id: id, name: "C\(id)") }
}
