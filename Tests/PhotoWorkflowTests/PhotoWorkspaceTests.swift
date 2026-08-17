// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

@MainActor
final class PhotoWorkspaceTests: XCTestCase {
  func testReopenSelectsFirstAvailableAssetAndRestoresItsLatestRecipe() async throws {
    let missing = makeAsset(name: "A-missing.raw", date: Date(timeIntervalSince1970: 20))
    let available = makeAsset(
      name: "B-available.jpg",
      date: Date(timeIntervalSince1970: 10),
      isMissing: true
    )
    let restored = makeRecipe(assetID: available.id, revision: 4, operations: [.exposureEV(0.75)])
    let catalog = CatalogSpy(assets: [missing, available], recipes: [available.id: restored])
    let access = SourceAccessSpy(missingAssetIDs: [missing.id])
    let renderer = ImmediateRenderer()
    let workspace = makeWorkspace(catalog: catalog, renderer: renderer, access: access)

    await workspace.reopen()

    XCTAssertEqual(workspace.assets.map(\.id), [missing.id, available.id])
    XCTAssertEqual(workspace.selectedAssetID, available.id)
    XCTAssertEqual(workspace.currentRecipe, restored)
    XCTAssertEqual(workspace.preview?.imageData, Data("preview-4".utf8))
    let missingUpdates = await catalog.missingUpdates()
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertEqual(missingUpdates, [missing.id: true, available.id: false])
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testImportRetainsSuccessfulFilesWhenOneFingerprintFails() async throws {
    let firstURL = URL(fileURLWithPath: "/tmp/first.jpg")
    let failedURL = URL(fileURLWithPath: "/tmp/broken.raw")
    let thirdURL = URL(fileURLWithPath: "/tmp/third.png")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy()
    let renderer = ImmediateRenderer()
    let fingerprintRecorder = FingerprintRecorder(failingURL: failedURL)
    let workspace = makeWorkspace(
      catalog: catalog,
      renderer: renderer,
      access: access,
      fingerprint: { try await fingerprintRecorder.fingerprint($0) }
    )

    await workspace.importURLs([firstURL, failedURL, thirdURL])

    XCTAssertEqual(workspace.assets.map(\.sourceURL), [firstURL, thirdURL])
    XCTAssertEqual(workspace.selectedAssetID, workspace.assets.first?.id)
    XCTAssertEqual(workspace.itemErrors.map(\.sourceURL), [failedURL])
    let savedRevisions = await catalog.savedRecipes().map(\.revision)
    let persistedURLs = await access.persistedURLs()
    let activeAccessCount = await access.activeAccessCount()
    let fingerprintURLs = await fingerprintRecorder.urls()
    XCTAssertEqual(savedRevisions, [0, 0])
    XCTAssertEqual(persistedURLs, [firstURL, thirdURL])
    XCTAssertEqual(activeAccessCount, 0)
    XCTAssertEqual(fingerprintURLs, [firstURL, failedURL, thirdURL])
  }

  func testAcceptedEditsCreateOrderedMonotonicRecipesAndSupportUndoRedoReset() async throws {
    let asset = makeAsset(name: "edit.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.commitAdjustment(.saturation, value: 0.2)
    await workspace.commitAdjustment(.exposure, value: 1.25)
    await workspace.commitAdjustment(.contrast, value: -0.1)
    await workspace.rotateClockwise()

    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1.25), .contrast(-0.1), .saturation(0.2), .rotationDegrees(90)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 4)

    await workspace.undo()
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1.25), .contrast(-0.1), .saturation(0.2)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 5)

    await workspace.redo()
    XCTAssertEqual(workspace.currentRecipe?.operations.last, .rotationDegrees(90))
    XCTAssertEqual(workspace.currentRecipe?.revision, 6)

    await workspace.resetEdits()
    XCTAssertEqual(workspace.currentRecipe?.operations, [])
    XCTAssertEqual(workspace.currentRecipe?.revision, 7)
    let revisions = await catalog.savedRecipes().map(\.revision)
    XCTAssertEqual(revisions, [1, 2, 3, 4, 5, 6, 7])
  }

  func testNewPreviewCancelsAndSuppressesStalePreview() async throws {
    let asset = makeAsset(name: "preview.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let renderer = ControllableRenderer()
    let workspace = makeWorkspace(catalog: catalog, renderer: renderer)

    let reopen = Task { await workspace.reopen() }
    await renderer.waitForRequestCount(1)
    await renderer.completeRequest(0, bytes: Data("initial".utf8))
    await reopen.value

    let first = Task { await workspace.refreshPreview() }
    await renderer.waitForRequestCount(2)
    let second = Task { await workspace.refreshPreview() }
    await renderer.waitForRequestCount(3)
    await renderer.completeRequest(2, bytes: Data("new".utf8))
    await renderer.completeRequest(1, bytes: Data("stale".utf8))
    await first.value
    await second.value

    XCTAssertEqual(workspace.preview?.imageData, Data("new".utf8))
    XCTAssertNil(workspace.errorMessage)
  }

  func testExportUsesSelectedAssetAndLatestDurableRecipe() async throws {
    let asset = makeAsset(name: "export.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let exporter = ExporterSpy()
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter)
    await workspace.reopen()
    await workspace.commitAdjustment(.exposure, value: 0.5)
    let destination = URL(fileURLWithPath: "/tmp/export.jpg")

    await workspace.exportJPEG(to: destination, quality: 0.82)

    let capturedRequest = await exporter.lastRequest()
    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(request.sourceURL, asset.sourceURL)
    XCTAssertEqual(request.recipe.revision, 1)
    XCTAssertEqual(request.recipe.operations, [.exposureEV(0.5)])
    XCTAssertEqual(request.destinationURL, destination)
    XCTAssertEqual(request.format, .jpeg)
    XCTAssertEqual(request.quality, 0.82)
    XCTAssertNotNil(workspace.lastExport)
  }

  func testBookmarkFailureKeepsImportedAssetAndRevisionZeroRecipeVisibleAndMissing() async throws {
    let url = URL(fileURLWithPath: "/tmp/bookmark-failure.jpg")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy(failingPersistURLs: [url])
    let workspace = makeWorkspace(catalog: catalog, access: access)

    await workspace.importURLs([url])

    XCTAssertEqual(workspace.assets.count, 1)
    XCTAssertEqual(workspace.currentRecipe?.revision, 0)
    XCTAssertEqual(workspace.assets.first?.isMissing, true)
    let savedRecipeCount = await catalog.savedRecipes().count
    XCTAssertEqual(savedRecipeCount, 1)
    XCTAssertEqual(workspace.itemErrors.map(\.sourceURL), [url])
    XCTAssertNotNil(workspace.lastError)
  }

  func testFailedUndoRestoresHistoryAndCanRetry() async throws {
    let asset = makeAsset(name: "undo.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()
    await workspace.commitAdjustment(.exposure, value: 1)
    await catalog.failNextRecipeSave()

    await workspace.undo()

    XCTAssertEqual(workspace.currentRecipe?.operations, [.exposureEV(1)])
    XCTAssertTrue(workspace.canUndo)
    XCTAssertFalse(workspace.canRedo)
    XCTAssertNotNil(workspace.lastError)

    await workspace.undo()
    XCTAssertEqual(workspace.currentRecipe?.operations, [])
    XCTAssertEqual(workspace.currentRecipe?.revision, 2)
  }

  func testNoOpAndUnknownRecipeEditsDoNotCreateRevisions() async throws {
    let asset = makeAsset(name: "future.jpg")
    let unknown = EditOperation.unknown("futureTone", payload: ["amount": .number(1)])
    let initial = makeRecipe(assetID: asset.id, operations: [unknown])
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.commitAdjustment(.exposure, value: 0)

    XCTAssertEqual(workspace.currentRecipe?.operations, [unknown])
    let savedRecipeCount = await catalog.savedRecipes().count
    XCTAssertEqual(savedRecipeCount, 0)
    XCTAssertEqual(workspace.lastError, .unknownOperationsBlockEditing)
  }

  func testConcurrentEditsSerializeUniqueRevisions() async throws {
    let asset = makeAsset(name: "concurrent.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    async let exposure: Void = workspace.commitAdjustment(.exposure, value: 1)
    async let contrast: Void = workspace.commitAdjustment(.contrast, value: 0.2)
    _ = await (exposure, contrast)

    let saves = await catalog.savedRecipes()
    XCTAssertEqual(saves.map(\.revision), [1, 2])
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1), .contrast(0.2)]
    )
  }

  func testExportClearsPriorResultAndReportsNoSelectionAsTypedError() async throws {
    let asset = makeAsset(name: "export-failure.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let exporter = ExporterSpy()
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter)
    await workspace.reopen()
    await workspace.exportJPEG(to: URL(fileURLWithPath: "/tmp/ok.jpg"), quality: 0.9)
    XCTAssertNotNil(workspace.lastExport)
    await exporter.failExports()

    await workspace.exportJPEG(to: URL(fileURLWithPath: "/tmp/fail.jpg"), quality: 0.9)
    XCTAssertNil(workspace.lastExport)
    XCTAssertNotNil(workspace.lastError)

    let empty = makeWorkspace()
    await empty.exportJPEG(to: URL(fileURLWithPath: "/tmp/none.jpg"), quality: 0.9)
    XCTAssertEqual(empty.lastError, .noSelection(operation: "export"))
  }

  func testSourceAccessCoversImportRenderAndExportAndPreservesProbePinsAndFingerprint() async throws
  {
    let url = URL(fileURLWithPath: "/tmp/access.raw")
    let destination = URL(fileURLWithPath: "/tmp/access-export.jpg")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy()
    let phases = AccessPhaseRecorder()
    let renderer = ImmediateRenderer(access: access)
    let exporter = ExporterSpy(access: access)
    let fingerprint = SourceFingerprint(
      sha256: String(repeating: "f", count: 64),
      byteCount: 9_007_199_254_740_993,
      modificationDate: Date(timeIntervalSince1970: 42)
    )!
    let pins = EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "exact-system-version",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let workspace = PhotoWorkspace(
      catalog: catalog,
      renderer: renderer,
      exporter: exporter,
      sourceAccess: access.operations,
      fingerprint: { sourceURL in
        await phases.record("fingerprint", active: access.isActive)
        XCTAssertEqual(sourceURL, url)
        return fingerprint
      },
      probe: { sourceURL in
        await phases.record("probe", active: access.isActive)
        XCTAssertEqual(sourceURL, url)
        return SourceProbe(
          dimensions: PixelDimensions(width: 30, height: 20)!,
          pins: pins,
          typeIdentifier: "public.camera-raw-image"
        )
      },
      previewDebounce: {}
    )

    await workspace.importURLs([url])
    await workspace.exportJPEG(to: destination, quality: 0.9)

    let assetSnapshot = await catalog.assetSnapshot()
    let savedRecipes = await catalog.savedRecipes()
    let phaseValues = await phases.values()
    let renderAccess = await renderer.wasAccessActive()
    let exportAccess = await exporter.wasAccessActive()
    let activeAccessCount = await access.activeAccessCount()
    let storedAsset = try XCTUnwrap(assetSnapshot.first)
    let storedRecipe = try XCTUnwrap(savedRecipes.first)
    XCTAssertEqual(storedAsset.fingerprint, fingerprint)
    XCTAssertEqual(storedRecipe.pins, pins)
    XCTAssertEqual(phaseValues, ["fingerprint": true, "probe": true])
    XCTAssertTrue(renderAccess)
    XCTAssertTrue(exportAccess)
    XCTAssertEqual(activeAccessCount, 0)
  }
}

