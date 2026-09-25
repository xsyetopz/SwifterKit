import Foundation

/// The handshake request payload: the protocol versions the host can speak.
struct RuntimeHandshakeOffer: Equatable {
  let versions: ClosedRange<RuntimeProtocolVersion>

  func encoded() -> Data {
    var result = Data(capacity: RuntimeSchema.handshakeRequestSize)
    result.appendRuntimeInteger(versions.lowerBound.rawValue)
    result.appendRuntimeInteger(versions.upperBound.rawValue)
    result.appendRuntimeInteger(UInt32(0))
    return result
  }

  init(versions: ClosedRange<RuntimeProtocolVersion>) { self.versions = versions }

  init(decoding payload: Data) throws {
    guard payload.count == RuntimeSchema.handshakeRequestSize else {
      throw DriverRuntimeError.invalidHandshake
    }
    let minimum: UInt16 = try payload.readRuntimeInteger(at: 0)
    let maximum: UInt16 = try payload.readRuntimeInteger(at: 2)
    let reserved: UInt32 = try payload.readRuntimeInteger(at: 4)
    guard minimum <= maximum, reserved == 0 else { throw DriverRuntimeError.invalidHandshake }
    versions = RuntimeProtocolVersion(rawValue: minimum)...RuntimeProtocolVersion(rawValue: maximum)
  }
}

/// The handshake response payload: the selected protocol version and advertised capabilities.
struct RuntimeHandshakeAcceptance: Equatable {
  let version: RuntimeProtocolVersion
  let capabilities: RuntimeCapabilities

  func encoded() -> Data {
    var result = Data(capacity: RuntimeSchema.handshakeResponseSize)
    result.appendRuntimeInteger(version.rawValue)
    result.appendRuntimeInteger(UInt16(0))
    result.appendRuntimeInteger(UInt32(0))
    result.appendRuntimeInteger(capabilities.rawValue)
    return result
  }

  init(version: RuntimeProtocolVersion, capabilities: RuntimeCapabilities) {
    self.version = version
    self.capabilities = capabilities
  }

  init(decoding payload: Data) throws {
    guard payload.count == RuntimeSchema.handshakeResponseSize else {
      throw DriverRuntimeError.invalidHandshake
    }
    let version: UInt16 = try payload.readRuntimeInteger(at: 0)
    let reserved16: UInt16 = try payload.readRuntimeInteger(at: 2)
    let reserved32: UInt32 = try payload.readRuntimeInteger(at: 4)
    guard reserved16 == 0, reserved32 == 0 else { throw DriverRuntimeError.invalidHandshake }
    self.version = RuntimeProtocolVersion(rawValue: version)
    capabilities = RuntimeCapabilities(rawValue: try payload.readRuntimeInteger(at: 8))
  }
}
