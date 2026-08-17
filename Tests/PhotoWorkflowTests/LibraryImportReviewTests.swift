// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

final class LibraryImportReviewTests: XCTestCase {
  func testReviewSelectsReadyMediaAndExposesStableOrder() throws {
    let first = makeMedia(id: "camera:1", filename: "IMG_0001.ARW")
    let second = makeMedia(id: "camera:2", filename: "IMG_0002.JPG", isRaw: false)

    let review = LibraryImportReview(
      deviceID: first.deviceID,
      mediaItems: [first, second]
    )

    XCTAssertEqual(review.items.map(\.id), ["camera:1", "camera:2"])
    XCTAssertEqual(review.selectedMediaItems.map(\.id), ["camera:1", "camera:2"])
    XCTAssertEqual(review.selectionCount, 2)
    XCTAssertTrue(review.allSelectableItemsSelected)
    XCTAssertTrue(review.items.allSatisfy(\.canImport))
  }

  func testDuplicateMediaIsShownButNotSelected() throws {
    let duplicateURL = URL(fileURLWithPath: "/Volumes/Card/IMG_0001.ARW")
    let media = makeMedia(id: "camera:1", filename: "IMG_0001.ARW", fileURL: duplicateURL)
    let existingAsset = try makeAsset(sourceURL: duplicateURL, filename: media.filename)

    let review = LibraryImportReview(
      deviceID: media.deviceID,
      mediaItems: [media],
      existingAssets: [existingAsset]
    )

    let item = try XCTUnwrap(review.items.first)
    XCTAssertEqual(item.state, .duplicate)
    XCTAssertFalse(item.isSelected)
    XCTAssertFalse(item.canImport)
    XCTAssertEqual(item.existingAsset?.id, existingAsset.id)
    XCTAssertTrue(review.selectedMediaItems.isEmpty)
  }

  func testSelectionMutationsOnlyAffectImportableMedia() throws {
    let first = makeMedia(id: "camera:1", filename: "IMG_0001.ARW")
    let secondURL = URL(fileURLWithPath: "/Volumes/Card/IMG_0002.ARW")
    let second = makeMedia(id: "camera:2", filename: "IMG_0002.ARW", fileURL: secondURL)
    let existing = try makeAsset(sourceURL: secondURL, filename: second.filename)
    var review = LibraryImportReview(
      deviceID: first.deviceID,
      mediaItems: [first, second],
      existingAssets: [existing]
    )

    review.toggleSelection(for: first.id)
    XCTAssertTrue(review.selectedMediaItems.isEmpty)

    review.selectAll()
    XCTAssertEqual(review.selectedMediaItems.map(\.id), [first.id])

    review.deselectAll()
    XCTAssertTrue(review.selectedMediaItems.isEmpty)

    review.setSelection(true, for: second.id)
    XCTAssertTrue(review.selectedMediaItems.isEmpty)
  }

  func testReviewRoundTripsThroughCodableWithoutChangingSelection() throws {
    let media = makeMedia(id: "camera:1", filename: "IMG_0001.RAF")
    var review = LibraryImportReview(deviceID: media.deviceID, mediaItems: [media])
    review.setSelection(false, for: media.id)

    let data = try JSONEncoder().encode(review)
    let decoded = try JSONDecoder().decode(LibraryImportReview.self, from: data)

    XCTAssertEqual(decoded, review)
    XCTAssertTrue(decoded.selectedMediaItems.isEmpty)
  }

  func testPhotoAssetCanBePresentedAsAlreadyImportedReviewItem() throws {
    let sourceURL = URL(fileURLWithPath: "/Volumes/Card/IMG_0042.CR2")
    let asset = try makeAsset(sourceURL: sourceURL, filename: "IMG_0042.CR2")

    let review = LibraryImportReview(
      deviceID: CaptureDeviceID(rawValue: "camera-1"), assets: [asset])

    let item = try XCTUnwrap(review.items.first)
    XCTAssertEqual(item.media.fileURL, sourceURL)
    XCTAssertEqual(item.media.filename, asset.filename)
    XCTAssertEqual(item.existingAsset, asset)
    XCTAssertEqual(item.state, .duplicate)
    XCTAssertTrue(review.selectedMediaItems.isEmpty)
  }

  func testAssetBackedReviewIDsAreStableAndUnique() throws {
    let first = try makeAsset(
      sourceURL: URL(fileURLWithPath: "/Volumes/Card/IMG_0042.CR2"),
      filename: "IMG_0042.CR2"
    )
    let second = try makeAsset(
      sourceURL: URL(fileURLWithPath: "/Volumes/Card/IMG_0043.CR2"),
      filename: "IMG_0043.CR2"
    )
    let review = LibraryImportReview(
      deviceID: CaptureDeviceID(rawValue: "camera-1"),
      assets: [first, second]
    )

    XCTAssertEqual(
      review.items.map(\.id),
      [
        "asset:\(first.id.uuidString)",
        "asset:\(second.id.uuidString)",
      ])
    XCTAssertEqual(Set(review.items.map(\.id)).count, 2)
  }

  private func makeMedia(
    id: String,
    filename: String,
    isRaw: Bool = true,
    fileURL: URL? = nil
  ) -> CaptureMediaItem {
    CaptureMediaItem(
      id: id,
      deviceID: CaptureDeviceID(rawValue: "camera-1"),
      filename: filename,
      typeIdentifier: isRaw ? "public.camera-raw-image" : "public.jpeg",
      fileURL: fileURL,
      isRaw: isRaw,
      creationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  private func makeAsset(sourceURL: URL, filename: String) throws -> PhotoAsset {
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "a", count: 64),
        byteCount: 1024,
        modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
    return try XCTUnwrap(
      PhotoAsset(
        sourceURL: sourceURL,
        filename: filename,
        typeIdentifier: "public.camera-raw-image",
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_001),
        captureDate: Date(timeIntervalSince1970: 1_700_000_000),
        pixelDimensions: PixelDimensions(width: 6_000, height: 4_000)
      )
    )
  }
}
