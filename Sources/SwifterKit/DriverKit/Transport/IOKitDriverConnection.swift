#if canImport(IOKit)
  import Foundation
  @preconcurrency import IOKit

  actor IOKitDriverConnection: DriverConnection {
    private var connection: io_connect_t
    private let serviceID: UInt64
    /// Created by the first registration. Releasing it tears the port down.
    private var notificationPort: IOKitNotificationPort?
    /// Live mappings by memory type, unmapped before the connection closes.
    private var mappings: [UInt32: WeakSharedMemory] = [:]
    /// Lets a mapping's unmap reach the connection only while it is open.
    private let mappingGate = IOKitMappingGate()

    init(connection: io_connect_t, serviceID: UInt64) {
      self.connection = connection
      self.serviceID = serviceID
    }

    // Mappings end while the connection is still open. The service closes next, so the extension
    // sends nothing more, and the stored notification port is destroyed after this body runs.
    deinit {
      for mapping in mappings.values { mapping.memory?.unmap() }
      mappingGate.close()
      if connection != 0 { IOServiceClose(connection) }
    }

    func mapMemory(type: UInt32, readOnly: Bool) throws -> DriverSharedMemory {
      let operation = "IOConnectMapMemory64"
      guard connection != 0 else {
        throw DriverKitError(kind: .sessionClosed, operation: operation, serviceID: serviceID)
      }
      if let existing = mappings[type]?.memory, existing.isMapped { return existing }
      var address: mach_vm_address_t = 0
      var size: mach_vm_size_t = 0
      let options = IOOptionBits(kIOMapAnywhere) | (readOnly ? IOOptionBits(kIOMapReadOnly) : 0)
      let result = IOConnectMapMemory64(connection, type, mach_task_self_, &address, &size, options)
      guard result == kIOReturnSuccess else {
        throw DriverKitError(kind: .ioReturn(result), operation: operation, serviceID: serviceID)
      }
      let connect = connection
      let mapped = address
      let gate = mappingGate
      let unmap: @Sendable () -> Void = {
        gate.whileOpen { _ = IOConnectUnmapMemory64(connect, type, mach_task_self_, mapped) }
      }
      guard size > 0, size <= UInt64(Int.max),
        let base = UnsafeMutableRawPointer(bitPattern: UInt(address))
      else {
        unmap()
        throw DriverKitError(
          kind: .ioReturn(kIOReturnNoMemory),
          operation: operation,
          serviceID: serviceID
        )
      }
      let memory = DriverSharedMemory(
        baseAddress: base,
        length: Int(size),
        isReadOnly: readOnly,
        unmap: unmap
      )
      mappings = mappings.filter { $0.value.memory != nil }
      mappings[type] = WeakSharedMemory(memory: memory)
      return memory
    }

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
      for mapping in mappings.values { mapping.memory?.unmap() }
      mappings = [:]
      mappingGate.close()
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

  private struct WeakSharedMemory { weak var memory: DriverSharedMemory? }

  // @unchecked Sendable: `lock` guards `isOpen`, and `whileOpen` runs its body while holding it.
  /// Serializes each mapping's unmap with the connection's close, so no unmap reaches a closed
  /// connection whose port name the process may have reused.
  private final class IOKitMappingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true

    func whileOpen(_ body: () -> Void) {
      lock.lock()
      defer { lock.unlock() }
      if isOpen { body() }
    }

    func close() {
      lock.lock()
      isOpen = false
      lock.unlock()
    }
  }

  private struct IOKitMethodOutput {
    let result: kern_return_t
    let scalarOutput: [UInt64]
    let structureOutput: [UInt8]
  }
#endif