extension PhotoWorkspaceTests {
  private func makeWorkspace(
    catalog: any CatalogStore = CatalogSpy(),
    renderer: any RenderEngine = ImmediateRenderer(),
    exporter: any Exporter = ExporterSpy(),
    access: SourceAccessSpy = SourceAccessSpy(),
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint = { _ in
      SourceFingerprint(
        sha256: String(repeating: "a", count: 64), byteCount: 10, modificationDate: nil)!
    }
  ) -> PhotoWorkspace {
    PhotoWorkspace(
      catalog: catalog,
      renderer: renderer,
      exporter: exporter,
      sourceAccess: access.operations,
      fingerprint: fingerprint,
      probe: { url in
        SourceProbe(
          dimensions: PixelDimensions(width: 20, height: 10)!,
          pins: EnginePins(
            decoderIdentifier: url.pathExtension == "raw"
              ? "com.apple.ciraw" : "com.apple.coreimage.common-image",
            decoderVersion: url.pathExtension == "raw" ? "raw-v1" : "system-default",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: url.pathExtension == "raw" ? "public.camera-raw-image" : "public.image"
        )
      },
      now: { Date(timeIntervalSince1970: 100) },
      previewDebounce: {}
    )
  }

  private func makeAsset(
    name: String,
    date: Date = Date(timeIntervalSince1970: 1),
    isMissing: Bool = false
  ) -> PhotoAsset {
    PhotoAsset(
      sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
      filename: name,
      typeIdentifier: "public.image",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "b", count: 64),
        byteCount: 20,
        modificationDate: nil
      )!,
      importDate: date,
      captureDate: nil,
      pixelDimensions: PixelDimensions(width: 20, height: 10),
      isMissing: isMissing
    )!
  }

  private func makeRecipe(
    assetID: UUID,
    revision: UInt64 = 0,
    operations: [EditOperation] = []
  ) -> EditRecipe {
    EditRecipe(
      assetID: assetID,
      revision: revision,
      date: Date(timeIntervalSince1970: 1),
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      ),
      operations: operations
    )
  }
}

