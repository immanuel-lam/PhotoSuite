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

public struct CatalogCollectionSaveRequest: Codable, Hashable, Sendable {
  public let collection: PhotoCollection

  public init(collection: PhotoCollection) {
    self.collection = collection
  }
}

public struct CatalogCollectionSaveResult: Codable, Hashable, Sendable {
  public let collection: PhotoCollection

  public init(collection: PhotoCollection) {
    self.collection = collection
  }
}

public struct CatalogCollectionListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogCollectionListResult: Codable, Hashable, Sendable {
  public let collections: [PhotoCollection]

  public init(collections: [PhotoCollection]) {
    self.collections = collections
  }
}

public struct CatalogCollectionDeleteRequest: Codable, Hashable, Sendable {
  public let collectionID: UUID

  public init(collectionID: UUID) {
    self.collectionID = collectionID
  }
}

public struct CatalogCollectionDeleteResult: Codable, Hashable, Sendable {
  public let collectionID: UUID

  public init(collectionID: UUID) {
    self.collectionID = collectionID
  }
}

public struct CatalogCollectionAssetsRequest: Codable, Hashable, Sendable {
  public let collectionID: UUID

  public init(collectionID: UUID) {
    self.collectionID = collectionID
  }
}

public struct CatalogCollectionAssetsResult: Codable, Hashable, Sendable {
  public let assets: [PhotoAsset]

  public init(assets: [PhotoAsset]) {
    self.assets = assets
  }
}

public struct CatalogStackSaveRequest: Codable, Hashable, Sendable {
  public let stack: PhotoStack

  public init(stack: PhotoStack) {
    self.stack = stack
  }
}

public struct CatalogStackSaveResult: Codable, Hashable, Sendable {
  public let stack: PhotoStack

  public init(stack: PhotoStack) {
    self.stack = stack
  }
}

public struct CatalogStackListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogStackListResult: Codable, Hashable, Sendable {
  public let stacks: [PhotoStack]

  public init(stacks: [PhotoStack]) {
    self.stacks = stacks
  }
}

public struct CatalogStackDeleteRequest: Codable, Hashable, Sendable {
  public let stackID: UUID

  public init(stackID: UUID) {
    self.stackID = stackID
  }
}

public struct CatalogStackDeleteResult: Codable, Hashable, Sendable {
  public let stackID: UUID

  public init(stackID: UUID) {
    self.stackID = stackID
  }
}

public struct CatalogStackAssetsRequest: Codable, Hashable, Sendable {
  public let stackID: UUID

  public init(stackID: UUID) {
    self.stackID = stackID
  }
}

public struct CatalogStackAssetsResult: Codable, Hashable, Sendable {
  public let assets: [PhotoAsset]

  public init(assets: [PhotoAsset]) {
    self.assets = assets
  }
}

public struct CatalogKeywordNodeSaveRequest: Codable, Hashable, Sendable {
  public let keyword: KeywordNode

  public init(keyword: KeywordNode) {
    self.keyword = keyword
  }
}

public struct CatalogKeywordNodeSaveResult: Codable, Hashable, Sendable {
  public let keyword: KeywordNode

  public init(keyword: KeywordNode) {
    self.keyword = keyword
  }
}

public struct CatalogKeywordNodeListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogKeywordNodeListResult: Codable, Hashable, Sendable {
  public let keywords: [KeywordNode]

  public init(keywords: [KeywordNode]) {
    self.keywords = keywords
  }
}

public struct CatalogKeywordNodeDeleteRequest: Codable, Hashable, Sendable {
  public let keywordID: UUID

  public init(keywordID: UUID) {
    self.keywordID = keywordID
  }
}

public struct CatalogKeywordNodeDeleteResult: Codable, Hashable, Sendable {
  public let keywordID: UUID

  public init(keywordID: UUID) {
    self.keywordID = keywordID
  }
}

public struct CatalogAssetKeywordSetRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let keywordIDs: [UUID]

  public init(assetID: UUID, keywordIDs: [UUID]) {
    self.assetID = assetID
    self.keywordIDs = keywordIDs
  }
}

public struct CatalogAssetKeywordSetResult: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let keywordIDs: [UUID]

  public init(assetID: UUID, keywordIDs: [UUID]) {
    self.assetID = assetID
    self.keywordIDs = keywordIDs
  }
}

public struct CatalogAssetKeywordListRequest: Codable, Hashable, Sendable {
  public let assetID: UUID

