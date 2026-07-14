import Foundation

/// An operation sent from Swift driver behavior to the internal extension runtime.
public struct DriverCommand: Sendable, Equatable {
  /// Verifies the command channel and returns the supplied payload unchanged.
  public static func ping(_ payload: Data = Data()) -> Self {
    Self(
      opcode: 0,
      payload: payload,
      maximumResponseSize: RuntimeMessage.headerSize + payload.count
    )
  }

  static let pollEvent = Self(opcode: 1)

  /// The operation identifier interpreted by the internal runtime.
  public let opcode: UInt32
  /// Capabilities that must be negotiated before this command is sent.
  public let requiredCapabilities: RuntimeCapabilities
  /// Operation-specific bytes.
  public let payload: Data
  /// Maximum complete response size accepted for this command.
  public let maximumResponseSize: Int

  /// Creates a low-level runtime command.
  public init(
    opcode: UInt32,
    requiredCapabilities: RuntimeCapabilities = [],
    payload: Data = Data(),
    maximumResponseSize: Int = 4_096
  ) {
    self.opcode = opcode
    self.requiredCapabilities = requiredCapabilities
    self.payload = payload
    self.maximumResponseSize = max(RuntimeMessage.headerSize, maximumResponseSize)
  }

  func encodedPayload() throws -> Data {
    guard payload.count <= Int(UInt32.max) - 16 else { throw RuntimeProtocolError.payloadTooLarge }

    var result = Data(capacity: 16 + payload.count)
    result.appendRuntimeInteger(opcode)
    result.appendRuntimeInteger(UInt32(0))
    result.appendRuntimeInteger(requiredCapabilities.rawValue)
    result.append(payload)
    return result
  }
}
