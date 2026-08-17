// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import PhotoDomain
import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DevelopView: View {
  @Bindable var workspace: PhotoWorkspace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var cropEditing = false

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

        if cropEditing {
          CropCanvasOverlay(
            workspace: workspace,
            isEditing: $cropEditing,
            previewDimensions: workspace.preview?.pixelDimensions
          )
        }

        if workspace.preview == nil {
          if workspace.errorMessage == nil {
            ProgressView("Rendering preview…").controlSize(.large)
          } else {
            Label("Preview unavailable", systemImage: "photo.badge.exclamationmark")
              .foregroundStyle(.white.opacity(0.78))
          }
        }

        if !workspace.proofMode {
          TransientCanvasControls(workspace: workspace, cropEditing: $cropEditing)
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
    .onChange(of: workspace.selectedAssetID) { _, _ in
      cropEditing = false
    }
  }
}

@MainActor
private struct TransientCanvasControls: View {
  @Bindable var workspace: PhotoWorkspace
  @Binding var cropEditing: Bool

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
        cropEditing.toggle()
      } label: {
        Label(cropEditing ? "Close Crop" : "Crop", systemImage: "crop")
      }
      .help("Drag the crop frame on the photograph")
      .modifier(GlassButtonWhenAvailable(prominent: cropEditing))
      .accessibilityIdentifier(ModernUIAccessibility.cropCanvasToggle)

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
  @State private var presetName = ""

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
        RetouchInspector(workspace: workspace)

        Divider()
        DevelopPresetControls(workspace: workspace, name: $presetName)

        Divider()
        MaskAuthoringInspector(workspace: workspace)

        Divider()
        AIModelControls(workspace: workspace)

        Divider()
        FaceAnnotationInspector(workspace: workspace, placement: .develop)

        Divider()
        CropInspector(workspace: workspace)

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

enum RetouchTool: String, CaseIterable, Identifiable, Sendable {
  case clone
  case healing
  case redEye

  var id: Self { self }

  var title: String {
    switch self {
    case .clone: "Clone"
    case .healing: "Healing"
    case .redEye: "Red-eye"
    }
  }
}

struct RetouchInspectorModel: Sendable {
  var tool: RetouchTool = .clone
  var sourceX = 0.2
  var sourceY = 0.35
  var targetX = 0.72
  var targetY = 0.65
  var radius = 0.16
  var feather = 0.3
  var flow = 0.9
  var redEyeCenterX = 0.5
  var redEyeCenterY = 0.5
  var redEyeRadius = 0.12
  var redEyeFeather = 0.25

  var validationMessage: String? {
    switch tool {
    case .clone, .healing:
      guard isUnit(sourceX), isUnit(sourceY), isUnit(targetX), isUnit(targetY) else {
        return "Source and target points must be between 0.00 and 1.00."
      }
      guard isBrushRadius(radius) else {
        return "Brush radius must be greater than 0 and no more than 0.50."
      }
      guard isUnit(feather), isUnit(flow) else {
        return "Feather and flow must be between 0.00 and 1.00."
      }
    case .redEye:
      guard isUnit(redEyeCenterX), isUnit(redEyeCenterY) else {
        return "Eye centre coordinates must be between 0.00 and 1.00."
      }
      guard isBrushRadius(redEyeRadius) else {
        return "Red-eye radius must be greater than 0 and no more than 0.50."
      }
      guard isUnit(redEyeFeather) else {
        return "Red-eye feather must be between 0.00 and 1.00."
      }
    }
    return nil
  }

  var operation: EditOperation? {
    guard validationMessage == nil else { return nil }

    switch tool {
    case .clone, .healing:
      guard
        let source = RetouchPointV1(x: sourceX, y: sourceY),
        let target = RetouchPointV1(x: targetX, y: targetY),
        let sample = RetouchBrushSampleV1(point: target, pressure: 1),
        let brush = RetouchBrushV1(
          samples: [sample],
          radius: radius,
          feather: feather,
          flow: flow
        )
      else { return nil }

      switch tool {
      case .clone:
        guard
          let adjustment = CloneAdjustmentV1(
            sourceAnchor: source,
            targetAnchor: target,
            brush: brush
          )
        else { return nil }
        return .clone(adjustment)
      case .healing:
        guard
          let adjustment = HealingAdjustmentV1(
            sourceAnchor: source,
            targetAnchor: target,
            brush: brush,
            blend: 1
          )
        else { return nil }
        return .healing(adjustment)
      case .redEye:
        return nil
      }
    case .redEye:
      guard
        let center = RetouchPointV1(x: redEyeCenterX, y: redEyeCenterY),
        let adjustment = RedEyeAdjustmentV1(
          center: center,
          radius: redEyeRadius,
          feather: redEyeFeather
        )
      else { return nil }
      return .redEye(adjustment)
    }
  }

  private func isUnit(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
  }

  private func isBrushRadius(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value <= 0.5
  }
}

