// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A reusable Develop recipe fragment.
///
/// Presets intentionally store the ordered operation stream without normalising or filtering it.
/// This keeps vendor operations that PhotoSuite does not understand available for a later engine
/// version. A virtual-copy reference is optional context and is never used as a source identity.
public struct DevelopPreset: Codable, Hashable, Sendable, Identifiable {
  public static let currentSchemaVersion: UInt = 1
  public static let maximumOperationCount = 512

  public let id: UUID
  public let name: String
  public let schemaVersion: UInt
  public let operations: [EditOperation]
  public let virtualCopyID: UUID?
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    name: String,
    schemaVersion: UInt = Self.currentSchemaVersion,
    operations: [EditOperation],
    virtualCopyID: UUID? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedName = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard
      !normalizedName.isEmpty,
      normalizedName.count <= 255,
      schemaVersion == Self.currentSchemaVersion,
      operations.count <= Self.maximumOperationCount
    else {
      return nil
    }
    self.id = id
    self.name = normalizedName
    self.schemaVersion = schemaVersion
    self.operations = operations
    self.virtualCopyID = virtualCopyID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let schemaVersion = try container.decode(UInt.self, forKey: .schemaVersion)
    let operations = try container.decode([EditOperation].self, forKey: .operations)
    let virtualCopyID = try container.decodeIfPresent(UUID.self, forKey: .virtualCopyID)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let preset = Self(
        id: id,
        name: name,
        schemaVersion: schemaVersion,
        operations: operations,
        virtualCopyID: virtualCopyID,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .name,
        in: container,
        debugDescription:
          "The Develop preset name, schema version, or operation count is invalid."
      )
    }
    self = preset
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case schemaVersion
    case operations
    case virtualCopyID
    case createdAt
    case updatedAt
  }
}
