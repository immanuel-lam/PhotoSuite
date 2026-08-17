// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import SwiftUI
import Testing

@testable import PhotoSuite

struct MissingSourceRelinkUIContractTests {
  @MainActor
  @Test
  func missingSourceRelinkViewCompilesWithCurrentAndFallbackGlassAPIs() {
    let asset = PhotoAsset(
      sourceURL: URL(fileURLWithPath: "/tmp/missing.jpg"),
      filename: "missing.jpg",
      typeIdentifier: "public.jpeg",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "a", count: 64),
        byteCount: 1,
        modificationDate: nil
      )!,
      importDate: Date(timeIntervalSince1970: 1),
      captureDate: nil,
      pixelDimensions: nil,
      isMissing: true
    )!

    _ = MissingSourceRelinkView(
      asset: asset,
      onRelink: { _ in },
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
  func missingSourceRelinkAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.missingSourceRelink == "missing-source-relink")
    #expect(ModernUIAccessibility.missingSourceRelinkChoose == "missing-source-relink-choose")
    #expect(ModernUIAccessibility.missingSourceRelinkCancel == "missing-source-relink-cancel")
    #expect(ModernUIAccessibility.missingSourceRelinkError == "missing-source-relink-error")
  }
}
