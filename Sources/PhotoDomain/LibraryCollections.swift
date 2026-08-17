// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct SmartCollectionRule: Codable, Hashable, Sendable {
  public enum Field: String, Codable, Hashable, Sendable {
    case filename
    case typeIdentifier
    case sourceURL
    case rating
    case colorLabel
    case isMissing
    case keyword
  }

  public enum Comparison: String, Codable, Hashable, Sendable {
    case equals
    case notEquals
    case contains
    case greaterThanOrEqual
    case lessThanOrEqual
  }

  public let field: Field
  public let comparison: Comparison
  public let value: String

  public init?(field: Field, comparison: Comparison, value: String) {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedValue.isEmpty, normalizedValue.count <= 512 else { return nil }
    self.field = field
    self.comparison = comparison
    self.value = normalizedValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let field = try container.decode(Field.self, forKey: .field)
    let comparison = try container.decode(Comparison.self, forKey: .comparison)
    let value = try container.decode(String.self, forKey: .value)
    guard let rule = Self(field: field, comparison: comparison, value: value) else {
      throw DecodingError.dataCorruptedError(
        forKey: .value,
        in: container,
        debugDescription: "Smart collection rule values must contain between 1 and 512 characters."
      )
    }
    self = rule
  }

  public func matches(_ asset: PhotoAsset) -> Bool {
    switch field {
    case .filename:
      return compareText(asset.filename)
    case .typeIdentifier:
      return compareText(asset.typeIdentifier ?? "")
    case .sourceURL:
      return compareText(asset.sourceURL.absoluteString)
    case .rating:
      guard let target = Int(value), (0...5).contains(target) else { return false }
      switch comparison {
      case .equals: return asset.rating == target
      case .notEquals: return asset.rating != target
      case .contains: return false
      case .greaterThanOrEqual: return asset.rating >= target
      case .lessThanOrEqual: return asset.rating <= target
      }
    case .colorLabel:
      return compareText(asset.colorLabel?.rawValue ?? "")
    case .isMissing:
      guard let target = Self.parseBool(value) else { return false }
      switch comparison {
      case .equals: return asset.isMissing == target
      case .notEquals: return asset.isMissing != target
      case .contains, .greaterThanOrEqual, .lessThanOrEqual: return false
      }
    case .keyword:
      let keywords = asset.metadata.keywords.map(Self.folded)
      switch comparison {
      case .equals: return keywords.contains(Self.folded(value))
      case .notEquals: return !keywords.contains(Self.folded(value))
      case .contains: return keywords.contains { $0.contains(Self.folded(value)) }
      case .greaterThanOrEqual, .lessThanOrEqual: return false
      }
    }
  }

  private func compareText(_ actual: String) -> Bool {
    let actual = Self.folded(actual)
    let expected = Self.folded(value)
    switch comparison {
    case .equals: return actual == expected
    case .notEquals: return actual != expected
    case .contains: return actual.contains(expected)
    case .greaterThanOrEqual, .lessThanOrEqual: return false
    }
  }

  private static func folded(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private static func parseBool(_ value: String) -> Bool? {
    switch folded(value) {
    case "true", "yes", "1": true
    case "false", "no", "0": false
    default: nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case field
    case comparison
    case value
  }
}

public struct SmartCollectionPredicate: Codable, Hashable, Sendable {
  public enum Match: String, Codable, Hashable, Sendable {
    case all
    case any
  }

  public let rules: [SmartCollectionRule]
  public let match: Match

  public init?(rules: [SmartCollectionRule], match: Match = .all) {
    guard !rules.isEmpty, rules.count <= 64 else { return nil }
    self.rules = rules
    self.match = match
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rules = try container.decode([SmartCollectionRule].self, forKey: .rules)
    let match = try container.decode(Match.self, forKey: .match)
    guard let predicate = Self(rules: rules, match: match) else {
      throw DecodingError.dataCorruptedError(
        forKey: .rules,
        in: container,
        debugDescription: "Smart collection predicates must contain between 1 and 64 rules."
      )
    }
    self = predicate
  }

  public func matches(_ asset: PhotoAsset) -> Bool {
    switch match {
    case .all: rules.allSatisfy { $0.matches(asset) }
    case .any: rules.contains { $0.matches(asset) }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case rules
    case match
  }
}

public struct PhotoCollection: Codable, Hashable, Sendable, Identifiable {
  public enum Kind: String, Codable, Hashable, Sendable {
    case regular
    case smart
  }

  public let id: UUID
  public let name: String
  public let kind: Kind
  public let predicate: SmartCollectionPredicate?
  public let assetIDs: [UUID]
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    name: String,
    kind: Kind,
    predicate: SmartCollectionPredicate? = nil,
    assetIDs: [UUID] = [],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty, normalizedName.count <= 255 else { return nil }
    guard Set(assetIDs).count == assetIDs.count else { return nil }
    switch kind {
    case .regular:
      guard predicate == nil else { return nil }
    case .smart:
      guard predicate != nil, assetIDs.isEmpty else { return nil }
    }
    self.id = id
    self.name = normalizedName
    self.kind = kind
    self.predicate = predicate
    self.assetIDs = assetIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let kind = try container.decode(Kind.self, forKey: .kind)
    let predicate = try container.decodeIfPresent(
      SmartCollectionPredicate.self, forKey: .predicate)
    let assetIDs = try container.decode([UUID].self, forKey: .assetIDs)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let collection = Self(
        id: id,
        name: name,
        kind: kind,
        predicate: predicate,
        assetIDs: assetIDs,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .name,
        in: container,
        debugDescription: "The photo collection violates its membership and predicate invariants."
      )
    }
    self = collection
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case kind
    case predicate
    case assetIDs
    case createdAt
    case updatedAt
  }
}

public struct PhotoStack: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let assetIDs: [UUID]
  public let representativeAssetID: UUID
  public let isCollapsed: Bool
  public let createdAt: Date
  public let updatedAt: Date

  public init?(
    id: UUID = UUID(),
    assetIDs: [UUID],
    representativeAssetID: UUID,
    isCollapsed: Bool = false,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    guard !assetIDs.isEmpty,
      Set(assetIDs).count == assetIDs.count,
      assetIDs.contains(representativeAssetID)
    else { return nil }
    self.id = id
    self.assetIDs = assetIDs
    self.representativeAssetID = representativeAssetID
    self.isCollapsed = isCollapsed
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let assetIDs = try container.decode([UUID].self, forKey: .assetIDs)
    let representativeAssetID = try container.decode(
      UUID.self, forKey: .representativeAssetID)
    let isCollapsed = try container.decode(Bool.self, forKey: .isCollapsed)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)
    let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    guard
      let stack = Self(
        id: id,
        assetIDs: assetIDs,
        representativeAssetID: representativeAssetID,
        isCollapsed: isCollapsed,
        createdAt: createdAt,
        updatedAt: updatedAt
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .assetIDs,
        in: container,
        debugDescription: "The photo stack requires unique assets and a representative member."
      )
    }
    self = stack
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case assetIDs
    case representativeAssetID
    case isCollapsed
    case createdAt
    case updatedAt
  }
}
