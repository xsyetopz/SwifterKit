import Foundation

/// The result of an asynchronous bulk or interrupt transfer, from `CompleteAsyncIO`.
public struct USBPipeIOCompletion: Sendable, Hashable {
  /// The identifier returned when the transfer was enqueued.
  public let requestID: UInt32
  /// The endpoint address of the pipe.
  public let endpoint: UInt8
  /// The `IOReturn` status. Zero is success; `kIOReturnAborted` follows an abort.
  public let status: Int32
  /// The number of bytes transferred.
  public let bytesTransferred: UInt32
  /// The completion time, in mach absolute time units.
  public let timestamp: UInt64
  /// Bytes read by an IN transfer; empty for an OUT transfer.
  public let data: [UInt8]

  /// Whether the transfer completed successfully.
  public var succeeded: Bool { status == 0 }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 24 else { throw USBRuntimeError.invalidResponse }
    requestID = try runtimePayload.readRuntimeInteger(at: 0)
    status = try runtimePayload.readRuntimeInteger(at: 4)
    bytesTransferred = try runtimePayload.readRuntimeInteger(at: 8)
    endpoint = runtimePayload[runtimePayload.startIndex + 12]
    timestamp = try runtimePayload.readRuntimeInteger(at: 16)
    data = Array(runtimePayload.dropFirst(24))
    let input = USBTransferDirection(encodedByte: endpoint) == .in
    guard requestID != 0, data.count == (input ? Int(bytesTransferred) : 0) else {
      throw USBRuntimeError.invalidResponse
    }
  }
}

/// The result of one frame of an isochronous transfer.
public struct USBIsochronousFrameResult: Sendable, Hashable {
  /// The frame's `IOReturn` status.
  public let status: Int32
  /// The number of bytes requested for the frame.
  public let requestCount: UInt32
  /// The number of bytes transferred in the frame.
  public let completeCount: UInt32
  /// The frame's completion time, in mach absolute time units.
  public let timestamp: UInt64
}

/// The result of an isochronous transfer, from `CompleteAsyncIsochIO`.
public struct USBIsochronousCompletion: Sendable, Hashable {
  /// The identifier returned when the transfer was enqueued.
  public let requestID: UInt32
  /// The endpoint address of the pipe.
  public let endpoint: UInt8
  /// The transfer's `IOReturn` status.
  public let status: Int32
  /// Per-frame results in submission order.
  public let frames: [USBIsochronousFrameResult]
  /// For an IN transfer, the whole data buffer. Frame `n` starts after the `requestCount`
  /// bytes of every earlier frame, and its first `completeCount` bytes are valid.
  public let data: [UInt8]

  /// Whether the transfer completed successfully.
  public var succeeded: Bool { status == 0 }

  /// The valid bytes that an IN transfer received in the frame at `index`.
  public func bytes(inFrame index: Int) -> ArraySlice<UInt8> {
    guard frames.indices.contains(index), !data.isEmpty else { return [] }
    let start = frames[..<index].reduce(0) { $0 + Int($1.requestCount) }
    return data[start..<start + Int(frames[index].completeCount)]
  }

  init(runtimePayload: Data) throws {
    guard runtimePayload.count >= 16 else { throw USBRuntimeError.invalidResponse }
    requestID = try runtimePayload.readRuntimeInteger(at: 0)
    status = try runtimePayload.readRuntimeInteger(at: 4)
    endpoint = runtimePayload[runtimePayload.startIndex + 8]
    let frameCount = Int(try runtimePayload.readRuntimeInteger(at: 10) as UInt16)
    let dataLength = Int(try runtimePayload.readRuntimeInteger(at: 12) as UInt32)
    guard requestID != 0, frameCount > 0, runtimePayload.count == 16 + frameCount * 24 + dataLength
    else { throw USBRuntimeError.invalidResponse }

    var frames: [USBIsochronousFrameResult] = []
    frames.reserveCapacity(frameCount)
    var requested = 0
    for index in 0..<frameCount {
      let offset = 16 + index * 24
      let frame = USBIsochronousFrameResult(
        status: try runtimePayload.readRuntimeInteger(at: offset),
        requestCount: try runtimePayload.readRuntimeInteger(at: offset + 4),
        completeCount: try runtimePayload.readRuntimeInteger(at: offset + 8),
        timestamp: try runtimePayload.readRuntimeInteger(at: offset + 16)
      )
      guard frame.completeCount <= frame.requestCount else { throw USBRuntimeError.invalidResponse }
      requested += Int(frame.requestCount)
      frames.append(frame)
    }
    let input = USBTransferDirection(encodedByte: endpoint) == .in
    guard dataLength == (input ? requested : 0) else { throw USBRuntimeError.invalidResponse }
    self.frames = frames
    data = Array(runtimePayload.suffix(dataLength))
  }
}

/// A USB pipe completion delivered as a runtime event.
public enum USBEvent: Sendable, Hashable {
  /// An asynchronous bulk or interrupt transfer completed.
  case pipeIO(USBPipeIOCompletion)
  /// An isochronous transfer completed.
  case isochronousIO(USBIsochronousCompletion)
}

extension DriverEvent {
  /// Decodes a USB pipe completion.
  ///
  /// Returns nil when the event belongs to another capability family. A completion can arrive
  /// before the call that enqueued the transfer returns, so match it by request identifier.
  public func usb() throws -> USBEvent? {
    switch type {
    case RuntimeEventType.usbPipeIO.rawValue:
      return .pipeIO(try USBPipeIOCompletion(runtimePayload: Data(payload)))
    case RuntimeEventType.usbPipeIsochIO.rawValue:
      return .isochronousIO(try USBIsochronousCompletion(runtimePayload: Data(payload)))
    default: return nil
    }
  }
}
