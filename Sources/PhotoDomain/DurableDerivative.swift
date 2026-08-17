// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum DurableDerivativeKind: Codable, Hashable, Sendable {
  case thumbnail
  case preview
  case export
  case sidecar
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
        reservedValues: ["thumbnail", "preview", "export", "sidecar"],
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private init(code: String) {
    switch code {
    case "thumbnail": self = .thumbnail
    case "preview": self = .preview
    case "export": self = .export
    case "sidecar": self = .sidecar
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .thumbnail: "thumbnail"
    case .preview: "preview"
    case .export: "export"
    case .sidecar: "sidecar"
    case .unknown(let code): code
    }
  }
}

public struct DurableDerivative: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let schemaVersion: UInt
  public let assetID: UUID
  public let recipeRevision: UInt64
  public let kind: DurableDerivativeKind
  public let outputURL: URL
  public let typeIdentifier: String
  public let fingerprint: SourceFingerprint?
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    schemaVersion: UInt,
    assetID: UUID,
    recipeRevision: UInt64,
    kind: DurableDerivativeKind,
    outputURL: URL,
    typeIdentifier: String,
    fingerprint: SourceFingerprint?,
    createdAt: Date
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.assetID = assetID
    self.recipeRevision = recipeRevision
    self.kind = kind
    self.outputURL = outputURL
    self.typeIdentifier = typeIdentifier
    self.fingerprint = fingerprint
    self.createdAt = createdAt
  }
}
