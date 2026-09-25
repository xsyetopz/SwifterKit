#if canImport(IOKit)
  import Foundation
  @preconcurrency import IOKit

  /// Owns one connection's IOKit notification port and the receivers its completions reach.
  ///
  /// IOKit calls the registered callout on the port's serial dispatch queue. Deinitialization
  /// destroys the port on that queue, so a running callout finishes first and none runs later, and
  /// then finishes and releases every receiver. Only ``IOKitDriverConnection`` holds an instance.
  final class IOKitNotificationPort {
    private let port: IONotificationPortRef
    private let queue = DispatchQueue(label: "SwifterKit.IOKitDriverConnection.notifications")
    /// Every registration's receiver. Each stays retained until the port is destroyed, because a
    /// completion already in flight can still carry an earlier registration's refcon.
    private var receivers: [Unmanaged<NotificationReceiver>] = []

    /// Creates a port served on a private dispatch queue, or nil when IOKit cannot create one.
    init?() {
      guard let port = IONotificationPortCreate(defaultIOKitMainPort) else { return nil }
      self.port = port
      IONotificationPortSetDispatchQueue(port, queue)
    }

    deinit {
      queue.sync { IONotificationPortDestroy(port) }
      for receiver in receivers {
        receiver.takeUnretainedValue().continuation.finish()
        receiver.release()
      }
    }

    /// The port that receives asynchronous completions.
    var machPort: mach_port_t { IONotificationPortGetMachPort(port) }

    /// Adds a receiver for `continuation` and returns the asynchronous reference that routes a
    /// completion to it. Earlier registrations' streams finish, because the extension keeps only
    /// the newest registration.
    func register(_ continuation: AsyncStream<Void>.Continuation) -> [UInt64] {
      for receiver in receivers { receiver.takeUnretainedValue().continuation.finish() }
      let receiver = Unmanaged.passRetained(NotificationReceiver(continuation: continuation))
      receivers.append(receiver)

      // IODispatchCalloutFromMessage calls the function stored at kIOAsyncCalloutFuncIndex with
      // the refcon stored at kIOAsyncCalloutRefconIndex.
      let callout: IOAsyncCallback = { refcon, _, _, _ in
        guard let refcon else { return }
        Unmanaged<NotificationReceiver>.fromOpaque(refcon).takeUnretainedValue().continuation
          .yield()
      }
      var reference = [UInt64](repeating: 0, count: Int(kOSAsyncRef64Count))
      reference[Int(kIOAsyncCalloutFuncIndex)] = UInt64(unsafeBitCast(callout, to: UInt.self))
      reference[Int(kIOAsyncCalloutRefconIndex)] = UInt64(UInt(bitPattern: receiver.toOpaque()))
      return reference
    }
  }

  /// Carries one registration's continuation to the IOKit callout through its refcon.
  ///
  /// The only stored property is a `Sendable` continuation, so the class is `Sendable` without an
  /// unchecked conformance, and it holds no reference to the connection.
  private final class NotificationReceiver: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
  }
#endif
