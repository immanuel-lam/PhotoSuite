// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
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

  @Test
  func cloneDraftBuildsVersionOneOperationFromNormalizedControls() throws {
    var draft = RetouchInspectorModel()
    draft.tool = .clone
    draft.sourceX = 0.2
    draft.sourceY = 0.35
    draft.targetX = 0.72
    draft.targetY = 0.65
    draft.radius = 0.16
    draft.feather = 0.3
    draft.flow = 0.9

    let operation = try #require(draft.operation)
    guard case .clone(let adjustment) = operation else {
      Issue.record("The clone tool must produce a clone operation.")
      return
    }

    #expect(adjustment.schemaVersion == 1)
    #expect(adjustment.sourceAnchor == RetouchPointV1(x: 0.2, y: 0.35))
    #expect(adjustment.targetAnchor == RetouchPointV1(x: 0.72, y: 0.65))
    #expect(adjustment.brush.radius == 0.16)
    #expect(adjustment.brush.feather == 0.3)
    #expect(adjustment.brush.flow == 0.9)
    #expect(adjustment.brush.samples.count == 1)
    #expect(adjustment.brush.samples[0].point == adjustment.targetAnchor)
    #expect(adjustment.brush.samples[0].pressure == 1)
  }

  @Test
  func healingDraftBuildsVersionOneOperationWithBoundedBlend() throws {
    var draft = RetouchInspectorModel()
    draft.tool = .healing
    draft.sourceX = 0.15
    draft.sourceY = 0.25
    draft.targetX = 0.75
    draft.targetY = 0.8
    draft.radius = 0.2
    draft.feather = 0.25
    draft.flow = 0.8

    let operation = try #require(draft.operation)
    guard case .healing(let adjustment) = operation else {
      Issue.record("The healing tool must produce a healing operation.")
      return
    }

    #expect(adjustment.schemaVersion == 1)
    #expect(adjustment.sourceAnchor == RetouchPointV1(x: 0.15, y: 0.25))
    #expect(adjustment.targetAnchor == RetouchPointV1(x: 0.75, y: 0.8))
    #expect(adjustment.brush.flow == 0.8)
    #expect(adjustment.blend == 1)
  }

  @Test
  func redEyeDraftBuildsVersionOneOperationFromManualCenter() throws {
    var draft = RetouchInspectorModel()
    draft.tool = .redEye
    draft.redEyeCenterX = 0.45
    draft.redEyeCenterY = 0.55
    draft.redEyeRadius = 0.12
    draft.redEyeFeather = 0.4

    let operation = try #require(draft.operation)
    guard case .redEye(let adjustment) = operation else {
      Issue.record("The red-eye tool must produce a red-eye operation.")
      return
    }

    #expect(adjustment.schemaVersion == 1)
    #expect(adjustment.center == RetouchPointV1(x: 0.45, y: 0.55))
    #expect(adjustment.radius == 0.12)
    #expect(adjustment.feather == 0.4)
  }

  @Test
  func invalidNormalizedDraftCannotBuildAnOperation() {
    var draft = RetouchInspectorModel()
    draft.tool = .clone
    draft.sourceX = -0.01
    #expect(draft.operation == nil)

    draft.sourceX = 0.2
    draft.radius = 0.51
    #expect(draft.operation == nil)

    draft.radius = 0.1
    draft.flow = .infinity
    #expect(draft.operation == nil)

    draft.tool = .redEye
    draft.flow = 0.8
    draft.redEyeRadius = 0
    #expect(draft.operation == nil)
  }

  @MainActor
  @Test
  func retouchInspectorAndFallbackGlassContractCompile() {
    _ = RetouchInspector.self
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
  }

  @Test
  func retouchAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.retouchInspector == "retouch-inspector")
    #expect(ModernUIAccessibility.retouchToolPicker == "retouch-tool-picker")
    #expect(ModernUIAccessibility.retouchSourceX == "retouch-source-x")
    #expect(ModernUIAccessibility.retouchSourceY == "retouch-source-y")
    #expect(ModernUIAccessibility.retouchTargetX == "retouch-target-x")
    #expect(ModernUIAccessibility.retouchTargetY == "retouch-target-y")
    #expect(ModernUIAccessibility.retouchRadius == "retouch-radius")
    #expect(ModernUIAccessibility.retouchFeather == "retouch-feather")
    #expect(ModernUIAccessibility.retouchFlow == "retouch-flow")
    #expect(ModernUIAccessibility.retouchRedEyeCenterX == "retouch-red-eye-center-x")
    #expect(ModernUIAccessibility.retouchRedEyeCenterY == "retouch-red-eye-center-y")
    #expect(ModernUIAccessibility.retouchRedEyeRadius == "retouch-red-eye-radius")
    #expect(ModernUIAccessibility.retouchRedEyeFeather == "retouch-red-eye-feather")
    #expect(ModernUIAccessibility.retouchApplyButton == "retouch-apply-button")
    #expect(ModernUIAccessibility.retouchClearButton == "retouch-clear-button")
    #expect(ModernUIAccessibility.retouchManualNotice == "retouch-manual-notice")
  }
}
