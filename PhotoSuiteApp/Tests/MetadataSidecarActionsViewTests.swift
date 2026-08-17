// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain
import PhotoWorkflow
import Testing

@testable import PhotoSuite

struct MetadataSidecarActionsViewTests {
  @MainActor
  @Test
  func actionsViewCompilesWithSidecarContract() {
    let asset = PhotoAsset(
      sourceURL: URL(fileURLWithPath: "/tmp/capture.jpg"),
      filename: "capture.jpg",
      typeIdentifier: "public.jpeg",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "a", count: 64),
        byteCount: 1,
        modificationDate: nil
      )!,
      importDate: Date(),
      captureDate: nil,
      pixelDimensions: PixelDimensions(width: 1, height: 1)
    )!
    let view = MetadataSidecarActionsView(
      status: .idle,
      onExport: {},
      onImport: { _ in }
    )

    _ = view
    #expect(MetadataSidecarAccessibility.view == "metadata-sidecar-actions")
    #expect(MetadataSidecarAccessibility.exportButton == "metadata-sidecar-export")
    #expect(MetadataSidecarAccessibility.importButton == "metadata-sidecar-import")
  }
}
