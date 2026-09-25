import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceCommandsTests {
  @Test
  func typedValuesMatchDriverKitConstants() {
    #expect(
      [ServicePowerCapability.off, .on, .low, .lowPowerWake].map(\.rawValue) == [
        0, 0x2, 0x1_0000, 0x2_0000,
      ]
    )
    #expect(ServicePMAssertionOptions.all.rawValue == 0x801)
    #expect(
      ServiceBusStall.allCases.map(\.rawValue) == [
        0, 5_000, 10_000, 20_000, 25_000, 30_000, 40_000,
      ]
    )
    #expect(ServicePropertySearchOptions.parents.rawValue == 0x1)
    #expect(RuntimeEventType.servicePowerState.rawValue == 0x0D00)
  }

  @Test
  func encodesRegistryCommands() throws {
    let set = try DriverCommand.setServiceProperties(["Ready": .boolean(true)])
    #expect(set.opcode == 0x0D00)
    #expect(set.requiredCapabilities.isEmpty)
    #expect(set.maximumResponseSize == RuntimeMessage.headerSize)
    #expect(try ServicePropertyCoding.decode(set.payload) == .dictionary(["Ready": .boolean(true)]))

    #expect(DriverCommand.serviceProperties.opcode == 0x0D01)
    #expect(DriverCommand.serviceProperties.payload.isEmpty)
    #expect(DriverCommand.serviceProperties.maximumResponseSize == RuntimeMessage.maximumSize)

    let remove = try DriverCommand.removeServiceProperty(named: "Ready")
    #expect(remove.opcode == 0x0D02)
    #expect(remove.payload == Data("Ready".utf8))

    let search = try DriverCommand.searchServiceProperty(named: "vendor-id", options: .parents)
    #expect(search.opcode == 0x0D03)
    #expect(try search.payload.readRuntimeInteger(at: 0) as UInt32 == 1)
    #expect(try search.payload.readRuntimeInteger(at: 4) as UInt16 == 9)
    #expect(try search.payload.readRuntimeInteger(at: 6) as UInt16 == 9)
    #expect(search.payload.dropFirst(8) == Data("vendor-idIOService".utf8))

    let provider = try DriverCommand.providerProperties(keys: ["IOClass"])
    #expect(provider.opcode == 0x0D04)
    #expect(try ServicePropertyCoding.decode(provider.payload) == .array([.string("IOClass")]))
    #expect(try DriverCommand.providerProperties().payload.isEmpty)

    #expect(DriverCommand.serviceName.opcode == 0x0D05)
    #expect(DriverCommand.serviceName.maximumResponseSize == RuntimeMessage.headerSize + 127)
    #expect(DriverCommand.registryEntryID.opcode == 0x0D06)
    #expect(DriverCommand.registryEntryID.maximumResponseSize == RuntimeMessage.headerSize + 8)
  }

  @Test
  func encodesSystemStateAndAnalyticsCommands() throws {
    let copy = try DriverCommand.systemStateItem(named: "com.apple.iokit.pm.sleepdescription")
    #expect(copy.opcode == 0x0D30)
    #expect(try copy.payload.readRuntimeInteger(at: 0) as UInt32 == 35)
    #expect(try copy.payload.readRuntimeInteger(at: 4) as UInt32 == 0)
    #expect(copy.payload.count == 8 + 35)
    #expect(copy.maximumResponseSize == RuntimeMessage.maximumSize)

    let create = try DriverCommand.createSystemStateItem(named: "item")
    #expect(create.opcode == 0x0D31)
    #expect(create.payload.count == 12)

    let set = try DriverCommand.setSystemStateItem(named: "item", value: ["on": .boolean(true)])
    #expect(set.opcode == 0x0D32)
    #expect(
      try ServicePropertyCoding.decode(set.payload.dropFirst(12))
        == .dictionary(["on": .boolean(true)])
    )

    let event = try DriverCommand.sendCoreAnalyticsEvent(named: "e", payload: [:])
    #expect(event.opcode == 0x0D33)
    #expect(event.payload.dropFirst(9) == Data([6, 0, 0, 0, 0]))
  }

  @Test
  func encodesPowerAndBusyCommands() throws {
    let change = try DriverCommand.changePowerState(.low)
    #expect(change.opcode == 0x0D10)
    #expect(change.payload == Data([0, 0, 1, 0]))
    #expect(DriverCommand.setPowerOverride(true).payload == Data([1, 0, 0, 0]))
    #expect(DriverCommand.setPowerOverride(true).opcode == 0x0D11)

    let assertion = try DriverCommand.createPMAssertion(.cpu, synced: true)
    #expect(assertion.opcode == 0x0D12)
    #expect(assertion.payload == Data([1, 0, 0, 0, 1, 0, 0, 0]))
    #expect(assertion.maximumResponseSize == RuntimeMessage.headerSize + 8)
    let release = try DriverCommand.releasePMAssertion(ServicePMAssertion(id: 9))
    #expect(release.opcode == 0x0D13)
    #expect(try release.payload.readRuntimeInteger(at: 0) as UInt64 == 9)

    let complete = try DriverCommand.completePowerState(requestID: 3)
    #expect(complete.opcode == 0x0D14)
    #expect(complete.payload == Data([3, 0, 0, 0, 0, 0, 0, 0]))

    #expect(try DriverCommand.adjustBusy(by: -1).payload == Data([0xFF, 0xFF, 0xFF, 0xFF]))
    #expect(try DriverCommand.adjustBusy(by: 1).opcode == 0x0D20)
    #expect(DriverCommand.busyState.opcode == 0x0D21)
    #expect(DriverCommand.busyState.maximumResponseSize == RuntimeMessage.headerSize + 4)
    let stall = DriverCommand.requireMaxBusStall(.microseconds10)
    #expect(stall.opcode == 0x0D22)
    #expect(try stall.payload.readRuntimeInteger(at: 0) as UInt64 == 10_000)
    #expect(DriverCommand.terminateService.opcode == 0x0D23)
    #expect(DriverCommand.terminateService.payload.isEmpty)
  }

  @Test
  func rejectsInvalidRequestsBeforeSending() {
    #expect(throws: ServiceRuntimeError.emptyRequest) {
      try DriverCommand.setServiceProperties([:])
    }
    #expect(throws: ServiceRuntimeError.emptyRequest) {
      try DriverCommand.providerProperties(keys: [])
    }
    #expect(throws: ServiceRuntimeError.invalidName("")) {
      try DriverCommand.providerProperties(keys: [""])
    }
    #expect(throws: ServiceRuntimeError.invalidOptions) {
      try DriverCommand.searchServiceProperty(named: "a", options: .init(rawValue: 2))
    }
    #expect(throws: ServiceRuntimeError.invalidName("")) {
      try DriverCommand.searchServiceProperty(named: "a", plane: "")
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.changePowerState(.lowPowerWake)
    }
    #expect(throws: ServiceRuntimeError.invalidOptions) { try DriverCommand.createPMAssertion([]) }
    #expect(throws: ServiceRuntimeError.invalidOptions) {
      try DriverCommand.createPMAssertion(.all, synced: true)
    }
    #expect(throws: ServiceRuntimeError.invalidOptions) {
      try DriverCommand.createPMAssertion(.init(rawValue: 0x2))
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.releasePMAssertion(ServicePMAssertion(id: 0))
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.completePowerState(requestID: 0)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) { try DriverCommand.adjustBusy(by: 0) }
    #expect(throws: ServiceRuntimeError.payloadTooLarge) {
      try DriverCommand.setSystemStateItem(
        named: "item",
        value: ["d": .data(Data(count: ServicePropertyCoding.maximumPayloadSize - 20))]
      )
    }
  }

  @Test
  func decodesPowerStateEvents() throws {
    let event = DriverEvent(type: 0x0D00, payload: [7, 0, 0, 0, 0, 0, 1, 0])
    let request = try #require(try event.servicePowerState())
    #expect(request.requestID == 7)
    #expect(request.capability == .low)
    #expect(try DriverEvent(type: 0x0700, payload: []).servicePowerState() == nil)
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0D00, payload: [0, 0, 0, 0, 2, 0, 0, 0]).servicePowerState()
    }
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try DriverEvent(type: 0x0D00, payload: [1, 0, 0, 0]).servicePowerState()
    }
  }

  @Test
  func detachedContextRejectsServiceCalls() async {
    let context = DriverContext(capabilities: [])
    await #expect(throws: DriverContextError.notConnected) { try await context.registryEntryID() }
  }
}
