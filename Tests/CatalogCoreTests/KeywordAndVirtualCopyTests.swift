// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class KeywordAndVirtualCopyTests: XCTestCase {
  func testHierarchicalKeywordsPersistAssignmentsAndProtectParentNodes() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let source = Data([0x0A, 0x0B, 0x0C])
    try source.write(to: sourceURL)
    let asset = try makeAsset(sourceURL: sourceURL)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store.upsertAsset(.init(asset: asset))

    let root = try XCTUnwrap(
      KeywordNode(
        name: "People",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
    )
    let child = try XCTUnwrap(
      KeywordNode(
        name: "Portraits",
        parentID: root.id,
        createdAt: Date(timeIntervalSince1970: 11),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )
    _ = try await store.saveKeywordNode(.init(keyword: root))
    _ = try await store.saveKeywordNode(.init(keyword: child))
    _ = try await store.setAssetKeywords(
      .init(assetID: asset.id, keywordIDs: [child.id]))

    let listedResult = try await store.listKeywordNodes(.init())
    XCTAssertEqual(listedResult.keywords, [root, child])
    let assignedResult = try await store.listAssetKeywords(.init(assetID: asset.id))
    let assigned = assignedResult.keywords
    XCTAssertEqual(assigned, [child])
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    try await store.close()
    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedAssignedResult = try await reopened.listAssetKeywords(.init(assetID: asset.id))
    XCTAssertEqual(reopenedAssignedResult.keywords, [child])
    do {
      _ = try await reopened.deleteKeywordNode(.init(keywordID: root.id))
      XCTFail("Expected a parent keyword with children to be protected.")
    } catch let error as CatalogStoreError {
      guard case .invalidRequest = error else {
        return XCTFail("Expected an invalid request, got \(error).")
      }
    }
  }

  func testVirtualCopyStoresIndependentRecipeReferenceAndPreservesBaseRecipe() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let source = Data([0x11, 0x12, 0x13])
    try source.write(to: sourceURL)
    let asset = try makeAsset(sourceURL: sourceURL)
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
    let baseRecipe = EditRecipe(
      assetID: asset.id,
      revision: 1,
      date: Date(timeIntervalSince1970: 20),
      pins: pins
    )
    _ = try await store.saveRecipe(.init(recipe: baseRecipe))
    let copy = try XCTUnwrap(
      VirtualCopy(
        sourceAssetID: asset.id,
        name: "Monochrome",
        createdAt: Date(timeIntervalSince1970: 21),
        updatedAt: Date(timeIntervalSince1970: 21)
      )
    )
    _ = try await store.saveVirtualCopy(.init(virtualCopy: copy))
    let copyRecipe = EditRecipe(
      assetID: asset.id,
      virtualCopyID: copy.id,
      revision: 1,
      date: Date(timeIntervalSince1970: 22),
      pins: pins
    )
    _ = try await store.saveRecipe(.init(recipe: copyRecipe))

    let listedCopiesResult = try await store.listVirtualCopies(.init())
    XCTAssertEqual(listedCopiesResult.virtualCopies, [copy])
    let baseLatestResult = try await store.latestRecipe(.init(assetID: asset.id))
    XCTAssertEqual(baseLatestResult.recipe, baseRecipe)
    let copyLatestResult = try await store.latestRecipe(
      .init(assetID: asset.id, virtualCopyID: copy.id))
    XCTAssertEqual(copyLatestResult.recipe, copyRecipe)
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    try await store.close()
    let reopened = try SQLiteCatalogStore(
      catalogURL: directory.appendingPathComponent("catalog.sqlite"))
    let reopenedLatestResult = try await reopened.latestRecipe(
      .init(assetID: asset.id, virtualCopyID: copy.id))
    XCTAssertEqual(reopenedLatestResult.recipe, copyRecipe)
    _ = try await reopened.deleteVirtualCopy(.init(virtualCopyID: copy.id))
    let remainingCopiesResult = try await reopened.listVirtualCopies(.init())
    XCTAssertTrue(remainingCopiesResult.virtualCopies.isEmpty)
  }

  func testSchemaVersionFourMigrationCreatesKeywordAndVirtualCopyTables() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    try await store.close()
    let database = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 7)
    XCTAssertEqual(
      try scalarInt(
        database,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'keyword_nodes';"
      ),
      1
    )
    XCTAssertEqual(
      try scalarInt(
        database,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'virtual_copies';"
      ),
      1
    )
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

  private func makeAsset(sourceURL: URL? = nil) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL ?? URL(fileURLWithPath: "/tmp/keyword-source.jpg"),
        filename: "keyword-source.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "b", count: 64), byteCount: 3, modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil
      )
    )
  }

  private func openDatabase(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let database
    else {
      throw NSError(domain: "KeywordAndVirtualCopyTests", code: 1)
    }
    return database
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement
    else {
      throw NSError(domain: "KeywordAndVirtualCopyTests", code: 2)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "KeywordAndVirtualCopyTests", code: 3)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
