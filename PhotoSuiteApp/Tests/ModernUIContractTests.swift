// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import Testing

@testable import PhotoSuite

struct ModernUIContractTests {
  @MainActor
  @Test
  func currentAndFallbackGlassAPIsCompileAtTheMacOSFifteenDeploymentTarget() {
    _ = Text("Fallback")
      .background(.regularMaterial, in: Capsule())
      .modifier(NavigationGlassSurface(cornerRadius: 18))

    _ = GlassControlGroup {
      Button("Action") {}
        .modifier(GlassButtonWhenAvailable())
    }

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
      _ = GlassEffectContainer(spacing: 6) {
        Button("Action") {}
          .buttonStyle(.glass)
      }
    }
  }

  @Test
  func accessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.workspaceNavigation == "workspace-navigation")
    #expect(ModernUIAccessibility.library == "workspace-library")
    #expect(ModernUIAccessibility.develop == "workspace-develop")
    #expect(ModernUIAccessibility.deliver == "workspace-deliver")
    #expect(ModernUIAccessibility.professionalWorkspace == "workspace-professional")
    #expect(ModernUIAccessibility.professionalToolRail == "professional-tool-rail")
    #expect(ModernUIAccessibility.professionalMap == "professional-map")
    #expect(ModernUIAccessibility.professionalStatus == "professional-status")
    #expect(ModernUIAccessibility.librarySearchField == "library-search-field")
    #expect(ModernUIAccessibility.librarySmartFilter == "library-smart-filter")
    #expect(ModernUIAccessibility.libraryMetadataControls == "library-metadata-controls")
    #expect(ModernUIAccessibility.newCollectionButton == "new-collection-button")
    #expect(ModernUIAccessibility.newStackButton == "new-stack-button")
    #expect(ModernUIAccessibility.importButton == "import-button")
    #expect(ModernUIAccessibility.proofModeToggle == "proof-mode-toggle")
    #expect(ModernUIAccessibility.developCanvas == "develop-canvas")
    #expect(ModernUIAccessibility.beforeAfterButton == "before-after-button")
    #expect(ModernUIAccessibility.developInspector == "develop-inspector")
    #expect(ModernUIAccessibility.adjustmentExposure == "adjustment-exposure")
    #expect(ModernUIAccessibility.exportJPEGButton == "export-jpeg-button")
    #expect(ModernUIAccessibility.deliverBatchExportButton == "deliver-batch-export-button")
    #expect(ModernUIAccessibility.precisionControlsSurface == "precision-controls-surface")
    #expect(ModernUIAccessibility.deliverResizeToggle == "deliver-resize-toggle")
    #expect(ModernUIAccessibility.deliverMetadataPicker == "deliver-metadata-picker")
    #expect(ModernUIAccessibility.deliverWatermarkToggle == "deliver-watermark-toggle")
    #expect(ModernUIAccessibility.deliverSharpeningPicker == "deliver-sharpening-picker")
    #expect(ModernUIAccessibility.deliverUnsupportedOptions == "deliver-unsupported-options")
  }
}
