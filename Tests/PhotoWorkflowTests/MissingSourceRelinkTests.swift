// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

@MainActor
final class MissingSourceRelinkTests: XCTestCase {
  func testRelinkPlanRejectsReplacementWithDifferentFingerprint() throws {
    let asset = makeAsset(isMissing: true)
    let plan = MissingSourceRelinkPlan(asset: asset)
    let replacementURL = URL(fileURLWithPath: "/tmp/replacement.jpg")
    let changedFingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "c", count: 64),
        byteCount: 20,
        modificationDate: nil
      )
    )

    XCTAssertThrowsError(
      try plan.validate(
        replacementURL: replacementURL,
        actualFingerprint: changedFingerprint
      )
    ) { error in
      XCTAssertEqual(
        error as? MissingSourceRelinkError,
        .fingerprintMismatch(expected: asset.fingerprint, actual: changedFingerprint)
      )
    }
  }

  func testWorkspaceRelinkUpdatesAssetAndBalancesSecurityScope() async throws {
    let asset = makeAsset(isMissing: true)
    let replacementURL = URL(fileURLWithPath: "/tmp/replacement.jpg")
    let access = RelinkAccessRecorder()
    let catalog = RelinkCatalogSpy(asset: asset, access: access)
    let workspace = makeWorkspace(
      catalog: catalog,
      access: access,
      fingerprint: { _ in
        await access.record("fingerprint")
        return asset.fingerprint
      }
    )
    workspace.assets = [asset]
    workspace.selectedAssetID = asset.id

    let result = try await workspace.relinkAsset(
      assetID: asset.id,
      to: replacementURL
    )

    XCTAssertEqual(result.asset.id, asset.id)
    XCTAssertEqual(workspace.selectedAsset?.sourceURL, replacementURL)
    let selectedAsset = try XCTUnwrap(workspace.selectedAsset)
    XCTAssertFalse(selectedAsset.isMissing)
    let relinkRequest = await catalog.lastRelinkRequest()
    let request = try XCTUnwrap(relinkRequest)
    XCTAssertEqual(request.assetID, asset.id)
    XCTAssertEqual(request.sourceURL, replacementURL)
    XCTAssertEqual(request.fingerprint, asset.fingerprint)
    let events = await access.events()
    XCTAssertEqual(events, ["start", "fingerprint", "catalog", "stop"])
  }

  func testWorkspaceRelinkDoesNotMutateCatalogWhenFingerprintDiffers() async throws {
    let asset = makeAsset(isMissing: true)
    let replacementURL = URL(fileURLWithPath: "/tmp/replacement.jpg")
    let access = RelinkAccessRecorder()
    let catalog = RelinkCatalogSpy(asset: asset, access: access)
    let changedFingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "d", count: 64),
        byteCount: 20,
        modificationDate: nil
      )
    )
    let workspace = makeWorkspace(
      catalog: catalog,
      access: access,
      fingerprint: { _ in
        await access.record("fingerprint")
        return changedFingerprint
      }
    )
    workspace.assets = [asset]

    do {
      _ = try await workspace.relinkAsset(assetID: asset.id, to: replacementURL)
      XCTFail("A changed replacement must be rejected.")
    } catch let error as MissingSourceRelinkError {
      XCTAssertEqual(
        error,
        .fingerprintMismatch(expected: asset.fingerprint, actual: changedFingerprint)
      )
    }

    let relinkRequest = await catalog.lastRelinkRequest()
    XCTAssertNil(relinkRequest)
    XCTAssertEqual(workspace.assets.first, asset)
    let events = await access.events()
    XCTAssertEqual(events, ["start", "fingerprint", "stop"])
  }

  func testWorkspaceRelinkRejectsAnAssetThatIsNotMissing() async throws {
    let asset = makeAsset(isMissing: false)
    let access = RelinkAccessRecorder()
    let workspace = makeWorkspace(
      catalog: RelinkCatalogSpy(asset: asset),
      access: access,
      fingerprint: { _ in
        XCTFail("A present asset must not be fingerprinted.")
        return asset.fingerprint
      }
    )
    workspace.assets = [asset]

    do {
      _ = try await workspace.relinkAsset(
        assetID: asset.id,
        to: URL(fileURLWithPath: "/tmp/replacement.jpg")
      )
      XCTFail("A present asset must not be relinked.")
    } catch let error as MissingSourceRelinkError {
      XCTAssertEqual(error, .assetNotMissing(asset.id))
    }
    let events = await access.events()
    XCTAssertEqual(events, [])
  }

  func testWorkspaceRelinkRejectsWhenSecurityScopeCannotStart() async throws {
    let asset = makeAsset(isMissing: true)
    let access = RelinkAccessRecorder()
    let catalog = RelinkCatalogSpy(asset: asset, access: access)
    let workspace = makeWorkspace(
      catalog: catalog,
      access: access,
      startResult: false,
      fingerprint: { _ in
        XCTFail("A replacement without a security scope must not be fingerprinted.")
        return asset.fingerprint
      }
    )
    workspace.assets = [asset]

    do {
      _ = try await workspace.relinkAsset(
        assetID: asset.id,
        to: URL(fileURLWithPath: "/tmp/replacement.jpg")
      )
      XCTFail("Relink must require a security-scoped replacement URL.")
    } catch let error as MissingSourceRelinkError {
      XCTAssertEqual(
        error,
        .sourceScopeUnavailable(URL(fileURLWithPath: "/tmp/replacement.jpg"))
      )
    }

    let events = await access.events()
    XCTAssertEqual(events, ["start"])
    let relinkRequest = await catalog.lastRelinkRequest()
    XCTAssertNil(relinkRequest)
  }
}

