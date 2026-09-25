import Foundation
import Testing

@testable import SwifterKit

@Suite
struct HIDDispatchCommandsTests {
  private func words(_ data: Data, from offset: Int = 0) throws -> [UInt32] {
    try stride(from: offset, to: data.count, by: 4).map { try data.readRuntimeInteger(at: $0) }
  }

  @Test
  func encodesKeyboardPointerAndScroll() throws {
    let key = DriverCommand.dispatchHIDKeyboardEvent(
      usagePage: 7,
      usage: 4,
      value: 1,
      repeats: false,
      timestamp: 5
    )
    #expect(key.opcode == RuntimeOpcode.hidDispatchKeyboard.rawValue)
    #expect(key.payload.count == 32)
    #expect(try key.payload.readRuntimeInteger(at: 0) as UInt64 == 5)
    #expect(try words(key.payload, from: 8) == [7, 4, 1, 0, 0, 0])

    let relative = try DriverCommand.dispatchHIDRelativePointerEvent(dx: 1.5, dy: -2, buttons: 1)
    #expect(relative.opcode == RuntimeOpcode.hidDispatchRelativePointer.rawValue)
    #expect(
      try words(relative.payload, from: 8) == [98_304, UInt32(bitPattern: -131_072), 0, 1, 0, 1]
    )

    let absolute = try DriverCommand.dispatchHIDAbsolutePointerEvent(
      x: 0.5,
      y: 0.25,
      accelerates: false
    )
    #expect(absolute.opcode == RuntimeOpcode.hidDispatchAbsolutePointer.rawValue)
    #expect(try words(absolute.payload, from: 8) == [32_768, 16_384, 0, 0, 0, 0])

    let scroll = try DriverCommand.dispatchHIDScrollEvent(dx: 0, dy: 1, dz: 2)
    #expect(try words(scroll.payload, from: 8) == [0, 65_536, 131_072, 0, 0, 1])
  }

  @Test
  func encodesDigitizers() throws {
    let stylus = try DriverCommand.dispatchHIDStylusEvent(
      HIDStylus(
        identifier: 3,
        x: 0.5,
        y: 1,
        tipPressure: 0.25,
        uniqueID: 9,
        state: [.inRange, .tip]
      )
    )
    #expect(stylus.payload.count == 64)
    #expect(try words(stylus.payload.subdata(in: 8..<24)) == [3, 32_768, 65_536, 16_384])
    #expect(try stylus.payload.readRuntimeInteger(at: 48) as UInt64 == 9)
    #expect(try words(stylus.payload, from: 56) == [3, 0])

    let touches = try DriverCommand.dispatchHIDTouchEvent([
      HIDTouch(identifier: 1, x: 0, y: 0.5, state: [.touch, .touchValid]),
      HIDTouch(identifier: 2, x: 1, y: 1, state: .inRange),
    ])
    #expect(touches.payload.count == 48)
    #expect(try words(touches.payload, from: 8) == [2, 0, 1, 0, 32_768, 6, 2, 65_536, 65_536, 1])

    let collection = try DriverCommand.dispatchHIDDigitizerCollection(
      HIDDigitizerCollection(
        type: .finger,
        identifier: 4,
        parentCookie: 10,
        elementCookies: [11, 12],
        x: 0.5,
        y: 0.5,
        touch: true,
        inRange: true,
        changes: [.touch, .position]
      )
    )
    #expect(collection.opcode == RuntimeOpcode.hidDispatchDigitizerCollection.rawValue)
    #expect(try words(collection.payload, from: 8) == [2, 4, 10, 15, 32_768, 32_768, 0, 2, 11, 12])
  }

  @Test
  func encodesGameControllersLEDsAndCategories() throws {
    var state = HIDGameControllerState()
    state.faceA = 1
    state.joystickX = -1
    state.thumbstickButtonRight = true
    let standard = try DriverCommand.dispatchHIDGameControllerEvent(state, options: 4)
    #expect(standard.payload.count == 80)
    let values = try words(standard.payload, from: 8)
    #expect(values[6] == 65_536)
    #expect(values[12] == UInt32(bitPattern: -65_536))
    #expect(Array(values.suffix(2)) == [2, 4])

    let extended = try DriverCommand.dispatchHIDExtendedGameControllerEvent(
      state,
      buttons: HIDGameControllerOptionalButtons(bottomM4: 1)
    )
    #expect(extended.payload.count == 104)
    #expect(try words(extended.payload, from: 80) == [0, 0, 0, 0, 0, 65_536])

    #expect(try words(DriverCommand.setHIDLED(usage: 2, on: true).payload) == [8, 2, 1, 0])
    let ledState = DriverCommand.setHIDLEDState(usagePage: 8, usage: 1, on: false)
    #expect(try words(ledState.payload) == [8, 1, 0, 0])
    #expect(
      try words(DriverCommand.hidServiceConforms(usagePage: 1, usage: 2).payload) == [0, 1, 2, 0]
    )
    let categories = try DriverCommand.setHIDEventDriverCategories([.keyboard, .scroll])
    #expect(try words(categories.payload) == [0, 5])
  }

  @Test
  func rejectsMalformedDispatches() {
    #expect(throws: HIDRuntimeError.valueOutOfRange) {
      try DriverCommand.dispatchHIDRelativePointerEvent(dx: .infinity, dy: 0)
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.dispatchHIDTouchEvent([])
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.dispatchHIDTouchEvent(
        Array(repeating: HIDTouch(identifier: 1, x: 0, y: 0, state: []), count: 65)
      )
    }
    #expect(throws: HIDRuntimeError.valueOutOfRange) {
      try DriverCommand.dispatchHIDTouchEvent([
        HIDTouch(identifier: 1, x: 0, y: 0, state: HIDTouchState(rawValue: 1 << 6))
      ])
    }
    #expect(throws: HIDRuntimeError.valueOutOfRange) {
      try DriverCommand.dispatchHIDStylusEvent(
        HIDStylus(identifier: 1, x: 0, y: 0, state: HIDStylusState(rawValue: 1 << 8))
      )
    }
    #expect(throws: HIDRuntimeError.invalidCookie) {
      try DriverCommand.dispatchHIDDigitizerCollection(
        HIDDigitizerCollection(
          type: .stylus,
          identifier: 1,
          elementCookies: [3, 3],
          x: 0,
          y: 0,
          touch: false,
          inRange: false
        )
      )
    }
    #expect(throws: HIDRuntimeError.invalidItemCount) {
      try DriverCommand.dispatchHIDDigitizerCollection(
        HIDDigitizerCollection(
          type: .stylus,
          identifier: 1,
          elementCookies: Array(1...65),
          x: 0,
          y: 0,
          touch: false,
          inRange: false
        )
      )
    }
    #expect(throws: HIDRuntimeError.valueOutOfRange) {
      try DriverCommand.setHIDEventDriverCategories(HIDEventDriverCategories(rawValue: 1 << 8))
    }
  }
}
