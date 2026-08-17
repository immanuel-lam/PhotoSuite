// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

extension ModernUIAccessibility {
  static let cropInspector = "crop-inspector"
  static let cropAspectPicker = "crop-aspect-picker"
  static let cropXField = "crop-x-field"
  static let cropYField = "crop-y-field"
  static let cropWidthField = "crop-width-field"
  static let cropHeightField = "crop-height-field"
  static let cropApplyButton = "crop-apply-button"
  static let cropResetButton = "crop-reset-button"
  static let cropRotateButton = "crop-rotate-button"
}

enum CropAspectPreset: String, CaseIterable, Identifiable, Sendable {
  case free
  case original
  case square
  case fourByFive
  case threeByTwo
  case fourByThree
  case sixteenByNine

  var id: Self { self }

  var title: String {
    switch self {
    case .free: "Free"
    case .original: "Original"
    case .square: "1:1"
    case .fourByFive: "4:5"
    case .threeByTwo: "3:2"
    case .fourByThree: "4:3"
    case .sixteenByNine: "16:9"
    }
  }

  fileprivate var ratio: Double? {
    switch self {
    case .free, .original: nil
    case .square: 1
    case .fourByFive: 4.0 / 5.0
    case .threeByTwo: 3.0 / 2.0
    case .fourByThree: 4.0 / 3.0
    case .sixteenByNine: 16.0 / 9.0
    }
  }
}

struct CropInspectorModel: Equatable, Sendable {
  var x = 0.0
  var y = 0.0
  var width = 1.0
  var height = 1.0
  var aspectPreset: CropAspectPreset = .free

  init(rect: NormalizedRect? = nil) {
    if let rect {
      x = rect.x
      y = rect.y
      width = rect.width
      height = rect.height
    }
  }

  var rect: NormalizedRect? {
    NormalizedRect(x: x, y: y, width: width, height: height)
  }

  var validationMessage: String? {
    let values = [x, y, width, height]
    guard values.allSatisfy(\.isFinite) else {
      return "Crop values must be finite numbers."
    }
    guard width > 0, height > 0 else {
      return "Crop width and height must be greater than zero."
    }
    guard (0...1).contains(x), (0...1).contains(y) else {
      return "Crop origin must be between 0.00 and 1.00."
    }
    guard (0...1).contains(width), (0...1).contains(height) else {
      return "Crop size must be between 0.00 and 1.00."
    }
    guard x + width <= 1, y + height <= 1 else {
      return "Crop must remain inside the image bounds."
    }
    return nil
  }

  mutating func apply(_ preset: CropAspectPreset) {
    aspectPreset = preset
    switch preset {
    case .free:
      return
    case .original:
      x = 0
      y = 0
      width = 1
      height = 1
    default:
      guard let ratio = preset.ratio else { return }
      fit(ratio: ratio)
    }
  }

  private mutating func fit(ratio: Double) {
    guard ratio.isFinite, ratio > 0 else { return }

    let centerX = x + width / 2
    let centerY = y + height / 2
    var fittedWidth = width
    var fittedHeight = fittedWidth / ratio

    if fittedHeight > height {
      fittedHeight = height
      fittedWidth = fittedHeight * ratio
    }
    if fittedWidth > 1 {
      fittedWidth = 1
      fittedHeight = fittedWidth / ratio
    }
    if fittedHeight > 1 {
      fittedHeight = 1
      fittedWidth = fittedHeight * ratio
    }

    x = clamped(centerX - fittedWidth / 2, upperBound: 1 - fittedWidth)
    y = clamped(centerY - fittedHeight / 2, upperBound: 1 - fittedHeight)
    width = fittedWidth
    height = fittedHeight
  }

  private func clamped(_ value: Double, upperBound: Double) -> Double {
    min(max(value, 0), max(upperBound, 0))
  }
}

@MainActor
struct CropInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var draft = CropInspectorModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Crop")
          .font(.headline)
        Text("Non-destructive framing")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Picker("Aspect", selection: $draft.aspectPreset) {
        ForEach(CropAspectPreset.allCases) { preset in
          Text(preset.title).tag(preset)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier(ModernUIAccessibility.cropAspectPicker)
      .onChange(of: draft.aspectPreset) { _, preset in
        draft.apply(preset)
      }

      Grid(horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          CropValueField(
            title: "X",
            value: $draft.x,
            identifier: ModernUIAccessibility.cropXField
          )
          CropValueField(
            title: "Y",
            value: $draft.y,
            identifier: ModernUIAccessibility.cropYField
          )
        }
        GridRow {
          CropValueField(
            title: "Width",
            value: $draft.width,
            identifier: ModernUIAccessibility.cropWidthField
          )
          CropValueField(
            title: "Height",
            value: $draft.height,
            identifier: ModernUIAccessibility.cropHeightField
          )
        }
      }

      if let validationMessage = draft.validationMessage {
        Label(validationMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("crop-validation-message")
      }

      GlassControlGroup {
        HStack(spacing: 8) {
          Button {
            guard let rect = draft.rect else { return }
            Task { await workspace.commitCrop(rect) }
          } label: {
            Label("Apply Crop", systemImage: "crop")
          }
          .modifier(GlassButtonWhenAvailable(prominent: true))
          .disabled(draft.rect == nil || workspace.selectedAsset == nil)
          .accessibilityIdentifier(ModernUIAccessibility.cropApplyButton)

          Button("Reset") {
            Task { await workspace.resetCrop() }
          }
          .modifier(GlassButtonWhenAvailable())
          .disabled(workspace.selectedAsset == nil)
          .accessibilityIdentifier(ModernUIAccessibility.cropResetButton)
        }
      }

      HStack {
        Button {
          Task { await workspace.rotateClockwise() }
        } label: {
          Label("Rotate 90°", systemImage: "rotate.right")
        }
        .modifier(GlassButtonWhenAvailable())
        .disabled(workspace.selectedAsset == nil)
        .accessibilityIdentifier(ModernUIAccessibility.cropRotateButton)
        Spacer()
      }
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier(ModernUIAccessibility.cropInspector)
    .task(id: workspace.selectedAssetID) {
      syncDraft()
    }
    .onChange(of: workspace.currentRecipe?.revision) { _, _ in
      syncDraft()
    }
  }

  private func syncDraft() {
    draft = CropInspectorModel(rect: currentCrop)
  }

  private var currentCrop: NormalizedRect? {
    workspace.currentRecipe?.operations.reversed().compactMap { operation in
      if case .normalizedCrop(let rect) = operation { return rect }
      return nil
    }.first
  }
}

@MainActor
private struct CropValueField: View {
  let title: String
  @Binding var value: Double
  let identifier: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(
        title,
        value: $value,
        format: .number.precision(.fractionLength(2))
      )
      .textFieldStyle(.roundedBorder)
      .monospacedDigit()
      .accessibilityLabel(title)
      .accessibilityIdentifier(identifier)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
