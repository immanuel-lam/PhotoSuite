// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class CatalogCoreTests: XCTestCase {
  func testOpenMigratesVersionOneAndConfiguresSQLite() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    let configuration = try await store.configurationForTesting()

    let database = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(configuration.journalMode, "wal")
    XCTAssertEqual(configuration.synchronous, 2)
    XCTAssertEqual(configuration.foreignKeys, 1)
    XCTAssertEqual(configuration.busyTimeout, 5_000)
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 1)
  }

  func testAssetsRecipesAndJobsSurviveReopen() async throws {
    let catalogURL = try makeCatalogURL()
    let asset = try makeAsset(filename: "Sydney sunrise.CR3", rating: 4)
    let firstStore = try SQLiteCatalogStore(catalogURL: catalogURL)
    let savedAsset = try await firstStore.upsertAsset(.init(asset: asset)).asset
    XCTAssertEqual(savedAsset, asset)

    let pins = EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "1",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let recipe = EditRecipe(
      assetID: asset.id,
      revision: 2,
      date: Date(timeIntervalSince1970: 1_700_000_100),
      pins: pins
    )
    let savedRecipe = try await firstStore.saveRecipe(.init(recipe: recipe)).recipe
    XCTAssertEqual(savedRecipe, recipe)

    let job = CatalogJob(
      schemaVersion: 1,
      kind: .generatePreview,
      state: .queued,
      assetIDs: [asset.id],
      createdAt: Date(timeIntervalSince1970: 1_700_000_200),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
      payload: Data([0x01])
    )
    let enqueuedJob = try await firstStore.enqueue(.init(job: job)).job
    XCTAssertEqual(enqueuedJob, job)

    let secondStore = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedAsset = try await secondStore.fetchAsset(.init(assetID: asset.id)).asset
    let reopenedRecipe = try await secondStore.latestRecipe(.init(assetID: asset.id)).recipe
    let reopenedJobs = try await secondStore.list(.init()).jobs
    XCTAssertEqual(reopenedAsset, asset)
    XCTAssertEqual(reopenedRecipe, recipe)
    XCTAssertEqual(reopenedJobs, [job])
  }

  func testFTSSearchAndEscapedFallbackSearch() async throws {
    let asset = try makeAsset(filename: "night_100%.CR3", typeIdentifier: "public.camera-raw")
    let ftsStore = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    _ = try await ftsStore.upsertAsset(.init(asset: asset))
    let ftsResults = try await ftsStore.searchAssets(.init(query: "night", limit: nil)).assets
    XCTAssertEqual(ftsResults, [asset])

    let fallbackStore = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(),
      ftsAvailabilityOverride: false
    )
    _ = try await fallbackStore.upsertAsset(.init(asset: asset))
    let fallbackResults = try await fallbackStore.searchAssets(
      .init(query: "night_100%", limit: nil)
    ).assets
    let blankResults = try await fallbackStore.searchAssets(.init(query: "   ", limit: nil)).assets
    XCTAssertEqual(fallbackResults, [asset])
    XCTAssertEqual(blankResults, [])
  }

  func testMissingRelinkAndListOrder() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let first = try makeAsset(filename: "zeta.jpg", importDate: 20)
    let second = try makeAsset(filename: "alpha.jpg", importDate: 10)
    _ = try await store.upsertAsset(.init(asset: first))
    _ = try await store.upsertAsset(.init(asset: second))
    let orderedIDs = try await store.listAssets(.init(order: .filenameAscending)).assets.map(\.id)
    XCTAssertEqual(orderedIDs, [second.id, first.id])

    let missing = try await store.markAssetMissing(.init(assetID: first.id, isMissing: true)).asset
    XCTAssertTrue(missing.isMissing)
    let newURL = URL(fileURLWithPath: "/tmp/relinked.jpg")
    let relinked = try await store.relinkAsset(
      .init(
        assetID: first.id,
        sourceURL: newURL,
        filename: "relinked.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: try fingerprint(character: "c")
      )
    ).asset
    XCTAssertFalse(relinked.isMissing)
    XCTAssertEqual(relinked.sourceURL, newURL)
    XCTAssertEqual(relinked.filename, "relinked.jpg")
  }

  func testJobUpdateAndStateFilter() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let queued = makeJob(state: .queued, updatedAt: 10)
    let unknown = makeJob(state: .unknown("future-state"), updatedAt: 20)
    _ = try await store.enqueue(.init(job: queued))
    _ = try await store.enqueue(.init(job: unknown))
    let updated = CatalogJob(
      id: queued.id,
      schemaVersion: queued.schemaVersion,
      kind: queued.kind,
      state: .succeeded,
      assetIDs: queued.assetIDs,
      createdAt: queued.createdAt,
      updatedAt: Date(timeIntervalSince1970: 30),
      payload: Data([0xFE])
    )
    let savedUpdate = try await store.update(.init(job: updated)).job
    let succeededJobs = try await store.list(.init(states: [.succeeded])).jobs
    let allJobs = try await store.list(.init()).jobs
    XCTAssertEqual(savedUpdate, updated)
    XCTAssertEqual(succeededJobs, [updated])
    XCTAssertEqual(allJobs, [updated, unknown])
  }

  func testBackupRestoresCatalogDataAndIntegrity() async throws {
    let sourceURL = try makeCatalogURL()
    let backupURL = sourceURL.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: sourceURL)
    let asset = try makeAsset(filename: "backup.jpg")
    _ = try await store.upsertAsset(.init(asset: asset))
    _ = try await store.enqueue(.init(job: makeJob(state: .queued, updatedAt: 1)))
    let sourceIntegrity = try await store.checkIntegrity(.init()).isValid
    let backupResult = try await store.backup(.init(destinationURL: backupURL)).destinationURL
    XCTAssertEqual(sourceIntegrity, true)
    XCTAssertEqual(backupResult, backupURL)

    let restored = try SQLiteCatalogStore(catalogURL: backupURL)
    let restoredAsset = try await restored.fetchAsset(.init(assetID: asset.id)).asset
    let restoredIntegrity = try await restored.checkIntegrity(.init()).isValid
    XCTAssertEqual(restoredAsset, asset)
    XCTAssertEqual(restoredIntegrity, true)
  }

  func testStreamingFingerprintDetectsTamperingWithoutMutatingSource() throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.bin")
    let original = Data((0..<(2 * 1024 * 1024 + 37)).map { UInt8($0 % 251) })
    try original.write(to: sourceURL)
    let fingerprint = try SourceFingerprinter.fingerprint(url: sourceURL, chunkSize: 64 * 1024)
    XCTAssertTrue(try SourceFingerprinter.verify(url: sourceURL, expected: fingerprint))
    XCTAssertEqual(try Data(contentsOf: sourceURL), original)

    var tampered = original
    tampered[tampered.count / 2] ^= 0xFF
    try tampered.write(to: sourceURL)
    XCTAssertFalse(try SourceFingerprinter.verify(url: sourceURL, expected: fingerprint))
  }

  func testSecurityScopedBookmarkRoundTripsTemporaryURL() throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("bookmark-source.jpg")
    try Data([0x01]).write(to: sourceURL)
    let data = try SecurityScopedBookmarkStore.create(url: sourceURL)
    let result = try SecurityScopedBookmarkStore.resolve(data: data)
    XCTAssertEqual(result.url.standardizedFileURL, sourceURL.standardizedFileURL)
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
    filename: String,
    typeIdentifier: String? = "public.jpeg",
    importDate: TimeInterval = 1_700_000_000,
    rating: Int = 0
  ) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/tmp/\(filename)"),
        filename: filename,
        typeIdentifier: typeIdentifier,
        fingerprint: try fingerprint(character: "b"),
        importDate: Date(timeIntervalSince1970: importDate),
        captureDate: nil,
        pixelDimensions: nil,
        rating: rating
      )
    )
  }

  private func fingerprint(character: Character) throws -> SourceFingerprint {
    try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: String(character), count: 64),
        byteCount: 1,
        modificationDate: nil
      )
    )
  }

  private func makeJob(state: CatalogJobState, updatedAt: TimeInterval) -> CatalogJob {
    CatalogJob(
      schemaVersion: 1,
      kind: .generatePreview,
      state: state,
      assetIDs: [],
      createdAt: Date(timeIntervalSince1970: updatedAt - 1),
      updatedAt: Date(timeIntervalSince1970: updatedAt),
      payload: Data([0x0A])
    )
  }

  private func openDatabase(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let database
    else {
      throw NSError(domain: "CatalogCoreTests", code: 1)
    }
    return database
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw NSError(domain: "CatalogCoreTests", code: 4)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "CatalogCoreTests", code: 5)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
