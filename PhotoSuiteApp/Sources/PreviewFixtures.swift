// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG
  import Foundation
  import PhotoDomain
  import PhotoWorkflow
  import SwiftUI

  private enum PreviewState: Equatable {
    case empty
    case loaded
    case error
  }

  @MainActor
  private struct PhotoSuitePreviewHost: View {
    @State private var workspace: PhotoWorkspace
    private let state: PreviewState

    init(state: PreviewState) {
      self.state = state
      let workspace = PhotoWorkspace(
        catalog: PreviewCatalog(),
        renderer: PreviewRenderer(),
        exporter: PreviewExporter(),
        sourceAccess: .unrestricted,
        fingerprint: { _ in
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64),
            byteCount: 1,
            modificationDate: nil
          )!
        },
        probe: { _ in
          SourceProbe(
            dimensions: PixelDimensions(width: 1, height: 1)!,
            pins: EnginePins(
              decoderIdentifier: "com.apple.coreimage.common-image",
              decoderVersion: "system-default",
              renderSchemaVersion: 1,
              cameraProfileVersion: nil,
              modelVersions: [:]
            ),
            typeIdentifier: "public.png"
          )
        },
        now: { Date(timeIntervalSince1970: 1) },
        previewDebounce: {}
      )
      if state == .error { workspace.errorMessage = "The preview source is unavailable." }
      _workspace = State(initialValue: workspace)
    }

    var body: some View {
      ContentView(workspace: workspace)
        .frame(width: 1_100, height: 700)
        .task {
          guard state == .loaded else { return }
          await workspace.importURLs([URL(fileURLWithPath: "/Preview/harbour-sunrise.png")])
          workspace.section = .develop
        }
    }
  }

  private actor PreviewCatalog: CatalogStore {
    private var assets: [PhotoAsset] = []
    private var recipes: [UUID: EditRecipe] = [:]

    func upsertAsset(_ request: CatalogAssetUpsertRequest) async throws -> CatalogAssetUpsertResult
    {
      assets.append(request.asset)
      return CatalogAssetUpsertResult(asset: request.asset)
    }

    func fetchAsset(_ request: CatalogAssetFetchRequest) async throws -> CatalogAssetFetchResult {
      CatalogAssetFetchResult(asset: assets.first { $0.id == request.assetID })
    }

    func listAssets(_ request: CatalogAssetListRequest) async throws -> CatalogAssetListResult {
      CatalogAssetListResult(assets: assets)
    }

    func searchAssets(_ request: CatalogAssetSearchRequest) async throws -> CatalogAssetSearchResult
    {
      CatalogAssetSearchResult(assets: assets)
    }

    func saveRecipe(_ request: CatalogRecipeSaveRequest) async throws -> CatalogRecipeSaveResult {
      recipes[request.recipe.assetID] = request.recipe
      return CatalogRecipeSaveResult(recipe: request.recipe)
    }

    func latestRecipe(_ request: CatalogLatestRecipeRequest) async throws
      -> CatalogLatestRecipeResult
    {
      CatalogLatestRecipeResult(recipe: recipes[request.assetID])
    }

    func markAssetMissing(_ request: CatalogMarkMissingRequest) async throws
      -> CatalogMarkMissingResult
    {
      CatalogMarkMissingResult(asset: assets.first { $0.id == request.assetID }!)
    }

    func relinkAsset(_ request: CatalogRelinkAssetRequest) async throws -> CatalogRelinkAssetResult
    {
      throw PreviewError.unsupported
    }

    func checkIntegrity(_ request: CatalogIntegrityRequest) async throws -> CatalogIntegrityResult {
      CatalogIntegrityResult(isValid: true, messages: [])
    }

    func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult {
      CatalogBackupResult(destinationURL: request.destinationURL)
    }
  }

  private actor PreviewRenderer: RenderEngine {
    func render(_ request: RenderRequest) async throws -> RenderResult {
      RenderResult(
        imageData: Data(
          base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZxZ0AAAAASUVORK5CYII="
        )!,
        typeIdentifier: "public.png",
        pixelDimensions: PixelDimensions(width: 1, height: 1)!
      )
    }
  }

  private actor PreviewExporter: Exporter {
    func export(_ request: ExportRequest) async throws -> ExportResult {
      throw PreviewError.unsupported
    }
  }

  private enum PreviewError: Error {
    case unsupported
  }

  #Preview("Empty Library") { PhotoSuitePreviewHost(state: .empty) }
  #Preview("Loaded Develop") { PhotoSuitePreviewHost(state: .loaded) }
  #Preview("Error Banner") { PhotoSuitePreviewHost(state: .error) }
#endif
