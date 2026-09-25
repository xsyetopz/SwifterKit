import Foundation
import Testing

@testable import SwifterKit

@Suite
struct ServiceDispatchCommandsTests {
  @Test
  func encodesTimerCommands() throws {
    let oneShot = try DriverCommand.startTimer(afterNanoseconds: 5_000, leewayNanoseconds: 100)
    #expect(oneShot.opcode == 0x0E00)
    #expect(oneShot.requiredCapabilities.isEmpty)
    #expect(oneShot.maximumResponseSize == RuntimeMessage.headerSize + 8)
    #expect(oneShot.payload.count == 24)
    #expect(try oneShot.payload.readRuntimeInteger(at: 0) as UInt64 == 5_000)
    #expect(try oneShot.payload.readRuntimeInteger(at: 8) as UInt64 == 0)
    #expect(try oneShot.payload.readRuntimeInteger(at: 16) as UInt64 == 100)

    let repeating = try DriverCommand.startTimer(
      afterNanoseconds: 0,
      repeatingEveryNanoseconds: ServiceTimerLimits.minimumIntervalNanoseconds
    )
    #expect(try repeating.payload.readRuntimeInteger(at: 8) as UInt64 == 1_000_000)

    let cancel = try DriverCommand.cancelTimer(ServiceTimer(id: 7))
    #expect(cancel.opcode == 0x0E01)
    #expect(cancel.payload == Data([7, 0, 0, 0, 0, 0, 0, 0]))
    #expect(cancel.maximumResponseSize == RuntimeMessage.headerSize)
  }

