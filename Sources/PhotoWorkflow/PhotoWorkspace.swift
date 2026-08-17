// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation
import PhotoDomain

private struct PreviewTaskOutput: Sendable {
  let result: RenderResult
  let recoveredRecipe: EditRecipe?
}

@MainActor
@Observable
public final class PhotoWorkspace {
  public var section: WorkspaceSection = .library
  public var assets: [PhotoAsset] = []
  public var selectedAssetID: UUID?
  public var currentRecipe: EditRecipe?
  public var preview: PreviewFrame?
  public var itemErrors: [WorkspaceItemError] = []
  public var errorMessage: String?
  public var lastError: PhotoWorkspaceError?
  public var searchText = ""
  public var isLoading = false
  public var isExporting = false
  public var isImporting = false
  public var isRelinking = false
  public var isChoosingExportDestination = false
  public var proofMode = false
  public var showsBefore = false
  public var lastExport: DurableDerivative?
  public var lastBatchExports: [DurableDerivative] = []
  public var isBatchExporting = false
  public var collections: [LibraryCollection] = []
  public var stacks: [LibraryStack] = []
  public var durableCollections: [PhotoCollection] = []
  public var durableStacks: [PhotoStack] = []
  public var folders: [LibraryFolder] = []
  public var folderAssetIDs: [UUID: Set<UUID>] = [:]
  public var keywordNodes: [KeywordNode] = []
  public var selectedAssetKeywords: [KeywordNode] = []
  /// Durable face geometry and optional user labels for the selected asset.
  /// Labels are user metadata only. PhotoSuite does not infer biometric identity.
  public var selectedAssetFaces: [PhotoFace] = []
  public var selectedFaceID: UUID?
  public var virtualCopies: [VirtualCopy] = []
  public var selectedVirtualCopyID: UUID?
  public var developPresets: [DevelopPreset] = []
  public var smartFilter = LibrarySmartFilter()
  public var activeCollectionID: UUID?
  public var activeFolderID: UUID?
  public var deliverOptions = DeliverOptions()
  public var professionalTool: ProfessionalTool = .map
  public var photoLocations: [PhotoLocation] = []
  public var isLoadingPhotoLocations = false
  public var isProfessionalExporting = false
  public var lastProfessionalOutput: URL?
  public var metadataSidecarStatus: MetadataSidecarStatus = .idle

  public var selectedAsset: PhotoAsset? {
    guard let selectedAssetID else { return nil }
    return assets.first { $0.id == selectedAssetID }
  }

  public var selectedFace: PhotoFace? {
    guard let selectedFaceID else { return selectedAssetFaces.first }
    return selectedAssetFaces.first { $0.id == selectedFaceID }
  }

  public var supportsPeopleMetadata: Bool {
    catalog is any PeopleCatalogStore
  }

  public var supportsDurableLibrary: Bool {
    catalog is any LibraryCatalogStore
  }

  /// The latest persisted three-way grade, or the neutral grade when the
  /// current recipe does not contain one. The UI uses this value as its
  /// starting point; edits are committed through `commitColorGrade(_:)`.
  public var currentColorGrade: ThreeWayColorGrade {
    for operation in currentRecipe?.operations.reversed() ?? [] {
      if case .threeWayColorGrade(let grade) = operation { return grade }
    }
    return .neutral
  }

  /// Baseline Develop operations currently persisted for the selected recipe.
  /// The application uses this read-only projection to restore inspector state
  /// without exposing catalog implementation details to the UI.
  public var currentDevelopOperations: [EditOperation] {
    currentRecipe?.operations.filter { Self.developFamily($0) != nil } ?? []
  }

  /// Masks are durable recipe data. Their graph payload remains opaque to the
  /// catalog, which keeps older recipes forward compatible while the current
  /// UI can author the version-one graph contracts.
  public var currentMasks: [MaskDefinition] {
    currentRecipe?.masks ?? []
  }

  public var filteredAssets: [PhotoAsset] {
    var collectionFilter: ((PhotoAsset) -> Bool)?
    if let collectionID = activeCollectionID {
      if let sessionCollection = collections.first(where: { $0.id == collectionID }) {
        let assetIDs = Set(sessionCollection.assetIDs)
        collectionFilter = { assetIDs.contains($0.id) }
      } else if let durableCollection = durableCollections.first(where: { $0.id == collectionID }) {
        switch durableCollection.kind {
        case .regular:
          let assetIDs = Set(durableCollection.assetIDs)
          collectionFilter = { assetIDs.contains($0.id) }
        case .smart:
          collectionFilter = { durableCollection.predicate?.matches($0) == true }
        }
      } else {
        collectionFilter = { _ in false }
      }
    }
    var folderFilter: ((PhotoAsset) -> Bool)?
    if let folderID = activeFolderID {
      let descendantIDs = Set(folderIDs(including: folderID))
      let assetIDs = folderAssetIDs.reduce(into: Set<UUID>()) { result, entry in
        guard descendantIDs.contains(entry.key) else { return }
        result.formUnion(entry.value)
      }
      folderFilter = { assetIDs.contains($0.id) }
    }
    return assets.filter { asset in
      if !searchText.isEmpty,
        !asset.filename.localizedCaseInsensitiveContains(searchText)
      {
        return false
      }
      if let collectionFilter, !collectionFilter(asset) { return false }
      if let folderFilter, !folderFilter(asset) { return false }
      return smartFilter.matches(asset)
    }
  }

  public var canUndo: Bool { !undoStack.isEmpty }
  public var canRedo: Bool { !redoStack.isEmpty }

  public func cachedPreview(for assetID: UUID) -> PreviewFrame? {
    previewCache[assetID]
  }

  private let catalog: any CatalogStore
  private let renderer: any RenderEngine
  private let exporter: any Exporter
  private let sourceAccess: SourceAccessOperations
  private let fingerprint: @Sendable (URL) async throws -> SourceFingerprint
  private let probe: @Sendable (URL) async throws -> SourceProbe
  private let locationProbe: @Sendable (URL) async throws -> PhotoCoordinate?
  private let now: @Sendable () -> Date
  private let previewDebounce: @Sendable () async throws -> Void
  private var previewCache: [UUID: PreviewFrame] = [:]
  private var draftValues: [AdjustmentKind: Double] = [:]
  private var undoStack: [[EditOperation]] = []
  private var redoStack: [[EditOperation]] = []
  private var previewGeneration: UInt64 = 0
  @ObservationIgnored private var previewTask: Task<PreviewTaskOutput, any Error>?
  @ObservationIgnored private var scheduledPreviewTask: Task<Void, Never>?
  @ObservationIgnored private var editMutationTail: Task<Void, Never>?
  @ObservationIgnored private var libraryMutationTail: Task<Void, Never>?
  private var editMutationGeneration: UInt64 = 0
  private var libraryMutationGeneration: UInt64 = 0

