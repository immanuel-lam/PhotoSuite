// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct EditRecipe: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let virtualCopyID: UUID?
  public let revision: UInt64
  public let date: Date
  public let pins: EnginePins
  public let operations: [EditOperation]
  public let masks: [MaskDefinition]

  public init(
    assetID: UUID,
    virtualCopyID: UUID? = nil,
    revision: UInt64 = 0,
    date: Date = Date(),
    pins: EnginePins,
    operations: [EditOperation] = [],
    masks: [MaskDefinition] = []
  ) {
    self.assetID = assetID
    self.virtualCopyID = virtualCopyID
    self.revision = revision
    self.date = date
    self.pins = pins
    self.operations = operations
    self.masks = masks
  }

  private enum CodingKeys: String, CodingKey {
    case assetID
    case virtualCopyID
    case revision
    case date
    case pins
    case operations
    case masks
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(assetID, forKey: .assetID)
    try container.encodeIfPresent(virtualCopyID, forKey: .virtualCopyID)
    try container.encode(revision, forKey: .revision)
    try container.encode(date, forKey: .date)
    try container.encode(pins, forKey: .pins)
    try container.encode(operations, forKey: .operations)
    try container.encode(masks, forKey: .masks)
  }
}
