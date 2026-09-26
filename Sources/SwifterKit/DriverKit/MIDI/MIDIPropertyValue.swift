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

  public static let name = Self("mnam")
  public static let manufacturer = Self("mmak")
  public static let model = Self("mmod")
  public static let uniqueID = Self("muid")
  public static let deviceID = Self("mdid")
  public static let receiveChannels = Self("rxch")
  public static let transmitChannels = Self("mtch")
  public static let maxSysExSpeed = Self("mmsp")
  public static let advanceScheduleTimeMuSec = Self("mast")
  public static let isEmbeddedEntity = Self("embe")
  public static let isBroadcast = Self("brca")
  public static let singleRealtimeEntity = Self("srte")
  public static let connectionUniqueID = Self("cuid")
  public static let offline = Self("moff")
  public static let `private` = Self("mprv")
  public static let driverOwner = Self("drow")
  public static let factoryPatchNameFile = Self("fpnf")
  public static let userPatchNameFile = Self("upnf")
  public static let nameConfiguration = Self("ncfg")
  public static let nameConfigurationDictionary = Self("ndct")
  public static let image = Self("mimg")
  public static let driverVersion = Self("dver")
  public static let supportsGeneralMIDI = Self("sgmd")
  public static let supportsMMC = Self("smmc")
  public static let canRoute = Self("canr")
  public static let receivesClock = Self("rclk")
  public static let receivesMTC = Self("rmtc")
  public static let receivesNotes = Self("rnts")
  public static let receivesProgramChanges = Self("rprc")
  public static let receivesBankSelectMSB = Self("rbsm")
  public static let receivesBankSelectLSB = Self("rbsl")
  public static let transmitsClock = Self("tclk")
  public static let transmitsMTC = Self("tmtc")
  public static let transmitsNotes = Self("tnts")
  public static let transmitsProgramChanges = Self("tprc")
  public static let transmitsBankSelectMSB = Self("tbsm")
  public static let transmitsBankSelectLSB = Self("tbsl")
  public static let panDisruptsStereo = Self("mpds")
  public static let isSampler = Self("samp")
  public static let isDrumMachine = Self("drmm")
  public static let isMixer = Self("mmix")
  public static let isEffectUnit = Self("effx")
  public static let maxReceiveChannels = Self("mxrc")
  public static let maxTransmitChannels = Self("mxtc")
  public static let driverDeviceEditorApp = Self("ddea")
  public static let supportsShowControl = Self("sscr")
  public static let displayName = Self("dnam")
  public static let protocolID = Self("prot")
  public static let umpActiveGroupBitmap = Self("uagb")
  public static let umpCanTransmitGroupless = Self("uctg")
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
      payload.appendRuntimeInteger(UInt32(0))
      payload.appendRuntimeInteger(property.rawValue)
    case .custom(let key):
      let bytes = try MIDIPropertyValue.key(key)
      payload.appendRuntimeInteger(UInt32(1))
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
/// as the `entities` array `IOUserMIDIDevice::SetProperties` accepts.
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
  public static let maximumDepth = 4
  /// The most entries one dictionary or array holds.
  public static let maximumEntries = 256

  func runtimePayload(depth: Int = 1) throws -> Data {
    var body = Data()
    let type: UInt32
    switch self {
    case .string(let value):
      body = Data(value.utf8)
      guard !body.contains(0) else { throw MIDIRuntimeError.invalidPropertyValue }
      type = 0
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
      type = 1
    case .data(let value):
      body = value
      type = 3
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
      type = 2
    case .array(let values):
      guard depth <= Self.maximumDepth, values.count <= Self.maximumEntries else {
        throw MIDIRuntimeError.invalidPropertyValue
      }
      body.appendRuntimeInteger(UInt32(values.count))
      body.appendRuntimeInteger(UInt32(0))
      for value in values { body.append(try value.runtimePayload(depth: depth + 1)) }
      type = 4
    }
    guard body.count <= RuntimeMessage.maximumSize - RuntimeMessage.headerSize else {
      throw MIDIRuntimeError.propertyValueTooLarge
    }
    var payload = Data(capacity: 8 + body.count)
    payload.appendRuntimeInteger(type)
    payload.appendRuntimeInteger(UInt32(body.count))
    payload.append(body)
    return payload
  }

  /// Decodes exactly one value that fills `payload`.
  init(runtimePayload payload: Data) throws {
    var offset = 0
    do { self = try Self.decode(Data(payload), at: &offset, depth: 1) } catch {
      // Truncated reads surface as RuntimeProtocolError; report them as malformed MIDI data.
      throw MIDIRuntimeError.invalidPayload
    }
    guard offset == payload.count else { throw MIDIRuntimeError.invalidPayload }
  }

  private static func decode(_ data: Data, at offset: inout Int, depth: Int) throws -> Self {
    let type: UInt32 = try data.readRuntimeInteger(at: offset)
    let length = Int(try data.readRuntimeInteger(at: offset + 4) as UInt32)
    let start = offset + 8
    guard length <= data.count - start else { throw MIDIRuntimeError.invalidPayload }
    let end = start + length
    offset = end
    switch type {
    case 0:
      let bytes = data[start..<end]
      guard !bytes.contains(0), let value = String(data: bytes, encoding: .utf8) else {
        throw MIDIRuntimeError.invalidPayload
      }
      return .string(value)
    case 1:
      guard length == 16 else { throw MIDIRuntimeError.invalidPayload }
      let bits: UInt32 = try data.readRuntimeInteger(at: start)
      let reserved: UInt32 = try data.readRuntimeInteger(at: start + 4)
      let raw: UInt64 = try data.readRuntimeInteger(at: start + 8)
      guard [8, 16, 32, 64].contains(bits), reserved == 0, bits == 64 || raw >> bits == 0 else {
        throw MIDIRuntimeError.invalidPayload
      }
      // OSNumber stores the low `bits` bits; sign-extend them.
      let shift = UInt64(64 - bits)
      return .number(Int64(bitPattern: raw << shift) >> shift, bits: bits)
    case 3: return .data(Data(data[start..<end]))
    case 2, 4:
      guard depth <= maximumDepth, length >= 8 else { throw MIDIRuntimeError.invalidPayload }
      let count = Int(try data.readRuntimeInteger(at: start) as UInt32)
      let reserved: UInt32 = try data.readRuntimeInteger(at: start + 4)
      guard reserved == 0, count <= maximumEntries else { throw MIDIRuntimeError.invalidPayload }
      let body = Data(data[start..<end])
      var cursor = 8
      var values: [Self] = []
      var entries: [String: Self] = [:]
      for _ in 0..<count {
        if type == 4 {
          values.append(try decode(body, at: &cursor, depth: depth + 1))
          continue
        }
        let keyLength = Int(try body.readRuntimeInteger(at: cursor) as UInt32)
        let keyReserved: UInt32 = try body.readRuntimeInteger(at: cursor + 4)
        cursor += 8
        guard keyReserved == 0, (1...255).contains(keyLength), keyLength <= body.count - cursor,
          let key = String(data: body[cursor..<(cursor + keyLength)], encoding: .utf8),
          !key.utf8.contains(0), entries[key] == nil
        else { throw MIDIRuntimeError.invalidPayload }
        cursor += keyLength
        entries[key] = try decode(body, at: &cursor, depth: depth + 1)
      }
      guard cursor == body.count else { throw MIDIRuntimeError.invalidPayload }
      return type == 2 ? .dictionary(entries) : .array(values)
    default: throw MIDIRuntimeError.invalidPayload
    }
  }

  static func key(_ key: String) throws -> Data {
    let bytes = Data(key.utf8)
    guard !bytes.isEmpty, bytes.count <= 255, !bytes.contains(0) else {
      throw MIDIRuntimeError.invalidPropertyKey
    }
    return bytes
  }
}