  public init(assetID: UUID) {
    self.assetID = assetID
  }
}

public struct CatalogAssetKeywordListResult: Codable, Hashable, Sendable {
  public let keywords: [KeywordNode]

  public init(keywords: [KeywordNode]) {
    self.keywords = keywords
  }
}

public struct CatalogVirtualCopySaveRequest: Codable, Hashable, Sendable {
  public let virtualCopy: VirtualCopy

  public init(virtualCopy: VirtualCopy) {
    self.virtualCopy = virtualCopy
  }
}

public struct CatalogVirtualCopySaveResult: Codable, Hashable, Sendable {
  public let virtualCopy: VirtualCopy

  public init(virtualCopy: VirtualCopy) {
    self.virtualCopy = virtualCopy
  }
}

public struct CatalogVirtualCopyListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogVirtualCopyListResult: Codable, Hashable, Sendable {
  public let virtualCopies: [VirtualCopy]

  public init(virtualCopies: [VirtualCopy]) {
    self.virtualCopies = virtualCopies
  }
}

public struct CatalogVirtualCopyDeleteRequest: Codable, Hashable, Sendable {
  public let virtualCopyID: UUID

  public init(virtualCopyID: UUID) {
    self.virtualCopyID = virtualCopyID
  }
}

public struct CatalogVirtualCopyDeleteResult: Codable, Hashable, Sendable {
  public let virtualCopyID: UUID

  public init(virtualCopyID: UUID) {
    self.virtualCopyID = virtualCopyID
  }
}

public struct CatalogDevelopPresetSaveRequest: Codable, Hashable, Sendable {
  public let preset: DevelopPreset

  public init(preset: DevelopPreset) {
    self.preset = preset
  }
}

public struct CatalogDevelopPresetSaveResult: Codable, Hashable, Sendable {
  public let preset: DevelopPreset

  public init(preset: DevelopPreset) {
    self.preset = preset
  }
}

public struct CatalogDevelopPresetListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogDevelopPresetListResult: Codable, Hashable, Sendable {
  public let presets: [DevelopPreset]

  public init(presets: [DevelopPreset]) {
    self.presets = presets
  }
}

public struct CatalogDevelopPresetDeleteRequest: Codable, Hashable, Sendable {
  public let presetID: UUID

  public init(presetID: UUID) {
    self.presetID = presetID
  }
}

public struct CatalogDevelopPresetDeleteResult: Codable, Hashable, Sendable {
  public let presetID: UUID

  public init(presetID: UUID) {
    self.presetID = presetID
  }
}

public struct CatalogApplyDevelopPresetRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let presetID: UUID
  public let virtualCopyID: UUID?

  public init(assetID: UUID, presetID: UUID, virtualCopyID: UUID? = nil) {
    self.assetID = assetID
    self.presetID = presetID
    self.virtualCopyID = virtualCopyID
  }
}

public struct CatalogApplyDevelopPresetResult: Codable, Hashable, Sendable {
  public let recipe: EditRecipe

  public init(recipe: EditRecipe) {
    self.recipe = recipe
  }
}

public struct CatalogFolderSaveRequest: Codable, Hashable, Sendable {
  public let folder: LibraryFolder

  public init(folder: LibraryFolder) {
    self.folder = folder
  }
}

public struct CatalogFolderSaveResult: Codable, Hashable, Sendable {
  public let folder: LibraryFolder

  public init(folder: LibraryFolder) {
    self.folder = folder
  }
}

public struct CatalogFolderListRequest: Codable, Hashable, Sendable {
  public init() {}
}

public struct CatalogFolderListResult: Codable, Hashable, Sendable {
  public let folders: [LibraryFolder]

  public init(folders: [LibraryFolder]) {
    self.folders = folders
  }
}

public struct CatalogFolderDeleteRequest: Codable, Hashable, Sendable {
  public let folderID: UUID

  public init(folderID: UUID) {
    self.folderID = folderID
  }
}

public struct CatalogFolderDeleteResult: Codable, Hashable, Sendable {
  public let folderID: UUID

  public init(folderID: UUID) {
    self.folderID = folderID
  }
}

public struct CatalogAssetFolderSetRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let folderID: UUID?

  public init(assetID: UUID, folderID: UUID?) {
    self.assetID = assetID
    self.folderID = folderID
  }
}

public struct CatalogAssetFolderSetResult: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let folderID: UUID?

  public init(assetID: UUID, folderID: UUID?) {
    self.assetID = assetID
    self.folderID = folderID
  }
}