@MainActor
struct RetouchInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var draft = RetouchInspectorModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Retouch")
          .font(.headline)
        Text("Manual local edits")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Place every source, target, or eye centre point yourself. Automatic detection is not used."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier(ModernUIAccessibility.retouchManualNotice)

      Picker("Tool", selection: $draft.tool) {
        ForEach(RetouchTool.allCases) { tool in
          Text(tool.title).tag(tool)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(ModernUIAccessibility.retouchToolPicker)

      switch draft.tool {
      case .clone, .healing:
        RetouchPointPairControls(
          title: "Source point",
          x: $draft.sourceX,
          y: $draft.sourceY,
          xIdentifier: ModernUIAccessibility.retouchSourceX,
          yIdentifier: ModernUIAccessibility.retouchSourceY
        )
        RetouchPointPairControls(
          title: "Target point",
          x: $draft.targetX,
          y: $draft.targetY,
          xIdentifier: ModernUIAccessibility.retouchTargetX,
          yIdentifier: ModernUIAccessibility.retouchTargetY
        )
        RetouchSlider(
          title: "Radius",
          value: $draft.radius,
          range: 0.01...0.5,
          identifier: ModernUIAccessibility.retouchRadius
        )
        RetouchSlider(
          title: "Feather",
          value: $draft.feather,
          range: 0...1,
          identifier: ModernUIAccessibility.retouchFeather
        )
        RetouchSlider(
          title: "Flow",
          value: $draft.flow,
          range: 0...1,
          identifier: ModernUIAccessibility.retouchFlow
        )
      case .redEye:
        RetouchPointPairControls(
          title: "Eye centre",
          x: $draft.redEyeCenterX,
          y: $draft.redEyeCenterY,
          xIdentifier: ModernUIAccessibility.retouchRedEyeCenterX,
          yIdentifier: ModernUIAccessibility.retouchRedEyeCenterY
        )
        RetouchSlider(
          title: "Radius",
          value: $draft.redEyeRadius,
          range: 0.01...0.5,
          identifier: ModernUIAccessibility.retouchRedEyeRadius
        )
        RetouchSlider(
          title: "Feather",
          value: $draft.redEyeFeather,
          range: 0...1,
          identifier: ModernUIAccessibility.retouchRedEyeFeather
        )
      }

      if let validationMessage = draft.validationMessage {
        Label(validationMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack {
        Button("Clear", role: .destructive) {
          clearRetouch()
        }
        .accessibilityIdentifier(ModernUIAccessibility.retouchClearButton)

        Spacer()

        Button("Apply") {
          applyRetouch()
        }
        .buttonStyle(.borderedProminent)
        .disabled(draft.operation == nil)
        .accessibilityIdentifier(ModernUIAccessibility.retouchApplyButton)
      }
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier(ModernUIAccessibility.retouchInspector)
  }

  private func applyRetouch() {
    guard let operation = draft.operation else { return }
    Task { await workspace.commitDevelopOperation(operation) }
  }

  private func clearRetouch() {
    let tool = draft.tool
    draft = RetouchInspectorModel()
    draft.tool = tool

    // Retouch families are intentionally discovered by raw value. This keeps
    // the UI compatible with the existing workflow API while allowing a
    // workflow version that exposes clone, healing, and red-eye families to
    // clear the durable operation without touching unrelated adjustments.
    guard let family = DevelopAdjustmentFamily(rawValue: tool.rawValue) else { return }
    Task { await workspace.clearDevelopOperation(family) }
  }
}

@MainActor
private struct RetouchPointPairControls: View {
  let title: String
  @Binding var x: Double
  @Binding var y: Double
  let xIdentifier: String
  let yIdentifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
      HStack(spacing: 10) {
        RetouchSlider(
          title: "X",
          value: $x,
          range: 0...1,
          identifier: xIdentifier
        )
        RetouchSlider(
          title: "Y",
          value: $y,
          range: 0...1,
          identifier: yIdentifier
        )
      }
    }
  }
}

@MainActor
private struct RetouchSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let identifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title)
        Spacer()
        Text(value, format: .number.precision(.fractionLength(2)))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(value: $value, in: range, step: 0.01)
        .accessibilityLabel(title)
        .accessibilityValue(
          Text(value, format: .number.precision(.fractionLength(2)))
        )
        .accessibilityIdentifier(identifier)
    }
  }
}

@MainActor
private struct DevelopPresetControls: View {
  @Bindable var workspace: PhotoWorkspace
  @Binding var name: String
  @State private var isImporting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Presets").font(.headline)
      HStack(spacing: 8) {
        TextField("Preset name", text: $name)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("develop-preset-name")
        Button("Save") {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          Task { await workspace.saveDevelopPreset(named: trimmed) }
          name = ""
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("develop-preset-save")
        Button("Import XMP…") {
          isImporting = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("develop-preset-import-xmp")
      }

      if workspace.developPresets.isEmpty {
        Text("Save a tone and colour recipe for reuse.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(workspace.developPresets) { preset in
          HStack(spacing: 8) {
            Button {
              Task { await workspace.applyDevelopPreset(preset.id) }
            } label: {
              Label(preset.name, systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("develop-preset-\(preset.id.uuidString)")
            Button {
              Task { await workspace.deleteDevelopPreset(preset.id) }
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete preset")
            .accessibilityLabel("Delete \(preset.name)")
          }
        }
      }
    }
    .accessibilityIdentifier("develop-preset-controls")
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.xml],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await workspace.importDevelopPreset(from: url) }
    }
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
