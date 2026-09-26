import Foundation

extension DriverCommand {
  /// The largest asynchronous IN transfer: its completion event must fit in one message.
  public static let usbMaximumAsyncReadLength = usbMaximumEventPayload - 24
  /// The largest asynchronous OUT transfer: its command must fit in one message.
  public static let usbMaximumAsyncWriteLength = usbMaximumCommandPayload - 16
  /// The most frames one isochronous transfer may describe.
  public static let usbMaximumIsochronousFrames = RuntimeUSBLimits.maximumIsochronousFrames

  /// Creates a command that enqueues an asynchronous bulk or interrupt IN transfer.
  ///
  /// The response carries a request identifier; the data arrives in a ``USBPipeIOCompletion``
  /// event. `timeout` must be zero for interrupt endpoints.
  public static func usbEnqueueRead(
    endpoint: UInt8,
    length: Int,
    timeout: UInt32 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .in else {
      throw USBRuntimeError.directionMismatch
    }
    guard length > 0 else { throw USBRuntimeError.emptyTransfer }
    guard length <= usbMaximumAsyncReadLength else { throw USBRuntimeError.transferTooLarge }
    return usbAsyncIO(endpoint: endpoint, length: length, data: [], timeout: timeout)
  }

  /// Creates a command that enqueues an asynchronous bulk or interrupt OUT transfer.
  ///
  /// The response carries a request identifier; the result arrives in a
  /// ``USBPipeIOCompletion`` event. `timeout` must be zero for interrupt endpoints.
  public static func usbEnqueueWrite(
    endpoint: UInt8,
    data: [UInt8],
    timeout: UInt32 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .out else {
      throw USBRuntimeError.directionMismatch
    }
    guard !data.isEmpty else { throw USBRuntimeError.emptyTransfer }
    guard data.count <= usbMaximumAsyncWriteLength else { throw USBRuntimeError.transferTooLarge }
    return usbAsyncIO(endpoint: endpoint, length: data.count, data: data, timeout: timeout)
  }

  /// Creates a command that enqueues an isochronous IN transfer of one or more frames.
  ///
  /// `frameLengths` gives each frame's requested byte count. A `firstFrame` of zero starts on
  /// the next available frame on XHCI controllers. The completion event carries every frame's
  /// result and the whole data buffer, so the frames, their data, and a 16-byte header must fit
  /// in one runtime message.
  public static func usbEnqueueIsochronousRead(
    endpoint: UInt8,
    frameLengths: [UInt32],
    firstFrame: UInt64 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .in else {
      throw USBRuntimeError.directionMismatch
    }
    let total = try validateIsochronousFrames(frameLengths)
    guard 16 + frameLengths.count * 24 + total <= usbMaximumEventPayload else {
      throw USBRuntimeError.transferTooLarge
    }
    return usbIsochIO(endpoint: endpoint, frameLengths: frameLengths, data: [], first: firstFrame)
  }

  /// Creates a command that enqueues an isochronous OUT transfer with one byte array per frame.
  ///
  /// A `firstFrame` of zero starts on the next available frame on XHCI controllers.
  public static func usbEnqueueIsochronousWrite(
    endpoint: UInt8,
    frames: [[UInt8]],
    firstFrame: UInt64 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .out else {
      throw USBRuntimeError.directionMismatch
    }
    let lengths = frames.map { UInt32(clamping: $0.count) }
    let total = try validateIsochronousFrames(lengths)
    guard 16 + lengths.count * 4 + total <= usbMaximumCommandPayload else {
      throw USBRuntimeError.transferTooLarge
    }
    return usbIsochIO(
      endpoint: endpoint,
      frameLengths: lengths,
      data: frames.flatMap { $0 },
      first: firstFrame
    )
  }

  /// Creates a command that asynchronously aborts every request on a pipe. Each aborted
  /// request still completes, with `kIOReturnAborted`.
  public static func usbAbortPipe(endpoint: UInt8) -> Self {
    usbPipeRequest(.usbPipeAbort, endpoint: endpoint)
  }

