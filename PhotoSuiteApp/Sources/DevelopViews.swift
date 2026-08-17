// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import PhotoWorkflow
import SwiftUI

@MainActor
struct DevelopView: View {
  @Bindable var workspace: PhotoWorkspace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    ZStack {
      Color(white: workspace.proofMode ? 0.18 : 0.14).ignoresSafeArea()

      if workspace.selectedAsset == nil {
        ContentUnavailableView(
          "No Photograph Selected",
          systemImage: "photo",
          description: Text("Select a photograph in Library to start developing it.")
        )
      } else {
        MetalPreviewCanvas(frame: workspace.preview)
          .accessibilityLabel("Develop canvas")
          .accessibilityValue(workspace.selectedAsset?.filename ?? "No photograph")
          .accessibilityIdentifier("develop-canvas")
          .focusable()

        if workspace.preview == nil { ProgressView("Rendering preview…").controlSize(.large) }

        if !workspace.proofMode {
          TransientCanvasControls(
            workspace: workspace,
            reduceTransparency: reduceTransparency
          )
          .padding(.bottom, 22)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: workspace.proofMode)
  }
}

@MainActor
private struct TransientCanvasControls: View {
  @Bindable var workspace: PhotoWorkspace
  let reduceTransparency: Bool

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: 10) {
          controlButtons.padding(8)
        }
      } else {
        controlButtons
          .buttonStyle(.bordered)
          .padding(8)
          .background(
            reduceTransparency
              ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
              : AnyShapeStyle(.regularMaterial),
            in: Capsule()
          )
      }
    }
    .accessibilityIdentifier("canvas-transient-controls")
  }

  private var controlButtons: some View {
    HStack(spacing: 8) {
      Button {
        workspace.section = .library
      } label: {
        Label("Library", systemImage: "chevron.left")
      }
      .help("Return to Library")
      .modifier(GlassButtonWhenAvailable())

      Button {
        workspace.toggleBeforeAfter()
      } label: {
        Label(
          workspace.showsBefore ? "Show After" : "Show Before",
          systemImage: "circle.lefthalf.filled"
        )
      }
      .help("Compare the original and edited photograph")
      .accessibilityIdentifier("before-after-button")
      .modifier(GlassButtonWhenAvailable(prominent: workspace.showsBefore))

      Button {
        workspace.proofMode = true
      } label: {
        Label("Proof", systemImage: "rectangle.inset.filled")
      }
      .help("Enter distraction-free proof mode")
      .modifier(GlassButtonWhenAvailable())
    }
    .labelStyle(.titleAndIcon)
  }
}

private struct GlassButtonWhenAvailable: ViewModifier {
  var prominent = false

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      if prominent {
        content.buttonStyle(.glassProminent)
      } else {
        content.buttonStyle(.glass)
      }
    } else {
      content
    }
  }
}

@MainActor
struct DevelopInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("Adjustments").font(.headline)
        AdjustmentRow(workspace: workspace, kind: .exposure, title: "Exposure", range: -5...5)
        AdjustmentRow(workspace: workspace, kind: .contrast, title: "Contrast", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .highlights, title: "Highlights", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .shadows, title: "Shadows", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .saturation, title: "Saturation", range: -1...1)

        Divider()
        Text("Geometry").font(.headline)
        HStack {
          Button("Reset Crop") { Task { await workspace.resetCrop() } }
            .accessibilityIdentifier("crop-reset-button")
          Button("Rotate 90°") { Task { await workspace.rotateClockwise() } }
            .accessibilityIdentifier("rotate-button")
        }

        Divider()
        HStack {
          Button("Undo") { Task { await workspace.undo() } }
            .disabled(!workspace.canUndo)
            .accessibilityIdentifier("undo-button")
          Button("Redo") { Task { await workspace.redo() } }
            .disabled(!workspace.canRedo)
            .accessibilityIdentifier("redo-button")
          Spacer()
          Button("Reset All", role: .destructive) { Task { await workspace.resetEdits() } }
            .accessibilityIdentifier("reset-edits-button")
        }
      }
      .padding(18)
      .disabled(workspace.selectedAsset == nil)
    }
    .background(
      Color(nsColor: contrast == .increased ? .textBackgroundColor : .windowBackgroundColor)
    )
    .overlay(alignment: .topTrailing) {
      if differentiateWithoutColor && workspace.currentRecipe?.operations.isEmpty == false {
        Image(systemName: "slider.horizontal.3")
          .accessibilityLabel("Edits applied")
          .padding(8)
      }
    }
    .accessibilityIdentifier("develop-inspector")
    .accessibilityHint(
      workspace.selectedAsset == nil
        ? "Select a photograph in Library to enable edit controls."
        : "Adjust the selected photograph."
    )
  }
}

@MainActor
private struct AdjustmentRow: View {
  @Bindable var workspace: PhotoWorkspace
  let kind: AdjustmentKind
  let title: String
  let range: ClosedRange<Double>

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
        Spacer()
        Text(workspace.adjustmentValue(kind), format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(
          get: { workspace.adjustmentValue(kind) },
          set: { workspace.updateDraft(kind, value: $0) }
        ),
        in: range
      ) { editing in
        if !editing { Task { await workspace.commitDraft(kind) } }
      }
      .accessibilityLabel(title)
      .accessibilityValue(
        Text(workspace.adjustmentValue(kind), format: .number.precision(.fractionLength(2)))
      )
      .accessibilityIdentifier("adjustment-\(kind.rawValue)")
      .help("Adjust \(title.lowercased())")
    }
  }
}
