// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class DevelopPresetTests: XCTestCase {
  func testDevelopPresetPersistsThroughReopenAndPreservesUnknownPayloadAndVirtualCopy() async throws
  {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let source = Data([0x01, 0x02, 0x03])
    try source.write(to: sourceURL)
    let asset = try makeAsset(sourceURL: sourceURL)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store.upsertAsset(.init(asset: asset))

    let pins = EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "1",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let baseRecipe = EditRecipe(
      assetID: asset.id,
      revision: 3,
      date: Date(timeIntervalSince1970: 20),
      pins: pins,
      operations: [
        .clone(
          try XCTUnwrap(
            CloneAdjustmentV1(
              sourceAnchor: try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.3)),
              targetAnchor: try XCTUnwrap(RetouchPointV1(x: 0.7, y: 0.8)),
              brush: try XCTUnwrap(
                RetouchBrushV1(
                  samples: [
                    try XCTUnwrap(
                      RetouchBrushSampleV1(
                        point: try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.3)), pressure: 1
                      )
                    )
                  ],
                  radius: 0.1,
                  feather: 0.5,
                  flow: 1
                ))
            )
          )
        )
      ]
    )
    _ = try await store.saveRecipe(.init(recipe: baseRecipe))

    let virtualCopy = try XCTUnwrap(
      VirtualCopy(sourceAssetID: asset.id, name: "Warm")
    )
    _ = try await store.saveVirtualCopy(.init(virtualCopy: virtualCopy))

    let unknown = EditOperation.unknown(
      "vendor.futureDevelop",
      payload: ["strength": .number(Decimal(string: "0.75")!)]
    )
    let preset = try XCTUnwrap(
      DevelopPreset(
        name: "Editorial",
        operations: [unknown, .exposureEV(0.75)],
        virtualCopyID: virtualCopy.id,
        createdAt: Date(timeIntervalSince1970: 30),
        updatedAt: Date(timeIntervalSince1970: 31)
      )
    )

    let saved = try await store.saveDevelopPreset(.init(preset: preset)).preset
    XCTAssertEqual(saved, preset)
    let listedPresets = try await store.listDevelopPresets(.init()).presets
    XCTAssertEqual(listedPresets, [preset])

    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedPresets = try await reopened.listDevelopPresets(.init()).presets
    XCTAssertEqual(reopenedPresets, [preset])

    let applied = try await reopened.applyDevelopPreset(
      .init(assetID: asset.id, presetID: preset.id)
    ).recipe
    XCTAssertEqual(applied.virtualCopyID, virtualCopy.id)
    XCTAssertEqual(
      applied.operations,
      [baseRecipe.operations[0], unknown, .exposureEV(0.75)]
    )
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    _ = try await reopened.deleteDevelopPreset(.init(presetID: preset.id))
    let deletedPresets = try await reopened.listDevelopPresets(.init()).presets
    XCTAssertTrue(deletedPresets.isEmpty)
  }

  func testApplyingDevelopPresetCanTargetVirtualCopyAndRejectMissingTarget() async throws {
    let directory = try makeTemporaryDirectory()
    let asset = try makeAsset(sourceURL: directory.appendingPathComponent("source.jpg"))
    let store = try SQLiteCatalogStore(
      catalogURL: directory.appendingPathComponent("catalog.sqlite"))
    _ = try await store.upsertAsset(.init(asset: asset))
    let pins = EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "1",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let base = EditRecipe(assetID: asset.id, revision: 0, pins: pins)
    _ = try await store.saveRecipe(.init(recipe: base))
    let preset = try XCTUnwrap(DevelopPreset(name: "Exposure", operations: [.exposureEV(1)]))
    _ = try await store.saveDevelopPreset(.init(preset: preset))

    do {
      _ = try await store.applyDevelopPreset(
        .init(assetID: asset.id, presetID: preset.id, virtualCopyID: UUID())
      )
      XCTFail("Expected a missing virtual-copy error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected a not-found error, got \(error).")
      }
    }
  }

  func testSchemaVersionSixMigrationCreatesDevelopPresetTable() async throws {
    let catalogURL = try makeTemporaryDirectory().appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    try await store.close()

    var database: OpaquePointer?
    XCTAssertEqual(
      sqlite3_open_v2(catalogURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    guard let database else { return XCTFail("The catalog could not be opened.") }
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 7)
    XCTAssertEqual(
      try scalarInt(
        database,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'develop_presets';"
      ),
      1
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func makeAsset(sourceURL: URL) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL,
        filename: sourceURL.lastPathComponent,
        typeIdentifier: "public.jpeg",
        fingerprint: XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64),
            byteCount: 3,
            modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil
      )
    )
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw NSError(domain: "DevelopPresetTests", code: 1)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "DevelopPresetTests", code: 2)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
