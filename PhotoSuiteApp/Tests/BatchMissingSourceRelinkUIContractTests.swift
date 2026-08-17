// SPDX-License-Identifier: MPL-2.0

import PhotoWorkflow
import SwiftUI
import Testing

@testable import PhotoSuite

struct BatchMissingSourceRelinkUIContractTests {
  @MainActor
  @Test
  func batchRelinkViewCompilesWithCurrentAndFallbackGlassAPIs() {
    _ = BatchMissingSourceRelinkView(
      missingAssetCount: 4,
      onRelink: { _ in
        BatchRelinkResult(
          folderURL: URL(fileURLWithPath: "/tmp/photos"),
          scannedFileCount: 0,
          matched: [],
          unmatched: [],
          failures: []
        )
      },
      onCancel: {}
    )
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
      _ = GlassEffectContainer(spacing: 6) {
        Button("Action") {}
          .buttonStyle(.glass)
      }
    }
  }

  @Test
  func batchRelinkAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.batchMissingSourceRelink == "batch-missing-source-relink")
    #expect(
      ModernUIAccessibility.batchMissingSourceRelinkChoose
        == "batch-missing-source-relink-choose"
    )
    #expect(
      ModernUIAccessibility.batchMissingSourceRelinkCancel
        == "batch-missing-source-relink-cancel"
    )
    #expect(
      ModernUIAccessibility.batchMissingSourceRelinkSummary
        == "batch-missing-source-relink-summary"
    )
  }
}
