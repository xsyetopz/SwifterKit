import Foundation

extension DriverCommand {
  /// The largest IN data stage of an asynchronous control request: its completion event must fit
  /// in one message.
  public static let usbMaximumAsyncControlReadLength = usbMaximumEventPayload - 16
  /// The largest OUT data stage of an asynchronous control request: its command must fit in one
  /// message.
  public static let usbMaximumAsyncControlWriteLength = usbMaximumCommandPayload - 16
  /// The most descriptor-ring entries one bundled pipe may have.
  public static let usbMaximumBundleRingEntries = RuntimeUSBLimits.maximumBundleRingEntries
  /// The largest buffer of one descriptor-ring entry: its completion event must fit in one message.
  public static let usbMaximumBundleBufferLength = usbMaximumEventPayload - 16
  /// The most bytes all buffers of one descriptor ring may hold together.
  public static let usbMaximumBundleRingBytes = RuntimeUSBLimits.maximumBundleRingBytes
  /// The most transfers one bundled submission may carry, `kIOUSBHostPipeBundlingMax`.
  public static let usbMaximumBundledTransfers = RuntimeUSBLimits.maximumBundledTransfers

  /// Creates a command that enqueues an asynchronous request on the default control endpoint.
  ///
  /// The response carries a request identifier; the result arrives in a
  /// ``USBDeviceRequestCompletion`` event. `data` is the OUT data stage and must be empty for an
  /// IN request.
  public static func usbEnqueueControlTransfer(
    _ request: USBControlRequest,
    data: [UInt8] = [],
    timeout: UInt32 = 5_000
  ) throws -> Self {
    switch request.direction {
    case .in:
      guard data.isEmpty else { throw USBRuntimeError.directionMismatch }
      guard Int(request.length) <= usbMaximumAsyncControlReadLength else {
        throw USBRuntimeError.transferTooLarge
      }
    case .out:
      guard data.count == Int(request.length) else { throw USBRuntimeError.invalidOutputLength }
    }
    return usbCommand(
      .usbAsyncDeviceRequest,
      payload: usbControlRequestPayload(request, data: data, timeout: timeout),
      response: 4
    )
  }

  /// Creates a command that gives a bulk pipe a runtime-owned descriptor ring for bundled I/O.
  ///
  /// The ring has `entryCount` buffers of `bufferLength` bytes, registered with
  /// `CreateMemoryDescriptorRing` and `SetMemoryDescriptor`. USBDriverKit keeps a pipe's ring until
  /// the pipe is destroyed.
  public static func usbCreateBundleRing(
    endpoint: UInt8,
    entryCount: Int,
    bufferLength: Int
  ) throws -> Self {
    guard (1...usbMaximumBundleRingEntries).contains(entryCount),
      (1...usbMaximumBundleBufferLength).contains(bufferLength),
      entryCount * bufferLength <= usbMaximumBundleRingBytes
    else { throw USBRuntimeError.invalidBundleRing }
    var payload = Data([endpoint, 0, 0, 0])
    payload.appendRuntimeInteger(UInt32(entryCount))
    payload.appendRuntimeInteger(UInt32(bufferLength))
    payload.appendRuntimeInteger(UInt32(0))
    return usbCommand(.usbPipeCreateBundleRing, payload: payload)
  }

  /// Creates a command that submits consecutive IN transfers from a pipe's descriptor ring.
  ///
  /// Transfer `n` reads up to `lengths[n]` bytes into ring entry `(firstIndex + n) % entryCount`.
  /// The response is the number of transfers the pipe accepted; each accepted transfer completes
  /// with a ``USBBundledIOCompletion`` event.
  public static func usbEnqueueBundledReads(
    endpoint: UInt8,
    firstIndex: Int,
    lengths: [Int],
    timeout: UInt32 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .in else {
      throw USBRuntimeError.directionMismatch
    }
    return try usbBundledIO(endpoint, firstIndex, lengths, [], timeout)
  }

  /// Creates a command that submits consecutive OUT transfers through a pipe's descriptor ring.
  ///
  /// Transfer `n` writes `transfers[n]` from ring entry `(firstIndex + n) % entryCount`. The
  /// response is the number of transfers the pipe accepted; each accepted transfer completes with
  /// a ``USBBundledIOCompletion`` event.
  public static func usbEnqueueBundledWrites(
    endpoint: UInt8,
    firstIndex: Int,
    transfers: [[UInt8]],
    timeout: UInt32 = 0
  ) throws -> Self {
    guard USBTransferDirection(encodedByte: endpoint) == .out else {
      throw USBRuntimeError.directionMismatch
    }
    let lengths = transfers.map(\.count)
    guard 16 + lengths.count * 4 + lengths.reduce(0, +) <= usbMaximumCommandPayload else {
      throw USBRuntimeError.transferTooLarge
    }
    return try usbBundledIO(endpoint, firstIndex, lengths, transfers.flatMap { $0 }, timeout)
  }

  /// Creates a command that releases an idle pipe's descriptor-ring buffers.
  public static func usbReleaseBundleRing(endpoint: UInt8) -> Self {
    var payload = Data([endpoint, 0, 0, 0])
    payload.appendRuntimeInteger(UInt32(0))
    return usbCommand(.usbPipeReleaseBundleRing, payload: payload)
  }

