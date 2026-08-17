// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class FaceCatalogTests: XCTestCase {
  func testFacesPersistSearchAndDeleteWithoutChangingSourceBytes() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("portrait.jpg")
    let source = Data([0x50, 0x68, 0x6F, 0x74, 0x6F, 0x53, 0x75, 0x69, 0x74, 0x65])
    try source.write(to: sourceURL)
    let asset = try makeAsset(sourceURL: sourceURL)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store.upsertAsset(.init(asset: asset))

    let region = try XCTUnwrap(FaceRegion(x: 0.2, y: 0.1, width: 0.25, height: 0.4))
    let face = try XCTUnwrap(
      PhotoFace(
        assetID: asset.id,
        region: region,
        label: "  Alex  ",
        confidence: 0.8,
        source: .vision,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )
    let unlabeled = try XCTUnwrap(
      PhotoFace(
        assetID: asset.id,
        region: try XCTUnwrap(FaceRegion(x: 0.6, y: 0.1, width: 0.2, height: 0.3)),
        source: .vision,
        createdAt: Date(timeIntervalSince1970: 12),
        updatedAt: Date(timeIntervalSince1970: 12)
      )
    )

    let savedFace = try await store.saveFace(.init(face: face)).face
    let savedUnlabeled = try await store.saveFace(.init(face: unlabeled)).face
    let listedFaces = try await store.listFaces(.init(assetID: asset.id)).faces
    let searchedFaces = try await store.searchFaces(.init(query: " alex ")).faces
    let unknownFaces = try await store.searchFaces(.init(query: "unknown")).faces
    XCTAssertEqual(savedFace, face)
    XCTAssertEqual(savedUnlabeled, unlabeled)
    XCTAssertEqual(listedFaces, [face, unlabeled])
    XCTAssertEqual(searchedFaces, [face])
    XCTAssertTrue(unknownFaces.isEmpty)
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    try await store.close()
    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedFaces = try await reopened.listFaces(.init(assetID: asset.id)).faces
    XCTAssertEqual(reopenedFaces, [face, unlabeled])
    _ = try await reopened.deleteFace(.init(faceID: face.id))
    let remainingFaces = try await reopened.listFaces(.init(assetID: asset.id)).faces
    XCTAssertEqual(remainingFaces, [unlabeled])
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)
  }

  func testFaceSaveRequiresExistingAssetAndSchemaIncludesFaceAnnotations() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    let face = try XCTUnwrap(
      PhotoFace(
        assetID: UUID(),
        region: try XCTUnwrap(FaceRegion(x: 0, y: 0, width: 0.2, height: 0.2))
      )
    )

    do {
      _ = try await store.saveFace(.init(face: face))
      XCTFail("Expected a missing asset error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected notFound, got (error).")
      }
    }

    let database = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(database) }
    XCTAssertEqual(try scalarInt(database, "PRAGMA user_version;"), 7)
    XCTAssertEqual(
      try scalarInt(
        database,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'face_annotations';"
      ),
      1
    )
  }

  func testFaceSearchTrimsBlankQueryAndRejectsDeleteForUnknownFace() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let blankSearch = try await store.searchFaces(.init(query: "   ")).faces
    XCTAssertTrue(blankSearch.isEmpty)

    do {
      _ = try await store.deleteFace(.init(faceID: UUID()))
      XCTFail("Expected a missing face error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected notFound, got (error).")
      }
    }
  }

  func testVersionSixCatalogMigratesFaceAnnotationTable() async throws {
    let catalogURL = try makeCatalogURL()
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    try await store.close()

    let database = try openWritableDatabase(catalogURL)
    try execute(database, "DROP TABLE face_annotations; PRAGMA user_version=6;")
    XCTAssertEqual(sqlite3_close_v2(database), SQLITE_OK)

    _ = try SQLiteCatalogStore(catalogURL: catalogURL)
    let migrated = try openDatabase(catalogURL)
    defer { sqlite3_close_v2(migrated) }
    XCTAssertEqual(try scalarInt(migrated, "PRAGMA user_version;"), 7)
    XCTAssertEqual(
      try scalarInt(
        migrated,
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'face_annotations';"
      ),
      1
    )
  }

  private func makeCatalogURL() throws -> URL {
    try makeTemporaryDirectory().appendingPathComponent("catalog.sqlite")
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-FaceCatalogTests-(UUID().uuidString)", isDirectory: true)
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
        fingerprint: try XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64), byteCount: 10, modificationDate: nil
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
    let code = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
    guard code == SQLITE_OK, let database else {
      throw NSError(domain: "FaceCatalogTests", code: Int(code))
    }
    return database
  }

  private func openWritableDatabase(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    let code = sqlite3_open_v2(
      url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
    guard code == SQLITE_OK, let database else {
      throw NSError(domain: "FaceCatalogTests", code: Int(code))
    }
    return database
  }

  private func execute(_ database: OpaquePointer, _ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    defer {
      if let errorMessage { sqlite3_free(errorMessage) }
    }
    guard code == SQLITE_OK else {
      throw NSError(domain: "FaceCatalogTests", code: Int(code))
    }
  }

  private func scalarInt(_ database: OpaquePointer, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw NSError(domain: "FaceCatalogTests", code: 1)
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw NSError(domain: "FaceCatalogTests", code: 2)
    }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
