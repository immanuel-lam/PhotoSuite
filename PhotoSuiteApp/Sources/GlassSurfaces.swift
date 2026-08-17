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
  static let adjustmentExposure = "adjustment-exposure"
  static let exportJPEGButton = "export-jpeg-button"
  static let precisionControlsSurface = "precision-controls-surface"
  static let deliverResizeToggle = "deliver-resize-toggle"
  static let deliverMetadataPicker = "deliver-metadata-picker"
  static let deliverWatermarkToggle = "deliver-watermark-toggle"
  static let deliverSharpeningPicker = "deliver-sharpening-picker"
  static let deliverUnsupportedOptions = "deliver-unsupported-options"
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
