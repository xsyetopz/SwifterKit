import Foundation
import Testing

@testable import SwifterKit

@Suite struct DriverCallTests {
  @Test func requestPreservesRawInputsAndCapacities() {
    let request = DriverRequest(
      selector: 7,
      scalarInput: [1, 2],
      structureInput: Data([3, 4]),
      scalarOutputCapacity: 3,
      structureOutputCapacity: 8
    )

    #expect(request.selector == 7)
    #expect(request.scalarInput == [1, 2])
    #expect(request.structureInput == Data([3, 4]))
    #expect(request.scalarOutputCapacity == 3)
    #expect(request.structureOutputCapacity == 8)
  }

  @Test func requestClampsNegativeCapacities() {
    let request = DriverRequest(selector: 0, scalarOutputCapacity: -1, structureOutputCapacity: -2)

    #expect(request.scalarOutputCapacity == 0)
    #expect(request.structureOutputCapacity == 0)
  }

  @Test func responsePreservesRawOutputs() {
    let response = DriverResponse(scalarOutput: [5], structureOutput: Data([6]))

    #expect(response.scalarOutput == [5])
    #expect(response.structureOutput == Data([6]))
  }
}
