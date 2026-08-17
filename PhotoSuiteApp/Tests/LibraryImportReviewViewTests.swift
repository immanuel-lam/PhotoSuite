// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoWorkflow
import Testing

@testable import PhotoSuite

struct LibraryImportReviewViewTests {
  @MainActor
  @Test
  func reviewViewCompilesWithNativeImportContract() {
    let media = CaptureMediaItem(
      id: "camera:1",
      deviceID: CaptureDeviceID(rawValue: "camera-1"),
      filename: "IMG_0001.ARW",
      typeIdentifier: "public.camera-raw-image",
      fileURL: nil,
      isRaw: true,
      creationDate: nil
    )
    let review = LibraryImportReview(
      deviceID: media.deviceID,
      mediaItems: [media]
    )

    let view = LibraryImportReviewView(
      review: review,
      onImport: { _ in }
    )

    _ = view
    #expect(LibraryImportReviewAccessibility.view == "library-import-review")
    #expect(LibraryImportReviewAccessibility.importButton == "library-import-review-import")
    #expect(
      LibraryImportReviewAccessibility.item(media.id) == "library-import-review-item-camera:1")
    #expect(LibraryImportModeChoice.allCases == [.add, .copy, .move])
    #expect(LibraryImportReviewAccessibility.modePicker == "library-import-review-mode")
    #expect(
      LibraryImportReviewAccessibility.destinationButton
        == "library-import-review-destination"
    )

    _ = LibraryImportReviewView(
      review: review,
      onImport: { _ in },
      onImportWithMode: { _, _ in }
    )
  }
}
