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
  public init(driver: Driver, client: DriverClient = DriverClient()) {
    self.driver = driver
    self.client = client
  }

  /// Discovers the generated extension, negotiates capabilities, and starts driver behavior.
  @discardableResult public func start() async throws -> DriverService {
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
      let context = await DriverContext(runtime: runtime)

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

  /// Processes one queued runtime event.
  ///
  /// Returns false when the queue is currently empty.
  @discardableResult public func processNextEvent() async throws -> Bool {
    guard state == .running, let runtime, let context else {
      throw DriverHostError.invalidState(expected: .running, actual: state)
    }
    guard let event = try await runtime.nextEvent() else { return false }
    try await driver.handle(event: event, context: context)
    return true
  }

  /// Processes events until cancellation or explicit shutdown.
  public func runEvents(idlePollNanoseconds: UInt64 = 10_000_000) async throws {
    while state == .running {
      try Task.checkCancellation()
      if try await !processNextEvent() {
        if #available(macOS 13.0, *), idlePollNanoseconds <= Int64.max {
          try await Task.sleep(for: .nanoseconds(Int64(idlePollNanoseconds)))
        } else {
          try await Task.sleep(nanoseconds: idlePollNanoseconds)
        }
      }
    }
  }

  /// Processes events until cancellation or explicit shutdown using a clock duration.
  @available(macOS 13.0, *) public func runEvents(idlePollInterval: Duration) async throws {
    while state == .running {
      try Task.checkCancellation()
      if try await !processNextEvent() { try await Task.sleep(for: idlePollInterval) }
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
