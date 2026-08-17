// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import Testing

@testable import PhotoSuite

struct FaceAnnotationUIContractTests {
  @MainActor
  @Test
  func faceAnnotationInspectorCompilesWithCurrentAndFallbackGlassAPIs() {
    _ = FaceAnnotationInspector.self
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
      _ = GlassEffectContainer(spacing: 6) {
        Button("Label") {}
          .buttonStyle(.glass)
      }
    }
  }

  @Test
  func faceAnnotationAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.faceAnnotationInspector == "face-annotation-inspector")
    #expect(ModernUIAccessibility.faceAnnotationList == "face-annotation-list")
    #expect(ModernUIAccessibility.faceAnnotationLabelField == "face-annotation-label-field")
    #expect(ModernUIAccessibility.faceAnnotationSaveButton == "face-annotation-save-button")
    #expect(ModernUIAccessibility.faceAnnotationEmptyState == "face-annotation-empty-state")
  }
}
