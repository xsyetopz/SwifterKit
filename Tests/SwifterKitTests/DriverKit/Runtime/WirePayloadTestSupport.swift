/// Joins byte chunks; one call keeps the Swift 6.1 type checker within its time limit.
func bytes(_ chunks: [UInt8]...) -> [UInt8] { chunks.flatMap { $0 } }

/// Returns `value` as little-endian bytes, the runtime wire order.
func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
  withUnsafeBytes(of: value.littleEndian) { Array($0) }
}
