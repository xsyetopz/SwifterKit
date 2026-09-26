import Foundation

// Typed `IOHIDEventService` dispatches for a generated HID event service. A zero timestamp asks
// the extension to stamp the event with the current mach absolute time. Pointer, scroll, and
// digitizer coordinates travel as 16.16 `IOFixed` values.

extension DriverCommand {
  /// Dispatches a keyboard or consumer key through `dispatchKeyboardEvent`.
  public static func dispatchHIDKeyboardEvent(
    usagePage: UInt32,
    usage: UInt32,
    value: UInt32,
    options: UInt32 = 0,
    repeats: Bool = true,
    timestamp: UInt64 = 0
  ) -> Self {
    var payload = Data(capacity: 32)
    payload.appendRuntimeInteger(timestamp)
    payload.append(HIDLimits.words([usagePage, usage, value, options, repeats ? 1 : 0, 0]))
    return dispatch(.hidDispatchKeyboard, payload)
  }

  /// Dispatches relative pointer motion through `dispatchRelativePointerEvent`.
  public static func dispatchHIDRelativePointerEvent(
    dx: Double,
    dy: Double,
    buttons: UInt32 = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) throws -> Self {
    dispatch(
      .hidDispatchRelativePointer,
      try pointer(timestamp, dx, dy, 0, buttons, options, accelerates)
    )
  }

  /// Dispatches an absolute pointer position through `dispatchAbsolutePointerEvent`.
  public static func dispatchHIDAbsolutePointerEvent(
    x: Double,
    y: Double,
    buttons: UInt32 = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) throws -> Self {
    dispatch(
      .hidDispatchAbsolutePointer,
      try pointer(timestamp, x, y, 0, buttons, options, accelerates)
    )
  }

  /// Dispatches scroll-wheel motion through `dispatchRelativeScrollWheelEvent`.
  public static func dispatchHIDScrollEvent(
    dx: Double,
    dy: Double,
    dz: Double = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) throws -> Self {
    dispatch(.hidDispatchScroll, try pointer(timestamp, dx, dy, dz, 0, options, accelerates))
  }

  /// Dispatches one stylus through `dispatchDigitizerStylusEvent`.
  public static func dispatchHIDStylusEvent(
    _ stylus: HIDStylus,
    timestamp: UInt64 = 0
  ) throws -> Self {
    let fixed = try [
      stylus.x, stylus.y, stylus.tipPressure, stylus.barrelPressure, stylus.tiltX, stylus.tiltY,
      stylus.twist,
    ].map(HIDFixed.raw)
    guard stylus.state.rawValue & ~RuntimeHIDStylusFlag.allBits == 0 else {
      throw HIDRuntimeError.valueOutOfRange
    }
    var payload = Data(capacity: 64)
    payload.appendRuntimeInteger(timestamp)
    payload.appendRuntimeInteger(stylus.identifier)
    for value in fixed { payload.appendRuntimeInteger(value) }
    payload.appendRuntimeInteger(stylus.pointerType)
    payload.appendRuntimeInteger(stylus.effect)
    payload.appendRuntimeInteger(stylus.uniqueID)
    payload.appendRuntimeInteger(stylus.state.rawValue)
    payload.appendRuntimeInteger(UInt32(0))
    return dispatch(.hidDispatchDigitizerStylus, payload)
  }

  /// Dispatches up to 64 fingers at once through `dispatchDigitizerTouchEvent`.
  public static func dispatchHIDTouchEvent(
    _ touches: [HIDTouch],
    timestamp: UInt64 = 0
  ) throws -> Self {
    guard !touches.isEmpty, touches.count <= HIDLimits.maximumTouches else {
      throw HIDRuntimeError.invalidItemCount
    }
    var payload = Data(capacity: 16 + touches.count * 16)
    payload.appendRuntimeInteger(timestamp)
    payload.append(HIDLimits.words([UInt32(touches.count), 0]))
    for touch in touches {
      guard touch.state.rawValue & ~RuntimeHIDTouchFlag.allBits == 0 else {
        throw HIDRuntimeError.valueOutOfRange
      }
      payload.appendRuntimeInteger(touch.identifier)
      payload.appendRuntimeInteger(try HIDFixed.raw(touch.x))
      payload.appendRuntimeInteger(try HIDFixed.raw(touch.y))
      payload.appendRuntimeInteger(touch.state.rawValue)
    }
    return dispatch(.hidDispatchDigitizerTouches, payload)
  }

