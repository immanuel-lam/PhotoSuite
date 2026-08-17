// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct DevelopView: View {
  @Bindable var workspace: PhotoWorkspace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color(white: workspace.proofMode ? 0.20 : 0.12).ignoresSafeArea()

      if workspace.selectedAsset == nil {
        ZStack {
          Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
          ContentUnavailableView {
            Label("No Photograph Selected", systemImage: "photo")
          } description: {
            Text("Select a photograph in Library to start developing it.")
          } actions: {
            Button("Open Library") { workspace.section = .library }
              .buttonStyle(.borderedProminent)
          }
        }
      } else {
        MetalPreviewCanvas(frame: workspace.preview)
          .accessibilityLabel("Develop canvas")
          .accessibilityValue(workspace.selectedAsset?.filename ?? "No photograph")
          .accessibilityIdentifier(ModernUIAccessibility.developCanvas)
          .focusable()

        if workspace.preview == nil {
          if workspace.errorMessage == nil {
            ProgressView("Rendering preview…").controlSize(.large)
          } else {
            Label("Preview unavailable", systemImage: "photo.badge.exclamationmark")
              .foregroundStyle(.white.opacity(0.78))
          }
        }

        if !workspace.proofMode {
          TransientCanvasControls(workspace: workspace)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
    }
    .overlay(alignment: .topLeading) {
      if let asset = workspace.selectedAsset {
        VStack(alignment: .leading, spacing: 3) {
          Text("Develop")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(.white)
          Text(asset.filename)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.top, 76)
        .padding(.leading, 24)
        .allowsHitTesting(false)
      }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: workspace.proofMode)
  }
}

@MainActor
private struct TransientCanvasControls: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    GlassControlGroup {
      controlButtons
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
      .accessibilityIdentifier(ModernUIAccessibility.beforeAfterButton)
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

@MainActor
struct DevelopInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @State private var draftColorGrade = ThreeWayColorGrade.neutral

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Adjustments").font(.title2.weight(.bold))
          Text("Tone and presence")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        AdjustmentRow(workspace: workspace, kind: .exposure, title: "Exposure", range: -5...5)
        AdjustmentRow(workspace: workspace, kind: .contrast, title: "Contrast", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .highlights, title: "Highlights", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .shadows, title: "Shadows", range: -1...1)
        AdjustmentRow(workspace: workspace, kind: .saturation, title: "Saturation", range: -1...1)

        Divider()
        HistogramView(histogram: workspace.preview?.histogram)

        Divider()
        ColorGradeView(
          grade: $draftColorGrade,
          onCommit: { grade in
            Task { await workspace.commitColorGrade(grade) }
          }
        )

        Divider()
        BaselineDevelopControls(workspace: workspace)

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
    .task(id: workspace.selectedAssetID) {
      draftColorGrade = workspace.currentColorGrade
    }
    .onChange(of: workspace.currentRecipe?.revision) { _, _ in
      draftColorGrade = workspace.currentColorGrade
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .accessibilityIdentifier(ModernUIAccessibility.precisionControlsSurface)
    .overlay(alignment: .topTrailing) {
      if differentiateWithoutColor && workspace.currentRecipe?.operations.isEmpty == false {
        Image(systemName: "slider.horizontal.3")
          .accessibilityLabel("Edits applied")
          .padding(8)
      }
    }
    .accessibilityIdentifier(ModernUIAccessibility.developInspector)
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
      .accessibilityIdentifier(kind.accessibilityIdentifier)
      .help("Adjust \(title.lowercased())")
    }
  }
}

extension AdjustmentKind {
  fileprivate var accessibilityIdentifier: String {
    switch self {
    case .exposure: ModernUIAccessibility.adjustmentExposure
    case .contrast: "adjustment-contrast"
    case .highlights: "adjustment-highlights"
    case .shadows: "adjustment-shadows"
    case .saturation: "adjustment-saturation"
    }
  }
}