private actor CatalogSpy: CatalogStore {
  private var storedAssets: [PhotoAsset]
  private var recipes: [UUID: EditRecipe]
  private var recipeSaves: [EditRecipe] = []
  private var missing: [UUID: Bool] = [:]
  private var shouldFailNextRecipeSave = false

  init(assets: [PhotoAsset] = [], recipes: [UUID: EditRecipe] = [:]) {
    storedAssets = assets
    self.recipes = recipes
  }

  func upsertAsset(_ request: CatalogAssetUpsertRequest) async throws -> CatalogAssetUpsertResult {
    storedAssets.removeAll { $0.id == request.asset.id }
    storedAssets.append(request.asset)
    return CatalogAssetUpsertResult(asset: request.asset)
  }

  func fetchAsset(_ request: CatalogAssetFetchRequest) async throws -> CatalogAssetFetchResult {
    CatalogAssetFetchResult(asset: storedAssets.first { $0.id == request.assetID })
  }

  func listAssets(_ request: CatalogAssetListRequest) async throws -> CatalogAssetListResult {
    CatalogAssetListResult(assets: storedAssets)
  }

  func searchAssets(_ request: CatalogAssetSearchRequest) async throws -> CatalogAssetSearchResult {
    CatalogAssetSearchResult(
      assets: storedAssets.filter { $0.filename.localizedCaseInsensitiveContains(request.query) })
  }

  func saveRecipe(_ request: CatalogRecipeSaveRequest) async throws -> CatalogRecipeSaveResult {
    if shouldFailNextRecipeSave {
      shouldFailNextRecipeSave = false
      throw TestError.recipeSave
    }
    recipes[request.recipe.assetID] = request.recipe
    recipeSaves.append(request.recipe)
    return CatalogRecipeSaveResult(recipe: request.recipe)
  }

  func latestRecipe(_ request: CatalogLatestRecipeRequest) async throws -> CatalogLatestRecipeResult
  {
    CatalogLatestRecipeResult(recipe: recipes[request.assetID])
  }

  func markAssetMissing(_ request: CatalogMarkMissingRequest) async throws
    -> CatalogMarkMissingResult
  {
    missing[request.assetID] = request.isMissing
    let old = storedAssets.first { $0.id == request.assetID }!
    let asset = PhotoAsset(
      id: old.id,
      sourceURL: old.sourceURL,
      filename: old.filename,
      typeIdentifier: old.typeIdentifier,
      fingerprint: old.fingerprint,
      importDate: old.importDate,
      captureDate: old.captureDate,
      pixelDimensions: old.pixelDimensions,
      rating: old.rating,
      colorLabel: old.colorLabel,
      isMissing: request.isMissing
    )!
    storedAssets.removeAll { $0.id == request.assetID }
    storedAssets.append(asset)
    return CatalogMarkMissingResult(asset: asset)
  }

  func relinkAsset(_ request: CatalogRelinkAssetRequest) async throws -> CatalogRelinkAssetResult {
    throw TestError.unused
  }

  func checkIntegrity(_ request: CatalogIntegrityRequest) async throws -> CatalogIntegrityResult {
    CatalogIntegrityResult(isValid: true, messages: [])
  }

  func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult {
    CatalogBackupResult(destinationURL: request.destinationURL)
  }

  func savedRecipes() -> [EditRecipe] { recipeSaves }
  func missingUpdates() -> [UUID: Bool] { missing }
  func failNextRecipeSave() { shouldFailNextRecipeSave = true }
  func assetSnapshot() -> [PhotoAsset] { storedAssets }
}

