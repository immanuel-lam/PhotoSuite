// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum CatalogJobKind: Codable, Hashable, Sendable {
  case importAssets
  case generateThumbnail
  case generatePreview
  case export
  case verifySource
  case aiMask
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
        reservedValues: [
          "importAssets",
          "generateThumbnail",
          "generatePreview",
          "export",
          "verifySource",
          "aiMask",
        ],
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private init(code: String) {
    switch code {
    case "importAssets": self = .importAssets
    case "generateThumbnail": self = .generateThumbnail
    case "generatePreview": self = .generatePreview
    case "export": self = .export
    case "verifySource": self = .verifySource
    case "aiMask": self = .aiMask
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .importAssets: "importAssets"
    case .generateThumbnail: "generateThumbnail"
    case .generatePreview: "generatePreview"
    case .export: "export"
    case .verifySource: "verifySource"
    case .aiMask: "aiMask"
    case .unknown(let code): code
    }
  }
}

public enum CatalogJobState: Codable, Hashable, Sendable {
  case queued
  case running
  case succeeded
  case failed
  case cancelled
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
        reservedValues: ["queued", "running", "succeeded", "failed", "cancelled"],
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private init(code: String) {
    switch code {
    case "queued": self = .queued
    case "running": self = .running
    case "succeeded": self = .succeeded
    case "failed": self = .failed
    case "cancelled": self = .cancelled
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .queued: "queued"
    case .running: "running"
    case .succeeded: "succeeded"
    case .failed: "failed"
    case .cancelled: "cancelled"
    case .unknown(let code): code
    }
  }
}

public struct CatalogJob: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let schemaVersion: UInt
  public let kind: CatalogJobKind
  public let state: CatalogJobState
  public let assetIDs: [UUID]
  public let createdAt: Date
  public let updatedAt: Date
  public let payload: Data

  public init(
    id: UUID = UUID(),
    schemaVersion: UInt,
    kind: CatalogJobKind,
    state: CatalogJobState,
    assetIDs: [UUID],
    createdAt: Date,
    updatedAt: Date,
    payload: Data
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.kind = kind
    self.state = state
    self.assetIDs = assetIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.payload = payload
  }
}