  /// Dispatches one transducer through an `IOHIDDigitizerCollection`.
  public static func dispatchHIDDigitizerCollection(
    _ collection: HIDDigitizerCollection,
    timestamp: UInt64 = 0
  ) throws -> Self {
    let cookies = collection.elementCookies
    guard cookies.count <= HIDLimits.maximumCollectionElements else {
      throw HIDRuntimeError.invalidItemCount
    }
    guard !cookies.contains(0), Set(cookies).count == cookies.count, collection.parentCookie != 0
    else { throw HIDRuntimeError.invalidCookie }
    guard collection.changes.rawValue & ~RuntimeHIDCollectionChange.allBits == 0 else {
      throw HIDRuntimeError.valueOutOfRange
    }
    let flags =
      (collection.touch ? RuntimeHIDCollectionFlag.touch.rawValue : 0)
      | (collection.inRange ? RuntimeHIDCollectionFlag.inRange.rawValue : 0) | collection.changes
      .rawValue << RuntimeHIDLimits.collectionChangeShift
    var payload = Data(capacity: 40 + cookies.count * 4)
    payload.appendRuntimeInteger(timestamp)
    payload.append(
      HIDLimits.words([
        collection.type.rawValue, collection.identifier, collection.parentCookie ?? 0, flags,
      ])
    )
    for value in [collection.x, collection.y, collection.z] {
      payload.appendRuntimeInteger(try HIDFixed.raw(value))
    }
    payload.append(HIDLimits.words([UInt32(cookies.count)] + cookies))
    return dispatch(.hidDispatchDigitizerCollection, payload)
  }

  /// Dispatches a standard game controller through `dispatchStandardGameControllerEvent`.
  public static func dispatchHIDGameControllerEvent(
    _ state: HIDGameControllerState,
    options: UInt32 = 0,
    timestamp: UInt64 = 0
  ) throws -> Self {
    dispatch(.hidDispatchGameController, try gameController(state, options, timestamp))
  }

  /// Dispatches an extended game controller through
  /// `dispatchExtendedGameControllerEventWithOptionalButtons`, which needs DriverKit 23.0 on the
  /// running system; older systems answer `kIOReturnUnsupported`.
  public static func dispatchHIDExtendedGameControllerEvent(
    _ state: HIDGameControllerState,
    buttons: HIDGameControllerOptionalButtons,
    options: UInt32 = 0,
    timestamp: UInt64 = 0
  ) throws -> Self {
    var payload = try gameController(state, options, timestamp)
    for value in buttons.values { payload.appendRuntimeInteger(try HIDFixed.raw(value)) }
    return dispatch(.hidDispatchExtendedGameController, payload)
  }

  /// Sets an LED-page usage through `SetLED`, which `IOUserHIDEventDriver` writes to the
  /// device's LED elements.
  public static func setHIDLED(usage: UInt32, on: Bool) -> Self {
    dispatch(.hidSetLED, HIDLimits.words([RuntimeHIDLimits.ledUsagePage, usage, on ? 1 : 0, 0]))
  }

  /// Sets an LED through `SetLEDState`; the change is also delivered as
  /// ``DriverEvent/hidLEDState()``.
  public static func setHIDLEDState(usagePage: UInt32, usage: UInt32, on: Bool) -> Self {
    dispatch(.hidSetLEDState, HIDLimits.words([usagePage, usage, on ? 1 : 0, 0]))
  }

  /// Asks `IOUserHIDEventService::conformsTo` whether the service matches a usage.
  public static func hidServiceConforms(usagePage: UInt32, usage: UInt32) -> Self {
    Self(
      opcode: .hidServiceConformsTo,
      requiredCapabilities: .hid,
      payload: HIDLimits.words([0, usagePage, usage, 0]),
      maximumResponseSize: RuntimeMessage.headerSize + 4
    )
  }

  /// Chooses which parsed `IOUserHIDEventDriver` categories dispatch events; categories the
  /// configuration did not parse stay silent.
  public static func setHIDEventDriverCategories(
    _ categories: HIDEventDriverCategories
  ) throws -> Self {
    guard categories.subtracting(.all).isEmpty else { throw HIDRuntimeError.valueOutOfRange }
    return dispatch(.hidSetEventDriverCategories, HIDLimits.words([0, categories.rawValue]))
  }

  private static func dispatch(_ opcode: RuntimeOpcode, _ payload: Data) -> Self {
    Self(
      opcode: opcode,
      requiredCapabilities: .hid,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize
    )
  }

  // swiftlint:disable:next function_parameter_count
  private static func pointer(
    _ timestamp: UInt64,
    _ x: Double,
    _ y: Double,
    _ z: Double,
    _ buttons: UInt32,
    _ options: UInt32,
    _ accelerates: Bool
  ) throws -> Data {
    var payload = Data(capacity: 32)
    payload.appendRuntimeInteger(timestamp)
    for value in [x, y, z] { payload.appendRuntimeInteger(try HIDFixed.raw(value)) }
    payload.append(HIDLimits.words([buttons, options, accelerates ? 1 : 0]))
    return payload
  }

