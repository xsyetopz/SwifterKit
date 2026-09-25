#if canImport(IOKit)
  import IOKit
  import Testing

  @testable import SwifterKit

  /// Exercises the callout bridge by invoking the registered callout directly, as
  /// `IODispatchCalloutFromMessage` does. No extension sends a real completion here.
  @Suite
  struct IOKitNotificationPortTests {
    @Test
    func calloutYieldsToTheRegisteredStreamAndCoalesces() async throws {
      let port = try #require(IOKitNotificationPort())
      let (stream, continuation) = AsyncStream.makeStream(
        of: Void.self,
        bufferingPolicy: .bufferingNewest(1)
      )
      let reference = port.register(continuation)
      #expect(reference.count == Int(kOSAsyncRef64Count))
      #expect(port.machPort != 0)

      invokeCallout(reference)
      invokeCallout(reference)
      continuation.finish()

      var count = 0
      for await _ in stream { count += 1 }
      #expect(count == 1)
    }

    @Test
    func laterRegistrationAndTeardownFinishStreams() async throws {
      var port = IOKitNotificationPort()
      let (first, firstContinuation) = AsyncStream.makeStream(of: Void.self)
      let (second, secondContinuation) = AsyncStream.makeStream(of: Void.self)
      let firstReference = try #require(port).register(firstContinuation)
      _ = try #require(port).register(secondContinuation)

      for await _ in first { Issue.record("the replaced stream yielded") }
      // A completion that still carries the replaced refcon reaches a finished stream safely.
      invokeCallout(firstReference)

      port = nil
      for await _ in second { Issue.record("the torn-down stream yielded") }
    }

    private func invokeCallout(_ reference: [UInt64]) {
      let callout = unsafeBitCast(
        UInt(reference[Int(kIOAsyncCalloutFuncIndex)]),
        to: IOAsyncCallback.self
      )
      let refcon = UnsafeMutableRawPointer(
        bitPattern: UInt(reference[Int(kIOAsyncCalloutRefconIndex)])
      )
      callout(refcon, kIOReturnSuccess, nil, 0)
    }
  }
#endif