  /// Creates a command that changes the bandwidth a periodic endpoint reserves, with
  /// `AdjustPipe`.
  ///
  /// Start from ``DriverContext/usbPipeDescriptors(endpoint:policy:)`` and lower the maximum packet
  /// size, burst, or interval. The endpoint address and transfer type cannot change.
  public static func usbAdjustPipe(endpoint: UInt8, descriptors: USBPipeDescriptors) throws -> Self
  {
    let transferType = descriptors.endpoint.transferType
    guard descriptors.endpoint.address == endpoint,
      transferType == .isochronous || transferType == .interrupt,
      USBPipeDescriptors.supportedReleases.contains(descriptors.usbRelease)
    else { throw USBRuntimeError.invalidEndpointPolicy }
    var payload = Data([endpoint, 0, 0, 0])
    payload.append(contentsOf: descriptors.runtimePayload)
    payload.append(0)
    return usbCommand(.usbPipeAdjust, payload: payload)
  }

  private static func usbBundledIO(
    _ endpoint: UInt8,
    _ firstIndex: Int,
    _ lengths: [Int],
    _ data: [UInt8],
    _ timeout: UInt32
  ) throws -> Self {
    guard (1...usbMaximumBundledTransfers).contains(lengths.count) else {
      throw USBRuntimeError.invalidBundledTransfer
    }
    guard (0..<usbMaximumBundleRingEntries).contains(firstIndex) else {
      throw USBRuntimeError.invalidBundledTransfer
    }
    guard lengths.allSatisfy({ $0 > 0 }) else { throw USBRuntimeError.emptyTransfer }
    guard lengths.allSatisfy({ $0 <= usbMaximumBundleBufferLength }) else {
      throw USBRuntimeError.transferTooLarge
    }
    var payload = Data(capacity: 16 + lengths.count * 4 + data.count)
    payload.append(endpoint)
    payload.append(UInt8(lengths.count))
    payload.appendRuntimeInteger(UInt16(0))
    payload.appendRuntimeInteger(UInt32(firstIndex))
    payload.appendRuntimeInteger(timeout)
    payload.appendRuntimeInteger(UInt32(0))
    for length in lengths { payload.appendRuntimeInteger(UInt32(length)) }
    payload.append(contentsOf: data)
    return usbCommand(.usbPipeEnqueueBundled, payload: payload, response: 4)
  }
}

extension DriverContext {
  /// Enqueues an asynchronous request on the default control endpoint and returns its request
  /// identifier.
  ///
  /// The result arrives in a ``USBDeviceRequestCompletion`` event, decoded with
  /// ``DriverEvent/usb()``, and can arrive before this call returns. Cancel outstanding requests
  /// with ``usbAbortDeviceRequests()``.
  public func usbEnqueueControlTransfer(
    _ request: USBControlRequest,
    data: [UInt8] = [],
    timeout: UInt32 = 5_000
  ) async throws -> UInt32 {
    let requestID = try await usbValue(
      .usbEnqueueControlTransfer(request, data: data, timeout: timeout)
    )
    guard requestID != 0 else { throw USBRuntimeError.invalidResponse }
    return requestID
  }

  /// Gives a bulk pipe a runtime-owned descriptor ring for bundled I/O.
  public func usbCreateBundleRing(endpoint: UInt8, entryCount: Int, bufferLength: Int) async throws
  {
    _ = try await execute(
      .usbCreateBundleRing(endpoint: endpoint, entryCount: entryCount, bufferLength: bufferLength)
    )
  }

  /// Submits consecutive IN transfers from a pipe's descriptor ring and returns how many the pipe
  /// accepted.
  public func usbEnqueueBundledReads(
    endpoint: UInt8,
    firstIndex: Int,
    lengths: [Int],
    timeout: UInt32 = 0
  ) async throws -> Int {
    Int(
      try await usbValue(
        .usbEnqueueBundledReads(
          endpoint: endpoint,
          firstIndex: firstIndex,
          lengths: lengths,
          timeout: timeout
        )
      )
    )
  }

  /// Submits consecutive OUT transfers through a pipe's descriptor ring and returns how many the
  /// pipe accepted.
  public func usbEnqueueBundledWrites(
    endpoint: UInt8,
    firstIndex: Int,
    transfers: [[UInt8]],
    timeout: UInt32 = 0
  ) async throws -> Int {
    Int(
      try await usbValue(
        .usbEnqueueBundledWrites(
          endpoint: endpoint,
          firstIndex: firstIndex,
          transfers: transfers,
          timeout: timeout
        )
      )
    )
  }

  /// Releases a pipe's descriptor-ring buffers once every entry has completed and been delivered.
  public func usbReleaseBundleRing(endpoint: UInt8) async throws {
    _ = try await execute(.usbReleaseBundleRing(endpoint: endpoint))
  }

  /// Changes the bandwidth a periodic endpoint reserves.
  public func usbAdjustPipe(endpoint: UInt8, descriptors: USBPipeDescriptors) async throws {
    _ = try await execute(.usbAdjustPipe(endpoint: endpoint, descriptors: descriptors))
  }
}
