import Foundation

/// A MIDIDriverKit object addressed by a runtime command.
public enum MIDIObjectTarget: Sendable, Hashable {
  /// The `IOUserMIDIDriver` service itself.
  case driver
  /// The generated `IOUserMIDIDevice`.
  case device
  /// The generated `IOUserMIDIEntity`.
  case entity
  /// A generated `IOUserMIDISource`, by its zero-based index in the entity.
  case source(UInt32)
  /// A generated `IOUserMIDIDestination`, by its zero-based index in the entity.
  case destination(UInt32)
  /// Any object the driver publishes, resolved through `GetMIDIObjectForObjectID`.
  case object(UInt32)

  /// The largest number of sources or destinations one generated entity declares.
  public static let maximumEndpointCount: UInt32 = 32

  var runtimeFields: (kind: UInt32, index: UInt32) {
    switch self {
    case .driver: (RuntimeMIDITargetKind.driver.rawValue, 0)
    case .device: (RuntimeMIDITargetKind.device.rawValue, 0)
    case .entity: (RuntimeMIDITargetKind.entity.rawValue, 0)
    case .source(let index): (RuntimeMIDITargetKind.source.rawValue, index)
    case .destination(let index): (RuntimeMIDITargetKind.destination.rawValue, index)
    case .object(let objectID): (RuntimeMIDITargetKind.object.rawValue, objectID)
    }
  }

  func validated() throws -> Self {
    switch self {
    case .driver, .device, .entity: return self
    case .source(let index), .destination(let index):
      guard index < Self.maximumEndpointCount else { throw MIDIRuntimeError.invalidObjectTarget }
      return self
    case .object(let objectID):
      guard objectID != 0 else { throw MIDIRuntimeError.invalidObjectTarget }
      return self
    }
  }
}

/// A MIDIDriverKit object class identifier, `IOUserMIDIClassID`.
public enum MIDIClassID: UInt32, Sendable, Hashable {
  /// `IOUserMIDIObject`.
  case object = 0
  /// `IOUserMIDISource`.
  case source = 1
  /// `IOUserMIDIDestination`.
  case destination = 2
  /// `IOUserMIDIEndpoint`.
  case endpoint = 3
  /// `IOUserMIDIEntity`.
  case entity = 4
  /// `IOUserMIDIDevice`.
  case device = 5
}

/// The value type MIDIDriverKit reports for a property, `IOUserMIDIPropertyType`.
public enum MIDIPropertyType: UInt32, Sendable, Hashable {
  /// An `OSString`.
  case string = 0
  /// An `OSNumber`.
  case number = 1
  /// An `OSDictionary`.
  case dictionary = 2
  /// An `OSData`.
  case data = 3
}

/// Identity metadata read from a MIDIDriverKit object or the driver.
public struct MIDIObjectInfo: Sendable, Hashable {
  /// The object's `IOUserMIDIObjectID`; the driver is always `1`.
  public let objectID: UInt32
  /// The owning object's ID, or zero for the driver.
  public let ownerObjectID: UInt32
  /// The concrete class, or `nil` for the driver, which is not an `IOUserMIDIObject`.
  public let classID: MIDIClassID?
  /// The base class, or `nil` for the driver.
  public let baseClassID: MIDIClassID?
  /// The object name, or an empty string when none is set.
  public let name: String