  /// Creates a command that sets how long, in milliseconds, a busy pipe stays busy after I/O.
  public static func usbSetPipeIdlePolicy(endpoint: UInt8, timeout: UInt32) -> Self {
    usbPipeRequest(.usbPipeSetIdlePolicy, endpoint: endpoint, value: timeout)
  }

  /// Creates a command that returns a pipe's idle timeout in milliseconds.
  public static func usbPipeIdlePolicy(endpoint: UInt8) -> Self {
    usbPipeRequest(.usbPipeGetIdlePolicy, endpoint: endpoint, response: 4)
  }

  /// Creates a command that returns the descriptors describing a pipe's endpoint.
  public static func usbPipeDescriptors(
    endpoint: UInt8,
    policy: USBPipeDescriptorPolicy = .original
  ) -> Self {
    usbPipeRequest(
      .usbPipeGetDescriptors,
      endpoint: endpoint,
      option: policy.rawValue,
      response: 23
    )
  }

  /// Creates a command that returns the operating speed reported by a pipe.
  public static func usbPipeSpeed(endpoint: UInt8) -> Self {
    usbPipeRequest(.usbPipeGetSpeed, endpoint: endpoint, response: 4)
  }

  /// Creates a command that returns the device address reported by a pipe.
  public static func usbPipeDeviceAddress(endpoint: UInt8) -> Self {
    usbPipeRequest(.usbPipeGetDeviceAddress, endpoint: endpoint, response: 4)
  }

  /// An event payload after the runtime header and the four-byte event type.
  static let usbMaximumEventPayload = RuntimeMessage.maximumSize - RuntimeMessage.headerSize - 4
  /// A command payload after the runtime and command headers.
  static let usbMaximumCommandPayload =
    RuntimeMessage.maximumSize - RuntimeMessage.headerSize - RuntimeSchema.commandHeaderSize

  private static func usbAsyncIO(
    endpoint: UInt8,
    length: Int,
    data: [UInt8],
    timeout: UInt32
  ) -> Self {
    usbCommand(
      .usbPipeAsyncIO,
      payload: usbPipeIOPayload(endpoint: endpoint, length: length, data: data, timeout: timeout),
      response: 4
    )
  }

  private static func validateIsochronousFrames(_ lengths: [UInt32]) throws -> Int {
    guard !lengths.isEmpty else { throw USBRuntimeError.emptyTransfer }
    guard lengths.count <= usbMaximumIsochronousFrames else {
      throw USBRuntimeError.transferTooLarge
    }
    let total = lengths.reduce(0) { $0 + Int($1) }
    guard total > 0 else { throw USBRuntimeError.emptyTransfer }
    return total
  }

  private static func usbIsochIO(
    endpoint: UInt8,
    frameLengths: [UInt32],
    data: [UInt8],
    first: UInt64
  ) -> Self {
    var payload = Data(capacity: 16 + frameLengths.count * 4 + data.count)
    payload.append(endpoint)
    payload.append(0)
    payload.appendRuntimeInteger(UInt16(frameLengths.count))
    payload.appendRuntimeInteger(UInt32(0))
    payload.appendRuntimeInteger(first)
    for length in frameLengths { payload.appendRuntimeInteger(length) }
    payload.append(contentsOf: data)
    return usbCommand(.usbPipeIsochIO, payload: payload, response: 4)
  }

  private static func usbPipeRequest(
    _ opcode: RuntimeOpcode,
    endpoint: UInt8,
    option: UInt8 = 0,
    value: UInt32 = 0,
    response: Int = 0
  ) -> Self {
    var payload = Data([endpoint, option, 0, 0])
    payload.appendRuntimeInteger(value)
    return usbCommand(opcode, payload: payload, response: response)
  }
}