  public init(
    catalog: any CatalogStore,
    renderer: any RenderEngine,
    exporter: any Exporter,
    sourceAccess: SourceAccessOperations,
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint,
    probe: @escaping @Sendable (URL) async throws -> SourceProbe,
    locationProbe: @escaping @Sendable (URL) async throws -> PhotoCoordinate? = { _ in nil },
    now: @escaping @Sendable () -> Date = { Date() },
    previewDebounce: @escaping @Sendable () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(160))
    }
  ) {
    self.catalog = catalog
    self.renderer = renderer
    self.exporter = exporter
    self.sourceAccess = sourceAccess
    self.fingerprint = fingerprint
    self.probe = probe
    self.locationProbe = locationProbe
    self.now = now
    self.previewDebounce = previewDebounce
  }

  deinit {
    previewTask?.cancel()
    scheduledPreviewTask?.cancel()
    editMutationTail?.cancel()
    libraryMutationTail?.cancel()
  }

  public func reopen() async {
    isLoading = true
    errorMessage = nil
    lastError = nil
    itemErrors = []
    defer { isLoading = false }

    do {
      assets = try await catalog.listAssets(
        CatalogAssetListRequest(order: .importDateDescending)
      ).assets
      selectedAssetID = nil
      currentRecipe = nil
      preview = nil
      durableCollections = []
      durableStacks = []
      folders = []
      folderAssetIDs = [:]
      activeFolderID = nil
      keywordNodes = []
      selectedAssetKeywords = []
      selectedAssetFaces = []
      selectedFaceID = nil
      virtualCopies = []
      selectedVirtualCopyID = nil
      developPresets = []
      metadataSidecarStatus = .idle

      if let libraryCatalog = catalog as? any LibraryCatalogStore {
        do {
          durableCollections = try await libraryCatalog.listCollections(
            CatalogCollectionListRequest()
          ).collections
          durableStacks = try await libraryCatalog.listStacks(
            CatalogStackListRequest()
          ).stacks
          keywordNodes = try await libraryCatalog.listKeywordNodes(
            CatalogKeywordNodeListRequest()
          ).keywords
          virtualCopies = try await libraryCatalog.listVirtualCopies(
            CatalogVirtualCopyListRequest()
          ).virtualCopies
          developPresets = try await libraryCatalog.listDevelopPresets(
            CatalogDevelopPresetListRequest()
          ).presets
          for folder in try await libraryCatalog.listFolders(CatalogFolderListRequest()).folders {
            folders.append(folder)
            do {
              folderAssetIDs[folder.id] = Set(
                try await libraryCatalog.listFolderAssets(
                  CatalogFolderAssetsRequest(folderID: folder.id)
                ).assets.map(\.id)
              )
            } catch {
              record(error, operation: "library.folder.assets")
            }
          }
        } catch {
          record(error, operation: "library.reopen")
        }
      }

      var availableAssetIDs: [UUID] = []
      for index in assets.indices {
        let asset = assets[index]
        do {
          _ = try await sourceAccess.resolve(asset)
          availableAssetIDs.append(asset.id)
          if asset.isMissing {
            let result = try await catalog.markAssetMissing(
              CatalogMarkMissingRequest(assetID: asset.id, isMissing: false)
            )
            assets[index] = result.asset
          }
        } catch {
          do {
            let result = try await catalog.markAssetMissing(
              CatalogMarkMissingRequest(assetID: asset.id, isMissing: true)
            )
            assets[index] = result.asset
          } catch {
            itemErrors.append(
              WorkspaceItemError(sourceURL: asset.sourceURL, message: message(for: error))
            )
          }
        }
      }

      for assetID in availableAssetIDs {
        guard
          let recipe = try await catalog.latestRecipe(
            CatalogLatestRecipeRequest(assetID: assetID)
          ).recipe
        else {
          continue
        }
        selectedAssetID = assetID
        currentRecipe = recipe
        await loadSelectedAssetKeywords(assetID)
        await loadSelectedAssetFaces(assetID)
        resetHistory()
        syncDraftValues()
        await refreshPreview()
        return
      }
    } catch {
      record(error, operation: "reopen")
    }
  }

  public func loadPhotoLocations() async {
    isLoadingPhotoLocations = true
    defer { isLoadingPhotoLocations = false }
    var loaded: [PhotoLocation] = []
    for asset in assets where !asset.isMissing {
      do {
        try Task.checkCancellation()
        let url = try await sourceAccess.resolve(asset)
        let started = await sourceAccess.start(url)
        do {
          let coordinate = try await locationProbe(url)
          if started { await sourceAccess.stop(url) }
          if let coordinate {
            loaded.append(
              PhotoLocation(assetID: asset.id, filename: asset.filename, coordinate: coordinate)
            )
          }
        } catch {
          if started { await sourceAccess.stop(url) }
          throw error
        }
      } catch is CancellationError {
        return
      } catch {
        // A source without readable GPS metadata does not make the catalog invalid.
      }
    }
    photoLocations = loaded
  }

  public func professionalStatus(for tool: ProfessionalTool) -> ProfessionalCapabilityStatus {
    switch tool {
    case .map:
      photoLocations.isEmpty ? .unavailable(.locationMetadataUnavailable) : .available
    case .tether:
      .previewOnly(.cameraAdapterRequired)
    case .print:
      preview == nil ? .unavailable(.selectionRequired) : .available
    case .book:
      professionalOutputAssets.isEmpty
        ? .unavailable(.selectionRequired) : .available
    case .slideshow:
      professionalOutputAssets.isEmpty
        ? .unavailable(.selectionRequired) : .available
    case .webGallery:
      professionalOutputAssets.isEmpty
        ? .unavailable(.selectionRequired) : .available
    case .plugins:
      .unavailable(.pluginHostUnavailable)
    case .adobeMigration:
      .unavailable(.adobeCatalogParserUnavailable)
    }
  }

  /// The current Library selection, or the active filtered set when it contains photographs.
  /// Professional outputs use the latest durable recipe for every item and never mutate sources.
  public var professionalOutputAssets: [PhotoAsset] {
    let candidates = filteredAssets.filter { !$0.isMissing }
    if !candidates.isEmpty { return candidates }
    if let selectedAsset, !selectedAsset.isMissing { return [selectedAsset] }
    return []
  }

  public func exportBook(
    to destinationURL: URL,
    title: String = "PhotoSuite Book",
    author: String? = nil,
    pageSize: PhotoBookPageSize = .a4
  ) async {
    await exportProfessionalOutput(operation: "book", assets: professionalOutputAssets) {
      let photos = try await self.professionalOutputPhotos()
      return try await PDFBookExporter(renderer: self.renderer).export(
        PhotoBookExportRequest(
          title: title,
          author: author,
          pages: photos,
          destinationURL: destinationURL,
          pageSize: pageSize
        )
      )
    }
  }

  public func exportSlideshow(
    to destinationURL: URL,
    title: String = "PhotoSuite Slideshow",
    secondsPerSlide: Double = 4,
    framesPerSecond: Int = 30,
    canvas: PhotoSlideshowCanvas = PhotoSlideshowCanvas()
  ) async {
    await exportProfessionalOutput(operation: "slideshow", assets: professionalOutputAssets) {
      let photos = try await self.professionalOutputPhotos()
      return try await AVFoundationSlideshowExporter(renderer: self.renderer).export(
        PhotoSlideshowExportRequest(
          title: title,
          slides: photos,
          destinationURL: destinationURL,
          secondsPerSlide: secondsPerSlide,
          framesPerSecond: framesPerSecond,
          canvas: canvas
        )
      )
    }
  }

  public func exportWebGallery(
    to destinationURL: URL,
    title: String = "PhotoSuite Gallery",
    subtitle: String? = nil,
    maximumPixelDimension: Int? = 2_400
  ) async {
    await exportProfessionalOutput(operation: "web gallery", assets: professionalOutputAssets) {
      let photos = try await self.professionalOutputPhotos()
      return try await StaticHTMLGalleryExporter(renderer: self.renderer).export(
        PhotoGalleryExportRequest(
          title: title,
          subtitle: subtitle,
          items: photos,
          destinationURL: destinationURL,
          maximumPixelDimension: maximumPixelDimension
        )
      )
    }
  }

  /// Imports files by reference for compatibility with existing callers. New import flows should
  /// use the mode overload, which defaults to fingerprint duplicate skipping.
  public func importURLs(_ urls: [URL]) async {
    await importURLs(urls, mode: .add, duplicatePolicy: .allow)
  }

  /// Imports files using explicit Add, Copy, or Move semantics. Transfer and checksum verification
  /// happen before a catalog row is created, so a failed copy or move cannot leave a dangling
  /// source record. Move removes the original only after the destination fingerprint matches.
  public func importURLs(
    _ urls: [URL],
    mode: PhotoImportMode,
    duplicatePolicy: PhotoImportDuplicatePolicy = .skip
  ) async {
    isLoading = true
    errorMessage = nil
    lastError = nil
    itemErrors = []
    defer { isLoading = false }

    let existingAssets: [PhotoAsset]
    do {
      existingAssets = try await catalog.listAssets(
        CatalogAssetListRequest(order: .importDateDescending)
      ).assets
    } catch {
      existingAssets = assets
      record(error, operation: "import.list")
    }

    let service = PhotoImportService(
      sourceAccess: PhotoImportSourceAccess(workspaceAccess: sourceAccess),
      fingerprint: fingerprint
    )
    let transferResult: PhotoImportResult
    do {
      transferResult = try await service.import(
        PhotoImportRequest(
          urls: urls,
          mode: mode,
          duplicatePolicy: duplicatePolicy,
          existingAssets: existingAssets
        )
      )
    } catch is CancellationError {
      return
    } catch {
      record(error, operation: "import.transfer")
      return
    }

    for duplicate in transferResult.duplicates {
      let detail: String
      if let existingSourceURL = duplicate.existingSourceURL {
        detail = "Skipped duplicate of \(existingSourceURL.lastPathComponent)."
      } else {
        detail = "Skipped duplicate source content."
      }
      itemErrors.append(WorkspaceItemError(sourceURL: duplicate.sourceURL, message: detail))
    }
    for failure in transferResult.failures {
      itemErrors.append(WorkspaceItemError(sourceURL: failure.sourceURL, message: failure.message))
    }

    var imported: [(PhotoAsset, EditRecipe)] = []
    for item in transferResult.imported {
      let started = await sourceAccess.start(item.catalogURL)
      do {
        let sourceProbe = try await probe(item.catalogURL)
        guard
          let asset = PhotoAsset(
            sourceURL: item.catalogURL,
            filename: item.catalogURL.lastPathComponent,
            typeIdentifier: sourceProbe.typeIdentifier,
            fingerprint: item.fingerprint,
            importDate: now(),
            captureDate: nil,
            pixelDimensions: sourceProbe.dimensions
          )
        else {
          throw PhotoWorkspaceError.invalidAsset(item.catalogURL)
        }
        _ = try await catalog.upsertAsset(CatalogAssetUpsertRequest(asset: asset))
        let recipe = EditRecipe(assetID: asset.id, date: now(), pins: sourceProbe.pins)
        do {
          _ = try await catalog.saveRecipe(CatalogRecipeSaveRequest(recipe: recipe))
        } catch {
          let missingAsset = await markImportedAssetMissing(asset)
          imported.append((missingAsset, recipe))
          recordItemError(url: item.catalogURL, error: error, operation: "import.recipe")
          if started { await sourceAccess.stop(item.catalogURL) }
          continue
        }

        var visibleAsset = asset
        do {
          try await sourceAccess.persist(asset.id, item.catalogURL)
        } catch {
          visibleAsset = await markImportedAssetMissing(asset)
          recordItemError(url: item.catalogURL, error: error, operation: "import.bookmark")
        }
        imported.append((visibleAsset, recipe))

        do {
          let result = try await renderer.render(
            renderRequest(url: item.catalogURL, recipe: recipe)
          )
          previewCache[asset.id] = PreviewFrame(result)
        } catch is CancellationError {
          // Cancellation is a normal result for rebuildable previews.
        } catch {
          itemErrors.append(
            WorkspaceItemError(
              sourceURL: item.catalogURL,
              message: "Preview: \(message(for: error))"
            )
          )
        }
      } catch {
        recordItemError(url: item.catalogURL, error: error, operation: "import")
      }
      if started { await sourceAccess.stop(item.catalogURL) }
    }

    assets.append(contentsOf: imported.map(\.0))
    if let first = imported.first {
      selectedAssetID = first.0.id
      currentRecipe = first.1
      await loadSelectedAssetFaces(first.0.id)
      preview = previewCache[first.0.id]
      resetHistory()
      syncDraftValues()
    }
  }

  /// Relinks one missing catalog asset to an unchanged local source file.
  ///
  /// The replacement URL is accessed inside the caller-provided security scope while
  /// its fingerprint is calculated. The catalog owns durable bookmark creation and
  /// the original source file is never modified.
  @discardableResult
  public func relinkAsset(
    assetID: UUID,
    to replacementURL: URL
  ) async throws -> CatalogRelinkAssetResult {
    guard let asset = assets.first(where: { $0.id == assetID }) else {
      throw MissingSourceRelinkError.assetNotFound(assetID)
    }
    let plan = MissingSourceRelinkPlan(asset: asset)
    guard plan.isMissing else {
      throw MissingSourceRelinkError.assetNotMissing(assetID)
    }
    isRelinking = true
    defer { isRelinking = false }

    let started = await sourceAccess.start(replacementURL)
    guard started else {
      throw MissingSourceRelinkError.sourceScopeUnavailable(replacementURL)
    }
    do {
      let replacementFingerprint = try await fingerprint(replacementURL)
      try plan.validate(
        replacementURL: replacementURL,
        actualFingerprint: replacementFingerprint
      )
      let result = try await catalog.relinkAsset(
        CatalogRelinkAssetRequest(
          assetID: asset.id,
          sourceURL: replacementURL,
          filename: replacementURL.lastPathComponent,
          typeIdentifier: asset.typeIdentifier,
          fingerprint: replacementFingerprint
        )
      )
      await sourceAccess.stop(replacementURL)

      if let index = assets.firstIndex(where: { $0.id == result.asset.id }) {
        assets[index] = result.asset
      }
      previewCache.removeValue(forKey: result.asset.id)
      if selectedAssetID == result.asset.id {
        preview = nil
        if currentRecipe != nil {
          await refreshPreview()
        }
      }
      errorMessage = nil
      lastError = nil
      return result
    } catch {
      await sourceAccess.stop(replacementURL)
      throw error
    }
  }

  /// Scans a selected folder and atomically relinks each missing asset whose source
  /// fingerprint is found. The catalog commits each successful asset independently;
  /// unmatched and failed assets remain missing and are returned in the typed result.
  @discardableResult
  public func relinkMissingSources(in folderURL: URL) async throws -> BatchRelinkResult {
    let missingAssets = assets.filter(\.isMissing)
    let catalog = self.catalog
    isRelinking = true
    defer { isRelinking = false }

    let service = BatchMissingSourceRelinkService(
      sourceAccess: sourceAccess,
      fingerprint: fingerprint,
      relink: { asset, replacementURL, replacementFingerprint in
        let result = try await catalog.relinkAsset(
          CatalogRelinkAssetRequest(
            assetID: asset.id,
            sourceURL: replacementURL,
            filename: replacementURL.lastPathComponent,
            typeIdentifier: asset.typeIdentifier,
            fingerprint: replacementFingerprint
          )
        )
        return result.asset
      }
    )

    do {
      let result = try await service.relink(assets: missingAssets, in: folderURL)
      for match in result.matched {
        if let index = assets.firstIndex(where: { $0.id == match.assetID }) {
          assets[index] = match.relinkedAsset
        }
        previewCache.removeValue(forKey: match.assetID)
      }
      if let selectedAssetID, result.matched.contains(where: { $0.assetID == selectedAssetID }) {
        preview = nil
        if currentRecipe != nil {
          await refreshPreview()
        }
      }
      lastError = nil
      errorMessage = nil
      return result
    } catch {
      errorMessage = message(for: error)
      throw error
    }
  }

  public func selectAsset(_ assetID: UUID) async {
    guard let asset = assets.first(where: { $0.id == assetID }) else {
      record(PhotoWorkspaceError.invalidSelection(assetID), operation: "select")
      return
    }
    do {
      guard
        let recipe = try await catalog.latestRecipe(
          CatalogLatestRecipeRequest(assetID: assetID, virtualCopyID: nil)
        ).recipe
      else {
        throw PhotoWorkspaceError.recipeMissing(assetID)
      }
      selectedAssetID = asset.id
      selectedVirtualCopyID = nil
      currentRecipe = recipe
      await loadSelectedAssetKeywords(assetID)
      await loadSelectedAssetFaces(assetID)
      preview = previewCache[asset.id]
      resetHistory()
      syncDraftValues()
      await refreshPreview()
    } catch {
      record(error, operation: "select")
    }
  }

  /// Returns the selected folder path, including all durable ancestors.
  public func folderPath(for folder: LibraryFolder) -> String {
    var names = [folder.name]
    var parentID = folder.parentID
    var visited: Set<UUID> = [folder.id]
    while let id = parentID, visited.insert(id).inserted,
      let parent = folders.first(where: { $0.id == id })
    {
      names.append(parent.name)
      parentID = parent.parentID
    }
    return names.reversed().joined(separator: " › ")
  }

  public func folderIDs(including folderID: UUID) -> [UUID] {
    var result = [folderID]
    var pending = [folderID]
    while let parentID = pending.popLast() {
      let children = folders.filter { $0.parentID == parentID }.map(\.id)
      result.append(contentsOf: children)
      pending.append(contentsOf: children)
    }
    return result
  }

  public func selectFolder(_ folderID: UUID?) {
    guard let folderID else {
      activeFolderID = nil
      return
    }
    guard folders.contains(where: { $0.id == folderID }) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.folder.select",
          message: "The folder is not available in this catalog."
        ),
        operation: "library.folder.select"
      )
      return
    }
    activeFolderID = folderID
    activeCollectionID = nil
  }

  public func createDurableFolder(named name: String, parentID: UUID? = nil) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.folder.create")
      return
    }
    guard let folder = LibraryFolder(name: name, parentID: parentID) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.folder.create",
          message: "The folder name or parent relationship is not valid."
        ),
        operation: "library.folder.create"
      )
      return
    }
    do {
      let saved = try await libraryCatalog.saveFolder(
        CatalogFolderSaveRequest(folder: folder)
      ).folder
      folders.append(saved)
      folders.sort {
        folderPath(for: $0).localizedCaseInsensitiveCompare(folderPath(for: $1))
          == .orderedAscending
      }
      folderAssetIDs[saved.id] = []
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.folder.create")
    }
  }

  public func deleteDurableFolder(_ folderID: UUID) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.folder.delete")
      return
    }
    do {
      _ = try await libraryCatalog.deleteFolder(CatalogFolderDeleteRequest(folderID: folderID))
      folders.removeAll { $0.id == folderID }
      folderAssetIDs.removeValue(forKey: folderID)
      if activeFolderID == folderID { activeFolderID = nil }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.folder.delete")
    }
  }

  public func assignAsset(_ assetID: UUID, toFolder folderID: UUID?) async {
    guard assets.contains(where: { $0.id == assetID }) else {
      record(PhotoWorkspaceError.invalidSelection(assetID), operation: "library.folder.assign")
      return
    }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.folder.assign")
      return
    }
    do {
      _ = try await libraryCatalog.setAssetFolder(
        CatalogAssetFolderSetRequest(assetID: assetID, folderID: folderID)
      )
      for key in folderAssetIDs.keys {
        folderAssetIDs[key]?.remove(assetID)
      }
      if let folderID {
        folderAssetIDs[folderID, default: []].insert(assetID)
      }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.folder.assign")
    }
  }

  /// Saves the selected recipe's Develop operations as a durable preset.
  public func saveDevelopPreset(named name: String) async {
    guard let recipe = currentRecipe else {
      record(
        PhotoWorkspaceError.noSelection(operation: "develop.preset.save"),
        operation: "develop.preset.save"
      )
      return
    }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "develop.preset.save")
      return
    }
    let operations = recipe.operations.filter { operation in
      if Self.developFamily(operation) != nil { return true }
      if case .unknown = operation { return true }
      return false
    }
    guard
      let preset = DevelopPreset(
        name: name,
        operations: operations,
        virtualCopyID: selectedVirtualCopyID,
        createdAt: now(),
        updatedAt: now()
      )
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "develop.preset.save",
          message: "The preset name or operation stream is invalid."
        ),
        operation: "develop.preset.save"
      )
      return
    }
    do {
      let saved = try await libraryCatalog.saveDevelopPreset(
        CatalogDevelopPresetSaveRequest(preset: preset)
      ).preset
      developPresets.removeAll { $0.id == saved.id }
      developPresets.append(saved)
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "develop.preset.save")
    }
  }

  /// Imports the supported, standards-based fields from an Adobe XMP sidecar as a durable preset.
  /// Unsupported fields are reported as a warning instead of being silently applied.
  public func importDevelopPreset(from url: URL) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "develop.preset.import")
      return
    }
    do {
      let result = try XMPDevelopPresetImporter.importResult(from: url)
      let saved = try await libraryCatalog.saveDevelopPreset(
        CatalogDevelopPresetSaveRequest(preset: result.preset)
      ).preset
      developPresets.removeAll { $0.id == saved.id }
      developPresets.append(saved)
      lastError = nil
      if result.skippedFields.isEmpty {
        errorMessage = nil
      } else {
        errorMessage =
          "Imported \(saved.name). Unsupported XMP fields were skipped: \(result.skippedFields.joined(separator: ", "))."
      }
    } catch {
      record(error, operation: "develop.preset.import")
    }
  }

  /// Applies a durable Develop preset to the selected asset or virtual copy.
  public func applyDevelopPreset(_ presetID: UUID) async {
    guard let assetID = selectedAssetID else {
      record(
        PhotoWorkspaceError.noSelection(operation: "develop.preset.apply"),
        operation: "develop.preset.apply"
      )
      return
    }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "develop.preset.apply")
      return
    }
    do {
      let result = try await libraryCatalog.applyDevelopPreset(
        CatalogApplyDevelopPresetRequest(
          assetID: assetID,
          presetID: presetID,
          virtualCopyID: selectedVirtualCopyID
        )
      ).recipe
      currentRecipe = result
      selectedVirtualCopyID = result.virtualCopyID
      resetHistory()
      syncDraftValues()
      await refreshPreview()
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "develop.preset.apply")
    }
  }

  public func deleteDevelopPreset(_ presetID: UUID) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "develop.preset.delete")
      return
    }
    do {
      _ = try await libraryCatalog.deleteDevelopPreset(
        CatalogDevelopPresetDeleteRequest(presetID: presetID)
      )
      developPresets.removeAll { $0.id == presetID }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "develop.preset.delete")
    }
  }

  /// Returns the selected asset's hierarchical keyword assignment in catalog order.
  public func keywordPath(for keyword: KeywordNode) -> String {
    var names = [keyword.name]
    var parentID = keyword.parentID
    var visited: Set<UUID> = [keyword.id]
    while let id = parentID, visited.insert(id).inserted,
      let parent = keywordNodes.first(where: { $0.id == id })
    {
      names.append(parent.name)
      parentID = parent.parentID
    }
    return names.reversed().joined(separator: " › ")
  }

  public func assignKeywords(to assetID: UUID, keywordIDs: [UUID]) async {
    guard selectedAssetID == assetID else {
      record(PhotoWorkspaceError.invalidSelection(assetID), operation: "library.keywords.set")
      return
    }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.keywords.set")
      return
    }
    let knownIDs = Set(keywordNodes.map(\.id))
    let normalizedIDs = keywordIDs.filter { knownIDs.contains($0) }
    do {
      _ = try await libraryCatalog.setAssetKeywords(
        CatalogAssetKeywordSetRequest(assetID: assetID, keywordIDs: normalizedIDs)
      )
      selectedAssetKeywords = keywordNodes.filter { normalizedIDs.contains($0.id) }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.keywords.set")
    }
  }

  public func selectVirtualCopy(_ virtualCopyID: UUID) async {
    guard let copy = virtualCopies.first(where: { $0.id == virtualCopyID }) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.virtual-copy.select",
          message: "The virtual copy is not available in this catalog."
        ),
        operation: "library.virtual-copy.select"
      )
      return
    }
    guard assets.contains(where: { $0.id == copy.sourceAssetID }) else {
      record(
        PhotoWorkspaceError.invalidSelection(copy.sourceAssetID),
        operation: "library.virtual-copy.select")
      return
    }
    do {
      guard
        let recipe = try await catalog.latestRecipe(
          CatalogLatestRecipeRequest(assetID: copy.sourceAssetID, virtualCopyID: copy.id)
        ).recipe
      else {
        throw PhotoWorkspaceError.recipeMissing(copy.sourceAssetID)
      }
      selectedAssetID = copy.sourceAssetID
      selectedVirtualCopyID = copy.id
      currentRecipe = recipe
      await loadSelectedAssetKeywords(copy.sourceAssetID)
      await loadSelectedAssetFaces(copy.sourceAssetID)
      preview = previewCache[copy.sourceAssetID]
      resetHistory()
      syncDraftValues()
      await refreshPreview()
    } catch {
      record(error, operation: "library.virtual-copy.select")
    }
  }

  public func createVirtualCopy(named name: String) async {
    guard let asset = selectedAsset, let baseRecipe = currentRecipe else {
      record(
        PhotoWorkspaceError.noSelection(operation: "library.virtual-copy.create"),
        operation: "library.virtual-copy.create")
      return
    }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.virtual-copy.create")
      return
    }
    guard let copy = VirtualCopy(sourceAssetID: asset.id, name: name) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.virtual-copy.create",
          message: "The virtual copy name is not valid."
        ),
        operation: "library.virtual-copy.create"
      )
      return
    }
    do {
      let savedCopy = try await libraryCatalog.saveVirtualCopy(
        CatalogVirtualCopySaveRequest(virtualCopy: copy)
      ).virtualCopy
      let copyRecipe = EditRecipe(
        assetID: asset.id,
        virtualCopyID: savedCopy.id,
        revision: 0,
        date: now(),
        pins: baseRecipe.pins,
        operations: baseRecipe.operations,
        masks: baseRecipe.masks
      )
      _ = try await catalog.saveRecipe(CatalogRecipeSaveRequest(recipe: copyRecipe))
      virtualCopies.append(savedCopy)
      virtualCopies.sort { $0.updatedAt > $1.updatedAt }
      selectedVirtualCopyID = savedCopy.id
      currentRecipe = copyRecipe
      resetHistory()
      syncDraftValues()
      await refreshPreview()
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.virtual-copy.create")
    }
  }

  public func deleteVirtualCopy(_ virtualCopyID: UUID) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.virtual-copy.delete")
      return
    }
    do {
      _ = try await libraryCatalog.deleteVirtualCopy(
        CatalogVirtualCopyDeleteRequest(virtualCopyID: virtualCopyID)
      )
      virtualCopies.removeAll { $0.id == virtualCopyID }
      if selectedVirtualCopyID == virtualCopyID, let assetID = selectedAssetID {
        selectedVirtualCopyID = nil
        await selectAsset(assetID)
      }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.virtual-copy.delete")
    }
  }

  private func loadSelectedAssetKeywords(_ assetID: UUID) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      selectedAssetKeywords = []
      return
    }
    do {
      selectedAssetKeywords = try await libraryCatalog.listAssetKeywords(
        CatalogAssetKeywordListRequest(assetID: assetID)
      ).keywords
    } catch {
      selectedAssetKeywords = []
      record(error, operation: "library.keywords.list")
    }
  }

  /// Loads durable face geometry and user labels for the selected photograph.
  ///
  /// This method exposes only the domain projection needed by Library and
  /// Develop. The catalog implementation and any storage details remain
  /// private to the workspace. A missing PeopleCatalogStore is a supported
  /// capability boundary, not a failed catalog reopen.
  public func loadSelectedAssetFaces() async {
    guard let assetID = selectedAssetID else {
      selectedAssetFaces = []
      selectedFaceID = nil
      return
    }
    await loadSelectedAssetFaces(assetID)
  }

  private func loadSelectedAssetFaces(_ assetID: UUID) async {
    guard let peopleCatalog = catalog as? any PeopleCatalogStore else {
      selectedAssetFaces = []
      selectedFaceID = nil
      return
    }
    do {
      let faces = try await peopleCatalog.listFaces(CatalogFaceListRequest(assetID: assetID)).faces
      selectedAssetFaces = faces
      if let selectedFaceID, faces.contains(where: { $0.id == selectedFaceID }) {
        self.selectedFaceID = selectedFaceID
      } else {
        selectedFaceID = faces.first?.id
      }
    } catch {
      selectedAssetFaces = []
      selectedFaceID = nil
      record(error, operation: "library.faces.list")
    }
  }

  /// Selects one of the currently projected face annotations for label editing.
  /// A nil selection returns the inspector to its first-annotation state.
  public func selectFace(_ faceID: UUID?) {
    guard let faceID else {
      selectedFaceID = selectedAssetFaces.first?.id
      return
    }
    guard selectedAssetFaces.contains(where: { $0.id == faceID }) else {
      record(PhotoWorkspaceError.invalidSelection(faceID), operation: "library.faces.select")
      return
    }
    selectedFaceID = faceID
  }

  /// Persists an optional user label without changing detector geometry or
  /// provenance. Blank labels are treated as an explicit clear operation.
  public func saveFaceLabel(_ label: String?, for faceID: UUID) async {
    guard let selectedAssetID else {
      record(
        PhotoWorkspaceError.noSelection(operation: "face labelling"),
        operation: "library.faces.save"
      )
      return
    }
    guard let peopleCatalog = catalog as? any PeopleCatalogStore else {
      record(PhotoWorkspaceError.peopleStoreUnavailable, operation: "library.faces.save")
      return
    }
    guard let face = selectedAssetFaces.first(where: { $0.id == faceID }),
      face.assetID == selectedAssetID
    else {
      record(PhotoWorkspaceError.invalidSelection(faceID), operation: "library.faces.save")
      return
    }
    let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
    let savedLabel = normalizedLabel.flatMap { $0.isEmpty ? nil : $0 }
    guard
      let updated = PhotoFace(
        id: face.id,
        assetID: face.assetID,
        region: face.region,
        label: savedLabel,
        confidence: face.confidence,
        source: face.source,
        createdAt: face.createdAt,
        updatedAt: now()
      )
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.faces.save",
          message: "The face label is invalid."
        ),
        operation: "library.faces.save"
      )
      return
    }
    do {
      let persisted = try await peopleCatalog.saveFace(CatalogFaceSaveRequest(face: updated)).face
      if let index = selectedAssetFaces.firstIndex(where: { $0.id == faceID }) {
        selectedAssetFaces[index] = persisted
      }
      selectedFaceID = persisted.id
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.faces.save")
    }
  }

  /// Removes one annotation from the catalog. This does not modify the source
  /// photograph and does not claim that a person was identified or removed.
  public func deleteFaceAnnotation(_ faceID: UUID) async {
    guard let peopleCatalog = catalog as? any PeopleCatalogStore else {
      record(PhotoWorkspaceError.peopleStoreUnavailable, operation: "library.faces.delete")
      return
    }
    guard selectedAssetFaces.contains(where: { $0.id == faceID }) else {
      record(PhotoWorkspaceError.invalidSelection(faceID), operation: "library.faces.delete")
      return
    }
    do {
      _ = try await peopleCatalog.deleteFace(CatalogFaceDeleteRequest(faceID: faceID))
      selectedAssetFaces.removeAll { $0.id == faceID }
      if selectedFaceID == faceID { selectedFaceID = selectedAssetFaces.first?.id }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.faces.delete")
    }
  }

  public func setRating(_ rating: Int) async {
    guard (0...5).contains(rating) else {
      record(PhotoWorkspaceError.invalidRating(rating), operation: "rating")
      return
    }
    await enqueueLibraryMutation { [weak self] in
      await self?.updateSelectedAssetMetadata(rating: rating, colorLabel: nil)
    }
  }

  public func setColorLabel(_ colorLabel: ColorLabel?) async {
    await enqueueLibraryMutation { [weak self] in
      await self?.updateSelectedAssetMetadata(rating: nil, colorLabel: .some(colorLabel))
    }
  }

  public func createDurableCollection(named name: String, assetIDs: [UUID] = []) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.collection.create")
      return
    }
    guard
      let collection = PhotoCollection(
        name: name,
        kind: .regular,
        assetIDs: assetIDs
      )
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.collection.create",
          message: "The collection name or membership is not valid."
        ),
        operation: "library.collection.create"
      )
      return
    }
    do {
      let saved = try await libraryCatalog.saveCollection(
        CatalogCollectionSaveRequest(collection: collection)
      ).collection
      durableCollections.append(saved)
      durableCollections.sort { $0.updatedAt > $1.updatedAt }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.collection.create")
    }
  }

  public func createDurableStack(assetIDs: [UUID]) async {
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.stack.create")
      return
    }
    guard let representativeAssetID = assetIDs.first,
      let stack = PhotoStack(
        assetIDs: assetIDs,
        representativeAssetID: representativeAssetID
      )
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.stack.create",
          message: "Select at least one photograph for a stack."
        ),
        operation: "library.stack.create"
      )
      return
    }
    do {
      let saved = try await libraryCatalog.saveStack(
        CatalogStackSaveRequest(stack: stack)
      ).stack
      durableStacks.append(saved)
      durableStacks.sort { $0.updatedAt > $1.updatedAt }
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.stack.create")
    }
  }

  public func toggleDurableStack(_ id: UUID) async {
    guard let index = durableStacks.firstIndex(where: { $0.id == id }) else { return }
    guard let libraryCatalog = catalog as? any LibraryCatalogStore else {
      record(PhotoWorkspaceError.libraryStoreUnavailable, operation: "library.stack.toggle")
      return
    }
    let current = durableStacks[index]
    guard
      let updated = PhotoStack(
        id: current.id,
        assetIDs: current.assetIDs,
        representativeAssetID: current.representativeAssetID,
        isCollapsed: !current.isCollapsed,
        createdAt: current.createdAt,
        updatedAt: now()
      )
    else { return }
    do {
      durableStacks[index] = try await libraryCatalog.saveStack(
        CatalogStackSaveRequest(stack: updated)
      ).stack
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.stack.toggle")
    }
  }

  /// Persist the editable IPTC/EXIF/XMP-like record without changing source bytes or identity.
  /// Catalogs created before metadata support continue to work, but report a typed capability
  /// error instead of silently discarding the edit.
  public func updateSelectedMetadata(_ metadata: PhotoMetadata) async {
    await enqueueLibraryMutation { [weak self] in
      await self?.performUpdateSelectedMetadata(metadata)
    }
  }

  /// Imports the supported PhotoMetadata fields from an XMP sidecar into the catalog.
  /// The sidecar is read inside its security-scoped access interval. The source photograph is
  /// never opened or mutated, and its fingerprint remains unchanged.
  public func importSelectedMetadataSidecar(from sidecarURL: URL) async {
    await enqueueLibraryMutation { [weak self] in
      await self?.performImportSelectedMetadataSidecar(from: sidecarURL)
    }
  }

  /// Writes the selected photograph's durable metadata to its adjacent XMP sidecar. The source
  /// remains immutable and the result is published atomically by the sidecar writer.
  public func exportSelectedMetadataSidecar() async {
    await enqueueLibraryMutation { [weak self] in
      await self?.performExportSelectedMetadataSidecar()
    }
  }

  @discardableResult
  public func createCollection(named name: String) -> LibraryCollection {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let collection = LibraryCollection(
      name: trimmedName.isEmpty ? "Untitled Collection" : trimmedName
    )
    collections.append(collection)
    return collection
  }

  public func addAsset(_ assetID: UUID, toCollection collectionID: UUID) {
    guard assets.contains(where: { $0.id == assetID }),
      let index = collections.firstIndex(where: { $0.id == collectionID }),
      !collections[index].assetIDs.contains(assetID)
    else { return }
    collections[index].assetIDs.append(assetID)
  }

  @discardableResult
  public func createStack(named name: String, assetIDs: [UUID]) -> LibraryStack {
    let availableIDs = Set(assets.map(\.id))
    var seen: Set<UUID> = []
    let members = assetIDs.filter { availableIDs.contains($0) && seen.insert($0).inserted }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let stack = LibraryStack(
      name: trimmedName.isEmpty ? "Untitled Stack" : trimmedName,
      assetIDs: members
    )
    stacks.append(stack)
    return stack
  }

  public func toggleStack(_ stackID: UUID) {
    guard let index = stacks.firstIndex(where: { $0.id == stackID }) else { return }
    stacks[index].isExpanded.toggle()
  }

  public func stack(containing assetID: UUID) -> LibraryStack? {
    stacks.first { $0.assetIDs.contains(assetID) }
  }

  public func adjustmentValue(_ kind: AdjustmentKind) -> Double {
    draftValues[kind] ?? 0
  }

  public func updateDraft(_ kind: AdjustmentKind, value: Double) {
    draftValues[kind] = value
    scheduledPreviewTask?.cancel()
    scheduledPreviewTask = Task { [weak self] in
      await self?.refreshPreview()
    }
  }

  public func commitDraft(_ kind: AdjustmentKind) async {
    scheduledPreviewTask?.cancel()
    await commitAdjustment(kind, value: adjustmentValue(kind))
  }

  public func commitAdjustment(_ kind: AdjustmentKind, value: Double) async {
    await enqueueEditMutation { [weak self] in
      await self?.performCommitAdjustment(kind, value: value)
    }
  }

  public func commitColorGrade(_ grade: ThreeWayColorGrade) async {
    await enqueueEditMutation { [weak self] in
      await self?.performCommitColorGrade(grade)
    }
  }

  /// Persist a validated normalized crop for the selected photograph.
  ///
  /// Crop is a single canonical Develop operation. A new crop replaces the
  /// previous crop, retains all unrelated operations, creates one recipe
  /// revision, records the prior operations for undo, and refreshes the
  /// rebuildable preview from the same recipe graph.
  public func commitCrop(_ rect: NormalizedRect) async {
    await enqueueEditMutation { [weak self] in
      await self?.performCommitCrop(rect)
    }
  }

  public func commitDevelopOperation(_ operation: EditOperation) async {
    await enqueueEditMutation { [weak self] in
      await self?.performCommitDevelopOperation(operation)
    }
  }

  public func clearDevelopOperation(_ family: DevelopAdjustmentFamily) async {
    await enqueueEditMutation { [weak self] in
      await self?.performClearDevelopOperation(family)
    }
  }

  public func addMask(kind: MaskKind, name: String? = nil) async {
    await enqueueEditMutation { [weak self] in
      await self?.performAddMask(kind: kind, name: name)
    }
  }

  public func removeMask(id: UUID) async {
    await enqueueEditMutation { [weak self] in
      await self?.performMaskMutation { masks in
        let updated = masks.filter { $0.id != id }
        return updated == masks ? nil : updated
      }
    }
  }

  public func toggleMaskInverted(id: UUID) async {
    await enqueueEditMutation { [weak self] in
      await self?.performMaskMutation { masks in
        guard let index = masks.firstIndex(where: { $0.id == id }) else { return nil }
        let mask = masks[index]
        var updatedMasks = masks
        updatedMasks[index] = MaskDefinition(
          id: mask.id,
          schemaVersion: mask.schemaVersion,
          kind: mask.kind,
          name: mask.name,
          isInverted: !mask.isInverted,
          payload: mask.payload
        )
        return updatedMasks
      }
    }
  }

  public func replaceMaskGraph(id: UUID, graph: MaskGraphV1) async {
    await enqueueEditMutation { [weak self] in
      await self?.performMaskMutation { masks in
        guard let index = masks.firstIndex(where: { $0.id == id }) else { return nil }
        let mask = masks[index]
        guard
          let updated = try? MaskDefinition(
            id: mask.id,
            kind: mask.kind,
            name: mask.name,
            graph: graph
          )
        else { return nil }
        var updatedMasks = masks
        updatedMasks[index] = updated
        return updatedMasks
      }
    }
  }

  /// Apply a result produced by a local AI provider only when it was generated for the current
  /// photograph and recipe revision. The provider remains outside PhotoWorkflow so vendor or
  /// system model services can be swapped without changing catalog contracts.
  public func applyGeneratedMask(
    _ mask: MaskDefinition,
    assetID: UUID,
    expectedRevision: UInt64
  ) async {
    await enqueueEditMutation { [weak self] in
      await self?.performApplyGeneratedMask(
        mask,
        assetID: assetID,
        expectedRevision: expectedRevision
      )
    }
  }

  /// Returns the selected rendered frame only after the source bookmark has
  /// been resolved through the normal security-scoped access path. The AI
  /// provider receives this source-backed preview, never a URL that it can
  /// access outside the workspace boundary. Access is balanced even when a
  /// provider-facing input check fails.
  public func prepareSelectedPreviewForLocalAI() async throws -> PreviewFrame {
    guard let asset = selectedAsset else {
      throw PhotoWorkspaceError.noSelection(operation: "local AI")
    }
    guard let preview else {
      throw PhotoWorkspaceError.previewUnavailable
    }

    let sourceURL = try await sourceAccess.resolve(asset)
    let started = await sourceAccess.start(sourceURL)
    do {
      try Task.checkCancellation()
      if started { await sourceAccess.stop(sourceURL) }
      return preview
    } catch {
      if started { await sourceAccess.stop(sourceURL) }
      throw error
    }
  }

  public func rotateClockwise() async {
    await enqueueEditMutation { [weak self] in await self?.performRotateClockwise() }
  }

  public func resetCrop() async {
    await enqueueEditMutation { [weak self] in await self?.performResetCrop() }
  }

  public func undo() async {
    await enqueueEditMutation { [weak self] in await self?.performUndo() }
  }

  public func redo() async {
    await enqueueEditMutation { [weak self] in await self?.performRedo() }
  }

  public func resetEdits() async {
    await enqueueEditMutation { [weak self] in await self?.performResetEdits() }
  }

  private func performCommitAdjustment(_ kind: AdjustmentKind, value: Double) async {
    guard value.isFinite else {
      record(PhotoWorkspaceError.invalidAdjustment(kind.rawValue), operation: "edit")
      return
    }
    guard let recipe = editableRecipe(operation: "edit") else { return }
    var operations = recipe.operations.filter { !matches($0, kind: kind) }
    if value != 0 { operations.append(operation(kind, value: value)) }
    operations = canonicalized(operations)
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(operations)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performCommitColorGrade(_ grade: ThreeWayColorGrade) async {
    guard let recipe = editableRecipe(operation: "colour grade") else { return }
    var operations = recipe.operations.filter {
      if case .threeWayColorGrade = $0 { return false }
      return true
    }
    if !grade.isNeutral { operations.append(.threeWayColorGrade(grade)) }
    operations = canonicalized(operations)
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(operations)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performCommitDevelopOperation(_ operation: EditOperation) async {
    guard let family = Self.developFamily(operation) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "develop adjustment",
          message: "The selected operation is not a baseline Develop adjustment."
        ),
        operation: "develop adjustment"
      )
      return
    }
    guard let recipe = editableRecipe(operation: "develop adjustment") else { return }
    var operations = recipe.operations.filter { Self.developFamily($0) != family }
    if !Self.isNeutralDevelopOperation(operation) { operations.append(operation) }
    operations = canonicalized(operations)
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(operations)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performClearDevelopOperation(_ family: DevelopAdjustmentFamily) async {
    guard let recipe = editableRecipe(operation: "reset develop adjustment") else { return }
    let operations = recipe.operations.filter { Self.developFamily($0) != family }
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(canonicalized(operations))) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performAddMask(kind: MaskKind, name: String?) async {
    guard editableRecipe(operation: "add mask") != nil else { return }
    guard
      let mask = try? MaskDefinition(
        kind: kind,
        name: name,
        graph: MaskGraphV1()
      )
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "add mask",
          message: "The mask definition could not be encoded."
        ),
        operation: "mask"
      )
      return
    }
    await performMaskMutation { masks in masks + [mask] }
  }

  private func performMaskMutation(
    _ mutation: ([MaskDefinition]) -> [MaskDefinition]?
  ) async {
    guard let recipe = editableRecipe(operation: "mask") else { return }
    guard let masks = mutation(recipe.masks), masks != recipe.masks else { return }
    let updatedRecipe = EditRecipe(
      assetID: recipe.assetID,
      virtualCopyID: recipe.virtualCopyID,
      revision: recipe.revision + 1,
      date: now(),
      pins: recipe.pins,
      operations: recipe.operations,
      masks: masks
    )
    do {
      currentRecipe = try await catalog.saveRecipe(
        CatalogRecipeSaveRequest(recipe: updatedRecipe)
      ).recipe
      await refreshPreview()
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "mask.save")
    }
  }

  private func performApplyGeneratedMask(
    _ mask: MaskDefinition,
    assetID: UUID,
    expectedRevision: UInt64
  ) async {
    guard let recipe = editableRecipe(operation: "apply local AI mask") else { return }
    guard recipe.assetID == assetID, recipe.revision == expectedRevision else {
      record(PhotoWorkspaceError.staleAIResult, operation: "mask.ai")
      return
    }
    await performMaskMutation { masks in
      masks + [mask]
    }
  }

  private func performRotateClockwise() async {
    guard let recipe = editableRecipe(operation: "rotate") else { return }
    let current =
      recipe.operations.compactMap { operation -> Double? in
        if case .rotationDegrees(let value) = operation { return value }
        return nil
      }.last ?? 0
    var operations = recipe.operations.filter {
      if case .rotationDegrees = $0 { return false }
      return true
    }
    operations.append(.rotationDegrees((current + 90).truncatingRemainder(dividingBy: 360)))
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(canonicalized(operations))) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performCommitCrop(_ rect: NormalizedRect) async {
    guard Self.isValidCrop(rect) else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "crop",
          message: "The crop rectangle must be finite, positive, and inside unit bounds."
        ),
        operation: "crop"
      )
      return
    }
    guard let recipe = editableRecipe(operation: "crop") else { return }
    var operations = recipe.operations.filter {
      if case .normalizedCrop = $0 { return false }
      return true
    }
    operations.append(.normalizedCrop(rect))
    operations = canonicalized(operations)
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(operations)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performResetCrop() async {
    guard let recipe = editableRecipe(operation: "crop") else { return }
    let operations = recipe.operations.filter {
      if case .normalizedCrop = $0 { return false }
      return true
    }
    guard operations != recipe.operations else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations(canonicalized(operations))) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performUndo() async {
    guard let target = undoStack.popLast(), let current = currentRecipe else { return }
    let oldUndo = undoStack + [target]
    let oldRedo = redoStack
    redoStack.append(current.operations)
    if !(await saveOperations(target)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performRedo() async {
    guard let target = redoStack.popLast(), let current = currentRecipe else { return }
    let oldUndo = undoStack
    let oldRedo = redoStack + [target]
    undoStack.append(current.operations)
    if !(await saveOperations(target)) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  private func performResetEdits() async {
    guard let recipe = editableRecipe(operation: "reset"), !recipe.operations.isEmpty else {
      return
    }
    let oldUndo = undoStack
    let oldRedo = redoStack
    undoStack.append(recipe.operations)
    redoStack.removeAll()
    if !(await saveOperations([])) {
      undoStack = oldUndo
      redoStack = oldRedo
    }
  }

  public func toggleBeforeAfter() {
    guard selectedAsset != nil, currentRecipe != nil else {
      record(PhotoWorkspaceError.noSelection(operation: "before and after"), operation: "compare")
      return
    }
    showsBefore.toggle()
    scheduledPreviewTask?.cancel()
    scheduledPreviewTask = Task { [weak self] in await self?.refreshPreview() }
  }

  public func refreshPreview() async {
    guard let asset = selectedAsset, let durableRecipe = currentRecipe else { return }
    previewGeneration &+= 1
    let generation = previewGeneration
    previewTask?.cancel()

    let displayedRecipe = displayRecipe(from: durableRecipe)
    let sourceAccess = sourceAccess
    let renderer = renderer
    let catalog = catalog
    let probe = probe
    let now = now
    let debounce = previewDebounce
    let needsPinRecovery = Self.needsEmptyRAWPinRecovery(durableRecipe.pins)
    let task = Task<PreviewTaskOutput, any Error> {
      try await debounce()
      try Task.checkCancellation()
      let url = try await sourceAccess.resolve(asset)
      let started = await sourceAccess.start(url)
      do {
        let recoveredRecipe: EditRecipe?
        let recipeForRender: EditRecipe
        if needsPinRecovery {
          let sourceProbe = try await probe(url)
          guard !Self.needsEmptyRAWPinRecovery(sourceProbe.pins) else {
            throw PhotoWorkspaceError.operationFailed(
              operation: "preview.recover",
              message: "The source still reports an empty RAW decoder pin."
            )
          }
          let (revision, overflow) = durableRecipe.revision.addingReportingOverflow(1)
          guard !overflow else {
            throw PhotoWorkspaceError.operationFailed(
              operation: "preview.recover",
              message: "The recipe revision cannot be incremented."
            )
          }
          let repaired = EditRecipe(
            assetID: durableRecipe.assetID,
            virtualCopyID: durableRecipe.virtualCopyID,
            revision: revision,
            date: now(),
            pins: sourceProbe.pins,
            operations: durableRecipe.operations,
            masks: durableRecipe.masks
          )
          recoveredRecipe = try await catalog.saveRecipe(
            CatalogRecipeSaveRequest(recipe: repaired)
          ).recipe
          recipeForRender = EditRecipe(
            assetID: displayedRecipe.assetID,
            virtualCopyID: displayedRecipe.virtualCopyID,
            revision: revision,
            date: repaired.date,
            pins: sourceProbe.pins,
            operations: displayedRecipe.operations,
            masks: displayedRecipe.masks
          )
        } else {
          recoveredRecipe = nil
          recipeForRender = displayedRecipe
        }
        try Task.checkCancellation()
        let result = try await renderer.render(renderRequest(url: url, recipe: recipeForRender))
        if started { await sourceAccess.stop(url) }
        return PreviewTaskOutput(result: result, recoveredRecipe: recoveredRecipe)
      } catch {
        if started { await sourceAccess.stop(url) }
        throw error
      }
    }
    previewTask = task

    do {
      let output = try await task.value
      guard generation == previewGeneration, selectedAssetID == asset.id else { return }
      if let recoveredRecipe = output.recoveredRecipe {
        currentRecipe = recoveredRecipe
      }
      let frame = PreviewFrame(output.result)
      previewCache[asset.id] = frame
      preview = frame
      errorMessage = nil
      lastError = nil
    } catch is CancellationError {
      // Superseded preview work is expected.
    } catch {
      guard generation == previewGeneration, selectedAssetID == asset.id else { return }
      record(error, operation: "preview")
    }
  }

  public func exportJPEG(to destinationURL: URL, quality: Double) async {
    await exportJPEG(to: destinationURL, quality: quality, options: deliverOptions)
  }

  public func exportJPEG(
    to destinationURL: URL,
    quality: Double,
    options: DeliverOptions
  ) async {
    lastExport = nil
    lastError = nil
    guard options.unsupportedFeatures.isEmpty else {
      record(
        PhotoWorkspaceError.unsupportedDeliverOptions(options.unsupportedFeatures),
        operation: "export"
      )
      return
    }
    guard let asset = selectedAsset, let recipe = currentRecipe else {
      record(PhotoWorkspaceError.noSelection(operation: "export"), operation: "export")
      return
    }
    isExporting = true
    errorMessage = nil
    defer { isExporting = false }
    do {
      let url = try await sourceAccess.resolve(asset)
      let started = await sourceAccess.start(url)
      do {
        let result = try await exporter.export(
          ExportRequest(
            sourceURL: url,
            recipe: recipe,
            destinationURL: destinationURL,
            format: options.format.exportFormat,
            quality: quality,
            options: options.exportOptions
          )
        )
        if started { await sourceAccess.stop(url) }
        lastExport = result.derivative
      } catch {
        if started { await sourceAccess.stop(url) }
        throw error
      }
    } catch is CancellationError {
      // User cancellation does not create an error banner.
    } catch {
      record(error, operation: "export")
    }
  }

  /// Exports every photograph visible in the current Library filter.
  /// Each item is published atomically, and completed derivatives remain available if a later
  /// item fails or the task is cancelled.
  public func exportBatch(to destinationFolder: URL, quality: Double) async {
    await exportBatch(to: destinationFolder, quality: quality, options: deliverOptions)
  }

  public func exportBatch(
    to destinationFolder: URL,
    quality: Double,
    options: DeliverOptions
  ) async {
    lastBatchExports = []
    lastExport = nil
    lastError = nil
    errorMessage = nil
    guard options.unsupportedFeatures.isEmpty else {
      record(
        PhotoWorkspaceError.unsupportedDeliverOptions(options.unsupportedFeatures),
        operation: "batch export"
      )
      return
    }
    let exportAssets = filteredAssets
    guard !exportAssets.isEmpty else {
      record(PhotoWorkspaceError.noSelection(operation: "batch export"), operation: "batch export")
      return
    }

    isBatchExporting = true
    defer { isBatchExporting = false }

    do {
      try FileManager.default.createDirectory(
        at: destinationFolder,
        withIntermediateDirectories: true
      )
      var completed: [DurableDerivative] = []
      completed.reserveCapacity(exportAssets.count)

      for asset in exportAssets {
        try Task.checkCancellation()
        let url = try await sourceAccess.resolve(asset)
        let started = await sourceAccess.start(url)
        do {
          guard
            let recipe = try await catalog.latestRecipe(
              CatalogLatestRecipeRequest(assetID: asset.id)
            ).recipe
          else {
            throw PhotoWorkspaceError.recipeMissing(asset.id)
          }
          let destinationURL = batchDestination(
            for: asset,
            folder: destinationFolder,
            format: options.format
          )
          let result = try await exporter.export(
            ExportRequest(
              sourceURL: url,
              recipe: recipe,
              destinationURL: destinationURL,
              format: options.format.exportFormat,
              quality: quality,
              options: options.exportOptions
            )
          )
          if started { await sourceAccess.stop(url) }
          completed.append(result.derivative)
          lastBatchExports = completed
          lastExport = completed.last
        } catch {
          if started { await sourceAccess.stop(url) }
          throw error
        }
      }
    } catch is CancellationError {
      // User cancellation does not create an error banner.
    } catch {
      record(error, operation: "batch export")
    }
  }

  private func batchDestination(
    for asset: PhotoAsset,
    folder: URL,
    format: DeliverFormat
  ) -> URL {
    let rawName = URL(fileURLWithPath: asset.filename).deletingPathExtension().lastPathComponent
    let baseName = rawName.isEmpty ? asset.id.uuidString : rawName
    return folder.appendingPathComponent(baseName).appendingPathExtension(format.fileExtension)
  }

  private func saveOperations(_ operations: [EditOperation]) async -> Bool {
    guard let current = currentRecipe else { return false }
    let recipe = EditRecipe(
      assetID: current.assetID,
      virtualCopyID: current.virtualCopyID,
      revision: current.revision + 1,
      date: now(),
      pins: current.pins,
      operations: operations,
      masks: current.masks
    )
    do {
      let saved = try await catalog.saveRecipe(CatalogRecipeSaveRequest(recipe: recipe)).recipe
      currentRecipe = saved
      syncDraftValues()
      await refreshPreview()
      lastError = nil
      return true
    } catch {
      record(error, operation: "edit.save")
      return false
    }
  }

  private func displayRecipe(from durableRecipe: EditRecipe) -> EditRecipe {
    var operations = durableRecipe.operations
    if showsBefore {
      operations = []
    } else if durableRecipe.operations.contains(where: isUnknownOperation) {
      operations = durableRecipe.operations
    } else {
      for kind in AdjustmentKind.allCases {
        operations.removeAll { matches($0, kind: kind) }
        if let value = draftValues[kind] {
          operations.append(operation(kind, value: value))
        }
      }
      operations = canonicalized(operations)
    }
    return EditRecipe(
      assetID: durableRecipe.assetID,
      virtualCopyID: durableRecipe.virtualCopyID,
      revision: durableRecipe.revision,
      date: durableRecipe.date,
      pins: durableRecipe.pins,
      operations: operations,
      masks: showsBefore ? [] : durableRecipe.masks
    )
  }

  private func renderRequest(url: URL, recipe: EditRecipe) -> RenderRequest {
    RenderRequest(
      sourceURL: url,
      recipe: recipe,
      maximumPixelDimension: 2_560,
      outputColorSpaceName: "extended-linear-display-p3"
    )
  }

  private static func needsEmptyRAWPinRecovery(_ pins: EnginePins) -> Bool {
    pins.decoderIdentifier == "com.apple.ciraw" && pins.decoderVersion.isEmpty
  }

  private static func isValidCrop(_ rect: NormalizedRect) -> Bool {
    let values = [rect.x, rect.y, rect.width, rect.height]
    return values.allSatisfy(\.isFinite)
      && values.allSatisfy { (0...1).contains($0) }
      && rect.width > 0
      && rect.height > 0
      && rect.x + rect.width <= 1
      && rect.y + rect.height <= 1
  }

  private func resetHistory() {
    undoStack.removeAll()
    redoStack.removeAll()
  }

  private func enqueueEditMutation(
    _ mutation: @escaping @MainActor @Sendable () async -> Void
  ) async {
    let previous = editMutationTail
    editMutationGeneration &+= 1
    let generation = editMutationGeneration
    let task = Task { @MainActor in
      await previous?.value
      guard !Task.isCancelled else { return }
      await mutation()
    }
    editMutationTail = task
    await task.value
    if generation == editMutationGeneration { editMutationTail = nil }
  }

  private func enqueueLibraryMutation(
    _ mutation: @escaping @MainActor @Sendable () async -> Void
  ) async {
    let previous = libraryMutationTail
    libraryMutationGeneration &+= 1
    let generation = libraryMutationGeneration
    let task = Task { @MainActor in
      await previous?.value
      guard !Task.isCancelled else { return }
      await mutation()
    }
    libraryMutationTail = task
    await task.value
    if generation == libraryMutationGeneration { libraryMutationTail = nil }
  }

  private func updateSelectedAssetMetadata(
    rating: Int?,
    colorLabel: ColorLabel??
  ) async {
    guard let asset = selectedAsset else {
      record(
        PhotoWorkspaceError.noSelection(operation: "library metadata"),
        operation: "library.metadata"
      )
      return
    }
    guard
      let updated = PhotoAsset(
        id: asset.id,
        sourceURL: asset.sourceURL,
        filename: asset.filename,
        typeIdentifier: asset.typeIdentifier,
        fingerprint: asset.fingerprint,
        importDate: asset.importDate,
        captureDate: asset.captureDate,
        pixelDimensions: asset.pixelDimensions,
        rating: rating ?? asset.rating,
        colorLabel: colorLabel ?? asset.colorLabel,
        isMissing: asset.isMissing,
        metadata: asset.metadata
      )
    else {
      record(PhotoWorkspaceError.invalidRating(rating ?? asset.rating), operation: "rating")
      return
    }
    guard updated != asset else { return }
    do {
      let persisted = try await catalog.upsertAsset(
        CatalogAssetUpsertRequest(asset: updated)
      ).asset
      guard let index = assets.firstIndex(where: { $0.id == persisted.id }) else { return }
      assets[index] = persisted
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.metadata")
    }
  }

  private func performImportSelectedMetadataSidecar(from sidecarURL: URL) async {
    guard selectedAsset != nil else {
      let error = MetadataSidecarError.noSelection
      metadataSidecarStatus = .failed(error)
      errorMessage = error.localizedDescription
      return
    }
    guard catalog is any MetadataCatalogStore else {
      let error = MetadataSidecarError.metadataStoreUnavailable
      metadataSidecarStatus = .failed(error)
      errorMessage = error.localizedDescription
      return
    }

    metadataSidecarStatus = .importing(sidecarURL)
    do {
      let result = try await MetadataSidecarService(sourceAccess: sourceAccess).`import`(
        from: sidecarURL
      )
      lastError = nil
      errorMessage = nil
      await performUpdateSelectedMetadata(result.metadata)
      if let error = lastError {
        let sidecarError = MetadataSidecarError.catalogUpdateFailed(error.localizedDescription)
        metadataSidecarStatus = .failed(sidecarError)
        errorMessage = sidecarError.localizedDescription
      } else {
        metadataSidecarStatus = .imported(result)
      }
    } catch let error as MetadataSidecarError {
      metadataSidecarStatus = .failed(error)
      errorMessage = error.localizedDescription
    } catch {
      let sidecarError = MetadataSidecarError.catalogUpdateFailed(error.localizedDescription)
      metadataSidecarStatus = .failed(sidecarError)
      errorMessage = sidecarError.localizedDescription
    }
  }

  private func performExportSelectedMetadataSidecar() async {
    guard let asset = selectedAsset else {
      let error = MetadataSidecarError.noSelection
      metadataSidecarStatus = .failed(error)
      errorMessage = error.localizedDescription
      return
    }

    metadataSidecarStatus = .exporting
    do {
      let sourceURL = try await sourceAccess.resolve(asset)
      let result = try await MetadataSidecarService(sourceAccess: sourceAccess).export(
        metadata: asset.metadata,
        for: sourceURL
      )
      metadataSidecarStatus = .exported(result)
      lastError = nil
      errorMessage = nil
    } catch let error as MetadataSidecarError {
      metadataSidecarStatus = .failed(error)
      errorMessage = error.localizedDescription
    } catch {
      let sidecarError = MetadataSidecarError.sourceScopeUnavailable(asset.sourceURL)
      metadataSidecarStatus = .failed(sidecarError)
      errorMessage = sidecarError.localizedDescription
    }
  }

  private func performUpdateSelectedMetadata(_ metadata: PhotoMetadata) async {
    guard let asset = selectedAsset else {
      record(
        PhotoWorkspaceError.noSelection(operation: "metadata editing"),
        operation: "library.metadata.edit"
      )
      return
    }
    guard let metadataCatalog = catalog as? any MetadataCatalogStore else {
      record(PhotoWorkspaceError.metadataStoreUnavailable, operation: "library.metadata.edit")
      return
    }
    guard metadata != asset.metadata else { return }
    guard
      PhotoAsset(
        id: asset.id,
        sourceURL: asset.sourceURL,
        filename: asset.filename,
        typeIdentifier: asset.typeIdentifier,
        fingerprint: asset.fingerprint,
        importDate: asset.importDate,
        captureDate: asset.captureDate,
        pixelDimensions: asset.pixelDimensions,
        rating: asset.rating,
        colorLabel: asset.colorLabel,
        isMissing: asset.isMissing,
        metadata: metadata
      ) != nil
    else {
      record(
        PhotoWorkspaceError.operationFailed(
          operation: "library.metadata.edit",
          message: "The metadata record is invalid."
        ),
        operation: "library.metadata.edit"
      )
      return
    }
    do {
      let persisted = try await metadataCatalog.updateMetadata(
        CatalogAssetMetadataUpdateRequest(assetID: asset.id, metadata: metadata)
      ).asset
      guard let index = assets.firstIndex(where: { $0.id == persisted.id }) else { return }
      assets[index] = persisted
      lastError = nil
      errorMessage = nil
    } catch {
      record(error, operation: "library.metadata.edit")
    }
  }

  private func editableRecipe(operation: String) -> EditRecipe? {
    guard let recipe = currentRecipe else {
      record(PhotoWorkspaceError.noSelection(operation: operation), operation: operation)
      return nil
    }
    guard !recipe.operations.contains(where: isUnknownOperation) else {
      record(PhotoWorkspaceError.unknownOperationsBlockEditing, operation: operation)
      return nil
    }
    return recipe
  }

  private func isUnknownOperation(_ operation: EditOperation) -> Bool {
    if case .unknown = operation { return true }
    return false
  }

  private func markImportedAssetMissing(_ asset: PhotoAsset) async -> PhotoAsset {
    do {
      return try await catalog.markAssetMissing(
        CatalogMarkMissingRequest(assetID: asset.id, isMissing: true)
      ).asset
    } catch {
      return PhotoAsset(
        id: asset.id,
        sourceURL: asset.sourceURL,
        filename: asset.filename,
        typeIdentifier: asset.typeIdentifier,
        fingerprint: asset.fingerprint,
        importDate: asset.importDate,
        captureDate: asset.captureDate,
        pixelDimensions: asset.pixelDimensions,
        rating: asset.rating,
        colorLabel: asset.colorLabel,
        isMissing: true,
        metadata: asset.metadata
      ) ?? asset
    }
  }

  private func professionalOutputPhotos() async throws -> [ProfessionalOutputPhoto] {
    var photos: [ProfessionalOutputPhoto] = []
    for asset in professionalOutputAssets {
      guard
        let recipe = try await catalog.latestRecipe(
          CatalogLatestRecipeRequest(assetID: asset.id)
        ).recipe
      else {
        continue
      }
      photos.append(ProfessionalOutputPhoto(asset: asset, recipe: recipe, caption: asset.filename))
    }
    guard !photos.isEmpty else {
      throw PhotoWorkspaceError.noSelection(operation: "professional export")
    }
    return photos
  }

  private func exportProfessionalOutput(
    operation: String,
    assets: [PhotoAsset],
    exporter: () async throws -> URL
  ) async {
    guard !assets.isEmpty else {
      record(
        PhotoWorkspaceError.noSelection(operation: "\(operation) export"),
        operation: "workspace.\(operation)"
      )
      return
    }
    isProfessionalExporting = true
    lastProfessionalOutput = nil
    errorMessage = nil
    lastError = nil
    var scopedURLs: [URL] = []
    for asset in assets {
      if await sourceAccess.start(asset.sourceURL) {
        scopedURLs.append(asset.sourceURL)
      }
    }
    do {
      let destinationURL = try await exporter()
      await stopScopedSources(scopedURLs)
      lastProfessionalOutput = destinationURL
      isProfessionalExporting = false
    } catch {
      await stopScopedSources(scopedURLs)
      isProfessionalExporting = false
      record(error, operation: "workspace.\(operation)")
    }
  }

  private func stopScopedSources(_ urls: [URL]) async {
    for url in urls {
      await sourceAccess.stop(url)
    }
  }

  private func recordItemError(url: URL, error: any Error, operation: String) {
    let typed = typedError(error, operation: operation)
    lastError = typed
    errorMessage = typed.localizedDescription
    itemErrors.append(WorkspaceItemError(sourceURL: url, message: typed.localizedDescription))
  }

  private func record(_ error: any Error, operation: String) {
    let typed = typedError(error, operation: operation)
    lastError = typed
    errorMessage = typed.localizedDescription
  }

  private func typedError(_ error: any Error, operation: String) -> PhotoWorkspaceError {
    if let typed = error as? PhotoWorkspaceError { return typed }
    return .operationFailed(operation: operation, message: message(for: error))
  }

  private func syncDraftValues() {
    draftValues.removeAll()
    for operation in currentRecipe?.operations ?? [] {
      switch operation {
      case .exposureEV(let value): draftValues[.exposure] = value
      case .contrast(let value): draftValues[.contrast] = value
      case .highlights(let value): draftValues[.highlights] = value
      case .shadows(let value): draftValues[.shadows] = value
      case .saturation(let value): draftValues[.saturation] = value
      default: break
      }
    }
  }

  private func matches(_ operation: EditOperation, kind: AdjustmentKind) -> Bool {
    switch (operation, kind) {
    case (.exposureEV, .exposure), (.contrast, .contrast), (.highlights, .highlights),
      (.shadows, .shadows), (.saturation, .saturation):
      true
    default:
      false
    }
  }

  private func operation(_ kind: AdjustmentKind, value: Double) -> EditOperation {
    switch kind {
    case .exposure: .exposureEV(value)
    case .contrast: .contrast(value)
    case .highlights: .highlights(value)
    case .shadows: .shadows(value)
    case .saturation: .saturation(value)
    }
  }

  private func canonicalized(_ operations: [EditOperation]) -> [EditOperation] {
    func rank(_ operation: EditOperation) -> Int {
      switch operation {
      case .exposureEV: 0
      case .contrast: 1
      case .highlights: 2
      case .shadows: 3
      case .saturation: 4
      case .threeWayColorGrade: 5
      case .maskedAdjustment: 6
      case .clone: 7
      case .healing: 8
      case .redEye: 9
      case .normalizedCrop: 10
      case .rotationDegrees: 11
      case .toneCurve: 12
      case .whiteBalance: 13
      case .transform: 14
      case .detail: 15
      case .optics: 16
      case .effects: 17
      case .calibration: 18
      case .blackAndWhite: 19
      case .hdr: 20
      case .unknown: 21
      }
    }
    return operations.enumerated().sorted { left, right in
      let leftRank = rank(left.element)
      let rightRank = rank(right.element)
      return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
    }.map(\.element)
  }

  private static func developFamily(_ operation: EditOperation) -> DevelopAdjustmentFamily? {
    switch operation {
    case .toneCurve: .toneCurve
    case .whiteBalance: .whiteBalance
    case .transform: .transform
    case .detail: .detail
    case .optics: .optics
    case .effects: .effects
    case .calibration: .calibration
    case .blackAndWhite: .blackAndWhite
    case .hdr: .hdr
    case .clone: .clone
    case .healing: .healing
    case .redEye: .redEye
    default: nil
    }
  }

  private static func isNeutralDevelopOperation(_ operation: EditOperation) -> Bool {
    switch operation {
    case .toneCurve(let adjustment):
      adjustment.blackPoint == 0
        && adjustment.shadows == 0.25
        && adjustment.midtones == 0.5
        && adjustment.highlights == 0.75
        && adjustment.whitePoint == 1
    case .whiteBalance(let adjustment):
      adjustment.temperature == 0 && adjustment.tint == 0
    case .transform(let adjustment):
      adjustment.straightenDegrees == 0
        && !adjustment.flipHorizontal
        && !adjustment.flipVertical
    case .detail(let adjustment):
      adjustment.sharpening == 0 && adjustment.luminanceNoiseReduction == 0
    case .optics(let adjustment): adjustment.vignetteCorrection == 0
    case .effects(let adjustment): adjustment.vignetteAmount == 0
    case .calibration(let adjustment):
      adjustment.redGain == 0 && adjustment.greenGain == 0 && adjustment.blueGain == 0
    case .hdr(let adjustment): !adjustment.isEnabled
    case .blackAndWhite: false
    default: false
    }
  }

  private func message(for error: any Error) -> String {
    (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
  }
}
