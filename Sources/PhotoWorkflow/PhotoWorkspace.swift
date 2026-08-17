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
  public var isChoosingExportDestination = false
  public var proofMode = false
  public var showsBefore = false
  public var lastExport: DurableDerivative?
  public var collections: [LibraryCollection] = []
  public var stacks: [LibraryStack] = []
  public var smartFilter = LibrarySmartFilter()
  public var activeCollectionID: UUID?
  public var deliverOptions = DeliverOptions()

  public var selectedAsset: PhotoAsset? {
    guard let selectedAssetID else { return nil }
    return assets.first { $0.id == selectedAssetID }
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
    let collectionAssetIDs = activeCollectionID.flatMap { collectionID in
      collections.first { $0.id == collectionID }.map { Set($0.assetIDs) }
    }
    return assets.filter { asset in
      if !searchText.isEmpty,
        !asset.filename.localizedCaseInsensitiveContains(searchText)
      {
        return false
      }
      if let collectionAssetIDs, !collectionAssetIDs.contains(asset.id) { return false }
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
        resetHistory()
        syncDraftValues()
        await refreshPreview()
        return
      }
    } catch {
      record(error, operation: "reopen")
    }
  }

  public func importURLs(_ urls: [URL]) async {
    isLoading = true
    errorMessage = nil
    lastError = nil
    itemErrors = []
    var imported: [(PhotoAsset, EditRecipe)] = []

    for url in urls {
      let started = await sourceAccess.start(url)
      do {
        let sourceFingerprint = try await fingerprint(url)
        let sourceProbe = try await probe(url)
        guard
          let asset = PhotoAsset(
            sourceURL: url,
            filename: url.lastPathComponent,
            typeIdentifier: sourceProbe.typeIdentifier,
            fingerprint: sourceFingerprint,
            importDate: now(),
            captureDate: nil,
            pixelDimensions: sourceProbe.dimensions
          )
        else {
          throw PhotoWorkspaceError.invalidAsset(url)
        }
        _ = try await catalog.upsertAsset(CatalogAssetUpsertRequest(asset: asset))
        let recipe = EditRecipe(assetID: asset.id, date: now(), pins: sourceProbe.pins)
        do {
          _ = try await catalog.saveRecipe(CatalogRecipeSaveRequest(recipe: recipe))
        } catch {
          let missingAsset = await markImportedAssetMissing(asset)
          imported.append((missingAsset, recipe))
          recordItemError(url: url, error: error, operation: "import.recipe")
          if started { await sourceAccess.stop(url) }
          continue
        }

        var visibleAsset = asset
        do {
          try await sourceAccess.persist(asset.id, url)
        } catch {
          visibleAsset = await markImportedAssetMissing(asset)
          recordItemError(url: url, error: error, operation: "import.bookmark")
        }
        imported.append((visibleAsset, recipe))

        do {
          let result = try await renderer.render(renderRequest(url: url, recipe: recipe))
          previewCache[asset.id] = PreviewFrame(result)
        } catch is CancellationError {
          // Cancellation is a normal result for rebuildable previews.
        } catch {
          itemErrors.append(
            WorkspaceItemError(sourceURL: url, message: "Preview: \(message(for: error))")
          )
        }
      } catch {
        recordItemError(url: url, error: error, operation: "import")
      }
      if started { await sourceAccess.stop(url) }
    }

    assets.append(contentsOf: imported.map(\.0))
    if let first = imported.first {
      selectedAssetID = first.0.id
      currentRecipe = first.1
      preview = previewCache[first.0.id]
      resetHistory()
      syncDraftValues()
    }
    isLoading = false
  }

  public func selectAsset(_ assetID: UUID) async {
    guard let asset = assets.first(where: { $0.id == assetID }) else {
      record(PhotoWorkspaceError.invalidSelection(assetID), operation: "select")
      return
    }
    do {
      guard
        let recipe = try await catalog.latestRecipe(
          CatalogLatestRecipeRequest(assetID: assetID)
        ).recipe
      else {
        throw PhotoWorkspaceError.recipeMissing(assetID)
      }
      selectedAssetID = asset.id
      currentRecipe = recipe
      preview = previewCache[asset.id]
      resetHistory()
      syncDraftValues()
      await refreshPreview()
    } catch {
      record(error, operation: "select")
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
            format: .jpeg,
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

  private func saveOperations(_ operations: [EditOperation]) async -> Bool {
    guard let current = currentRecipe else { return false }
    let recipe = EditRecipe(
      assetID: current.assetID,
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
        isMissing: asset.isMissing
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
        isMissing: true
      ) ?? asset
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
      case .normalizedCrop: 6
      case .rotationDegrees: 7
      case .toneCurve: 8
      case .whiteBalance: 9
      case .transform: 10
      case .detail: 11
      case .optics: 12
      case .effects: 13
      case .calibration: 14
      case .blackAndWhite: 15
      case .hdr: 16
      case .unknown: 17
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
