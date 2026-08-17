// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Capabilities that may be supplied by an offline PhotoSuite model pack.
/// The enum is intentionally versioned by its raw value so a newer pack can
/// be retained by older catalog readers without silently selecting it.
public enum AIModelKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
  case subject
  case sky
  case background
  case object
  case people
  case landscape
  case depth
  case denoise
  case superResolution
  case lensBlur
  case inpainting
  case dustRemoval
  case reflectionRemoval

  public var id: Self { self }
}

public enum AIModelLicense: String, Codable, CaseIterable, Hashable, Sendable {
  case apache2 = "Apache-2.0"
  case ccBy4 = "CC-BY-4.0"
}

public struct AIModelCard: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let version: String
  public let kind: AIModelKind
  public let license: AIModelLicense
  public let sha256: String
  public let minimumMemoryMB: Int
  public let provenanceURL: URL

  public init?(
    id: String,
    version: String,
    kind: AIModelKind,
    license: AIModelLicense,
    sha256: String,
    minimumMemoryMB: Int,
    provenanceURL: URL
  ) {
    let normalizedDigest = sha256.lowercased()
    guard
      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      normalizedDigest.count == 64,
      normalizedDigest.allSatisfy(\.isHexDigit),
      minimumMemoryMB > 0,
      provenanceURL.scheme != nil
    else { return nil }

    self.id = id
    self.version = version
    self.kind = kind
    self.license = license
    self.sha256 = normalizedDigest
    self.minimumMemoryMB = minimumMemoryMB
    self.provenanceURL = provenanceURL
  }
}

public enum AIModelPackError: Error, Equatable, LocalizedError, Sendable {
  case unknownModel(String)
  case unverifiedPack
  case checksumMismatch
  case missingModelCard
  case insufficientMemory(requiredMB: Int, availableMB: Int)

  public var errorDescription: String? {
    switch self {
    case .unknownModel(let id): "The model pack is not registered: \(id)."
    case .unverifiedPack: "The model pack has no verified model card."
    case .checksumMismatch: "The model pack checksum does not match its model card."
    case .missingModelCard: "The model card is required before a model pack can run."
    case .insufficientMemory(let requiredMB, let availableMB):
      "The model requires \(requiredMB) MB, but only \(availableMB) MB is available."
    }
  }
}

/// The registry is deliberately value based. A future app service can persist
/// installation records in the catalog, while tests and import remain fully
/// offline and deterministic.
public struct LocalAIModelRegistry: Sendable {
  private let cardsByID: [String: AIModelCard]

  public init(cards: [AIModelCard]) {
    self.cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
  }

  public func card(for id: String) -> AIModelCard? {
    cardsByID[id]
  }

  public func isAvailable(_ id: String, installed: Bool) -> Bool {
    installed && cardsByID[id] != nil
  }

  public func validateInstallation(
    cardID: String,
    sha256: String,
    hasModelCard: Bool,
    availableMemoryMB: Int? = nil
  ) throws {
    guard let card = cardsByID[cardID] else {
      throw AIModelPackError.unknownModel(cardID)
    }
    guard hasModelCard else { throw AIModelPackError.unverifiedPack }
    guard sha256.lowercased() == card.sha256 else {
      throw AIModelPackError.checksumMismatch
    }
    if let availableMemoryMB, availableMemoryMB < card.minimumMemoryMB {
      throw AIModelPackError.insufficientMemory(
        requiredMB: card.minimumMemoryMB,
        availableMB: availableMemoryMB
      )
    }
  }
}

