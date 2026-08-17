// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct EditRecipe: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let revision: UInt64
  public let date: Date
  public let pins: EnginePins
  public let operations: [EditOperation]
  public let masks: [MaskDefinition]

  public init(
    assetID: UUID,
    revision: UInt64 = 0,
    date: Date = Date(),
    pins: EnginePins,
    operations: [EditOperation] = [],
    masks: [MaskDefinition] = []
  ) {
    self.assetID = assetID
    self.revision = revision
    self.date = date
    self.pins = pins
    self.operations = operations
    self.masks = masks
  }
}
