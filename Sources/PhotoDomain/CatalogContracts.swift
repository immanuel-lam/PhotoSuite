// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct CatalogAssetUpsertRequest: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public struct CatalogAssetUpsertResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public struct CatalogAssetFetchRequest: Codable, Hashable, Sendable {
  public let assetID: UUID

  public init(assetID: UUID) {
    self.assetID = assetID
  }
}

public struct CatalogAssetFetchResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset?

  public init(asset: PhotoAsset?) {
    self.asset = asset
  }
}

public struct CatalogAssetMetadataUpdateRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let metadata: PhotoMetadata

  public init(assetID: UUID, metadata: PhotoMetadata) {
    self.assetID = assetID
    self.metadata = metadata
  }
}

public struct CatalogAssetMetadataUpdateResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public struct CatalogMetadataPresetSaveRequest: Codable, Hashable, Sendable {
  public let preset: MetadataPreset

  public init(preset: MetadataPreset) {
    self.preset = preset
  }
}

public struct CatalogMetadataPresetSaveResult: Codable, Hashable, Sendable {
  public let preset: MetadataPreset

  public init(preset: MetadataPreset) {
    self.preset = preset
  }
}

public struct CatalogMetadataPresetListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogMetadataPresetListResult: Codable, Hashable, Sendable {
  public let presets: [MetadataPreset]

  public init(presets: [MetadataPreset]) {
    self.presets = presets
  }
}

public struct CatalogMetadataPresetDeleteRequest: Codable, Hashable, Sendable {
  public let presetID: UUID

  public init(presetID: UUID) {
    self.presetID = presetID
  }
}

public struct CatalogMetadataPresetDeleteResult: Codable, Hashable, Sendable {
  public let presetID: UUID

  public init(presetID: UUID) {
    self.presetID = presetID
  }
}

public struct CatalogApplyMetadataPresetRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let presetID: UUID

  public init(assetID: UUID, presetID: UUID) {
    self.assetID = assetID
    self.presetID = presetID
  }
}

public struct CatalogApplyMetadataPresetResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public enum CatalogAssetOrder: String, Codable, Hashable, Sendable {
  case importDateAscending
  case importDateDescending
  case captureDateAscending
  case captureDateDescending
  case filenameAscending
  case filenameDescending
}

public struct CatalogAssetListRequest: Codable, Hashable, Sendable {
  public let order: CatalogAssetOrder
  public let limit: Int?
  public let offset: Int

  public init(
    order: CatalogAssetOrder = .importDateDescending,
    limit: Int? = nil,
    offset: Int = 0
  ) {
    self.order = order
    self.limit = limit
    self.offset = offset
  }
}

public struct CatalogAssetListResult: Codable, Hashable, Sendable {
  public let assets: [PhotoAsset]

  public init(assets: [PhotoAsset]) {
    self.assets = assets
  }
}

public struct CatalogAssetSearchRequest: Codable, Hashable, Sendable {
  public let query: String
  public let limit: Int?

  public init(query: String, limit: Int? = nil) {
    self.query = query
    self.limit = limit
  }
}

public struct CatalogAssetSearchResult: Codable, Hashable, Sendable {
  public let assets: [PhotoAsset]

  public init(assets: [PhotoAsset]) {
    self.assets = assets
  }
}

public struct CatalogRecipeSaveRequest: Codable, Hashable, Sendable {
  public let recipe: EditRecipe

  public init(recipe: EditRecipe) {
    self.recipe = recipe
  }
}

public struct CatalogRecipeSaveResult: Codable, Hashable, Sendable {
  public let recipe: EditRecipe

  public init(recipe: EditRecipe) {
    self.recipe = recipe
  }
}

public struct CatalogLatestRecipeRequest: Codable, Hashable, Sendable {
  public let assetID: UUID

  public init(assetID: UUID) {
    self.assetID = assetID
  }
}

public struct CatalogLatestRecipeResult: Codable, Hashable, Sendable {
  public let recipe: EditRecipe?

  public init(recipe: EditRecipe?) {
    self.recipe = recipe
  }
}

public struct CatalogMarkMissingRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let isMissing: Bool

  public init(assetID: UUID, isMissing: Bool) {
    self.assetID = assetID
    self.isMissing = isMissing
  }
}

