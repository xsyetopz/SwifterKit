import Foundation

/// Stylus state bits for ``HIDStylus``, from `IOHIDDigitizerStylusData`.
public struct HIDStylusState: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a stylus state from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The stylus is within range of the surface.
  public static let inRange = Self(rawValue: 1 << 0)
  /// The tip touches the surface.
  public static let tip = Self(rawValue: 1 << 1)
  /// The barrel switch is pressed.
  public static let barrelSwitch = Self(rawValue: 1 << 2)
  /// The stylus is inverted.
  public static let invert = Self(rawValue: 1 << 3)
  /// The eraser touches the surface.
  public static let eraser = Self(rawValue: 1 << 4)
  /// The tip state changed since the last event.
  public static let tipChanged = Self(rawValue: 1 << 5)
  /// The position changed since the last event.
  public static let positionChanged = Self(rawValue: 1 << 6)
  /// The range state changed since the last event.
  public static let rangeChanged = Self(rawValue: 1 << 7)
}

/// One stylus transducer for `dispatchDigitizerStylusEvent`.
///
/// Positions, pressures, tilt, and twist are `IOFixed` values; `x` and `y` are normalized to
/// `0...1` of the surface.
public struct HIDStylus: Sendable, Hashable {
  /// The transducer identifier.
  public var identifier: UInt32
  /// The normalized horizontal position.
  public var x: Double
  /// The normalized vertical position.
  public var y: Double
  /// The tip pressure.
  public var tipPressure: Double
  /// The barrel pressure.
  public var barrelPressure: Double
  /// The horizontal tilt in degrees.
  public var tiltX: Double
  /// The vertical tilt in degrees.
  public var tiltY: Double
  /// The twist in degrees.
  public var twist: Double
  /// The `IOHIDDigitizerStylusData` pointer type.
  public var pointerType: UInt32
  /// The `IOHIDDigitizerStylusData` effect.
  public var effect: UInt32
  /// The stylus's unique identifier, or zero.
  public var uniqueID: UInt64
  /// Range, tip, switch, and change bits.
  public var state: HIDStylusState

  /// Creates a stylus transducer.
  public init(
    identifier: UInt32,
    x: Double,
    y: Double,
    tipPressure: Double = 0,
    barrelPressure: Double = 0,
    tiltX: Double = 0,
    tiltY: Double = 0,
    twist: Double = 0,
    pointerType: UInt32 = 0,
    effect: UInt32 = 0,
    uniqueID: UInt64 = 0,
    state: HIDStylusState
  ) {
    self.identifier = identifier
    self.x = x
    self.y = y
    self.tipPressure = tipPressure
    self.barrelPressure = barrelPressure
    self.tiltX = tiltX
    self.tiltY = tiltY
    self.twist = twist
    self.pointerType = pointerType
    self.effect = effect
    self.uniqueID = uniqueID
    self.state = state
  }
}

/// Touch state bits for ``HIDTouch``, from `IOHIDDigitizerTouchData`.
public struct HIDTouchState: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a touch state from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The finger is within range of the surface.
  public static let inRange = Self(rawValue: 1 << 0)
  /// The finger touches the surface.
  public static let touch = Self(rawValue: 1 << 1)
  /// The touch is valid rather than a palm or other rejected contact.
  public static let touchValid = Self(rawValue: 1 << 2)
  /// The touch state changed since the last event.
  public static let touchChanged = Self(rawValue: 1 << 3)
  /// The position changed since the last event.
  public static let positionChanged = Self(rawValue: 1 << 4)
  /// The range state changed since the last event.
  public static let rangeChanged = Self(rawValue: 1 << 5)
}

/// One finger transducer for `dispatchDigitizerTouchEvent`, positioned in `0...1` of the surface.
public struct HIDTouch: Sendable, Hashable {
  /// The transducer identifier.
  public var identifier: UInt32
  /// The normalized horizontal position.
  public var x: Double
  /// The normalized vertical position.
  public var y: Double
  /// Range, touch, validity, and change bits.
  public var state: HIDTouchState

  /// Creates a touch transducer.
  public init(identifier: UInt32, x: Double, y: Double, state: HIDTouchState) {
    self.identifier = identifier
    self.x = x
    self.y = y
    self.state = state
  }
}

/// The transducer kind of a ``HIDDigitizerCollection``, from `IOHIDDigitizerCollectionType`.
public enum HIDDigitizerCollectionType: UInt32, Sendable, Hashable {
  /// A stylus; dispatched as a stylus event.
  case stylus = 0
  /// A puck; dispatched as a stylus event.
  case puck = 1
  /// A finger; dispatched as a touch event.
  case finger = 2
  /// A hand; dispatched as a touch event.
  case hand = 3
}

/// Which parts of a ``HIDDigitizerCollection`` changed since its last event.
public struct HIDDigitizerChanges: OptionSet, Sendable, Hashable {
  /// The underlying bit mask.
  public let rawValue: UInt32

  /// Creates a change set from its raw bit mask.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// The touch or tip state changed.
  public static let touch = Self(rawValue: 1 << 0)
  /// The position changed.
  public static let position = Self(rawValue: 1 << 1)
  /// The range state changed.
  public static let range = Self(rawValue: 1 << 2)
}

