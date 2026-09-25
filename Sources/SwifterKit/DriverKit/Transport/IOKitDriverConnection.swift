#if canImport(IOKit)
  import Foundation
  @preconcurrency import IOKit

  actor IOKitDriverConnection: DriverConnection {
    private var connection: io_connect_t
    private let serviceID: UInt64
    /// Created by the first registration; releasing it tears the port down.
    private var notificationPort: IOKitNotificationPort?

    init(connection: io_connect_t, serviceID: UInt64) {
      self.connection = connection
      self.serviceID = serviceID
    }

    // The service closes first, so the extension sends nothing more, and the stored notification
    // port is destroyed after this body runs.
    deinit { if connection != 0 { IOServiceClose(connection) } }

    func notifications(selector: UInt32) throws -> AsyncStream<Void> {
      let operation = "IOConnectCallAsyncStructMethod"
      guard connection != 0 else {
        throw DriverKitError(kind: .sessionClosed, operation: operation, serviceID: serviceID)
      }
      if notificationPort == nil { notificationPort = IOKitNotificationPort() }
      guard let port = notificationPort else {
        throw DriverKitError(
          kind: .ioReturn(kIOReturnNoResources),
          operation: "IONotificationPortCreate",
          serviceID: serviceID
        )
      }
      let (stream, continuation) = AsyncStream.makeStream(
        of: Void.self,
        bufferingPolicy: .bufferingNewest(1)
      )
      var reference = port.register(continuation)
      let result = IOConnectCallAsyncStructMethod(
        connection,
        selector,
        port.machPort,
        &reference,
        UInt32(reference.count),
        nil,
        0,
        nil,
        nil
      )
      guard result == kIOReturnSuccess else {
        continuation.finish()
        throw DriverKitError(kind: .ioReturn(result), operation: operation, serviceID: serviceID)
      }
      return stream
    }

    func call(_ request: DriverRequest) throws -> DriverResponse {
      guard connection != 0 else {
        throw DriverKitError(
          kind: .sessionClosed,
          operation: "IOConnectCallMethod",
          serviceID: serviceID
        )
      }
      try validate(request)

      let output = Self.invoke(connection: connection, request: request)

      guard output.result == kIOReturnSuccess else {
        throw DriverKitError(
          kind: .ioReturn(output.result),
          operation: "IOConnectCallMethod",
          serviceID: serviceID
        )
      }

      return DriverResponse(
        scalarOutput: output.scalarOutput,
        structureOutput: Data(output.structureOutput)
      )
    }

    nonisolated private static func invoke(
      connection: io_connect_t,
      request: DriverRequest
    ) -> IOKitMethodOutput {
      var scalarOutput = [UInt64](repeating: 0, count: request.scalarOutputCapacity)
      var scalarOutputCount = UInt32(request.scalarOutputCapacity)
      var structureOutput = [UInt8](repeating: 0, count: request.structureOutputCapacity)
      var structureOutputSize = request.structureOutputCapacity

      let result = request.scalarInput.withUnsafeBufferPointer { scalarInput in
        request.structureInput.withUnsafeBytes { structureInput in
          scalarOutput.withUnsafeMutableBufferPointer { scalarOutput in
            structureOutput.withUnsafeMutableBytes { structureOutput in
              IOConnectCallMethod(
                connection,
                request.selector,
                scalarInput.baseAddress,
                UInt32(scalarInput.count),
                structureInput.baseAddress,
                structureInput.count,
                scalarOutput.baseAddress,
                &scalarOutputCount,
                structureOutput.baseAddress,
                &structureOutputSize
              )
            }
          }
        }
      }

      return IOKitMethodOutput(
        result: result,
        scalarOutput: Array(scalarOutput.prefix(Int(scalarOutputCount))),
        structureOutput: Array(structureOutput.prefix(structureOutputSize))
      )
    }

    func close() {
      if connection != 0 {
        IOServiceClose(connection)
        connection = 0
      }
      notificationPort = nil
    }

    private func validate(_ request: DriverRequest) throws {
      let capacities = [
        request.scalarInput.count, request.structureInput.count, request.scalarOutputCapacity,
        request.structureOutputCapacity,
      ]
      guard capacities.allSatisfy({ $0 <= Int(UInt32.max) }) else {
        throw DriverKitError(
          kind: .bufferTooLarge,
          operation: "IOConnectCallMethod",
          serviceID: serviceID
        )
      }
    }
  }

  private struct IOKitMethodOutput {
    let result: kern_return_t
    let scalarOutput: [UInt64]
    let structureOutput: [UInt8]
  }
#endif
