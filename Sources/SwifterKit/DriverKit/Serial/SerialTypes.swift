import Foundation

/// Static terminal metadata published by a generated serial extension.
public struct SerialPortConfiguration: Sendable, Hashable {
  /// The base BSD device name published through `IOTTYBaseName`.
  public let baseName: String
  /// The suffix appended to the BSD device name through `IOTTYSuffix`.
  public let suffix: String
  /// Modem-input state returned until Swift reports a hardware change.
  public let initialModemStatus: SerialModemStatus

  /// Creates serial-port metadata for a generated extension.
  public init(
    baseName: String,
    suffix: String,
    initialModemStatus: SerialModemStatus = SerialModemStatus()
  ) {
    self.baseName = baseName
    self.suffix = suffix
    self.initialModemStatus = initialModemStatus
  }
}

/// Hardware modem-input signals exposed by SerialDriverKit.
public struct SerialModemStatus: Sendable, Hashable {
  /// Clear to send.
  public let clearToSend: Bool
  /// Data set ready.
  public let dataSetReady: Bool
  /// Ring indicator.
  public let ringIndicator: Bool
  /// Data carrier detect.
  public let dataCarrierDetect: Bool

  /// Creates a modem-input snapshot.
  public init(
    clearToSend: Bool = false,
    dataSetReady: Bool = false,
    ringIndicator: Bool = false,
    dataCarrierDetect: Bool = false
  ) {
    self.clearToSend = clearToSend
    self.dataSetReady = dataSetReady
    self.ringIndicator = ringIndicator
    self.dataCarrierDetect = dataCarrierDetect
  }

  var runtimePayload: Data {
    Data([
      clearToSend ? 1 : 0, dataSetReady ? 1 : 0, ringIndicator ? 1 : 0, dataCarrierDetect ? 1 : 0,
    ])
  }
}

/// Receive-side errors reported to SerialDriverKit.
public struct SerialReceiveErrors: OptionSet, Sendable, Hashable {
  /// Encoded error flags.
  public let rawValue: UInt8

  /// The receive FIFO overran.
  public static let overrun = Self(rawValue: 1 << 0)
  /// A break condition was received.
  public static let breakCondition = Self(rawValue: 1 << 1)
  /// A frame had invalid timing or stop bits.
  public static let framing = Self(rawValue: 1 << 2)
  /// A frame had invalid parity.
  public static let parity = Self(rawValue: 1 << 3)

  /// Creates error flags from their wire representation.
  public init(rawValue: UInt8) { self.rawValue = rawValue }
}

/// Parity values accepted by SerialDriverKit hardware-programming callbacks.
public enum SerialParity: UInt8, Sendable, Hashable {
  /// Follow transmit parity when used for receive configuration.
  case `default` = 0
  /// Do not insert or expect a parity bit.
  case none = 1
  /// Use odd parity.
  case odd = 2
  /// Use even parity.
  case even = 3
  /// Use mark parity.
  case mark = 4
  /// Use space parity.
  case space = 5
  /// Accept any receive parity.
  case any = 6
}

/// A complete UART programming request from SerialDriverKit.
public struct SerialUARTConfiguration: Sendable, Hashable {
  /// Baud rate in bits per second.
  public let baudRate: UInt32
  /// Number of data bits.
  public let dataBits: UInt8
  /// Stop-bit count in half-bit units.
  public let halfStopBits: UInt8
  /// Requested parity behavior.
  public let parity: SerialParity

  /// Creates a UART configuration.
  public init(baudRate: UInt32, dataBits: UInt8, halfStopBits: UInt8, parity: SerialParity) {
    self.baudRate = baudRate
    self.dataBits = dataBits
    self.halfStopBits = halfStopBits
    self.parity = parity
  }
}

/// A flow-control programming request from SerialDriverKit.
public struct SerialFlowControlConfiguration: Sendable, Hashable {
  /// DriverKit flow-control flags, preserved without narrowing.
  public let flags: UInt32
  /// Software-flow-control resume byte.
  public let xon: UInt8
  /// Software-flow-control pause byte.
  public let xoff: UInt8

  /// Creates a flow-control configuration.
  public init(flags: UInt32, xon: UInt8, xoff: UInt8) {
    self.flags = flags
    self.xon = xon
    self.xoff = xoff
  }
}

/// A synchronous hardware request forwarded from SerialDriverKit to Swift behavior.
public enum SerialEvent: Sendable, Hashable {
  /// The terminal was opened and hardware should be activated.
  case activate
  /// The terminal closed and hardware may be deactivated.
  case deactivate
  /// Space is available in SerialDriverKit’s receive queue.
  case receiveSpaceAvailable
  /// SerialDriverKit has transmit bytes ready for the hardware.
  case transmitDataAvailable
  /// The selected hardware FIFOs should be reset.
  case resetFIFO(transmit: Bool, receive: Bool)
  /// Hardware break transmission should change state.
  case sendBreak(Bool)
  /// The complete UART configuration changed.
  case programUART(SerialUARTConfiguration)
  /// Only the baud rate changed.
  case programBaudRate(UInt32)
  /// Data-terminal-ready and request-to-send outputs changed.
  case programModemControl(dataTerminalReady: Bool, requestToSend: Bool)
  /// The latency timer changed.
  case programLatencyTimer(UInt32)
  /// Flow-control settings changed.
  case programFlowControl(SerialFlowControlConfiguration)

  init(runtimePayload: Data) throws {
    guard runtimePayload.count == 16 else { throw SerialRuntimeError.invalidPayload }
    let kind: UInt32 = try runtimePayload.readRuntimeInteger(at: 0)
    let value: UInt32 = try runtimePayload.readRuntimeInteger(at: 4)
    switch kind {
    case 1: self = .activate
    case 2: self = .deactivate
    case 3: self = .receiveSpaceAvailable
    case 4: self = .transmitDataAvailable
    case 5: self = .resetFIFO(transmit: value & 1 != 0, receive: value & 2 != 0)
    case 6: self = .sendBreak(value != 0)
    case 7:
      guard let parity = SerialParity(rawValue: runtimePayload[10]) else {
        throw SerialRuntimeError.invalidPayload
      }
      self = .programUART(
        SerialUARTConfiguration(
          baudRate: value,
          dataBits: runtimePayload[8],
          halfStopBits: runtimePayload[9],
          parity: parity
        )
      )
    case 8: self = .programBaudRate(value)
    case 9:
      self = .programModemControl(dataTerminalReady: value & 1 != 0, requestToSend: value & 2 != 0)
    case 10: self = .programLatencyTimer(value)
    case 11:
      self = .programFlowControl(
        SerialFlowControlConfiguration(
          flags: value,
          xon: runtimePayload[8],
          xoff: runtimePayload[9]
        )
      )
    default: throw SerialRuntimeError.invalidEventKind(kind)
    }
  }
}

/// An invalid serial request or runtime payload.
public enum SerialRuntimeError: Error, Sendable, Equatable {
  /// A receive submission contained no bytes.
  case emptyReceiveData
  /// A requested transfer length is not positive.
  case invalidTransferLength
  /// A transfer cannot fit in one runtime message.
  case transferTooLarge
  /// The native runtime returned malformed serial data.
  case invalidPayload
  /// The native runtime returned an unknown serial event kind.
  case invalidEventKind(UInt32)
}