/// One digitizer transducer and the interface elements that describe it.
///
/// The runtime builds an `IOHIDDigitizerCollection` over ``elementCookies`` under the collection
/// element ``parentCookie``, sets its touch, range, and position, and dispatches the collection's
/// state as a stylus event (stylus, puck) or a touch event (finger, hand), with `z` as the tip
/// pressure of a stylus.
public struct HIDDigitizerCollection: Sendable, Hashable {
  /// The transducer kind.
  public var type: HIDDigitizerCollectionType
  /// The transducer identifier.
  public var identifier: UInt32
  /// The collection element that groups the transducer, if any.
  public var parentCookie: UInt32?
  /// The interface elements that belong to the transducer.
  public var elementCookies: [UInt32]
  /// The normalized horizontal position.
  public var x: Double
  /// The normalized vertical position.
  public var y: Double
  /// The pressure or distance axis.
  public var z: Double
  /// Whether the transducer touches the surface.
  public var touch: Bool
  /// Whether the transducer is within range.
  public var inRange: Bool
  /// What changed since the last event.
  public var changes: HIDDigitizerChanges

  /// Creates a digitizer collection.
  public init(
    type: HIDDigitizerCollectionType,
    identifier: UInt32,
    parentCookie: UInt32? = nil,
    elementCookies: [UInt32] = [],
    x: Double,
    y: Double,
    z: Double = 0,
    touch: Bool,
    inRange: Bool,
    changes: HIDDigitizerChanges = []
  ) {
    self.type = type
    self.identifier = identifier
    self.parentCookie = parentCookie
    self.elementCookies = elementCookies
    self.x = x
    self.y = y
    self.z = z
    self.touch = touch
    self.inRange = inRange
    self.changes = changes
  }
}

/// The controls of a standard game controller, as `IOFixed` values in `0...1`, with signed
/// joystick axes in `-1...1`.
public struct HIDGameControllerState: Sendable, Hashable {
  /// Directional pad up.
  public var dpadUp: Double
  /// Directional pad down.
  public var dpadDown: Double
  /// Directional pad left.
  public var dpadLeft: Double
  /// Directional pad right.
  public var dpadRight: Double
  /// Face button X.
  public var faceX: Double
  /// Face button Y.
  public var faceY: Double
  /// Face button A.
  public var faceA: Double
  /// Face button B.
  public var faceB: Double
  /// Left shoulder L1.
  public var shoulderL1: Double
  /// Right shoulder R1.
  public var shoulderR1: Double
  /// Left trigger L2.
  public var shoulderL2: Double
  /// Right trigger R2.
  public var shoulderR2: Double
  /// Left joystick X.
  public var joystickX: Double
  /// Left joystick Y.
  public var joystickY: Double
  /// Right joystick Z (horizontal).
  public var joystickZ: Double
  /// Right joystick Rz (vertical).
  public var joystickRz: Double
  /// Left thumbstick button.
  public var thumbstickButtonLeft: Bool
  /// Right thumbstick button.
  public var thumbstickButtonRight: Bool

  /// Creates a controller state with every control released.
  public init() {
    dpadUp = 0
    dpadDown = 0
    dpadLeft = 0
    dpadRight = 0
    faceX = 0
    faceY = 0
    faceA = 0
    faceB = 0
    shoulderL1 = 0
    shoulderR1 = 0
    shoulderL2 = 0
    shoulderR2 = 0
    joystickX = 0
    joystickY = 0
    joystickZ = 0
    joystickRz = 0
    thumbstickButtonLeft = false
    thumbstickButtonRight = false
  }

  var axes: [Double] {
    [
      dpadUp, dpadDown, dpadLeft, dpadRight, faceX, faceY, faceA, faceB, shoulderL1, shoulderR1,
      shoulderL2, shoulderR2, joystickX, joystickY, joystickZ, joystickRz,
    ]
  }
}

/// The optional buttons of an extended game controller, as `IOFixed` values in `0...1`.
public struct HIDGameControllerOptionalButtons: Sendable, Hashable {
  /// Left shoulder L4.
  public var shoulderL4: Double
  /// Right shoulder R4.
  public var shoulderR4: Double
  /// Bottom paddle M1.
  public var bottomM1: Double
  /// Bottom paddle M2.
  public var bottomM2: Double
  /// Bottom paddle M3.
  public var bottomM3: Double
  /// Bottom paddle M4.
  public var bottomM4: Double

  /// Creates optional buttons, all released unless given.
  public init(
    shoulderL4: Double = 0,
    shoulderR4: Double = 0,
    bottomM1: Double = 0,
    bottomM2: Double = 0,
    bottomM3: Double = 0,
    bottomM4: Double = 0
  ) {
    self.shoulderL4 = shoulderL4
    self.shoulderR4 = shoulderR4
    self.bottomM1 = bottomM1
    self.bottomM2 = bottomM2
    self.bottomM3 = bottomM3
    self.bottomM4 = bottomM4
  }

  var values: [Double] { [shoulderL4, shoulderR4, bottomM1, bottomM2, bottomM3, bottomM4] }
}