extension DriverContext {
  /// Enqueues an asynchronous bulk or interrupt IN transfer and returns its request identifier.
  ///
  /// The data arrives in a ``USBPipeIOCompletion`` event, decoded with ``DriverEvent/usb()``.
  /// The event can arrive before this call returns. `timeout` must be zero for interrupt
  /// endpoints.
  public func usbEnqueueRead(
    endpoint: UInt8,
    length: Int,
    timeout: UInt32 = 0
  ) async throws -> UInt32 {
    try await usbRequestID(.usbEnqueueRead(endpoint: endpoint, length: length, timeout: timeout))
  }

  /// Enqueues an asynchronous bulk or interrupt OUT transfer and returns its request identifier.
  ///
  /// The result arrives in a ``USBPipeIOCompletion`` event, decoded with ``DriverEvent/usb()``.
  /// The event can arrive before this call returns. `timeout` must be zero for interrupt
  /// endpoints.
  public func usbEnqueueWrite(
    endpoint: UInt8,
    data: [UInt8],
    timeout: UInt32 = 0
  ) async throws -> UInt32 {
    try await usbRequestID(.usbEnqueueWrite(endpoint: endpoint, data: data, timeout: timeout))
  }

  /// Enqueues an isochronous IN transfer and returns its request identifier.
  ///
  /// The result arrives in a ``USBIsochronousCompletion`` event.
  public func usbEnqueueIsochronousRead(
    endpoint: UInt8,
    frameLengths: [UInt32],
    firstFrame: UInt64 = 0
  ) async throws -> UInt32 {
    try await usbRequestID(
      .usbEnqueueIsochronousRead(
        endpoint: endpoint,
        frameLengths: frameLengths,
        firstFrame: firstFrame
      )
    )
  }

  /// Enqueues an isochronous OUT transfer and returns its request identifier.
  ///
  /// The result arrives in a ``USBIsochronousCompletion`` event.
  public func usbEnqueueIsochronousWrite(
    endpoint: UInt8,
    frames: [[UInt8]],
    firstFrame: UInt64 = 0
  ) async throws -> UInt32 {
    try await usbRequestID(
      .usbEnqueueIsochronousWrite(endpoint: endpoint, frames: frames, firstFrame: firstFrame)
    )
  }

  /// Asynchronously aborts every request on a pipe. Each aborted request still completes, with
  /// `kIOReturnAborted`.
  public func usbAbortPipe(endpoint: UInt8) async throws {
    _ = try await execute(.usbAbortPipe(endpoint: endpoint))
  }

  /// Sets how long, in milliseconds, a pipe stays busy after I/O before it counts as idle.
  public func usbSetPipeIdlePolicy(endpoint: UInt8, timeout: UInt32) async throws {
    _ = try await execute(.usbSetPipeIdlePolicy(endpoint: endpoint, timeout: timeout))
  }

  /// Returns a pipe's idle timeout in milliseconds.
  public func usbPipeIdlePolicy(endpoint: UInt8) async throws -> UInt32 {
    try await usbValue(.usbPipeIdlePolicy(endpoint: endpoint))
  }

  /// Returns the descriptors describing a pipe's endpoint.
  public func usbPipeDescriptors(
    endpoint: UInt8,
    policy: USBPipeDescriptorPolicy = .original
  ) async throws -> USBPipeDescriptors {
    try USBPipeDescriptors(
      runtimePayload: await execute(.usbPipeDescriptors(endpoint: endpoint, policy: policy))
    )
  }

  /// Returns the operating speed reported by a pipe.
  public func usbPipeSpeed(endpoint: UInt8) async throws -> USBDeviceSpeed {
    USBDeviceSpeed(
      rawValue: UInt8(truncatingIfNeeded: try await usbValue(.usbPipeSpeed(endpoint: endpoint)))
    )
  }

  /// Returns the device address reported by a pipe.
  public func usbPipeDeviceAddress(endpoint: UInt8) async throws -> UInt8 {
    UInt8(truncatingIfNeeded: try await usbValue(.usbPipeDeviceAddress(endpoint: endpoint)))
  }

  private func usbRequestID(_ command: DriverCommand) async throws -> UInt32 {
    let requestID = try await usbValue(command)
    guard requestID != 0 else { throw USBRuntimeError.invalidResponse }
    return requestID
  }
}
