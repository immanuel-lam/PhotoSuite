// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import CatalogCore

final class LibraryCatalogTests: XCTestCase {
  func testRegularCollectionPersistsMembershipOrderThroughReopenWithoutChangingSources()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let firstURL = directory.appendingPathComponent("first.jpg")
    let secondURL = directory.appendingPathComponent("second.jpg")
    let firstSource = Data([0x01, 0x02, 0x03])
    let secondSource = Data([0x04, 0x05, 0x06])
    try firstSource.write(to: firstURL)
    try secondSource.write(to: secondURL)
    let first = try makeAsset(id: UUID(), sourceURL: firstURL, filename: "first.jpg")
    let second = try makeAsset(id: UUID(), sourceURL: secondURL, filename: "second.jpg")
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")

    var store: SQLiteCatalogStore? = try SQLiteCatalogStore(catalogURL: catalogURL)
    _ = try await store!.upsertAsset(.init(asset: first))
    _ = try await store!.upsertAsset(.init(asset: second))
    let collection = try XCTUnwrap(
      PhotoCollection(
        name: "Selects",
        kind: .regular,
        assetIDs: [second.id, first.id],
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10)
      )
    )
    _ = try await store!.saveCollection(.init(collection: collection))
    let savedAssets = try await store!.listCollectionAssets(.init(collectionID: collection.id))
      .assets
    XCTAssertEqual(savedAssets.map(\.id), [second.id, first.id])
    XCTAssertEqual(try Data(contentsOf: firstURL), firstSource)
    XCTAssertEqual(try Data(contentsOf: secondURL), secondSource)

    try await store!.close()
    store = nil

    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let listed = try await reopened.listCollections(.init()).collections
    XCTAssertEqual(listed, [collection])
    let reopenedAssets = try await reopened.listCollectionAssets(.init(collectionID: collection.id))
      .assets
    XCTAssertEqual(reopenedAssets.map(\.id), [second.id, first.id])
    XCTAssertEqual(try Data(contentsOf: firstURL), firstSource)
    XCTAssertEqual(try Data(contentsOf: secondURL), secondSource)
  }

  func testSmartCollectionPersistsRulesAndEvaluatesLocally() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let matching = try makeAsset(
      filename: "travel.jpg",
      rating: 5,
      metadata: try XCTUnwrap(PhotoMetadata(keywords: ["Travel", "Sydney"]))
    )
    let nonMatching = try makeAsset(
      filename: "quiet.jpg",
      rating: 2,
      metadata: try XCTUnwrap(PhotoMetadata(keywords: ["quiet"]))
    )
    _ = try await store.upsertAsset(.init(asset: matching))
    _ = try await store.upsertAsset(.init(asset: nonMatching))
    let ratingRule = try XCTUnwrap(
      SmartCollectionRule(field: .rating, comparison: .greaterThanOrEqual, value: "4")
    )
    let keywordRule = try XCTUnwrap(
      SmartCollectionRule(field: .keyword, comparison: .contains, value: "travel")
    )
    let predicate = try XCTUnwrap(
      SmartCollectionPredicate(
        rules: [ratingRule, keywordRule],
        match: .all
      )
    )
    let collection = try XCTUnwrap(
      PhotoCollection(
        name: "Travel selects",
        kind: .smart,
        predicate: predicate,
        createdAt: Date(timeIntervalSince1970: 30),
        updatedAt: Date(timeIntervalSince1970: 30)
      )
    )
    _ = try await store.saveCollection(.init(collection: collection))

    let saved = try await store.listCollections(.init()).collections
    XCTAssertEqual(saved, [collection])
    XCTAssertEqual(saved[0].assetIDs, [])
    let assetsResult = try await store.listCollectionAssets(.init(collectionID: collection.id))
    let assets = assetsResult.assets
    XCTAssertEqual(assets.map(\.id), [matching.id])
  }

  func testStackPersistsRepresentativeAndOrderThroughReopen() async throws {
    let directory = try makeTemporaryDirectory()
    let first = try makeAsset(
      sourceURL: directory.appendingPathComponent("stack-first.jpg"), filename: "stack-first.jpg")
    let second = try makeAsset(
      sourceURL: directory.appendingPathComponent("stack-second.jpg"), filename: "stack-second.jpg")
    let third = try makeAsset(
      sourceURL: directory.appendingPathComponent("stack-third.jpg"), filename: "stack-third.jpg")
    let catalogURL = directory.appendingPathComponent("catalog.sqlite")
    let store = try SQLiteCatalogStore(catalogURL: catalogURL)
    for asset in [first, second, third] {
      _ = try await store.upsertAsset(.init(asset: asset))
    }
    let stack = try XCTUnwrap(
      PhotoStack(
        assetIDs: [second.id, first.id, third.id],
        representativeAssetID: first.id,
        isCollapsed: true,
        createdAt: Date(timeIntervalSince1970: 20),
        updatedAt: Date(timeIntervalSince1970: 20)
      )
    )
    _ = try await store.saveStack(.init(stack: stack))
    let listedStacks = try await store.listStacks(.init()).stacks
    XCTAssertEqual(listedStacks, [stack])

    let missingAssetStack = try XCTUnwrap(
      PhotoStack(
        id: stack.id,
        assetIDs: [second.id, UUID()],
        representativeAssetID: second.id,
        isCollapsed: false,
        createdAt: stack.createdAt,
        updatedAt: stack.updatedAt
      ))
    do {
      _ = try await store.saveStack(.init(stack: missingAssetStack))
      XCTFail("Expected a missing asset error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected a missing asset error, got \(error).")
      }
    }

    try await store.close()
    let reopened = try SQLiteCatalogStore(catalogURL: catalogURL)
    let reopenedStack = try await reopened.listStacks(.init()).stacks
    XCTAssertEqual(reopenedStack, [stack])
    let stackAssetsResult = try await reopened.listStackAssets(.init(stackID: stack.id))
    let stackAssets = stackAssetsResult.assets
    XCTAssertEqual(stackAssets.map(\.id), [second.id, first.id, third.id])
  }

  func testCollectionAndStackRejectMissingAssetsAndIncompatibleSmartMembership() async throws {
    let store = try SQLiteCatalogStore(catalogURL: try makeCatalogURL())
    let existing = try makeAsset(filename: "existing.jpg")
    _ = try await store.upsertAsset(.init(asset: existing))
    let regular = try XCTUnwrap(
      PhotoCollection(name: "Regular", kind: .regular, assetIDs: [existing.id, UUID()])
    )
    do {
      _ = try await store.saveCollection(.init(collection: regular))
      XCTFail("Expected a missing asset error.")
    } catch let error as CatalogStoreError {
      guard case .notFound = error else {
        return XCTFail("Expected a missing asset error, got \(error).")
      }
    }

    let filenameRule = try XCTUnwrap(
      SmartCollectionRule(field: .filename, comparison: .contains, value: "existing")
    )
    let smartPredicate = try XCTUnwrap(SmartCollectionPredicate(rules: [filenameRule]))
    XCTAssertNil(
      PhotoCollection(
        name: "Smart",
        kind: .smart,
        predicate: smartPredicate,
        assetIDs: [existing.id]
      )
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

  private func makeAsset(
    id: UUID = UUID(),
    sourceURL: URL? = nil,
    filename: String,
    rating: Int = 0,
    metadata: PhotoMetadata = .empty
  ) throws -> PhotoAsset {
    try XCTUnwrap(
      PhotoAsset(
        id: id,
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
        rating: rating,
        metadata: metadata
      )
    )
  }
}
