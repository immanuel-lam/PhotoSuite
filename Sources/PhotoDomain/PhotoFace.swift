// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A face bounding box in source-image normalised coordinates.
///
/// This is an annotation geometry only. It does not contain biometric data or
/// make an identity claim about the person in the image.
public struct FaceRegion: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init?(x: Double, y: Double, width: Double, height: Double) {
    guard
      x.isFinite, y.isFinite, width.isFinite, height.isFinite,
      x >= 0, y >= 0, width > 0, height > 0,
      x <= 1, y <= 1,
      x + width <= 1, y + height <= 1
    else {
      return nil
    }
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let x = try container.decode(Double.self, forKey: .x)
    let y = try container.decode(Double.self, forKey: .y)
    let width = try container.decode(Double.self, forKey: .width)
    let height = try container.decode(Double.self, forKey: .height)
    guard let region = Self(x: x, y: y, width: width, height: height) else {
      throw DecodingError.dataCorruptedError(
        forKey: .width,
        in: container,
        debugDescription: "Face regions must be finite, positive, and within normalised bounds."
      )
    }
    self = region
  }

  private enum CodingKeys: String, CodingKey {
    case x
    case y
    case width
    case height
  }
}

/// The provenance of a face annotation. A Vision annotation supplies geometry
/// only. A label is user or import metadata and is never inferred by this type.
public enum FaceAnnotationSource: RawRepresentable, Codable, CaseIterable, Hashable, Sendable {
  case manual
  case vision
  case imported
  case unknown(String)

  public static let allCases: [FaceAnnotationSource] = [.manual, .vision, .imported]

  public init(rawValue: String) {
    switch rawValue {
    case "manual": self = .manual
    case "vision": self = .vision
    case "imported": self = .imported
    default: self = .unknown(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .manual: "manual"
    case .vision: "vision"
    case .imported: "imported"
    case .unknown(let value): value
    }
  }

  public init(from decoder: any Decoder) throws {
    self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A durable face annotation attached to one catalog asset.
///
/// `label` is an optional user-assigned or imported display label. It is not a
/// recognised identity. Storing an unlabeled annotation is the default for
/// local detection results.
public struct PhotoFace: Codable, Hashable, Sendable, Identifiable {
  public static let currentSchemaVersion: UInt = 1

  public let id: UUID
  public let assetID: UUID
  public let region: FaceRegion
  public let label: String?
  public let confidence: Double?
  public let source: FaceAnnotationSource
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    assetID: UUID,
    region: FaceRegion,
    label: String? = nil,
    confidence: Double? = nil,
    source: FaceAnnotationSource = .manual,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedLabel = label.map(Self.normalizeLabel)
    guard
      normalizedLabel?.isEmpty != true,
      normalizedLabel?.count ?? 0 <= 255,
      confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
      !source.rawValue.isEmpty
    else {
      return nil
    }

    self.id = id
    self.assetID = assetID
    self.region = region
    self.label = normalizedLabel
    self.confidence = confidence
    self.source = source
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let assetID = try container.decode(UUID.self, forKey: .assetID)
    let region = try container.decode(FaceRegion.self, forKey: .region)
    let label = try container.decodeIfPresent(String.self, forKey: .label)
    let confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    let source = try container.decode(FaceAnnotationSource.self, forKey: .source)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let face = Self(
        id: id,
        assetID: assetID,
        region: region,
        label: label,
        confidence: confidence,
        source: source,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .label,
        in: container,
        debugDescription: "The face label or confidence is invalid."
      )
    }
    self = face
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case assetID
    case region
    case label
    case confidence
    case source
    case createdAt
    case updatedAt
  }

  private static func normalizeLabel(_ label: String) -> String {
    label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
