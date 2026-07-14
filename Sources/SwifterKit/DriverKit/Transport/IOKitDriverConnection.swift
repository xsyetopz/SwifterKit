import Foundation
@preconcurrency import IOKit

actor IOKitDriverConnection: DriverConnection {
  private var connection: io_connect_t
  private let serviceID: UInt64

  init(connection: io_connect_t, serviceID: UInt64) {
    self.connection = connection
    self.serviceID = serviceID
  }

  deinit { if connection != 0 { IOServiceClose(connection) } }

  func call(_ request: DriverRequest) throws -> DriverResponse {
    guard connection != 0 else {
      throw DriverKitError(
        kind: .sessionClosed,
        operation: "IOConnectCallMethod",
        serviceID: serviceID
      )
    }
    try validate(request)

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

    guard result == kIOReturnSuccess else {
      throw DriverKitError(
        kind: .ioReturn(result),
        operation: "IOConnectCallMethod",
        serviceID: serviceID
      )
    }

    return DriverResponse(
      scalarOutput: Array(scalarOutput.prefix(Int(scalarOutputCount))),
      structureOutput: Data(structureOutput.prefix(structureOutputSize))
    )
  }

  func close() {
    guard connection != 0 else { return }
    IOServiceClose(connection)
    connection = 0
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