private actor SourceAccessSpy {
  private var missingAssetIDs: Set<UUID>
  private var persisted: [URL] = []
  private var active = 0
  private let failingPersistURLs: Set<URL>

  init(missingAssetIDs: Set<UUID> = [], failingPersistURLs: Set<URL> = []) {
    self.missingAssetIDs = missingAssetIDs
    self.failingPersistURLs = failingPersistURLs
  }

  nonisolated var operations: SourceAccessOperations {
    SourceAccessOperations(
      persist: { [self] _, url in try await recordPersist(url) },
      resolve: { [self] asset in
        if await isMissing(asset.id) { throw TestError.missing }
        return asset.sourceURL
      },
      start: { [self] url in
        await start(url)
        return true
      },
      stop: { [self] url in await stop(url) }
    )
  }

  private func recordPersist(_ url: URL) throws {
    if failingPersistURLs.contains(url) { throw TestError.bookmark }
    persisted.append(url)
  }
  private func isMissing(_ id: UUID) -> Bool { missingAssetIDs.contains(id) }
  private func start(_ url: URL) { active += 1 }
  private func stop(_ url: URL) { active -= 1 }
  func persistedURLs() -> [URL] { persisted }
  func activeAccessCount() -> Int { active }
  var isActive: Bool { active > 0 }
}

