// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SQLite3
import XCTest

@testable import CatalogCore

final class FolderCatalogTests: XCTestCase {
  func testFolderHierarchyAndAssetAssignmentSurviveReopenWithoutChangingSource() async throws {
    let directory = try makeTemporaryDirectory()
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let source = Data([0x01, 0x02, 0x03, 0x04])
    try source.write(to: sourceURL)
    let asset = try makeAsset(sourceURL: sourceURL)
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store.upsertAsset(.init(asset: asset))

    let root = try XCTUnwrap(
      LibraryFolder(
        name: "2026",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
    )
    let child = try XCTUnwrap(
      LibraryFolder(
        name: "Sydney",
        parentID: root.id,
        createdAt: Date(timeIntervalSince1970: 11),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )
    _ = try await store.saveFolder(.init(folder: root))
    _ = try await store.saveFolder(.init(folder: child))
    _ = try await store.setAssetFolder(.init(assetID: asset.id, folderID: child.id))

    let folders = try await store.listFolders(.init()).folders
    let assignedFolderID = try await store.listAssetFolder(.init(assetID: asset.id)).folderID
    let folderAssets = try await store.listFolderAssets(.init(folderID: child.id)).assets
    XCTAssertEqual(folders, [root, child])
    XCTAssertEqual(assignedFolderID, child.id)
    XCTAssertEqual(folderAssets, [asset])
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)

    try await store.close()
    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedFolders = try await reopened.listFolders(.init()).folders
    let reopenedFolderID = try await reopened.listAssetFolder(.init(assetID: asset.id)).folderID
    XCTAssertEqual(reopenedFolders, [root, child])
    XCTAssertEqual(reopenedFolderID, child.id)
    XCTAssertEqual(try Data(contentsOf: sourceURL), source)
  }

  func testFolderTreeRejectsMissingParentsCyclesDuplicateSiblingsAndUnsafeDelete() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let asset = try makeAsset()
    _ = try await store.upsertAsset(.init(asset: asset))
    let root = try XCTUnwrap(LibraryFolder(name: "Trips"))
    _ = try await store.saveFolder(.init(folder: root))

    let missingParent = try XCTUnwrap(LibraryFolder(name: "Missing", parentID: UUID()))
    await assertInvalidRequest {
      _ = try await store.saveFolder(.init(folder: missingParent))
    }

    let duplicate = try XCTUnwrap(LibraryFolder(id: UUID(), name: " trips "))
    await assertInvalidRequest {
      _ = try await store.saveFolder(.init(folder: duplicate))
    }

    let child = try XCTUnwrap(LibraryFolder(name: "Sydney", parentID: root.id))
    _ = try await store.saveFolder(.init(folder: child))
    let cycle = try XCTUnwrap(LibraryFolder(id: root.id, name: root.name, parentID: child.id))
    await assertInvalidRequest {
      _ = try await store.saveFolder(.init(folder: cycle))
    }

    await assertInvalidRequest {
      _ = try await store.deleteFolder(.init(folderID: root.id))
    }
    _ = try await store.setAssetFolder(.init(assetID: asset.id, folderID: child.id))
    await assertInvalidRequest {
      _ = try await store.deleteFolder(.init(folderID: child.id))
    }

    _ = try await store.setAssetFolder(.init(assetID: asset.id, folderID: nil))
    _ = try await store.deleteFolder(.init(folderID: child.id))
    _ = try await store.deleteFolder(.init(folderID: root.id))
    let folders = try await store.listFolders(.init()).folders
    XCTAssertTrue(folders.isEmpty)
  }

  func testClearingFolderAssignmentLeavesAssetInCatalog() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let asset = try makeAsset()
    _ = try await store.upsertAsset(.init(asset: asset))
    let folder = try XCTUnwrap(LibraryFolder(name: "Unfiled later"))
    _ = try await store.saveFolder(.init(folder: folder))
    _ = try await store.setAssetFolder(.init(assetID: asset.id, folderID: folder.id))
    _ = try await store.setAssetFolder(.init(assetID: asset.id, folderID: nil))

    let assignedFolderID = try await store.listAssetFolder(.init(assetID: asset.id)).folderID
    let fetchedAsset = try await store.fetchAsset(.init(assetID: asset.id)).asset
    XCTAssertNil(assignedFolderID)
    XCTAssertEqual(fetchedAsset, asset)
  }

  private func assertInvalidRequest(
    _ operation: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await operation()
      XCTFail("Expected an invalid request.", file: file, line: line)
    } catch let error as CatalogStoreError {
      guard case .invalidRequest = error else {
        XCTFail("Expected an invalid request, got \(error).", file: file, line: line)
        return
      }
    } catch {
      XCTFail("Expected a catalog invalid request, got \(error).", file: file, line: line)
    }
  }

  private func makeCatalogURL() throws -> URL {
    try makeTemporaryDirectory().appendingPathComponent("catalog.sqlite")
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "PhotoSuite-FolderCatalogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func makeAsset(sourceURL: URL? = nil) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL ?? URL(fileURLWithPath: "/tmp/folder-source.jpg"),
        filename: "folder-source.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64), byteCount: 4, modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil
      )
    )
  }
}
