/// An error produced while accessing a DriverKit service.
public struct DriverKitError: Error, Sendable, Equatable {
  /// The failure category.
  public enum Kind: Sendable, Equatable {
    /// IOKit returned a non-success IOReturn.
    case ioReturn(Int32)
    /// A matching dictionary could not be created.
    case invalidServiceClass
    /// A discovered service disappeared.
    case serviceUnavailable
    /// An operation used a closed session.
    case sessionClosed
    /// A buffer cannot be represented by the IOKit ABI.
    case bufferTooLarge
  }

  /// The failure category.
  public let kind: Kind
  /// The operation that failed.
  public let operation: String
  /// The related registry identifier.
  public let serviceID: UInt64?

  /// Creates a DriverKit error.
  public init(kind: Kind, operation: String, serviceID: UInt64? = nil) {
    self.kind = kind
    self.operation = operation
    self.serviceID = serviceID
  }
}

extension DriverKitError: CustomStringConvertible {
  /// A diagnostic description preserving the operation and result.
  public var description: String {
    var result = "DriverKitError(operation: \(operation), kind: \(kind)"
    if let serviceID { result += ", serviceID: \(serviceID)" }
    return result + ")"
  }
}
