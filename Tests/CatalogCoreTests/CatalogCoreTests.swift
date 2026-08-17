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
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 7)
  }

  func testExistingVersionOneCatalogMigratesMetadataTables() throws {
    let catalogURL = try makeCatalogURL()
    let database = try openWritableDatabase(catalogURL)
    try execute(database, versionOneSchema + "\nPRAGMA user_version=1;")
    XCTAssertEqual(sqlite3_close_v2(database), SQLITE_OK)

    _ = try SQLiteCatalogStore(catalogURL: catalogURL, ftsAvailabilityOverride: false)
    let migrated = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(migrated) }
    XCTAssertEqual(try scalarInt(migrated, "PRAGMA user_version;"), 7)
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM pragma_table_info('assets') WHERE name = 'metadata_json';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'asset_keywords';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'collections';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'photo_stacks';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'keyword_nodes';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'virtual_copies';"
      ),
      1
    )
  }

  func testAssetsRecipesAndJobsSurviveReopen() async throws {
    let catalogURL = try makeCatalogURL()
    let asset = try makeAsset(filename: "Sydney sunrise.CR3", rating: 4)
    var firstStore: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    let savedAsset = try await firstStore!.upsertAsset(.init(asset: asset)).asset
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
    let savedRecipe = try await firstStore!.saveRecipe(.init(recipe: recipe)).recipe
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
    let enqueuedJob = try await firstStore!.enqueue(.init(job: job)).job
    XCTAssertEqual(enqueuedJob, job)

    try await firstStore!.close()
    firstStore = nil

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

  func testForcedFTSAndFallbackSearchHaveEquivalentSubstringResults() async throws {
    let ftsStore = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(), ftsAvailabilityOverride: true)
    let fallbackStore = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(), ftsAvailabilityOverride: false)
    let midnight = try makeAsset(filename: "midnight-landscape.CR3", importDate: 20)
    let night = try makeAsset(filename: "night-portrait.CR3", importDate: 10)
    for asset in [midnight, night] {
      _ = try await ftsStore.upsertAsset(.init(asset: asset))
      _ = try await fallbackStore.upsertAsset(.init(asset: asset))
    }

    let ftsIDs = try await ftsStore.searchAssets(.init(query: "night")).assets.map(\.id)
    let fallbackIDs = try await fallbackStore.searchAssets(.init(query: "night")).assets.map(\.id)
    XCTAssertEqual(ftsIDs, [midnight.id, night.id])
    XCTAssertEqual(ftsIDs, fallbackIDs)
  }

  func testForcedFTSAndFallbackSearchHaveEquivalentDiacriticResults() async throws {
    let ftsStore = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(), ftsAvailabilityOverride: true)
    let fallbackStore = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(), ftsAvailabilityOverride: false)
    let accented = try makeAsset(filename: "café.CR3", importDate: 20)
    let plain = try makeAsset(filename: "cafe.CR3", importDate: 10)
    for asset in [accented, plain] {
      _ = try await ftsStore.upsertAsset(.init(asset: asset))
      _ = try await fallbackStore.upsertAsset(.init(asset: asset))
    }

    let accentedFTSIDs = try await ftsStore.searchAssets(.init(query: "café")).assets.map(\.id)
    let accentedFallbackIDs = try await fallbackStore.searchAssets(.init(query: "café")).assets.map(
      \.id)
    XCTAssertEqual(accentedFTSIDs, [accented.id])
    XCTAssertEqual(accentedFTSIDs, accentedFallbackIDs)
  }

  func testSearchMatchesFilenameTypeAndSourceURLWithQuotesAndBackslashes() async throws {
    let store = try SQLiteCatalogStore(
      catalogURL: try makeCatalogURL(), ftsAvailabilityOverride: false)
    let source = URL(fileURLWithPath: "/tmp/quote's\\source.jpg")
    let asset = try makeAsset(
      filename: "quote's\\name.jpg", typeIdentifier: "com.example.special-type", sourceURL: source)
    _ = try await store.upsertAsset(.init(asset: asset))
    for query in ["quote's\\name", "special-type", source.absoluteString] {
      let results = try await store.searchAssets(.init(query: query)).assets
      XCTAssertEqual(results, [asset])
    }
  }

  func testInvalidCatalogPathAndMissingRecipeAssetAreTypedFailures() async throws {
    XCTAssertThrowsError(
      try SQLiteCatalogStore(catalogURL: URL(string: "https://example.com/catalog")!))
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    do {
      _ = try await store.saveRecipe(.init(recipe: makeRecipe(assetID: UUID(), revision: 1)))
      XCTFail("Expected a missing asset error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else { return XCTFail("Expected notFound, got \(error).") }
    }
  }

  func testRepeatedOpenWriteAndExplicitCloseLoop() async throws {
    let url = try makeCatalogURL()
    for index in 0..<3 {
      let store = try SQLiteCatalogStore(catalogURL: url)
      let asset = try makeAsset(filename: "loop-\(index).jpg")
      _ = try await store.upsertAsset(.init(asset: asset))
      try await store.close()
    }
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
    let recipe = makeRecipe(assetID: asset.id, revision: 4)
    let job = makeJob(state: .queued, updatedAt: 1)
    _ = try await store.saveRecipe(.init(recipe: recipe))
    _ = try await store.enqueue(.init(job: job))
    let sourceIntegrity = try await store.checkIntegrity(.init()).isValid
    let backupResult = try await store.backup(.init(destinationURL: backupURL)).destinationURL
    XCTAssertEqual(sourceIntegrity, true)
    XCTAssertEqual(backupResult, backupURL)

    let restored = try SQLiteCatalogStore(catalogURL: backupURL)
    let restoredAsset = try await restored.fetchAsset(.init(assetID: asset.id)).asset
    let restoredRecipe = try await restored.latestRecipe(.init(assetID: asset.id)).recipe
    let restoredJobs = try await restored.list(.init()).jobs
    let restoredIntegrity = try await restored.checkIntegrity(.init()).isValid
    XCTAssertEqual(restoredAsset, asset)
    XCTAssertEqual(restoredRecipe, recipe)
    XCTAssertEqual(restoredJobs, [job])
    XCTAssertEqual(restoredIntegrity, true)
  }

  func testBackupFailureDoesNotReplaceAnExistingDestination() async throws {
    let catalogURL = try makeCatalogURL()
    let destinationURL = catalogURL.deletingLastPathComponent().appendingPathComponent(
      "existing.sqlite")
    let originalDestination = Data([0xAA, 0xBB])
    try originalDestination.write(to: destinationURL)
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    do {
      _ = try await store.backup(.init(destinationURL: destinationURL))
      XCTFail("Expected the existing backup destination to be rejected.")
    } catch let error as CatalogStoreError {
      guard case .invalidRequest = error else {
        return XCTFail("Expected an invalid request error, got \(error).")
      }
    }
    XCTAssertEqual(try Data(contentsOf: destinationURL), originalDestination)
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

  func testPersistedBookmarkSurvivesReopenAndStaleRenewalIsStored() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("bookmark-source.jpg")
    try Data([0x01]).write(to: sourceURL)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let asset = try makeAsset(filename: "bookmark-source.jpg", sourceURL: sourceURL)
    var firstStore: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await firstStore!.upsertAsset(.init(asset: asset))
    let original = try await firstStore!.createBookmark(forAssetID: asset.id)
    try await firstStore!.close()
    firstStore = nil

    let secondStore = try SQLiteCatalogStore(catalogURL: catalogURL)
    let resolved = try await secondStore.resolveBookmark(forAssetID: asset.id)
    XCTAssertEqual(resolved.url.standardizedFileURL, sourceURL.standardizedFileURL)
    let reopenedBookmark = try await secondStore.bookmarkData(forAssetID: asset.id)
    XCTAssertEqual(reopenedBookmark, original)

    let renewed = Data([0xFF, 0xAA])
    let forcedResult = ResolvedSecurityScopedBookmark(
      url: sourceURL, isStale: true, renewedData: renewed)
    _ = try await secondStore.resolveBookmarkForTesting(forAssetID: asset.id) { _ in forcedResult }
    let renewedBookmark = try await secondStore.bookmarkData(forAssetID: asset.id)
    XCTAssertEqual(renewedBookmark, renewed)
  }

  func testRelinkStoresBookmarkWhenTheNewSourceIsAvailable() async throws {
    let directory = try makeTemporaryDirectory()
    let originalURL = directory.appendingPathComponent("original.jpg")
    let relinkedURL = directory.appendingPathComponent("relinked.jpg")
    try Data([0x01]).write(to: originalURL)
    try Data([0x02]).write(to: relinkedURL)
    let store = try SQLiteCatalogStore(
      catalogURL: directory.appendingPathComponent("catalog.sqlite"))
    let asset = try makeAsset(filename: "original.jpg", sourceURL: originalURL)
    _ = try await store.upsertAsset(.init(asset: asset))
    _ = try await store.relinkAsset(
      .init(
        assetID: asset.id,
        sourceURL: relinkedURL,
        filename: "relinked.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: try fingerprint(character: "c")
      )
    )
    let bookmark = try await store.bookmarkData(forAssetID: asset.id)
    XCTAssertNotNil(bookmark)
    let resolved = try await store.resolveBookmark(forAssetID: asset.id)
    XCTAssertEqual(resolved.url.standardizedFileURL, relinkedURL.standardizedFileURL)
  }

  func testRelinkBookmarkFailureDeletesTheOldBookmark() async throws {
    let directory = try makeTemporaryDirectory()
    let originalURL = directory.appendingPathComponent("original.jpg")
    try Data([0x01]).write(to: originalURL)
    let store = try SQLiteCatalogStore(
      catalogURL: directory.appendingPathComponent("catalog.sqlite"))
    let asset = try makeAsset(filename: "original.jpg", sourceURL: originalURL)
    _ = try await store.upsertAsset(.init(asset: asset))
    _ = try await store.createBookmark(forAssetID: asset.id)

    _ = try await store.relinkAssetForTesting(
      .init(
        assetID: asset.id,
        sourceURL: URL(fileURLWithPath: "/tmp/unavailable.jpg"),
        filename: "unavailable.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: try fingerprint(character: "c")
      ),
      bookmarkCreator: { _ in
        throw CatalogStoreError.bookmark(operation: "test", message: "no scope")
      }
    )
    let bookmark = try await store.bookmarkData(forAssetID: asset.id)
    XCTAssertNil(bookmark)
  }

  func testUnknownReservedColorLabelSurvivesReopen() async throws {
    let catalogURL = try makeCatalogURL()
    let asset = try makeAsset(
      filename: "unknown-color.jpg", colorLabel: .unknown("red"))
    var firstStore: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await firstStore!.upsertAsset(.init(asset: asset))
    try await firstStore!.close()
    firstStore = nil
    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let fetched = try await reopened.fetchAsset(.init(assetID: asset.id)).asset
    XCTAssertEqual(fetched?.colorLabel, .unknown("red"))
  }

  func testStaleBookmarkRenewalBracketsScopeAccess() throws {
    let url = URL(fileURLWithPath: "/tmp/renewed.jpg")
    var started = 0
    var stopped = 0
    let renewed = try SecurityScopedBookmarkStore.renewForTesting(
      url: url,
      access: {
        started += 1
        return true
      },
      stopAccess: { stopped += 1 },
      create: { _ in Data([0x01]) }
    )
    XCTAssertEqual(renewed, Data([0x01]))
    XCTAssertEqual(started, 1)
    XCTAssertEqual(stopped, 1)
  }

  func testFutureSchemaVersionIsRejectedWithoutChangingTheCatalog() throws {
    let catalogURL = try makeCatalogURL()
    let database = try openWritableDatabase(catalogURL)
    try execute(database, "PRAGMA journal_mode=DELETE; PRAGMA user_version=8;")
    sqlite3_close_v2(database)

    XCTAssertThrowsError(try SQLiteCatalogStore(catalogURL: catalogURL))
    let reopened = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(reopened) }
    XCTAssertEqual(try scalarInt(reopened, "PRAGMA user_version;"), 8)
    XCTAssertEqual(try scalarString(reopened, "PRAGMA journal_mode;"), "delete")
  }

  func testMigrationRollsBackAndExistingVersionOneSchemaIsValidated() throws {
    let migrationURL = try makeCatalogURL()
    let migrationDatabase = try openWritableDatabase(migrationURL)
    try execute(
      migrationDatabase, "CREATE TABLE assets (id TEXT PRIMARY KEY); PRAGMA user_version=0;")
    sqlite3_close_v2(migrationDatabase)
    XCTAssertThrowsError(try SQLiteCatalogStore(catalogURL: migrationURL))
    let afterFailure = try openDatabase(migrationURL)
    defer { sqlite3_close_v2(afterFailure) }
    XCTAssertEqual(try scalarInt(afterFailure, "PRAGMA user_version;"), 0)
    XCTAssertEqual(
      try scalarInt(
        afterFailure, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'edit_recipes';"), 0)

    let invalidV1URL = try makeCatalogURL()
    let invalidV1Database = try openWritableDatabase(invalidV1URL)
    try execute(
      invalidV1Database, "CREATE TABLE assets (id TEXT PRIMARY KEY); PRAGMA user_version=1;")
    sqlite3_close_v2(invalidV1Database)
    XCTAssertThrowsError(try SQLiteCatalogStore(catalogURL: invalidV1URL))
  }

  func testVersionOneSchemaRejectsWrongColumnTypeNullabilityAndPrimaryKey() throws {
    let cases = [
      (
        "type",
        versionOneSchema.replacingOccurrences(
          of: "type_identifier TEXT,", with: "type_identifier BLOB,")
      ),
      (
        "nullability",
        versionOneSchema.replacingOccurrences(
          of: "capture_ms INTEGER,", with: "capture_ms INTEGER NOT NULL,")
      ),
      (
        "primary key",
        versionOneSchema.replacingOccurrences(
          of: "CREATE TABLE catalog_jobs (\n  id TEXT PRIMARY KEY,",
          with: "CREATE TABLE catalog_jobs (\n  id TEXT UNIQUE,")
      ),
      (
        "default",
        versionOneSchema.replacingOccurrences(
          of: "bookmark BLOB NOT NULL,\n  updated_ms INTEGER NOT NULL",
          with: "bookmark BLOB NOT NULL,\n  updated_ms INTEGER NOT NULL DEFAULT 0")
      ),
    ]

    for (name, schema) in cases {
      try assertVersionOneSchemaRejected(schema, name: name, ftsAvailabilityOverride: false)
    }
  }

  func testVersionOneSchemaRejectsWrongCheckAndCompositePrimaryKey() throws {
    let cases = [
      (
        "check",
        versionOneSchema.replacingOccurrences(
          of: "CHECK (rating BETWEEN 0 AND 5)", with: "CHECK (rating BETWEEN 0 AND 6)")
      ),
      (
        "composite primary key",
        versionOneSchema.replacingOccurrences(
          of: "PRIMARY KEY (asset_id, revision)", with: "PRIMARY KEY (revision, asset_id)")
      ),
    ]

    for (name, schema) in cases {
      try assertVersionOneSchemaRejected(schema, name: name, ftsAvailabilityOverride: false)
    }
  }

  func testVersionOneSchemaRejectsWrongIndexDefinition() throws {
    let schema = versionOneSchema.replacingOccurrences(
      of: "CREATE INDEX assets_import_ms_index ON assets(import_ms);",
      with: "CREATE INDEX assets_import_ms_index ON assets(import_ms DESC);")
    try assertVersionOneSchemaRejected(
      schema, name: "descending import index", ftsAvailabilityOverride: false)
  }

  func testVersionOneSchemaRejectsNonFTS5SearchTable() throws {
    let schema =
      versionOneSchema + """

        CREATE TABLE asset_search (
          asset_id TEXT,
          filename TEXT,
          type_identifier TEXT,
          source_url TEXT
        );
        """
    try assertVersionOneSchemaRejected(
      schema, name: "ordinary search table", ftsAvailabilityOverride: true)
  }

  func testVersionOneSchemaRequiresFTS5SearchTableWhenConfigured() throws {
    try assertVersionOneSchemaRejected(
      versionOneSchema, name: "missing FTS5 search table", ftsAvailabilityOverride: true)
  }

  func testReadOnlyCatalogAndDuplicateJobConstraintReturnTypedSQLiteErrors() async throws {
    let catalogURL = try makeCatalogURL()
    var writableStore: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    try await writableStore!.close()
    writableStore = nil
    let catalogDirectory = catalogURL.deletingLastPathComponent()
    for fileURL in try FileManager.default.contentsOfDirectory(
      at: catalogDirectory, includingPropertiesForKeys: nil)
    {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: catalogDirectory.path)
    addTeardownBlock {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: catalogDirectory.path)
      for fileURL
        in (try? FileManager.default.contentsOfDirectory(
          at: catalogDirectory, includingPropertiesForKeys: nil)) ?? []
      {
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
      }
    }
    let readOnlyStore = try SQLiteCatalogStore(catalogURL: catalogURL)
    do {
      _ = try await readOnlyStore.upsertAsset(.init(asset: makeAsset(filename: "read-only.jpg")))
      XCTFail("Expected a write to the read-only catalog to fail.")
    } catch let error as CatalogStoreError {
      guard case .sqlite = error else {
        return XCTFail("Expected a typed SQLite error, got \(error).")
      }
    }

    let duplicateStore = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let job = makeJob(state: .queued, updatedAt: 1)
    _ = try await duplicateStore.enqueue(.init(job: job))
    do {
      _ = try await duplicateStore.enqueue(.init(job: job))
      XCTFail("Expected a duplicate constraint failure.")
    } catch let error as CatalogStoreError {
      guard case .sqlite(let operation, let code, _, _) = error else {
        return XCTFail("Expected a typed SQLite error, got \(error).")
      }
      XCTAssertEqual(operation, "job.enqueue.step")
      XCTAssertEqual(code, SQLITE_CONSTRAINT)
    }
  }

  func testBackupFusesStepFinishCloseAndFilesystemCleanupFailures() async throws {
    let catalogURL = try makeCatalogURL()
    let destinationURL = catalogURL.deletingLastPathComponent().appendingPathComponent(
      "failed-backup.sqlite")
    let store = try SQLiteCatalogStore(
      catalogURL: catalogURL,
      ftsAvailabilityOverride: nil,
      backupFaults: SQLiteCatalogBackupFaults(
        stepCode: SQLITE_IOERR,
        finishCode: SQLITE_BUSY,
        closeCode: SQLITE_BUSY,
        filesystemCleanupMessage: "forced filesystem cleanup failure"
      )
    )

    do {
      _ = try await store.backup(.init(destinationURL: destinationURL))
      XCTFail("Expected the injected backup failures.")
    } catch let error as CatalogStoreError {
      guard case .cleanup(let operation, let primaryError, let cleanupError) = error else {
        return XCTFail("Expected a fused cleanup error, got \(error).")
      }
      XCTAssertEqual(operation, "catalog.backup")
      XCTAssertTrue(primaryError.contains("catalog.backup.step"))
      XCTAssertTrue(cleanupError.contains("catalog.backup.finish"))
      XCTAssertTrue(cleanupError.contains("catalog.backup.close"))
      XCTAssertTrue(cleanupError.contains("forced filesystem cleanup failure"))
    }
  }

  func testNormalizedAssetRowsRejectMalformedData() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    let id = UUID()
    let database = try openWritableDatabase(catalogURL)
    try execute(
      database,
      """
      INSERT INTO assets (
        id, source_url, filename, type_identifier, fingerprint_json, import_ms,
        capture_ms, dimensions_json, rating, color_label, is_missing
      ) VALUES (
        '\(id.uuidString.lowercased())', 'file:///tmp/malformed.jpg', 'malformed.jpg',
        NULL, X'00', 0, NULL, NULL, 1, NULL, 0
      );
      """
    )
    sqlite3_close_v2(database)
    do {
      _ = try await store.fetchAsset(.init(assetID: id))
      XCTFail("Expected a typed decoding error for malformed normalized data.")
    } catch let error as CatalogStoreError {
      guard case .decoding = error else {
        return XCTFail("Expected a decoding error, got \(error).")
      }
    }
  }

  func testAssetReadsUseNormalizedColumnsWithoutAFullAssetJSONCopy() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    let asset = try makeAsset(filename: "before.jpg")
    _ = try await store.upsertAsset(.init(asset: asset))
    let database = try openWritableDatabase(catalogURL)
    try execute(
      database,
      "UPDATE assets SET filename = 'after.jpg' WHERE id = '\(asset.id.uuidString.lowercased())';"
    )
    let storedAssetJSONColumnCount = try scalarInt(
      database, "SELECT COUNT(*) FROM pragma_table_info('assets') WHERE name = 'asset_json';")
    sqlite3_close_v2(database)

    let fetched = try await store.fetchAsset(.init(assetID: asset.id)).asset
    XCTAssertEqual(fetched?.filename, "after.jpg")
    XCTAssertEqual(storedAssetJSONColumnCount, 0)
  }

  func testListOrdersPaginationAndMissingIDs() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let first = try makeAsset(filename: "bravo.jpg", importDate: 10, captureDate: 20)
    let second = try makeAsset(filename: "alpha.jpg", importDate: 20, captureDate: 10)
    _ = try await store.upsertAsset(.init(asset: first))
    _ = try await store.upsertAsset(.init(asset: second))

    let expected: [CatalogAssetOrder: [UUID]] = [
      .importDateAscending: [first.id, second.id],
      .importDateDescending: [second.id, first.id],
      .captureDateAscending: [second.id, first.id],
      .captureDateDescending: [first.id, second.id],
      .filenameAscending: [second.id, first.id],
      .filenameDescending: [first.id, second.id],
    ]
    for (order, ids) in expected {
      let actual = try await store.listAssets(.init(order: order)).assets.map(\.id)
      XCTAssertEqual(actual, ids)
    }
    let secondPage = try await store.listAssets(.init(limit: 1, offset: 1)).assets.map(\.id)
    XCTAssertEqual(secondPage, [first.id])
    await assertInvalidRequest { try await store.listAssets(.init(offset: -1)) }
    await assertInvalidRequest { try await store.listAssets(.init(limit: 0)) }
    let absentAsset = try await store.fetchAsset(.init(assetID: UUID())).asset
    XCTAssertNil(absentAsset)
    await assertNotFound {
      try await store.markAssetMissing(.init(assetID: UUID(), isMissing: true))
    }
    let missingFingerprint = try fingerprint(character: "a")
    await assertNotFound {
      try await store.relinkAsset(
        .init(
          assetID: UUID(), sourceURL: URL(fileURLWithPath: "/tmp/missing.jpg"),
          filename: "missing.jpg", typeIdentifier: nil, fingerprint: missingFingerprint
        )
      )
    }
  }

  func testLatestRecipeSelectsTheHighestRevision() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let asset = try makeAsset(filename: "recipe.jpg")
    _ = try await store.upsertAsset(.init(asset: asset))
    let early = makeRecipe(assetID: asset.id, revision: 1)
    let latest = makeRecipe(assetID: asset.id, revision: 3)
    _ = try await store.saveRecipe(.init(recipe: early))
    _ = try await store.saveRecipe(.init(recipe: latest))
    let result = try await store.latestRecipe(.init(assetID: asset.id)).recipe
    XCTAssertEqual(result, latest)
  }

  func testConcurrentActorCallsRemainDurable() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let assets = try (0..<20).map { index in
      try makeAsset(filename: "concurrent-\(index).jpg", importDate: TimeInterval(index))
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for asset in assets {
        group.addTask { _ = try await store.upsertAsset(.init(asset: asset)) }
      }
      try await group.waitForAll()
    }
    let storedAssets = try await store.listAssets(.init()).assets
    XCTAssertEqual(storedAssets.count, assets.count)
  }

  private func makeCatalogURL() throws -> URL {
    try makeTemporaryDirectory().appendingPathComponent("catalog.sqlite")
  }

  private func assertVersionOneSchemaRejected(
    _ schema: String,
    name: String,
    ftsAvailabilityOverride: Bool
  ) throws {
    let catalogURL = try makeCatalogURL()
    let database = try openWritableDatabase(catalogURL)
    do {
      try execute(database, schema + "\nPRAGMA user_version=1;")
      XCTAssertEqual(sqlite3_close_v2(database), SQLITE_OK)
    } catch {
      _ = sqlite3_close_v2(database)
      throw error
    }
    XCTAssertThrowsError(
      try SQLiteCatalogStore(
        catalogURL: catalogURL, ftsAvailabilityOverride: ftsAvailabilityOverride),
      "Expected rejection for malformed schema case: \(name)"
    ) { error in
      guard case .unsupported = error as? CatalogStoreError else {
        return XCTFail("Expected an unsupported schema error for \(name), got \(error).")
      }
    }
  }

  private var versionOneSchema: String {
    """
    CREATE TABLE assets (
      id TEXT PRIMARY KEY,
      source_url TEXT NOT NULL,
      filename TEXT NOT NULL,
      type_identifier TEXT,
      fingerprint_json BLOB NOT NULL,
      import_ms INTEGER NOT NULL,
      capture_ms INTEGER,
      dimensions_json BLOB,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 0 AND 5),
      color_label BLOB,
      is_missing INTEGER NOT NULL CHECK (is_missing IN (0, 1))
    );
    CREATE INDEX assets_import_ms_index ON assets(import_ms);
    CREATE INDEX assets_capture_ms_index ON assets(capture_ms);
    CREATE INDEX assets_filename_index ON assets(filename COLLATE NOCASE);
    CREATE TABLE edit_recipes (
      asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
      revision INTEGER NOT NULL,
      date_ms INTEGER NOT NULL,
      recipe_json BLOB NOT NULL,
      PRIMARY KEY (asset_id, revision)
    );
    CREATE TABLE catalog_jobs (
      id TEXT PRIMARY KEY,
      created_ms INTEGER NOT NULL,
      updated_ms INTEGER NOT NULL,
      job_json BLOB NOT NULL
    );
    CREATE INDEX catalog_jobs_updated_ms_index ON catalog_jobs(updated_ms, created_ms);
    CREATE TABLE asset_bookmarks (
      asset_id TEXT PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
      bookmark BLOB NOT NULL,
      updated_ms INTEGER NOT NULL
    );
    """
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
    captureDate: TimeInterval? = nil,
    sourceURL: URL? = nil,
    colorLabel: ColorLabel? = nil,
    rating: Int = 0
  ) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL ?? URL(fileURLWithPath: "/tmp/\(filename)"),
        filename: filename,
        typeIdentifier: typeIdentifier,
        fingerprint: try fingerprint(character: "b"),
        importDate: Date(timeIntervalSince1970: importDate),
        captureDate: captureDate.map { Date(timeIntervalSince1970: $0) },
        pixelDimensions: nil,
        rating: rating,
        colorLabel: colorLabel
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

  private func makeRecipe(assetID: UUID, revision: UInt64) -> EditRecipe {
    EditRecipe(
      assetID: assetID,
      revision: revision,
      date: Date(timeIntervalSince1970: TimeInterval(revision)),
      pins: EnginePins(
        decoderIdentifier: "com.apple.ciraw",
        decoderVersion: "1",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
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

  private func openWritableDatabase(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(
        url.path,
        &database,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nil
      ) == SQLITE_OK,
      let database
    else {
      throw NSError(domain: "CatalogCoreTests", code: 2)
    }
    return database
  }

  private func execute(_ database: OpaquePointer, _ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    defer { if let message { sqlite3_free(message) } }
    guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
      throw NSError(domain: "CatalogCoreTests", code: 3)
    }
  }

  private func scalarString(_ database: OpaquePointer, _ sql: String) throws -> String {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw NSError(domain: "CatalogCoreTests", code: 4)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
    else {
      throw NSError(domain: "CatalogCoreTests", code: 5)
    }
    return String(cString: value)
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw NSError(domain: "CatalogCoreTests", code: 6)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "CatalogCoreTests", code: 7)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func assertInvalidRequest<T>(
    _ operation: @escaping () async throws -> T
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected an invalid request error.")
    } catch let error as CatalogStoreError {
      guard case .invalidRequest = error else {
        return XCTFail("Expected an invalid request error, got \(error).")
      }
    } catch {
      XCTFail("Expected CatalogStoreError, got \(error).")
    }
  }

  private func assertNotFound<T>(
    _ operation: @escaping () async throws -> T
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected a not-found error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected a not-found error, got \(error).")
      }
    } catch {
      XCTFail("Expected CatalogStoreError, got \(error).")
    }
  }
}
