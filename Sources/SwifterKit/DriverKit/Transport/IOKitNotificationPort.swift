#if canImport(IOKit)
  import Foundation
  import IOKit

  // Owns one connection's IOKit notification port and the receivers its completions reach.
  //
  // IOKit calls the registered callout on the port's serial dispatch queue. Deinitialization
  // destroys the port on that queue, so a running callout finishes first and none runs later, and
  // then finishes and releases every receiver. Only ``IOKitDriverConnection`` holds an instance.
  @safe
  final class IOKitNotificationPort {
    private let port: IONotificationPortRef
    private let queue = DispatchQueue(label: "SwifterKit.IOKitDriverConnection.notifications")
    // Every registration's receiver. Each stays retained until the port is destroyed, because a
    // completion already in flight can still carry an earlier registration's refcon.
    private var receivers: [Unmanaged<NotificationReceiver>] = unsafe []

    // Creates a port served on a private dispatch queue, or nil when IOKit cannot create one.
    init?() {
      guard let created = unsafe IONotificationPortCreate(defaultIOKitMainPort) else { return nil }
      unsafe port = created
      unsafe IONotificationPortSetDispatchQueue(created, queue)
    }

    deinit {
      queue.sync { unsafe IONotificationPortDestroy(port) }
      for unsafe receiver in unsafe receivers {
        unsafe receiver.takeUnretainedValue().continuation.finish()
        unsafe receiver.release()
      }
    }

    // The port that receives asynchronous completions.
    var machPort: mach_port_t { unsafe IONotificationPortGetMachPort(port) }

    // Adds a receiver for `continuation` and returns the asynchronous reference that routes a
    // completion to it. Earlier registrations' streams finish, because the extension keeps only
    // the newest registration.
    func register(_ continuation: AsyncStream<Void>.Continuation) -> [UInt64] {
      for unsafe receiver in unsafe receivers {
        unsafe receiver.takeUnretainedValue().continuation.finish()
      }
      let receiver = unsafe Unmanaged.passRetained(NotificationReceiver(continuation: continuation))
      unsafe receivers.append(receiver)

      // IODispatchCalloutFromMessage calls the function stored at kIOAsyncCalloutFuncIndex with
      // the refcon stored at kIOAsyncCalloutRefconIndex.
      let callout: IOAsyncCallback = { refcon, _, _, _ in
        guard let receiverPointer = unsafe refcon else { return }
        unsafe Unmanaged<NotificationReceiver>.fromOpaque(receiverPointer).takeUnretainedValue()
          .continuation
          .yield()
      }
      var reference = [UInt64](repeating: 0, count: Int(kOSAsyncRef64Count))
      reference[Int(kIOAsyncCalloutFuncIndex)] = unsafe UInt64(
        unsafeBitCast(callout, to: UInt.self)
      )
      reference[Int(kIOAsyncCalloutRefconIndex)] = unsafe UInt64(
        UInt(bitPattern: receiver.toOpaque())
      )
      return reference
    }
  }

  // Carries one registration's continuation to the IOKit callout through its refcon.
  //
  // The only stored property is a `Sendable` continuation, so the class is `Sendable` without an
  // unchecked conformance, and it holds no reference to the connection.
  private final class NotificationReceiver: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
  }
#endif
