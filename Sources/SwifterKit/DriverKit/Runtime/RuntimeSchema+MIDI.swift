// MIDI wire constants: lifecycle events, object targets, and property values.
//
// `RuntimeSchemaHeader` renders these into `SwifterKitRuntimeSchema.h`, which
// `SwifterKitRuntimeMIDI.cpp`, `SwifterKitRuntimeMIDIObjects.cpp`, and
// `SwifterKitRuntimeMIDIProperties.cpp` read, so neither side spells a value twice.

/// What a `midi` event reports. See `SwifterKitMIDIEventHeader`.
enum RuntimeMIDIEventKind: UInt32, CaseIterable {
  case startIO = 1
  case stopIO = 2
  case received = 3
}

/// The object a MIDI object command addresses, the first `u32` of its payload.
enum RuntimeMIDITargetKind: UInt32, CaseIterable {
  case driver = 0
  case device = 1
  case entity = 2
  case source = 3
  case destination = 4
  case object = 5
}

/// How a MIDI property command names its property, the `u32` after the target.
enum RuntimeMIDIKeyKind: UInt32, CaseIterable {
  /// An `IOUserMIDIProperty` selector.
  case selector = 0
  /// A UTF-8 string key.
  case string = 1
}

/// Bounds and markers of the MIDI object commands.
enum RuntimeMIDIObjectLimits {
  /// Stands in for a class ID on the driver, which is not an `IOUserMIDIObject`.
  static let driverClass: UInt32 = 0xFFFF_FFFF
  /// The most object IDs one list response carries.
  static let maximumListedObjects = 64
  /// The longest object name, in UTF-8 bytes.
  static let nameMaximumLength = 255
}

/// The value type that begins each value in the MIDI property encoding.
enum RuntimeMIDIValueType: UInt32, CaseIterable {
  case string = 0
  case number = 1
  case dictionary = 2
  case data = 3
  case array = 4
}

/// Bounds of the MIDI property encoding.
enum RuntimeMIDIPropertyLimits {
  /// The deepest nesting of dictionaries and arrays, counting the outermost.
  static let maximumDepth = 4
  /// The most entries one dictionary or array holds.
  static let maximumEntries = 256
  /// The longest dictionary or property key, in UTF-8 bytes.
  static let keyMaximumLength = 255
}