  private static func gameController(
    _ state: HIDGameControllerState,
    _ options: UInt32,
    _ timestamp: UInt64
  ) throws -> Data {
    var payload = Data(capacity: 104)
    payload.appendRuntimeInteger(timestamp)
    for value in state.axes { payload.appendRuntimeInteger(try HIDFixed.raw(value)) }
    let flags =
      (state.thumbstickButtonLeft ? RuntimeHIDGameControllerFlag.thumbstickButtonLeft.rawValue : 0)
      | (state.thumbstickButtonRight
        ? RuntimeHIDGameControllerFlag.thumbstickButtonRight.rawValue : 0)
    payload.append(HIDLimits.words([flags, options]))
    return payload
  }
}

extension DriverContext {
  /// Dispatches a keyboard or consumer key through `dispatchKeyboardEvent`.
  public func dispatchHIDKeyboardEvent(
    usagePage: UInt32,
    usage: UInt32,
    value: UInt32,
    options: UInt32 = 0,
    repeats: Bool = true,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDKeyboardEvent(
        usagePage: usagePage,
        usage: usage,
        value: value,
        options: options,
        repeats: repeats,
        timestamp: timestamp
      )
    )
  }

  /// Dispatches relative pointer motion through `dispatchRelativePointerEvent`.
  public func dispatchHIDRelativePointerEvent(
    dx: Double,
    dy: Double,
    buttons: UInt32 = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDRelativePointerEvent(
        dx: dx,
        dy: dy,
        buttons: buttons,
        options: options,
        accelerates: accelerates,
        timestamp: timestamp
      )
    )
  }

  /// Dispatches an absolute pointer position through `dispatchAbsolutePointerEvent`.
  public func dispatchHIDAbsolutePointerEvent(
    x: Double,
    y: Double,
    buttons: UInt32 = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDAbsolutePointerEvent(
        x: x,
        y: y,
        buttons: buttons,
        options: options,
        accelerates: accelerates,
        timestamp: timestamp
      )
    )
  }

  /// Dispatches scroll-wheel motion through `dispatchRelativeScrollWheelEvent`.
  public func dispatchHIDScrollEvent(
    dx: Double,
    dy: Double,
    dz: Double = 0,
    options: UInt32 = 0,
    accelerates: Bool = true,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDScrollEvent(
        dx: dx,
        dy: dy,
        dz: dz,
        options: options,
        accelerates: accelerates,
        timestamp: timestamp
      )
    )
  }

  /// Dispatches one stylus through `dispatchDigitizerStylusEvent`.
  public func dispatchHIDStylusEvent(_ stylus: HIDStylus, timestamp: UInt64 = 0) async throws {
    _ = try await execute(.dispatchHIDStylusEvent(stylus, timestamp: timestamp))
  }

  /// Dispatches up to 64 fingers at once through `dispatchDigitizerTouchEvent`.
  public func dispatchHIDTouchEvent(_ touches: [HIDTouch], timestamp: UInt64 = 0) async throws {
    _ = try await execute(.dispatchHIDTouchEvent(touches, timestamp: timestamp))
  }

  /// Dispatches one transducer through an `IOHIDDigitizerCollection`.
  public func dispatchHIDDigitizerCollection(
    _ collection: HIDDigitizerCollection,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(.dispatchHIDDigitizerCollection(collection, timestamp: timestamp))
  }

  /// Dispatches a standard game controller through `dispatchStandardGameControllerEvent`.
  public func dispatchHIDGameControllerEvent(
    _ state: HIDGameControllerState,
    options: UInt32 = 0,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDGameControllerEvent(state, options: options, timestamp: timestamp)
    )
  }

  /// Dispatches an extended game controller with optional buttons.
  public func dispatchHIDExtendedGameControllerEvent(
    _ state: HIDGameControllerState,
    buttons: HIDGameControllerOptionalButtons,
    options: UInt32 = 0,
    timestamp: UInt64 = 0
  ) async throws {
    _ = try await execute(
      .dispatchHIDExtendedGameControllerEvent(
        state,
        buttons: buttons,
        options: options,
        timestamp: timestamp
      )
    )
  }

  /// Sets an LED-page usage through `SetLED`.
  public func setHIDLED(usage: UInt32, on: Bool) async throws {
    _ = try await execute(.setHIDLED(usage: usage, on: on))
  }

  /// Sets an LED through `SetLEDState`.
  public func setHIDLEDState(usagePage: UInt32, usage: UInt32, on: Bool) async throws {
    _ = try await execute(.setHIDLEDState(usagePage: usagePage, usage: usage, on: on))
  }

  /// Asks `IOUserHIDEventService::conformsTo` whether the service matches a usage.
  public func hidServiceConforms(usagePage: UInt32, usage: UInt32) async throws -> Bool {
    try HIDLimits.flag(from: await execute(.hidServiceConforms(usagePage: usagePage, usage: usage)))
  }

  /// Chooses which parsed `IOUserHIDEventDriver` categories dispatch events.
  public func setHIDEventDriverCategories(_ categories: HIDEventDriverCategories) async throws {
    _ = try await execute(.setHIDEventDriverCategories(categories))
  }
}