public struct CatalogAssetFolderRequest: Codable, Hashable, Sendable {
  public let assetID: UUID

  public init(assetID: UUID) {
    self.assetID = assetID
  }
}

public struct CatalogAssetFolderResult: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let folderID: UUID?

  public init(assetID: UUID, folderID: UUID?) {
    self.assetID = assetID
    self.folderID = folderID
  }
}

public struct CatalogFolderAssetsRequest: Codable, Hashable, Sendable {
  public let folderID: UUID

  public init(folderID: UUID) {
    self.folderID = folderID
  }
}

public struct CatalogFolderAssetsResult: Codable, Hashable, Sendable {
  public let assets: [PhotoAsset]

  public init(assets: [PhotoAsset]) {
    self.assets = assets
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
  public let virtualCopyID: UUID?

  public init(assetID: UUID, virtualCopyID: UUID? = nil) {
    self.assetID = assetID
    self.virtualCopyID = virtualCopyID
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

public protocol LibraryCatalogStore: CatalogStore {
  func saveCollection(_ request: CatalogCollectionSaveRequest) async throws
    -> CatalogCollectionSaveResult
  func listCollections(_ request: CatalogCollectionListRequest) async throws
    -> CatalogCollectionListResult
  func deleteCollection(_ request: CatalogCollectionDeleteRequest) async throws
    -> CatalogCollectionDeleteResult
  func listCollectionAssets(_ request: CatalogCollectionAssetsRequest) async throws
    -> CatalogCollectionAssetsResult
  func saveStack(_ request: CatalogStackSaveRequest) async throws -> CatalogStackSaveResult
  func listStacks(_ request: CatalogStackListRequest) async throws -> CatalogStackListResult
  func deleteStack(_ request: CatalogStackDeleteRequest) async throws -> CatalogStackDeleteResult
  func listStackAssets(_ request: CatalogStackAssetsRequest) async throws
    -> CatalogStackAssetsResult
  func saveKeywordNode(_ request: CatalogKeywordNodeSaveRequest) async throws
    -> CatalogKeywordNodeSaveResult
  func listKeywordNodes(_ request: CatalogKeywordNodeListRequest) async throws
    -> CatalogKeywordNodeListResult
  func deleteKeywordNode(_ request: CatalogKeywordNodeDeleteRequest) async throws
    -> CatalogKeywordNodeDeleteResult
  func setAssetKeywords(_ request: CatalogAssetKeywordSetRequest) async throws
    -> CatalogAssetKeywordSetResult
  func listAssetKeywords(_ request: CatalogAssetKeywordListRequest) async throws
    -> CatalogAssetKeywordListResult
  func saveVirtualCopy(_ request: CatalogVirtualCopySaveRequest) async throws
    -> CatalogVirtualCopySaveResult
  func listVirtualCopies(_ request: CatalogVirtualCopyListRequest) async throws
    -> CatalogVirtualCopyListResult
  func deleteVirtualCopy(_ request: CatalogVirtualCopyDeleteRequest) async throws
    -> CatalogVirtualCopyDeleteResult
  func saveDevelopPreset(_ request: CatalogDevelopPresetSaveRequest) async throws
    -> CatalogDevelopPresetSaveResult
  func listDevelopPresets(_ request: CatalogDevelopPresetListRequest) async throws
    -> CatalogDevelopPresetListResult
  func deleteDevelopPreset(_ request: CatalogDevelopPresetDeleteRequest) async throws
    -> CatalogDevelopPresetDeleteResult
  func applyDevelopPreset(_ request: CatalogApplyDevelopPresetRequest) async throws
    -> CatalogApplyDevelopPresetResult
  func saveFolder(_ request: CatalogFolderSaveRequest) async throws -> CatalogFolderSaveResult
  func listFolders(_ request: CatalogFolderListRequest) async throws -> CatalogFolderListResult
  func deleteFolder(_ request: CatalogFolderDeleteRequest) async throws -> CatalogFolderDeleteResult
  func setAssetFolder(_ request: CatalogAssetFolderSetRequest) async throws
    -> CatalogAssetFolderSetResult
  func listAssetFolder(_ request: CatalogAssetFolderRequest) async throws
    -> CatalogAssetFolderResult
  func listFolderAssets(_ request: CatalogFolderAssetsRequest) async throws
    -> CatalogFolderAssetsResult
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
