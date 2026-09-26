import Foundation

/// Lifecycle state for a Swift-authored driver host.
public enum DriverHostState: Sendable, Equatable {
  /// No extension connection is active.
  case stopped
  /// Service discovery and runtime negotiation are in progress.
  case starting
  /// Swift driver behavior is active.
  case running
  /// Driver shutdown is in progress.
  case stopping
}

/// Runs Swift driver behavior against a generated internal DriverKit extension.
public actor DriverHost<Driver: SwiftDriver> {
  /// The current lifecycle state.
  public private(set) var state: DriverHostState = .stopped
  /// The connected registry service when running.
  public private(set) var service: DriverService?

  private let driver: Driver
  private let client: DriverClient
  private var runtime: DriverRuntimeConnection?
  private var context: DriverContext?

  /// Creates a host for one Swift driver implementation.
  public init(driver: Driver, client: DriverClient) {
    self.driver = driver
    self.client = client
  }

  #if canImport(IOKit)
    /// Creates a host that discovers the generated extension through native IOKit.
    public init(driver: Driver) { self.init(driver: driver, client: DriverClient()) }
  #endif

  /// Discovers the generated extension, negotiates capabilities, and starts driver behavior.
  @discardableResult
  public func start() async throws -> DriverService {
    guard state == .stopped else {
      throw DriverHostError.invalidState(expected: .stopped, actual: state)
    }
    state = .starting

    do {
      let configuration = Driver.configuration
      guard let service = try await client.services(matching: configuration.serviceMatch).first
      else { throw DriverHostError.serviceNotFound(configuration.serviceMatch) }

      let session = try await client.open(service)
      let runtime = try await DriverRuntimeConnection.connect(
        session: session,
        requiring: configuration.capabilities
      )
      let context = await DriverContext(runtime: runtime, fastPath: configuration.fastPath)

      do { try await driver.start(context: context) } catch {
        await runtime.close()
        throw error
      }

      self.service = service
      self.runtime = runtime
      self.context = context
      state = .running
      return service
    } catch {
      service = nil
      runtime = nil
      context = nil
      state = .stopped
      throw error
    }
  }

  /// Delivers the extension's events to the driver until the host stops or the task is cancelled.
  ///
  /// The host registers for event notifications, takes queued events until the queue is empty,
  /// passes each one to ``SwiftDriver/handle(event:context:)``, and then waits for the extension
  /// to report more events. It does not poll while the queue is empty.
  ///
  /// The method returns after ``stop()`` closes the connection and throws `CancellationError` when
  /// its task is cancelled. An error thrown by the driver's handler ends delivery and propagates.
  public func runEvents() async throws {
    guard state == .running, let runtime, let context else {
      throw DriverHostError.invalidState(expected: .running, actual: state)
    }
    for try await event in try await runtime.events() {
      try await driver.handle(event: event, context: context)
    }
  }

  /// Stops Swift behavior and closes the extension connection idempotently.
  public func stop() async {
    guard state == .running, let runtime, let context else { return }
    state = .stopping
    await driver.stop(context: context)
    await runtime.close()
    self.runtime = nil
    self.context = nil
    service = nil
    state = .stopped
  }
}

/// A Swift driver host lifecycle failure.
public enum DriverHostError: Error, Sendable, Equatable {
  /// An operation is invalid for the current host state.
  case invalidState(expected: DriverHostState, actual: DriverHostState)
  /// No generated extension matched the driver's configuration.
  case serviceNotFound(DriverServiceMatch)
}
