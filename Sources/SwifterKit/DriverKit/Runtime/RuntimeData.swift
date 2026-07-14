import Foundation

extension Data {
  mutating func appendRuntimeInteger<T: FixedWidthInteger>(_ value: T) {
    var encoded = value.littleEndian
    Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
  }

  func readRuntimeInteger<T: FixedWidthInteger>(at offset: Int) throws -> T {
    let size = MemoryLayout<T>.size
    guard offset >= 0, offset <= count - size else { throw RuntimeProtocolError.truncatedPayload }

    var value: T = 0
    for index in 0..<size {
      let dataIndex = self.index(startIndex, offsetBy: offset + index)
      value |= T(self[dataIndex]) << T(index * 8)
    }
    return value
  }
}
