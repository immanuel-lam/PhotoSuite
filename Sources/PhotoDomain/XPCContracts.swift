// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum XPCResponseStatus: Codable, Hashable, Sendable {
  case success
  case failure
  case unknown(String)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self(code: try container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(code)
  }

  private init(code: String) {
    switch code {
    case "success": self = .success
    case "failure": self = .failure
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .success: "success"
    case .failure: "failure"
    case .unknown(let code): code
    }
  }
}

public struct XPCErrorPayload: Codable, Hashable, Sendable {
  public let code: String
  public let message: String
  public let details: Data?

  public init(code: String, message: String, details: Data?) {
    self.code = code
    self.message = message
    self.details = details
  }
}

public enum CameraAdapterXPC {
  public enum Operation: Codable, Hashable, Sendable {
    case listDevices
    case capture
    case startTether
    case stopTether
    case unknown(String)

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self = Self(code: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(code)
    }

    private init(code: String) {
      switch code {
      case "listDevices": self = .listDevices
      case "capture": self = .capture
      case "startTether": self = .startTether
      case "stopTether": self = .stopTether
      default: self = .unknown(code)
      }
    }

    private var code: String {
      switch self {
      case .listDevices: "listDevices"
      case .capture: "capture"
      case .startTether: "startTether"
      case .stopTether: "stopTether"
      case .unknown(let code): code
      }
    }
  }

  public struct RequestEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: UInt
    public let requestID: UUID
    public let operation: Operation
    public let payload: Data

    public init(schemaVersion: UInt, requestID: UUID, operation: Operation, payload: Data) {
      self.schemaVersion = schemaVersion
      self.requestID = requestID
      self.operation = operation
      self.payload = payload
    }
  }

  public struct ResponseEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: UInt
    public let requestID: UUID
    public let status: XPCResponseStatus
    public let payload: Data
    public let error: XPCErrorPayload?

    public init(
      schemaVersion: UInt,
      requestID: UUID,
      status: XPCResponseStatus,
      payload: Data,
      error: XPCErrorPayload?
    ) {
      self.schemaVersion = schemaVersion
      self.requestID = requestID
      self.status = status
      self.payload = payload
      self.error = error
    }
  }
}

public enum PhotoPluginXPC {
  public enum Operation: Codable, Hashable, Sendable {
    case handshake
    case describeCapabilities
    case process
    case unknown(String)

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self = Self(code: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(code)
    }

    private init(code: String) {
      switch code {
      case "handshake": self = .handshake
      case "describeCapabilities": self = .describeCapabilities
      case "process": self = .process
      default: self = .unknown(code)
      }
    }

    private var code: String {
      switch self {
      case .handshake: "handshake"
      case .describeCapabilities: "describeCapabilities"
      case .process: "process"
      case .unknown(let code): code
      }
    }
  }

  public struct RequestEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: UInt
    public let requestID: UUID
    public let operation: Operation
    public let payload: Data

    public init(schemaVersion: UInt, requestID: UUID, operation: Operation, payload: Data) {
      self.schemaVersion = schemaVersion
      self.requestID = requestID
      self.operation = operation
      self.payload = payload
    }
  }

  public struct ResponseEnvelope: Codable, Hashable, Sendable {
    public let schemaVersion: UInt
    public let requestID: UUID
    public let status: XPCResponseStatus
    public let payload: Data
    public let error: XPCErrorPayload?

    public init(
      schemaVersion: UInt,
      requestID: UUID,
      status: XPCResponseStatus,
      payload: Data,
      error: XPCErrorPayload?
    ) {
      self.schemaVersion = schemaVersion
      self.requestID = requestID
      self.status = status
      self.payload = payload
      self.error = error
    }
  }
}