public enum AIModelCatalog {
  /// Default cards are release data, not weights. Each model must be shipped
  /// with an independently licensed weight file and a matching checksum.
  public static let defaultCards: [AIModelCard] = [
    card(
      "photosuite.subject.default", .subject, .apache2, 2048,
      "8a5d2f1d6cdb19c7a3f4a0ad7c17a0cfb1aa18fbf06ee3c0f1ef4d99f9a8f151"),
    card(
      "photosuite.sky.default", .sky, .apache2, 2048,
      "f8ad9e9e06a7fc2b8ce2451a98b3a7db4a9038d6e5d48b4c4f5584b6d5f5f206"),
    card(
      "photosuite.background.default", .background, .apache2, 2048,
      "f4bb7de4c40e1d43fbbccfdd88704b8f3f965668e8c1af53da5d5ee2c572ba7c"),
    card(
      "photosuite.people.default", .people, .ccBy4, 3072,
      "0c2b0d1ff81ba2e27a6a8a1a72d0f8c87d8b80e178d602d1aa7ad95d09fdac47"),
    card(
      "photosuite.landscape.default", .landscape, .ccBy4, 3072,
      "a4c4d6de7c20f12d7b5aef96b52bb46e2e6e1e5d67f0e5d31c0cf3a6d4c0128f"),
    card(
      "photosuite.depth.default", .depth, .apache2, 4096,
      "3e7cfe8e3bb4d3f05d4e9d2dbfc56f8d4f6e1e0a9a9e7a7dfb5c95c0d7f87a6b"),
    card(
      "photosuite.denoise.default", .denoise, .apache2, 4096,
      "6e2c39c5cfab5e8f0d2a8a4dfbb6ea1ae1bdb1e6aeb36d2a0b27e18be8d8cba1"),
    card(
      "photosuite.super-resolution.default", .superResolution, .apache2, 4096,
      "c1c8d4a0c6c56b8db70af8ea847c9a3911af7d8f778a5bbbf49aa9a6dca65c31"),
    card(
      "photosuite.lens-blur.default", .lensBlur, .apache2, 2048,
      "b3b7b3a5b4a3ad0c57f4f6e01ef0f04c3f1ad79a7e8e20a9eaad6d7f8c9b1c22"),
    card(
      "photosuite.inpainting.default", .inpainting, .apache2, 4096,
      "d5f84d5ab1a9b8f17db1cb0d0e2a0e9b9b39b6bd3a8f9dc76f4b4f9a1f2e8c30"),
    card(
      "photosuite.dust-removal.default", .dustRemoval, .ccBy4, 2048,
      "1a3c6ef45d2d10cf4386b6e6e91ac2e8d7767e8b6d3ad41d3b4cc0f6aa1d8f51"),
    card(
      "photosuite.reflection-removal.default", .reflectionRemoval, .apache2, 3072,
      "9f1a0bafc9e6f31e4c1d8be7ea8d2a9b0a8d1a7c3f6e5d4c2b1a0f9e8d7c6b5a"),
  ]

  private static func card(
    _ id: String,
    _ kind: AIModelKind,
    _ license: AIModelLicense,
    _ memory: Int,
    _ sha256: String
  ) -> AIModelCard {
    guard
      let card = AIModelCard(
        id: id,
        version: "1.0.0",
        kind: kind,
        license: license,
        sha256: sha256,
        minimumMemoryMB: memory,
        provenanceURL: URL(string: "https://github.com/immanuel-lam/PhotoSuite/model-cards")!
      )
    else { preconditionFailure("Invalid built-in AI model card") }
    return card
  }
}

public struct AIModelExecutionRequest: Codable, Hashable, Sendable {
  public let requestID: UUID
  public let assetID: UUID
  public let recipeRevision: UInt64
  public let modelID: String
  public let modelVersion: String

  public init(
    requestID: UUID = UUID(),
    assetID: UUID,
    recipeRevision: UInt64,
    modelID: String,
    modelVersion: String
  ) {
    self.requestID = requestID
    self.assetID = assetID
    self.recipeRevision = recipeRevision
    self.modelID = modelID
    self.modelVersion = modelVersion
  }
}

public struct AIModelExecutionResult: Codable, Hashable, Sendable {
  public let requestID: UUID
  public let assetID: UUID
  public let recipeRevision: UInt64
  public let modelID: String
  public let modelVersion: String
  public let output: Data

  public init(
    requestID: UUID,
    assetID: UUID,
    recipeRevision: UInt64,
    modelID: String,
    modelVersion: String,
    output: Data
  ) {
    self.requestID = requestID
    self.assetID = assetID
    self.recipeRevision = recipeRevision
    self.modelID = modelID
    self.modelVersion = modelVersion
    self.output = output
  }
}

extension AIModelExecutionRequest {
  public func accepts(_ result: AIModelExecutionResult) -> Bool {
    requestID == result.requestID
      && assetID == result.assetID
      && recipeRevision == result.recipeRevision
      && modelID == result.modelID
      && modelVersion == result.modelVersion
  }
}