public struct CatalogMarkMissingResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public struct CatalogRelinkAssetRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let sourceURL: URL
  public let filename: String
  public let typeIdentifier: String?
  public let fingerprint: SourceFingerprint

  public init(
    assetID: UUID,
    sourceURL: URL,
    filename: String,
    typeIdentifier: String?,
    fingerprint: SourceFingerprint
  ) {
    self.assetID = assetID
    self.sourceURL = sourceURL
    self.filename = filename
    self.typeIdentifier = typeIdentifier
    self.fingerprint = fingerprint
  }
}

public struct CatalogRelinkAssetResult: Codable, Hashable, Sendable {
  public let asset: PhotoAsset

  public init(asset: PhotoAsset) {
    self.asset = asset
  }
}

public struct CatalogIntegrityRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogIntegrityResult: Codable, Hashable, Sendable {
  public let isValid: Bool
  public let messages: [String]

  public init(isValid: Bool, messages: [String]) {
    self.isValid = isValid
    self.messages = messages
  }
}

public struct CatalogBackupRequest: Codable, Hashable, Sendable {
  public let destinationURL: URL

  public init(destinationURL: URL) {
    self.destinationURL = destinationURL
  }
}

public struct CatalogBackupResult: Codable, Hashable, Sendable {
  public let destinationURL: URL

  public init(destinationURL: URL) {
    self.destinationURL = destinationURL
  }
}

public protocol CatalogStore: Sendable {
  func upsertAsset(_ request: CatalogAssetUpsertRequest) async throws -> CatalogAssetUpsertResult
  func fetchAsset(_ request: CatalogAssetFetchRequest) async throws -> CatalogAssetFetchResult
  func listAssets(_ request: CatalogAssetListRequest) async throws -> CatalogAssetListResult
  func searchAssets(_ request: CatalogAssetSearchRequest) async throws -> CatalogAssetSearchResult
  func saveRecipe(_ request: CatalogRecipeSaveRequest) async throws -> CatalogRecipeSaveResult
  func latestRecipe(_ request: CatalogLatestRecipeRequest) async throws -> CatalogLatestRecipeResult
  func markAssetMissing(_ request: CatalogMarkMissingRequest) async throws
    -> CatalogMarkMissingResult
  func relinkAsset(_ request: CatalogRelinkAssetRequest) async throws -> CatalogRelinkAssetResult
  func checkIntegrity(_ request: CatalogIntegrityRequest) async throws -> CatalogIntegrityResult
  func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult
}

public protocol MetadataCatalogStore: CatalogStore {
  func updateMetadata(_ request: CatalogAssetMetadataUpdateRequest) async throws
    -> CatalogAssetMetadataUpdateResult
  func saveMetadataPreset(_ request: CatalogMetadataPresetSaveRequest) async throws
    -> CatalogMetadataPresetSaveResult
  func listMetadataPresets(_ request: CatalogMetadataPresetListRequest) async throws
    -> CatalogMetadataPresetListResult
  func deleteMetadataPreset(_ request: CatalogMetadataPresetDeleteRequest) async throws
    -> CatalogMetadataPresetDeleteResult
  func applyMetadataPreset(_ request: CatalogApplyMetadataPresetRequest) async throws
    -> CatalogApplyMetadataPresetResult
}

public struct JobEnqueueRequest: Codable, Hashable, Sendable {
  public let job: CatalogJob

  public init(job: CatalogJob) {
    self.job = job
  }
}

public struct JobEnqueueResult: Codable, Hashable, Sendable {
  public let job: CatalogJob

  public init(job: CatalogJob) {
    self.job = job
  }
}

public struct JobUpdateRequest: Codable, Hashable, Sendable {
  public let job: CatalogJob

  public init(job: CatalogJob) {
    self.job = job
  }
}

public struct JobUpdateResult: Codable, Hashable, Sendable {
  public let job: CatalogJob

  public init(job: CatalogJob) {
    self.job = job
  }
}

public struct JobListRequest: Codable, Hashable, Sendable {
  public let states: [CatalogJobState]

  public init(states: [CatalogJobState] = []) {
    self.states = states
  }
}

public struct JobListResult: Codable, Hashable, Sendable {
  public let jobs: [CatalogJob]

  public init(jobs: [CatalogJob]) {
    self.jobs = jobs
  }
}

public protocol JobEngine: Sendable {
  func enqueue(_ request: JobEnqueueRequest) async throws -> JobEnqueueResult
  func update(_ request: JobUpdateRequest) async throws -> JobUpdateResult
  func list(_ request: JobListRequest) async throws -> JobListResult
}
