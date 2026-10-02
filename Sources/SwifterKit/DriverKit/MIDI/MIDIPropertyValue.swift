import Foundation

/// A CoreMIDI property selector, `IOUserMIDIProperty`.
public struct MIDIProperty: RawRepresentable, Sendable, Hashable {
  /// The unmodified four-character selector.
  public let rawValue: UInt32
  /// Preserves a raw `IOUserMIDIProperty` selector.
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  private init(_ code: StaticString) {
    rawValue = code.withUTF8Buffer { $0.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
  }

  /// The name of the MIDI object.
  public static let name = Self("mnam")
  /// The manufacturer of the MIDI object.
  public static let manufacturer = Self("mmak")
  /// The model name of the MIDI object.
  public static let model = Self("mmod")
  /// The unique numeric identifier of the MIDI object.
  public static let uniqueID = Self("muid")
  /// The MIDI device ID of the entity.
  public static let deviceID = Self("mdid")
  /// The number of MIDI channels that the entity receives.
  public static let receiveChannels = Self("rxch")
  /// The number of MIDI channels that the entity transmits.
  public static let transmitChannels = Self("mtch")
  /// The maximum System Exclusive transfer speed in bytes per second.
  public static let maxSysExSpeed = Self("mmsp")
  /// The scheduling advance time in microseconds.
  public static let advanceScheduleTimeMuSec = Self("mast")
  /// Indicates whether the device contains this entity.
  public static let isEmbeddedEntity = Self("embe")
  /// Indicates whether the endpoint broadcasts messages to all destinations.
  public static let isBroadcast = Self("brca")
  /// Identifies the single real-time entity associated with the endpoint.
  public static let singleRealtimeEntity = Self("srte")
  /// The unique ID of the connected MIDI object.
  public static let connectionUniqueID = Self("cuid")
  /// Indicates whether the MIDI object is offline.
  public static let offline = Self("moff")
  /// Indicates whether the MIDI object is private.
  public static let `private` = Self("mprv")
  /// The name of the driver that owns the MIDI object.
  public static let driverOwner = Self("drow")
  /// The path to the factory patch names file.
  public static let factoryPatchNameFile = Self("fpnf")
  /// The path to the user patch names file.
  public static let userPatchNameFile = Self("upnf")
  /// The name configuration for the MIDI object.
  public static let nameConfiguration = Self("ncfg")
  /// The dictionary of names for the MIDI object.
  public static let nameConfigurationDictionary = Self("ndct")
  /// The image associated with the MIDI object.
  public static let image = Self("mimg")
  /// The version number of the MIDI driver.
  public static let driverVersion = Self("dver")
  /// Indicates whether the MIDI object supports General MIDI.
  public static let supportsGeneralMIDI = Self("sgmd")
  /// Indicates whether the MIDI object supports MIDI Machine Control.
  public static let supportsMMC = Self("smmc")
  /// Indicates whether the MIDI object can route MIDI data.
  public static let canRoute = Self("canr")
  /// Indicates whether the MIDI object receives MIDI clock messages.
  public static let receivesClock = Self("rclk")
  /// Indicates whether the MIDI object receives MIDI Time Code.
  public static let receivesMTC = Self("rmtc")
  /// Indicates whether the MIDI object receives MIDI note messages.
  public static let receivesNotes = Self("rnts")
  /// Indicates whether the MIDI object receives program changes.
  public static let receivesProgramChanges = Self("rprc")
  /// Indicates whether the MIDI object receives Bank Select MSB messages.
  public static let receivesBankSelectMSB = Self("rbsm")
  /// Indicates whether the MIDI object receives Bank Select LSB messages.
  public static let receivesBankSelectLSB = Self("rbsl")
  /// Indicates whether the MIDI object transmits MIDI clock messages.
  public static let transmitsClock = Self("tclk")
  /// Indicates whether the MIDI object transmits MIDI Time Code.
  public static let transmitsMTC = Self("tmtc")
  /// Indicates whether the MIDI object transmits MIDI note messages.
  public static let transmitsNotes = Self("tnts")
  /// Indicates whether the MIDI object transmits program changes.
  public static let transmitsProgramChanges = Self("tprc")
  /// Indicates whether the MIDI object transmits Bank Select MSB messages.
  public static let transmitsBankSelectMSB = Self("tbsm")
  /// Indicates whether the MIDI object transmits Bank Select LSB messages.
  public static let transmitsBankSelectLSB = Self("tbsl")
  /// Indicates whether panning disrupts stereo output.
  public static let panDisruptsStereo = Self("mpds")
  /// Indicates whether the MIDI object is a sampler.
  public static let isSampler = Self("samp")
  /// Indicates whether the MIDI object is a drum machine.
  public static let isDrumMachine = Self("drmm")
  /// Indicates whether the MIDI object is a mixer.
  public static let isMixer = Self("mmix")
  /// Indicates whether the MIDI object is an effect unit.
  public static let isEffectUnit = Self("effx")
  /// The maximum number of MIDI channels that the entity can receive.
  public static let maxReceiveChannels = Self("mxrc")
  /// The maximum number of MIDI channels that the entity can transmit.
  public static let maxTransmitChannels = Self("mxtc")
  /// The application URL for the driver device editor.
  public static let driverDeviceEditorApp = Self("ddea")
  /// Indicates whether the MIDI object supports MIDI Show Control.
  public static let supportsShowControl = Self("sscr")
  /// The name that identifies the MIDI object in user interfaces.
  public static let displayName = Self("dnam")
  /// The MIDI protocol supported by the endpoint.
  public static let protocolID = Self("prot")
  /// A bitmap of the active UMP groups on the endpoint.
  public static let umpActiveGroupBitmap = Self("uagb")
  /// Indicates whether the endpoint can transmit UMP groupless messages.
  public static let umpCanTransmitGroupless = Self("uctg")
  /// The unique ID of the endpoint associated with this object.
  public static let associatedEndpoint = Self("aept")
}

/// Names a property by selector or by string key.
public enum MIDIPropertyKey: Sendable, Hashable {
  /// The `IOUserMIDIProperty` overloads of `CopyProperty` and `SetProperty`.
  case property(MIDIProperty)
  /// The `OSString` key overloads of `CopyProperty` and `SetProperty`.
  case custom(String)

