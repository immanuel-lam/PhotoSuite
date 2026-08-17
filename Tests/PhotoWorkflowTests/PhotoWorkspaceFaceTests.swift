// SPDX-License-Identifier: MPL-2.0

import CatalogCore
import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

@MainActor
final class PhotoWorkspaceFaceTests: XCTestCase {
  func testReopenProjectsStoredFaceGeometryWithoutInferringIdentity() async throws {
    let fixture = try FaceWorkspaceFixture()
    defer { fixture.remove() }

    let face = try fixture.makeFace(label: nil)
    try await fixture.storeFace(face)
    let workspace = fixture.makeWorkspace()

    await workspace.reopen()

    XCTAssertTrue(workspace.supportsPeopleMetadata)
    XCTAssertEqual(workspace.selectedAssetID, fixture.asset.id)
    XCTAssertEqual(workspace.selectedAssetFaces, [face])
    XCTAssertEqual(workspace.selectedFace?.region, face.region)
    XCTAssertNil(workspace.selectedFace?.label)
    XCTAssertEqual(workspace.selectedFace?.source, .vision)

    try await fixture.close()
  }

  func testSaveFaceLabelPersistsUserMetadataAndPreservesDetectionFields() async throws {
    let fixture = try FaceWorkspaceFixture()
    defer { fixture.remove() }

    let face = try fixture.makeFace(label: nil)
    try await fixture.storeFace(face)
    let workspace = fixture.makeWorkspace()
    await workspace.reopen()

    await workspace.saveFaceLabel("  Alex  ", for: face.id)

    let saved = try XCTUnwrap(workspace.selectedAssetFaces.first)
    XCTAssertEqual(saved.id, face.id)
    XCTAssertEqual(saved.label, "Alex")
    XCTAssertEqual(saved.region, face.region)
    XCTAssertEqual(saved.confidence, face.confidence)
    XCTAssertEqual(saved.source, .vision)

    let persisted = try await fixture.faces().first
    XCTAssertEqual(persisted?.label, "Alex")
    XCTAssertEqual(persisted?.source, .vision)
    XCTAssertEqual(persisted?.region, face.region)

    await workspace.saveFaceLabel("   ", for: face.id)
    XCTAssertNil(workspace.selectedFace?.label)
    let clearedPersisted = try await fixture.faces().first
    XCTAssertNil(clearedPersisted?.label)

    try await fixture.close()
  }

  func testSelectingAnotherAssetReloadsItsFaceProjection() async throws {
    let fixture = try FaceWorkspaceFixture(secondAsset: true)
    defer { fixture.remove() }

    let firstFace = try fixture.makeFace(assetID: fixture.asset.id, label: "First")
    let secondFace = try fixture.makeFace(assetID: fixture.secondAsset!.id, label: nil)
    try await fixture.storeFace(firstFace)
    try await fixture.storeFace(secondFace)
    let workspace = fixture.makeWorkspace()

    await workspace.reopen()
    await workspace.selectAsset(fixture.secondAsset!.id)

    XCTAssertEqual(workspace.selectedAssetID, fixture.secondAsset!.id)
    XCTAssertEqual(workspace.selectedAssetFaces, [secondFace])
    XCTAssertNil(workspace.selectedFace?.label)

    try await fixture.close()
  }
}

@MainActor
private final class FaceWorkspaceFixture {
  let root: URL
  let store: SQLiteCatalogStore
  let asset: PhotoAsset
  let secondAsset: PhotoAsset?
  private var isSeeded = false

  init(secondAsset: Bool = false) throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-FaceWorkspace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = try SQLiteCatalogStore(catalogURL: root.appendingPathComponent("PhotoSuite.sqlite"))
    asset = try Self.makeAsset(name: "first.jpg")
    self.secondAsset = secondAsset ? try Self.makeAsset(name: "second.jpg") : nil
  }

  func makeFace(assetID: UUID? = nil, label: String?) throws -> PhotoFace {
    try XCTUnwrap(
      PhotoFace(
        assetID: assetID ?? asset.id,
        region: try XCTUnwrap(FaceRegion(x: 0.2, y: 0.15, width: 0.25, height: 0.3)),
        label: label,
        confidence: 0.94,
        source: .vision,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
    )
  }

  func storeFace(_ face: PhotoFace) async throws {
    if !isSeeded {
      _ = try await store.upsertAsset(.init(asset: asset))
      _ = try await store.saveRecipe(.init(recipe: makeRecipe(assetID: asset.id)))
      if let secondAsset {
        _ = try await store.upsertAsset(.init(asset: secondAsset))
        _ = try await store.saveRecipe(.init(recipe: makeRecipe(assetID: secondAsset.id)))
      }
      isSeeded = true
    }
    _ = try await store.saveFace(.init(face: face))
  }

  func faces() async throws -> [PhotoFace] {
    try await store.listFaces(.init(assetID: asset.id)).faces
  }

  @MainActor
  func makeWorkspace() -> PhotoWorkspace {
    PhotoWorkspace(
      catalog: store,
      renderer: FaceWorkspaceRenderer(),
      exporter: FaceWorkspaceExporter(),
      sourceAccess: .unrestricted,
      fingerprint: { _ in
        SourceFingerprint(
          sha256: String(repeating: "a", count: 64), byteCount: 10, modificationDate: nil
        )!
      },
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 2, height: 2)!,
          pins: EnginePins(
            decoderIdentifier: "test.decoder",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.jpeg"
        )
      },
      now: { Date(timeIntervalSince1970: 100) },
      previewDebounce: {}
    )
  }

  func close() async throws {
    try await store.close()
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  private static func makeAsset(name: String) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
        filename: name,
        typeIdentifier: "public.jpeg",
        fingerprint: try XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "b", count: 64), byteCount: 10, modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1),
        captureDate: nil,
        pixelDimensions: PixelDimensions(width: 2, height: 2)
      )
    )
  }

  private func makeRecipe(assetID: UUID) -> EditRecipe {
    EditRecipe(
      assetID: assetID,
      revision: 0,
      date: Date(timeIntervalSince1970: 1),
      pins: EnginePins(
        decoderIdentifier: "test.decoder",
        decoderVersion: "test-v1",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )
  }
}

private struct FaceWorkspaceRenderer: RenderEngine {
  func render(_ request: RenderRequest) async throws -> RenderResult {
    RenderResult(
      imageData: Data([0, 0, 0, 255]),
      typeIdentifier: "public.jpeg",
      pixelDimensions: PixelDimensions(width: 2, height: 2)!
    )
  }
}

private struct FaceWorkspaceExporter: Exporter {
  func export(_ request: ExportRequest) async throws -> ExportResult {
    ExportResult(
      derivative: DurableDerivative(
        schemaVersion: 1,
        assetID: request.recipe.assetID,
        recipeRevision: request.recipe.revision,
        kind: .export,
        outputURL: request.destinationURL,
        typeIdentifier: "public.jpeg",
        fingerprint: nil,
        createdAt: Date(timeIntervalSince1970: 100)
      )
    )
  }
}
