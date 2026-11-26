// Fixed-width text for unsigned integers in generated plists and native sources.
//
// `String(format:)` passes C variadic arguments, which strict memory safety rejects, so generated
// identifiers are padded here instead.
extension FixedWidthInteger where Self: UnsignedInteger {
  // The value in `radix`, uppercase, left-padded with zeros to at least `width` digits.
  func zeroPadded(width: Int, radix: Int = 10) -> String {
    let digits = String(self, radix: radix, uppercase: true)
    return String(repeating: "0", count: Swift.max(0, width - digits.count)) + digits
  }
}