extension MissingSourceRelinkTests {
  fileprivate func makeAsset(isMissing: Bool) -> PhotoAsset {
    PhotoAsset(
      id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
      sourceURL: URL(fileURLWithPath: "/tmp/original.jpg"),
      filename: "original.jpg",
      typeIdentifier: "public.jpeg",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "b", count: 64),
        byteCount: 20,
        modificationDate: nil
      )!,
      importDate: Date(timeIntervalSince1970: 1),
      captureDate: nil,
      pixelDimensions: PixelDimensions(width: 20, height: 10),
      isMissing: isMissing
    )!
  }

  fileprivate func makeWorkspace(
    catalog: any CatalogStore,
    access: RelinkAccessRecorder,
    startResult: Bool = true,
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint
  ) -> PhotoWorkspace {
    PhotoWorkspace(
      catalog: catalog,
      renderer: RelinkRenderer(),
      exporter: RelinkExporter(),
      sourceAccess: SourceAccessOperations(
        persist: { _, _ in },
        resolve: { $0.sourceURL },
        start: { url in
          await access.record("start")
          return startResult
        },
        stop: { url in
          await access.record("stop")
        }
      ),
      fingerprint: fingerprint,
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 20, height: 10)!,
          pins: EnginePins(
            decoderIdentifier: "com.apple.coreimage.common-image",
            decoderVersion: "system-default",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.jpeg"
        )
      },
      previewDebounce: {}
    )
  }
}

private actor RelinkAccessRecorder {
  private var values: [String] = []

  func record(_ value: String) {
    values.append(value)
  }

  func events() -> [String] { values }
}

private actor RelinkCatalogSpy: CatalogStore {
  private var asset: PhotoAsset
  private var request: CatalogRelinkAssetRequest?
  private let access: RelinkAccessRecorder?

  init(asset: PhotoAsset, access: RelinkAccessRecorder? = nil) {
    self.asset = asset
    self.access = access
  }

  func upsertAsset(_ request: CatalogAssetUpsertRequest) async throws -> CatalogAssetUpsertResult {
    asset = request.asset
    return CatalogAssetUpsertResult(asset: asset)
  }

  func fetchAsset(_ request: CatalogAssetFetchRequest) async throws -> CatalogAssetFetchResult {
    CatalogAssetFetchResult(asset: request.assetID == asset.id ? asset : nil)
  }

  func listAssets(_ request: CatalogAssetListRequest) async throws -> CatalogAssetListResult {
    CatalogAssetListResult(assets: [asset])
  }

  func searchAssets(_ request: CatalogAssetSearchRequest) async throws -> CatalogAssetSearchResult {
    CatalogAssetSearchResult(assets: asset.filename.contains(request.query) ? [asset] : [])
  }

  func saveRecipe(_ request: CatalogRecipeSaveRequest) async throws -> CatalogRecipeSaveResult {
    CatalogRecipeSaveResult(recipe: request.recipe)
  }

  func latestRecipe(_ request: CatalogLatestRecipeRequest) async throws -> CatalogLatestRecipeResult
  {
    CatalogLatestRecipeResult(recipe: nil)
  }

  func markAssetMissing(_ request: CatalogMarkMissingRequest) async throws
    -> CatalogMarkMissingResult
  {
    asset = PhotoAsset(
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
      isMissing: request.isMissing,
      metadata: asset.metadata
    )!
    return CatalogMarkMissingResult(asset: asset)
  }

  func relinkAsset(_ request: CatalogRelinkAssetRequest) async throws -> CatalogRelinkAssetResult {
    await access?.record("catalog")
    self.request = request
    asset = PhotoAsset(
      id: asset.id,
      sourceURL: request.sourceURL,
      filename: request.filename,
      typeIdentifier: request.typeIdentifier,
      fingerprint: request.fingerprint,
      importDate: asset.importDate,
      captureDate: asset.captureDate,
      pixelDimensions: asset.pixelDimensions,
      rating: asset.rating,
      colorLabel: asset.colorLabel,
      isMissing: false,
      metadata: asset.metadata
    )!
    return CatalogRelinkAssetResult(asset: asset)
  }

  func checkIntegrity(_ request: CatalogIntegrityRequest) async throws -> CatalogIntegrityResult {
    CatalogIntegrityResult(isValid: true, messages: [])
  }

  func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult {
    CatalogBackupResult(destinationURL: request.destinationURL)
  }

  func lastRelinkRequest() -> CatalogRelinkAssetRequest? { request }
}

private struct RelinkRenderer: RenderEngine {
  func render(_ request: RenderRequest) async throws -> RenderResult {
    RenderResult(
      imageData: Data(),
      typeIdentifier: "public.jpeg",
      pixelDimensions: PixelDimensions(width: 20, height: 10)!
    )
  }
}

private struct RelinkExporter: Exporter {
  func export(_ request: ExportRequest) async throws -> ExportResult {
    throw RelinkTestError.unused
  }
}

private enum RelinkTestError: Error {
  case unused
}