  func runtimePayload() throws -> Data {
    var payload = Data()
    switch self {
    case .property(let property):
      guard property.rawValue != 0 else { throw MIDIRuntimeError.invalidPropertyKey }
      payload.appendRuntimeInteger(RuntimeMIDIKeyKind.selector.rawValue)
      payload.appendRuntimeInteger(property.rawValue)
    case .custom(let key):
      let bytes = try MIDIPropertyValue.key(key)
      payload.appendRuntimeInteger(RuntimeMIDIKeyKind.string.rawValue)
      payload.appendRuntimeInteger(UInt32(bytes.count))
      payload.append(bytes)
    }
    return payload
  }
}

/// A MIDIDriverKit property value, mapped to and from `OSObject` by the extension.
///
/// Numbers keep their `OSNumber` width: `bits` is 8, 16, 32, or 64, and the value must fit that
/// signed width. CoreMIDI integer properties are 32-bit. `array` exists for nested values such
/// as the `entities` array a device's properties dictionary accepts.
public indirect enum MIDIPropertyValue: Sendable, Hashable {
  /// An `OSString`.
  case string(String)
  /// An `OSNumber` of `bits` width.
  case number(Int64, bits: UInt32)
  /// An `OSData`.
  case data(Data)
  /// An `OSDictionary` with string keys.
  case dictionary([String: Self])
  /// An `OSArray`.
  case array([Self])

  /// A 32-bit number, the width of CoreMIDI integer properties.
  public static func int32(_ value: Int32) -> Self { .number(Int64(value), bits: 32) }

  /// The deepest nesting of dictionaries and arrays, counting the outermost.
  public static let maximumDepth = RuntimeMIDIPropertyLimits.maximumDepth
  /// The most entries one dictionary or array holds.
  public static let maximumEntries = RuntimeMIDIPropertyLimits.maximumEntries

  func runtimePayload(depth: Int = 1) throws -> Data {
    var body = Data()
    let type: RuntimeMIDIValueType
    switch self {
    case .string(let value):
      body = Data(value.utf8)
      guard !body.contains(0) else { throw MIDIRuntimeError.invalidPropertyValue }
      type = .string
    case .number(let value, let bits):
      guard [8, 16, 32, 64].contains(bits) else { throw MIDIRuntimeError.invalidPropertyValue }
      let limit = Int64(1) << (Int64(bits) - 1) &- 1
      guard bits == 64 || (value >= ~limit && value <= limit) else {
        throw MIDIRuntimeError.invalidPropertyValue
      }
      body.appendRuntimeInteger(bits)
      body.appendRuntimeInteger(UInt32(0))
      // The wire carries the low `bits` bits, as OSNumber stores them.
      let mask = bits == 64 ? UInt64.max : (UInt64(1) << UInt64(bits)) - 1
      body.appendRuntimeInteger(UInt64(bitPattern: value) & mask)
      type = .number
    case .data(let value):
      body = value
      type = .data
    case .dictionary(let entries):
      guard depth <= Self.maximumDepth, entries.count <= Self.maximumEntries else {
        throw MIDIRuntimeError.invalidPropertyValue
      }
      body.appendRuntimeInteger(UInt32(entries.count))
      body.appendRuntimeInteger(UInt32(0))
      for key in entries.keys.sorted() {
        let bytes = try Self.key(key)
        body.appendRuntimeInteger(UInt32(bytes.count))
        body.appendRuntimeInteger(UInt32(0))
        body.append(bytes)
        body.append(try entries[key, default: .data(Data())].runtimePayload(depth: depth + 1))
      }
      type = .dictionary
    case .array(let values):
      guard depth <= Self.maximumDepth, values.count <= Self.maximumEntries else {
        throw MIDIRuntimeError.invalidPropertyValue
      }
      body.appendRuntimeInteger(UInt32(values.count))
      body.appendRuntimeInteger(UInt32(0))
      for value in values { body.append(try value.runtimePayload(depth: depth + 1)) }
      type = .array
    }
    guard body.count <= RuntimeMessage.maximumSize - RuntimeMessage.headerSize else {
      throw MIDIRuntimeError.propertyValueTooLarge
    }
    var payload = Data(capacity: 8 + body.count)
    payload.appendRuntimeInteger(type.rawValue)
    payload.appendRuntimeInteger(UInt32(body.count))
    payload.append(body)
    return payload
  }

  /// Decodes exactly one value that fills `payload`.
  init(runtimePayload payload: Data) throws {
    var offset = 0
    do { self = try Self.decode(Data(payload), at: &offset, depth: 1) } catch {
      // A truncated read throws RuntimeProtocolError. Report it as malformed MIDI data.
      throw MIDIRuntimeError.invalidPayload
    }
    guard offset == payload.count else { throw MIDIRuntimeError.invalidPayload }
  }

  private static func decode(_ data: Data, at offset: inout Int, depth: Int) throws -> Self {
    let rawType: UInt32 = try data.readRuntimeInteger(at: offset)
    let length = Int(try data.readRuntimeInteger(at: offset + 4) as UInt32)
    let start = offset + 8
    guard length <= data.count - start else { throw MIDIRuntimeError.invalidPayload }
    let end = start + length
    offset = end
    let type = RuntimeMIDIValueType(rawValue: rawType)
    switch type {
    case .string?:
      let bytes = data[start..<end]
      guard !bytes.contains(0), let value = String(data: bytes, encoding: .utf8) else {
        throw MIDIRuntimeError.invalidPayload
      }
      return .string(value)
    case .number?:
      guard length == 16 else { throw MIDIRuntimeError.invalidPayload }
      let bits: UInt32 = try data.readRuntimeInteger(at: start)
      let reserved: UInt32 = try data.readRuntimeInteger(at: start + 4)
      let raw: UInt64 = try data.readRuntimeInteger(at: start + 8)
      guard [8, 16, 32, 64].contains(bits), reserved == 0, bits == 64 || raw >> bits == 0 else {
        throw MIDIRuntimeError.invalidPayload
      }
      // OSNumber stores the low `bits` bits. Sign-extend them.
      let shift = UInt64(64 - bits)
      return .number(Int64(bitPattern: raw << shift) >> shift, bits: bits)
    case .data?: return .data(Data(data[start..<end]))
    case .dictionary?, .array?:
      guard depth <= maximumDepth, length >= 8 else { throw MIDIRuntimeError.invalidPayload }
      let count = Int(try data.readRuntimeInteger(at: start) as UInt32)
      let reserved: UInt32 = try data.readRuntimeInteger(at: start + 4)
      guard reserved == 0, count <= maximumEntries else { throw MIDIRuntimeError.invalidPayload }
      let body = Data(data[start..<end])
      var cursor = 8
      var values: [Self] = []
      var entries: [String: Self] = [:]
      for _ in 0..<count {
        if type == .array {
          values.append(try decode(body, at: &cursor, depth: depth + 1))
          continue
        }
        let keyLength = Int(try body.readRuntimeInteger(at: cursor) as UInt32)
        let keyReserved: UInt32 = try body.readRuntimeInteger(at: cursor + 4)
        cursor += 8
        guard keyReserved == 0,
          (1...RuntimeMIDIPropertyLimits.keyMaximumLength).contains(keyLength),
          keyLength <= body.count - cursor,
          let key = String(data: body[cursor..<(cursor + keyLength)], encoding: .utf8),
          !key.utf8.contains(0), entries[key] == nil
        else { throw MIDIRuntimeError.invalidPayload }
        cursor += keyLength
        entries[key] = try decode(body, at: &cursor, depth: depth + 1)
      }
      guard cursor == body.count else { throw MIDIRuntimeError.invalidPayload }
      return type == .dictionary ? .dictionary(entries) : .array(values)
    case nil: throw MIDIRuntimeError.invalidPayload
    }
  }

  static func key(_ key: String) throws -> Data {
    let bytes = Data(key.utf8)
    guard !bytes.isEmpty, bytes.count <= RuntimeMIDIPropertyLimits.keyMaximumLength,
      !bytes.contains(0)
    else { throw MIDIRuntimeError.invalidPropertyKey }
    return bytes
  }
}
