// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum ColorLabel: RawRepresentable, Codable, CaseIterable, Hashable, Sendable {
  case red
  case yellow
  case green
  case blue
  case purple
  case unknown(String)

  public static let allCases: [ColorLabel] = [.red, .yellow, .green, .blue, .purple]

  public init?(rawValue: String) {
    switch rawValue {
    case "red": self = .red
    case "yellow": self = .yellow
    case "green": self = .green
    case "blue": self = .blue
    case "purple": self = .purple
    default: self = .unknown(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .red: "red"
    case .yellow: "yellow"
    case .green: "green"
    case .blue: "blue"
    case .purple: "purple"
    case .unknown(let value): value
    }
  }

  public init(from decoder: any Decoder) throws {
    let decoded = try UnknownStringCodeCoding.decode(from: decoder)
    guard !decoded.isExplicitlyUnknown else {
      self = .unknown(decoded.value)
      return
    }

    switch decoded.value {
    case "red": self = .red
    case "yellow": self = .yellow
    case "green": self = .green
    case "blue": self = .blue
    case "purple": self = .purple
    default: self = .unknown(decoded.value)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .red: try UnknownStringCodeCoding.encodeKnown("red", to: encoder)
    case .yellow: try UnknownStringCodeCoding.encodeKnown("yellow", to: encoder)
    case .green: try UnknownStringCodeCoding.encodeKnown("green", to: encoder)
    case .blue: try UnknownStringCodeCoding.encodeKnown("blue", to: encoder)
    case .purple: try UnknownStringCodeCoding.encodeKnown("purple", to: encoder)
    case .unknown(let value):
      try UnknownStringCodeCoding.encodeUnknown(
        value,
        reservedValues: ["red", "yellow", "green", "blue", "purple"],
        to: encoder
      )
    }
  }
}

public struct PhotoAsset: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let sourceURL: URL
  public let filename: String
  public let typeIdentifier: String?
  public let fingerprint: SourceFingerprint
  public let importDate: Date
  public let captureDate: Date?
  public let pixelDimensions: PixelDimensions?
  public let rating: Int
  public let colorLabel: ColorLabel?
  public let isMissing: Bool
  public let metadata: PhotoMetadata

  public init?(
    id: UUID = UUID(),
    sourceURL: URL,
    filename: String,
    typeIdentifier: String?,
    fingerprint: SourceFingerprint,
    importDate: Date,
    captureDate: Date?,
    pixelDimensions: PixelDimensions?,
    rating: Int = 0,
    colorLabel: ColorLabel? = nil,
    isMissing: Bool = false,
    metadata: PhotoMetadata = .empty
  ) {
    guard (0...5).contains(rating) else {
      return nil
    }

    self.id = id
    self.sourceURL = sourceURL
    self.filename = filename
    self.typeIdentifier = typeIdentifier
    self.fingerprint = fingerprint
    self.importDate = importDate
    self.captureDate = captureDate
    self.pixelDimensions = pixelDimensions
    self.rating = rating
    self.colorLabel = colorLabel
    self.isMissing = isMissing
    self.metadata = metadata
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let sourceURL = try container.decode(URL.self, forKey: .sourceURL)
    let filename = try container.decode(String.self, forKey: .filename)
    let typeIdentifier = try container.decodeIfPresent(String.self, forKey: .typeIdentifier)
    let fingerprint = try container.decode(SourceFingerprint.self, forKey: .fingerprint)
    let importDate = try container.decode(Date.self, forKey: .importDate)
    let captureDate = try container.decodeIfPresent(Date.self, forKey: .captureDate)
    let pixelDimensions = try container.decodeIfPresent(
      PixelDimensions.self,
      forKey: .pixelDimensions
    )
    let rating = try container.decode(Int.self, forKey: .rating)
    let colorLabel = try container.decodeIfPresent(ColorLabel.self, forKey: .colorLabel)
    let isMissing = try container.decode(Bool.self, forKey: .isMissing)
    let metadata = try container.decodeIfPresent(PhotoMetadata.self, forKey: .metadata) ?? .empty

    guard
      let asset = Self(
        id: id,
        sourceURL: sourceURL,
        filename: filename,
        typeIdentifier: typeIdentifier,
        fingerprint: fingerprint,
        importDate: importDate,
        captureDate: captureDate,
        pixelDimensions: pixelDimensions,
        rating: rating,
        colorLabel: colorLabel,
        isMissing: isMissing,
        metadata: metadata
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .rating,
        in: container,
        debugDescription: "Rating must be in the inclusive range 0 through 5."
      )
    }

    self = asset
  }
}
