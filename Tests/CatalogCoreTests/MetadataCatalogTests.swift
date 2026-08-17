// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class MetadataCatalogTests: XCTestCase {
  func testMetadataPersistsThroughAssetUpsertAndReopenWithoutChangingSource() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let source = Data([0x01, 0x02, 0x03, 0x04])
    try source.write(to: sourceURL)
    let metadata = try XCTUnwrap(
      PhotoMetadata(
        title: "Sunrise",
        description: "A quiet morning",
        creator: "Alex",
        copyrightNotice: "Copyright 2026 Alex",
        keywords: ["sunrise", "landscape"]
      )
    )
    let asset = try makeAsset(sourceURL: sourceURL, metadata: metadata)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    var store: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store!.upsertAsset(.init(asset: asset))
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)
    try await store!.close()
    store = nil

    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let fetched = try await reopened.fetchAsset(.init(assetID: asset.id)).asset
    XCTAssertEqual(fetched?.metadata, metadata)
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    let database = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 7)
    XCTAssertEqual(try scalarInt(database, "SELECT COUNT(*) FROM asset_keywords;"), 2)
  }

  func testMetadataUpdatePreservesIdentityAndSupportsSearchAcrossKeywordsAndFields() async throws {
    let metadata = try XCTUnwrap(
      PhotoMetadata(creator: "Jane Doe", keywords: ["Rainforest", "Birds"]))
    let asset = try makeAsset(filename: "green.jpg", metadata: metadata)
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    _ = try await store.upsertAsset(.init(asset: asset))

    let searchedKeyword = try await store.searchAssets(.init(query: "rainforest")).assets
    let searchedCreator = try await store.searchAssets(.init(query: "jane")).assets
    XCTAssertEqual(searchedKeyword.map(\.id), [asset.id])
    XCTAssertEqual(searchedCreator.map(\.id), [asset.id])

    let updatedMetadata = try XCTUnwrap(
      PhotoMetadata(title: "Updated", keywords: ["forest", "birds"]))
    let updated = try await store.updateMetadata(
      .init(assetID: asset.id, metadata: updatedMetadata)
    ).asset
    XCTAssertEqual(updated.id, asset.id)
    XCTAssertEqual(updated.fingerprint, asset.fingerprint)
    XCTAssertEqual(updated.metadata, updatedMetadata)
    let updatedResults = try await store.searchAssets(.init(query: "updated")).assets
    let removedResults = try await store.searchAssets(.init(query: "rainforest")).assets
    XCTAssertTrue(updatedResults.contains(updated))
    XCTAssertTrue(removedResults.isEmpty)
  }

  func testMetadataPresetSaveListApplyDeleteAndReopen() async throws {
    let asset = try makeAsset(filename: "preset.jpg")
    let directory = try makeTemporaryDirectory()
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store.upsertAsset(.init(asset: asset))
    let preset = try XCTUnwrap(
      MetadataPreset(
        name: "Editorial",
        metadata: try XCTUnwrap(
          PhotoMetadata(
            creator: "Alex",
            rightsUsageTerms: "Editorial use only",
            keywords: ["editorial"]
          )
        ),
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
    )
    let savedPreset = try await store.saveMetadataPreset(.init(preset: preset)).preset
    let listedPresets = try await store.listMetadataPresets(.init()).presets
    XCTAssertEqual(savedPreset, preset)
    XCTAssertEqual(listedPresets, [preset])

    let applied = try await store.applyMetadataPreset(
      .init(assetID: asset.id, presetID: preset.id)
    ).asset
    XCTAssertEqual(applied.metadata, preset.metadata)

    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedPresets = try await reopened.listMetadataPresets(.init()).presets
    XCTAssertEqual(reopenedPresets, [preset])
    _ = try await reopened.deleteMetadataPreset(.init(presetID: preset.id))
    let deletedPresets = try await reopened.listMetadataPresets(.init()).presets
    XCTAssertTrue(deletedPresets.isEmpty)
  }

  private func makeCatalogURL() throws -> URL {
    try makeTemporaryDirectory().appendingPathComponent("catalog.sqlite")
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func makeAsset(
    filename: String = "metadata.jpg",
    sourceURL: URL? = nil,
    metadata: PhotoMetadata = .empty
  ) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL ?? URL(fileURLWithPath: "/tmp/\(filename)"),
        filename: filename,
        typeIdentifier: "public.jpeg",
        fingerprint: XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64), byteCount: 1, modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        metadata: metadata
      )
    )
  }

  private func openDatabase(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let database
    else {
      throw NSError(domain: "MetadataCatalogTests", code: 1)
    }
    return database
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement
    else {
      throw NSError(domain: "MetadataCatalogTests", code: 2)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "MetadataCatalogTests", code: 3)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
