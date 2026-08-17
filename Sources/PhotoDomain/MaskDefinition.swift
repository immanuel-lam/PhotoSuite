// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum MaskKind: Codable, Hashable, Sendable {
  case brush
  case linearGradient
  case radialGradient
  case luminanceRange
  case colorRange
  case depthRange
  case subject
  case sky
  case background
  case object
  case unknown(String)

  public init(from decoder: any Decoder) throws {
    let decoded = try UnknownStringCodeCoding.decode(from: decoder)
    guard !decoded.isExplicitlyUnknown else {
      self = .unknown(decoded.value)
      return
    }
    self = Self(code: decoded.value)
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .unknown(let value):
      try UnknownStringCodeCoding.encodeUnknown(
        value,
        reservedValues: Self.reservedCodes,
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private static let reservedCodes: Set<String> = [
    "brush",
    "linearGradient",
    "radialGradient",
    "luminanceRange",
    "colorRange",
    "depthRange",
    "subject",
    "sky",
    "background",
    "object",
  ]

  private init(code: String) {
    switch code {
    case "brush": self = .brush
    case "linearGradient": self = .linearGradient
    case "radialGradient": self = .radialGradient
    case "luminanceRange": self = .luminanceRange
    case "colorRange": self = .colorRange
    case "depthRange": self = .depthRange
    case "subject": self = .subject
    case "sky": self = .sky
    case "background": self = .background
    case "object": self = .object
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .brush: "brush"
    case .linearGradient: "linearGradient"
    case .radialGradient: "radialGradient"
    case .luminanceRange: "luminanceRange"
    case .colorRange: "colorRange"
    case .depthRange: "depthRange"
    case .subject: "subject"
    case .sky: "sky"
    case .background: "background"
    case .object: "object"
    case .unknown(let code): code
    }
  }
}

public struct MaskDefinition: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let schemaVersion: UInt
  public let kind: MaskKind
  public let name: String?
  public let isInverted: Bool
  public let payload: Data

  public init(
    id: UUID = UUID(),
    schemaVersion: UInt,
    kind: MaskKind,
    name: String?,
    isInverted: Bool,
    payload: Data
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.kind = kind
    self.name = name
    self.isInverted = isInverted
    self.payload = payload
  }
}
