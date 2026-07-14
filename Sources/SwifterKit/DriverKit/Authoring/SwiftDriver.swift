import Foundation

/// Driver behavior authored in Swift and hosted by the SwifterKit runtime.
public protocol SwiftDriver: Sendable {
  /// Metadata and capabilities for the generated extension.
  static var configuration: DriverConfiguration { get }

  /// Handles runtime startup after the internal extension connects.
  func start(context: DriverContext) async throws

  /// Handles an event forwarded by the internal extension.
  func handle(event: DriverEvent, context: DriverContext) async throws

  /// Handles runtime shutdown before the user-client connection closes.
  func stop(context: DriverContext) async
}

extension SwiftDriver {
  /// Provides a cooperative startup hook.
  public func start(context: DriverContext) async throws {
    await Task.yield()
    try Task.checkCancellation()
  }

  /// Provides a cooperative shutdown hook.
  public func stop(context: DriverContext) async { await Task.yield() }
}

/// An event forwarded from the internal DriverKit extension.
public struct DriverEvent: Sendable, Equatable {
  /// Runtime-defined event type.
  public let type: UInt32
  /// Event-specific bytes.
  public let payload: [UInt8]

  /// Creates a forwarded driver event.
  public init(type: UInt32, payload: [UInt8] = []) {
    self.type = type
    self.payload = payload
  }
}

/// A capability-checked interface to the internal DriverKit extension.
public struct DriverContext: Sendable {
  /// Capabilities negotiated with the internal extension.
  public let capabilities: RuntimeCapabilities

  private let runtime: DriverRuntimeConnection?

  /// Creates a detached context for validation or testing.
  public init(capabilities: RuntimeCapabilities) {
    self.capabilities = capabilities
    self.runtime = nil
  }

  /// Creates a context attached to a negotiated runtime.
  public init(runtime: DriverRuntimeConnection) async {
    self.capabilities = await runtime.capabilities
    self.runtime = runtime
  }

  /// Requires a capability before issuing a related operation.
  public func require(_ capability: RuntimeCapabilities) throws {
    guard capabilities.contains(capability) else {
      throw DriverContextError.unsupportedCapability(capability)
    }
  }

  /// Executes a low-level command through the attached extension runtime.
  public func execute(_ command: DriverCommand) async throws -> Data {
    try require(command.requiredCapabilities)
    guard let runtime else { throw DriverContextError.notConnected }
    return try await runtime.execute(command)
  }
}

/// An invalid operation requested by Swift driver behavior.
public enum DriverContextError: Error, Sendable, Equatable {
  /// The generated extension lacks the requested capability.
  case unsupportedCapability(RuntimeCapabilities)
  /// The context was created without a runtime connection.
  case notConnected
}
