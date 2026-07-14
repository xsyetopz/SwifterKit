import Foundation

/// A raw DriverKit user-client external-method request.
public struct DriverRequest: Sendable, Equatable {
  /// The external-method selector.
  public let selector: UInt32
  /// Scalar input values.
  public let scalarInput: [UInt64]
  /// Structured input bytes.
  public let structureInput: Data
  /// Maximum scalar values returned.
  public let scalarOutputCapacity: Int
  /// Maximum structured bytes returned.
  public let structureOutputCapacity: Int

  /// Creates a raw external-method request.
  public init(
    selector: UInt32,
    scalarInput: [UInt64] = [],
    structureInput: Data = Data(),
    scalarOutputCapacity: Int = 0,
    structureOutputCapacity: Int = 0
  ) {
    self.selector = selector
    self.scalarInput = scalarInput
    self.structureInput = structureInput
    self.scalarOutputCapacity = max(0, scalarOutputCapacity)
    self.structureOutputCapacity = max(0, structureOutputCapacity)
  }
}

/// Values returned by a user-client external method.
public struct DriverResponse: Sendable, Equatable {
  /// Scalar output values.
  public let scalarOutput: [UInt64]
  /// Structured output bytes.
  public let structureOutput: Data

  /// Creates a raw external-method response.
  public init(scalarOutput: [UInt64] = [], structureOutput: Data = Data()) {
    self.scalarOutput = scalarOutput
    self.structureOutput = structureOutput
  }
}