private actor FingerprintRecorder {
  private let failingURL: URL
  private var recorded: [URL] = []

  init(failingURL: URL) { self.failingURL = failingURL }

  func fingerprint(_ url: URL) throws -> SourceFingerprint {
    recorded.append(url)
    if url == failingURL { throw TestError.fingerprint }
    return SourceFingerprint(
      sha256: String(repeating: url == recorded.first ? "c" : "d", count: 64),
      byteCount: 30,
      modificationDate: nil
    )!
  }

  func urls() -> [URL] { recorded }
}

private actor ImmediateRenderer: RenderEngine {
  private let access: SourceAccessSpy?
  private var accessWasActive = false

  init(access: SourceAccessSpy? = nil) { self.access = access }

  func render(_ request: RenderRequest) async throws -> RenderResult {
    if let access { accessWasActive = await access.isActive }
    return RenderResult(
      imageData: Data("preview-\(request.recipe.revision)".utf8),
      typeIdentifier: "public.png",
      pixelDimensions: PixelDimensions(width: 20, height: 10)!
    )
  }

  func wasAccessActive() -> Bool { accessWasActive }
}

private actor ControllableRenderer: RenderEngine {
  private var continuations: [CheckedContinuation<RenderResult, any Error>] = []

  func render(_ request: RenderRequest) async throws -> RenderResult {
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitForRequestCount(_ count: Int) async {
    while continuations.count < count { await Task.yield() }
  }

  func completeRequest(_ index: Int, bytes: Data) {
    continuations[index].resume(
      returning: RenderResult(
        imageData: bytes,
        typeIdentifier: "public.png",
        pixelDimensions: PixelDimensions(width: 20, height: 10)!
      )
    )
  }
}

private actor ExporterSpy: Exporter {
  private var request: ExportRequest?
  private var shouldFail = false
  private let access: SourceAccessSpy?
  private var accessWasActive = false

  init(access: SourceAccessSpy? = nil) { self.access = access }

  func export(_ request: ExportRequest) async throws -> ExportResult {
    self.request = request
    if let access { accessWasActive = await access.isActive }
    if shouldFail { throw TestError.export }
    return ExportResult(
      derivative: DurableDerivative(
        schemaVersion: 1,
        assetID: request.recipe.assetID,
        recipeRevision: request.recipe.revision,
        kind: .export,
        outputURL: request.destinationURL,
        typeIdentifier: "public.jpeg",
        fingerprint: SourceFingerprint(
          sha256: String(repeating: "e", count: 64),
          byteCount: 100,
          modificationDate: nil
        )!,
        createdAt: Date(timeIntervalSince1970: 100)
      )
    )
  }

  func lastRequest() -> ExportRequest? { request }
  func failExports() { shouldFail = true }
  func wasAccessActive() -> Bool { accessWasActive }
}

private actor AccessPhaseRecorder {
  private var recorded: [String: Bool] = [:]

  func record(_ phase: String, active: Bool) { recorded[phase] = active }
  func values() -> [String: Bool] { recorded }
}

private enum TestError: Error {
  case fingerprint
  case missing
  case unused
  case bookmark
  case recipeSave
  case export
}