  static let driverClass = RuntimeMIDIObjectLimits.driverClass

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 24 else { throw MIDIRuntimeError.invalidPayload }
    objectID = try runtimePayload.readRuntimeInteger(at: 0)
    ownerObjectID = try runtimePayload.readRuntimeInteger(at: 4)
    let rawClass: UInt32 = try runtimePayload.readRuntimeInteger(at: 8)
    let rawBase: UInt32 = try runtimePayload.readRuntimeInteger(at: 12)
    let nameLength = Int(try runtimePayload.readRuntimeInteger(at: 16) as UInt32)
    let reserved: UInt32 = try runtimePayload.readRuntimeInteger(at: 20)
    guard reserved == 0, objectID != 0, nameLength <= RuntimeMIDIObjectLimits.nameMaximumLength,
      runtimePayload.count == 24 + nameLength,
      (rawClass == Self.driverClass) == (rawBase == Self.driverClass),
      let name = String(data: runtimePayload.suffix(nameLength), encoding: .utf8)
    else { throw MIDIRuntimeError.invalidPayload }
    if rawClass == Self.driverClass {
      guard objectID == 1, ownerObjectID == 0 else { throw MIDIRuntimeError.invalidPayload }
      classID = nil
      baseClassID = nil
    } else {
      guard let classID = MIDIClassID(rawValue: rawClass),
        let baseClassID = MIDIClassID(rawValue: rawBase)
      else { throw MIDIRuntimeError.invalidPayload }
      self.classID = classID
      self.baseClassID = baseClassID
    }
    self.name = name
  }
}

/// Running state and entities of the generated MIDI device.
public struct MIDIDeviceState: Sendable, Hashable {
  /// `IOUserMIDIDevice::GetDeviceIsRunning`.
  public let isRunning: Bool
  /// Object IDs of the entities `GetEntities` returns, in order.
  public let entityObjectIDs: [UInt32]

  init(runtimePayload: Data) throws {
    let (flag, ids) = try MIDIObjectIDList.decode(runtimePayload)
    guard flag <= 1 else { throw MIDIRuntimeError.invalidPayload }
    isRunning = flag == 1
    entityObjectIDs = ids
  }
}

/// Sources and destinations the generated entity currently holds.
public struct MIDIEntityMembers: Sendable, Hashable {
  /// Object IDs of the sources `GetSources` returns, in order.
  public let sourceObjectIDs: [UInt32]
  /// Object IDs of the destinations `GetDestinations` returns, in order.
  public let destinationObjectIDs: [UInt32]

  init(runtimePayload: Data) throws {
    let (sourceCount, ids) = try MIDIObjectIDList.decode(runtimePayload)
    guard Int(sourceCount) <= ids.count else { throw MIDIRuntimeError.invalidPayload }
    sourceObjectIDs = Array(ids.prefix(Int(sourceCount)))
    destinationObjectIDs = Array(ids.dropFirst(Int(sourceCount)))
  }
}

/// A generated object that can leave its owner and rejoin it.
public enum MIDIMember: Sendable, Hashable {
  /// The entity, through `IOUserMIDIDevice::RemoveEntity` and `AddEntity`.
  case entity
  /// A source, through `IOUserMIDIEntity::RemoveSource` and `AddSource`.
  case source(UInt32)
  /// A destination, through `IOUserMIDIEntity::RemoveDestination` and `AddDestination`.
  case destination(UInt32)

  var target: MIDIObjectTarget {
    switch self {
    case .entity: .entity
    case .source(let index): .source(index)
    case .destination(let index): .destination(index)
    }
  }
}

/// Decodes `u32 value, u32 count, count × u32 object ID` responses.
enum MIDIObjectIDList {
  /// The most object IDs one list response carries.
  static let maximumCount = RuntimeMIDIObjectLimits.maximumListedObjects

  static func decode(_ payload: Data) throws -> (UInt32, [UInt32]) {
    guard payload.count >= 8 else { throw MIDIRuntimeError.invalidPayload }
    let value: UInt32 = try payload.readRuntimeInteger(at: 0)
    let count = Int(try payload.readRuntimeInteger(at: 4) as UInt32)
    guard count <= maximumCount, payload.count == 8 + count * 4 else {
      throw MIDIRuntimeError.invalidPayload
    }
    var ids: [UInt32] = []
    ids.reserveCapacity(count)
    for index in 0..<count {
      let id: UInt32 = try payload.readRuntimeInteger(at: 8 + index * 4)
      guard id != 0 else { throw MIDIRuntimeError.invalidPayload }
      ids.append(id)
    }
    return (value, ids)
  }
}
