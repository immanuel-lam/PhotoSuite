// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A durable, logical Library folder. Folders organise catalog membership and
/// never move, rename, or rewrite the immutable source file.
public struct LibraryFolder: Codable, Hashable, Sendable, Identifiable {
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
      let folder = Self(
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
        debugDescription: "The Library folder name or parent relationship is invalid."
      )
    }
    self = folder
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case parentID
    case createdAt
    case updatedAt
  }
}