  @Test
  func rejectsInvalidTimers() {
    let limit = ServiceTimerLimits.maximumNanoseconds
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.startTimer(afterNanoseconds: limit + 1)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.startTimer(afterNanoseconds: 0, leewayNanoseconds: limit + 1)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.startTimer(afterNanoseconds: 0, repeatingEveryNanoseconds: 999_999)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.startTimer(afterNanoseconds: 0, repeatingEveryNanoseconds: limit + 1)
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.cancelTimer(ServiceTimer(id: 0))
    }
  }

  @Test
  func decodesTimerFirings() throws {
    var payload = Data()
    payload.appendRuntimeInteger(UInt32(3))
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(UInt64(2))
    payload.appendRuntimeInteger(UInt64(123_456))
    let firing = try #require(
      try DriverEvent(type: RuntimeEventType.timer.rawValue, payload: [UInt8](payload))
        .timerFiring()
    )
    #expect(firing.timer == ServiceTimer(id: 3))
    #expect(firing.fireCount == 2)
    #expect(firing.timestamp == 123_456)
    #expect(try DriverEvent(type: 0x0100, payload: []).timerFiring() == nil)

    for invalid in [payload.dropLast(), zeroed(payload, at: 0), zeroed(payload, at: 8)] {
      #expect(throws: ServiceRuntimeError.invalidPayload) {
        try DriverEvent(type: RuntimeEventType.timer.rawValue, payload: [UInt8](invalid))
          .timerFiring()
      }
    }
    var reserved = payload
    reserved[4] = 1
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try DriverEvent(type: RuntimeEventType.timer.rawValue, payload: [UInt8](reserved))
        .timerFiring()
    }
  }

  @Test
  func encodesWatchCommands() throws {
    let match = DriverServiceMatch(
      serviceClass: "IOPCIDevice",
      name: "display",
      registryProperties: ["vendor-id": .unsignedInteger(0x1234)]
    )
    let services = try DriverCommand.watchServices(matching: match)
    #expect(services.opcode == 0x0E10)
    #expect(services.maximumResponseSize == RuntimeMessage.headerSize + 8)
    #expect(
      try ServicePropertyCoding.decode(services.payload)
        == .dictionary([
          "IOProviderClass": .string("IOPCIDevice"), "IONameMatch": .string("display"),
          "IOPropertyMatch": .dictionary(["vendor-id": .unsignedInteger(0x1234)]),
        ])
    )

    let state = try DriverCommand.watchSystemState(items: ["com.example.state"])
    #expect(state.opcode == 0x0E11)
    #expect(
      try ServicePropertyCoding.decode(state.payload) == .array([.string("com.example.state")])
    )

    let cancel = try DriverCommand.cancelWatch(ServiceWatch(id: 9))
    #expect(cancel.opcode == 0x0E12)
    #expect(cancel.payload == Data([9, 0, 0, 0, 0, 0, 0, 0]))
  }

  @Test
  func rejectsInvalidWatches() {
    #expect(throws: ServiceRuntimeError.invalidName("")) {
      try DriverCommand.watchServices(matching: DriverServiceMatch(serviceClass: ""))
    }
    #expect(throws: ServiceRuntimeError.invalidName("a\0b")) {
      try DriverCommand.watchServices(
        matching: DriverServiceMatch(serviceClass: "IOService", name: "a\0b")
      )
    }
    #expect(throws: ServiceRuntimeError.unsupportedProperty) {
      try DriverCommand.watchServices(
        matching: DriverServiceMatch(serviceClass: "IOService", registryProperties: ["x": .real(1)])
      )
    }
    #expect(throws: ServiceRuntimeError.emptyRequest) {
      try DriverCommand.watchSystemState(items: [])
    }
    #expect(throws: ServiceRuntimeError.payloadTooLarge) {
      try DriverCommand.watchSystemState(items: (0...8).map { "item\($0)" })
    }
    let long = String(repeating: "x", count: 128)
    #expect(throws: ServiceRuntimeError.invalidName(long)) {
      try DriverCommand.watchSystemState(items: [long])
    }
    #expect(throws: ServiceRuntimeError.invalidValue) {
      try DriverCommand.cancelWatch(ServiceWatch(id: 0))
    }
  }

  @Test
  func decodesServiceMatchNotifications() throws {
    let payload = serviceEvent(kind: 1, name: "display0")
    let event = DriverEvent(
      type: RuntimeEventType.watchServices.rawValue,
      payload: [UInt8](payload)
    )
    let notification = try #require(try event.serviceMatchNotification())
    #expect(notification.watch == ServiceWatch(id: 4))
    #expect(notification.kind == .matched)
    #expect(notification.sequence == 1)
    #expect(notification.registryEntryID == 0x1_0000_0042)
    #expect(notification.name == "display0")
    #expect(try serviceNotification(serviceEvent(kind: 0, name: "")).kind == .terminated)

    for invalid in [
      serviceEvent(kind: 2, name: "x"), payload.dropLast(), zeroed(payload, at: 0),
      zeroed(payload, at: 8),
    ] { #expect(throws: ServiceRuntimeError.invalidPayload) { try serviceNotification(invalid) } }
  }

  @Test
  func decodesSystemStateNotifications() throws {
    let value = try ServicePropertyCoding.encode(.dictionary(["on": .boolean(true)]))
    let payload = stateEvent(item: "com.example.state", value: value)
    let notification = try #require(
      try DriverEvent(type: RuntimeEventType.watchSystemState.rawValue, payload: [UInt8](payload))
        .systemStateNotification()
    )
    #expect(notification.watch == ServiceWatch(id: 5))
    #expect(notification.sequence == 3)
    #expect(notification.item == "com.example.state")
    #expect(notification.value == ["on": .boolean(true)])
    #expect(try stateNotification(stateEvent(item: "x", value: Data())).value == nil)

    let array = try ServicePropertyCoding.encode(.array([]))
    for invalid in [
      stateEvent(item: "", value: Data()), stateEvent(item: "x", value: array),
      stateEvent(item: "x", value: value.dropLast()), payload.prefix(20),
    ] { #expect(throws: ServiceRuntimeError.self) { try stateNotification(invalid) } }
    #expect(throws: ServiceRuntimeError.invalidPayload) {
      try stateNotification(zeroed(stateEvent(item: "x", value: Data()), at: 8))
    }
  }

  private func zeroed(_ data: Data, at offset: Int) -> Data {
    var copy = data
    copy.replaceSubrange(offset..<(offset + 4), with: [0, 0, 0, 0])
    if offset == 8 { copy.replaceSubrange(8..<16, with: [UInt8](repeating: 0, count: 8)) }
    return copy
  }

  private func serviceEvent(kind: UInt32, name: String) -> Data {
    var data = Data()
    data.appendRuntimeInteger(UInt32(4))
    data.appendRuntimeInteger(kind)
    data.appendRuntimeInteger(UInt64(1))
    data.appendRuntimeInteger(UInt64(0x1_0000_0042))
    data.appendRuntimeInteger(UInt32(name.utf8.count))
    data.appendRuntimeInteger(UInt32(0))
    data.append(contentsOf: name.utf8)
    return data
  }

  private func stateEvent(item: String, value: Data) -> Data {
    var data = Data()
    data.appendRuntimeInteger(UInt32(5))
    data.appendRuntimeInteger(UInt32(item.utf8.count))
    data.appendRuntimeInteger(UInt64(3))
    data.append(contentsOf: item.utf8)
    data.append(value)
    return data
  }

  private func serviceNotification(_ payload: Data) throws -> ServiceMatchNotification {
    try #require(
      try DriverEvent(type: RuntimeEventType.watchServices.rawValue, payload: [UInt8](payload))
        .serviceMatchNotification()
    )
  }

  private func stateNotification(_ payload: Data) throws -> SystemStateNotification {
    try #require(
      try DriverEvent(type: RuntimeEventType.watchSystemState.rawValue, payload: [UInt8](payload))
        .systemStateNotification()
    )
  }
}
