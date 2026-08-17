// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI

enum ModernUIAccessibility {
  static let workspaceNavigation = "workspace-navigation"
  static let library = "workspace-library"
  static let develop = "workspace-develop"
  static let deliver = "workspace-deliver"
  static let professionalWorkspace = "workspace-professional"
  static let professionalToolRail = "professional-tool-rail"
  static let professionalMap = "professional-map"
  static let professionalStatus = "professional-status"
  static let librarySearchField = "library-search-field"
  static let librarySmartFilter = "library-smart-filter"
  static let libraryMetadataControls = "library-metadata-controls"
  static let newCollectionButton = "new-collection-button"
  static let newStackButton = "new-stack-button"
  static let importButton = "import-button"
  static let proofModeToggle = "proof-mode-toggle"
  static let developCanvas = "develop-canvas"
  static let beforeAfterButton = "before-after-button"
  static let developInspector = "develop-inspector"
  static let maskAuthoringInspector = "mask-authoring-inspector"
  static let maskAuthoringToolPicker = "mask-authoring-tool-picker"
  static let maskAuthoringOperationPicker = "mask-authoring-operation-picker"
  static let maskAuthoringUnavailable = "mask-authoring-unavailable"
  static let maskAuthoringAIAction = "mask-authoring-ai-action"
  static let maskAuthoringAIStatus = "mask-authoring-ai-status"
  static let adjustmentExposure = "adjustment-exposure"
  static let exportJPEGButton = "export-jpeg-button"
  static let deliverBatchExportButton = "deliver-batch-export-button"
  static let precisionControlsSurface = "precision-controls-surface"
  static let retouchInspector = "retouch-inspector"
  static let retouchToolPicker = "retouch-tool-picker"
  static let retouchSourceX = "retouch-source-x"
  static let retouchSourceY = "retouch-source-y"
  static let retouchTargetX = "retouch-target-x"
  static let retouchTargetY = "retouch-target-y"
  static let retouchRadius = "retouch-radius"
  static let retouchFeather = "retouch-feather"
  static let retouchFlow = "retouch-flow"
  static let retouchRedEyeCenterX = "retouch-red-eye-center-x"
  static let retouchRedEyeCenterY = "retouch-red-eye-center-y"
  static let retouchRedEyeRadius = "retouch-red-eye-radius"
  static let retouchRedEyeFeather = "retouch-red-eye-feather"
  static let retouchApplyButton = "retouch-apply-button"
  static let retouchClearButton = "retouch-clear-button"
  static let retouchManualNotice = "retouch-manual-notice"
  static let lensProfileInspector = "lens-profile-inspector"
  static let lensProfilePicker = "lens-profile-picker"
  static let lensProfileImportButton = "lens-profile-import"
  static let lensProfileAttribution = "lens-profile-attribution"
  static let lensProfileStatus = "lens-profile-status"
  static let deliverResizeToggle = "deliver-resize-toggle"
  static let deliverMetadataPicker = "deliver-metadata-picker"
  static let deliverWatermarkToggle = "deliver-watermark-toggle"
  static let deliverSharpeningPicker = "deliver-sharpening-picker"
  static let deliverUnsupportedOptions = "deliver-unsupported-options"
  static let professionalOutputSettings = "professional-output-settings"
  static let professionalOutputTitle = "professional-output-title"
  static let professionalOutputAuthor = "professional-output-author"
  static let professionalOutputPageSize = "professional-output-page-size"
  static let professionalOutputDuration = "professional-output-duration"
  static let professionalOutputFrameRate = "professional-output-frame-rate"
  static let professionalOutputCanvas = "professional-output-canvas"
  static let professionalOutputSubtitle = "professional-output-subtitle"
  static let professionalOutputMaximumDimension = "professional-output-maximum-dimension"
  static let professionalOutputStart = "professional-output-start"
  static let professionalOutputCancel = "professional-output-cancel"
  static let professionalOutputError = "professional-output-error"
  static let professionalOutputResult = "professional-output-result"
}

struct NavigationGlassSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(
          Color(nsColor: .controlBackgroundColor),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    } else if #available(macOS 26.0, *) {
      content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      content
        .background(
          .regularMaterial,
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
  }
}

struct GlassControlGroup<Content: View>: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  @ViewBuilder
  var body: some View {
    if reduceTransparency {
      content
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay { Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5) }
    } else if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 6) {
        content.padding(6)
      }
    } else {
      content
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5) }
    }
  }
}

struct GlassButtonWhenAvailable: ViewModifier {
  var prominent = false

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        content.buttonStyle(.glassProminent)
      } else {
        content.buttonStyle(.glass)
      }
    } else if prominent {
      content.buttonStyle(.borderedProminent)
    } else {
      content.buttonStyle(.bordered)
    }
  }
}
