// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct KeywordNode: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let name: String
  public let parentID: UUID?
  public let createdAt: Date
  public let updatedAt: Date

  public var normalizedName: String {
    name.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Self.normalizationLocale
    )
    .lowercased(with: Self.normalizationLocale)
  }

  private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

  public init?(
    id: UUID = UUID(),
    name: String,
    parentID: UUID? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty, normalizedName.count <= 255, parentID != id else { return nil }
    self.id = id
    self.name = normalizedName
    self.parentID = parentID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let node = Self(
        id: id,
        name: name,
        parentID: parentID,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .name,
        in: container,
        debugDescription: "The keyword name or parent relationship is invalid."
      )
    }
    self = node
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case parentID
    case createdAt
    case updatedAt
  }
}

public struct VirtualCopy: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let sourceAssetID: UUID
  public let name: String
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    sourceAssetID: UUID,
    name: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty, normalizedName.count <= 255 else { return nil }
    self.id = id
    self.sourceAssetID = sourceAssetID
    self.name = normalizedName
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let sourceAssetID = try container.decode(UUID.self, forKey: .sourceAssetID)
    let name = try container.decode(String.self, forKey: .name)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let copy = Self(
        id: id,
        sourceAssetID: sourceAssetID,
        name: name,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .name,
        in: container,
        debugDescription: "The virtual copy name is invalid."
      )
    }
    self = copy
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case sourceAssetID
    case name
    case createdAt
    case updatedAt
  }
}
