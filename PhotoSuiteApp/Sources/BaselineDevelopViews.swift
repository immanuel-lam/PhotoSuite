// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct BaselineDevelopControls: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var draft = BaselineDevelopDraft()
  @State private var toneCurveExpanded = true
  @State private var whiteBalanceExpanded = true
  @State private var transformExpanded = false
  @State private var detailExpanded = false
  @State private var opticsExpanded = false
  @State private var calibrationExpanded = false
  @State private var blackAndWhiteExpanded = false
  @State private var hdrExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Develop")
        .font(.headline)

      DisclosureGroup("Tone Curve", isExpanded: $toneCurveExpanded) {
        VStack(alignment: .leading, spacing: 10) {
          ToneCurveGraph(draft: draft)
            .frame(height: 124)
            .accessibilityLabel("Tone curve preview")
          DevelopSlider(
            title: "Black point",
            value: $draft.blackPoint,
            range: 0...1,
            commit: commitToneCurve
          )
          DevelopSlider(
            title: "Shadows",
            value: $draft.curveShadows,
            range: 0...1,
            commit: commitToneCurve
          )
          DevelopSlider(
            title: "Midtones",
            value: $draft.curveMidtones,
            range: 0...1,
            commit: commitToneCurve
          )
          DevelopSlider(
            title: "Highlights",
            value: $draft.curveHighlights,
            range: 0...1,
            commit: commitToneCurve
          )
          DevelopSlider(
            title: "White point",
            value: $draft.whitePoint,
            range: 0...1,
            commit: commitToneCurve
          )
        }
        .padding(.top, 8)
        .accessibilityIdentifier("tone-curve-controls")
      }

      DisclosureGroup("White Balance", isExpanded: $whiteBalanceExpanded) {
        VStack(spacing: 8) {
          DevelopSlider(
            title: "Temperature",
            value: $draft.temperature,
            range: -1...1,
            commit: commitWhiteBalance
          )
          DevelopSlider(
            title: "Tint",
            value: $draft.tint,
            range: -1...1,
            commit: commitWhiteBalance
          )
        }
        .padding(.top, 8)
        .accessibilityIdentifier("white-balance-controls")
      }

      DisclosureGroup("Transform", isExpanded: $transformExpanded) {
        VStack(spacing: 8) {
          DevelopSlider(
            title: "Straighten",
            value: $draft.straightenDegrees,
            range: -45...45,
            commit: commitTransform
          )
          Toggle("Flip horizontally", isOn: $draft.flipHorizontal)
            .onChange(of: draft.flipHorizontal) { _, _ in commitTransform() }
          Toggle("Flip vertically", isOn: $draft.flipVertical)
            .onChange(of: draft.flipVertical) { _, _ in commitTransform() }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("transform-controls")
      }

      DisclosureGroup("Detail", isExpanded: $detailExpanded) {
        VStack(spacing: 8) {
          DevelopSlider(
            title: "Sharpening",
            value: $draft.sharpening,
            range: 0...1,
            commit: commitDetail
          )
          DevelopSlider(
            title: "Noise reduction",
            value: $draft.noiseReduction,
            range: 0...1,
            commit: commitDetail
          )
        }
        .padding(.top, 8)
        .accessibilityIdentifier("detail-controls")
      }

      DisclosureGroup("Optics & Effects", isExpanded: $opticsExpanded) {
        VStack(spacing: 8) {
          DevelopSlider(
            title: "Vignette correction",
            value: $draft.vignetteCorrection,
            range: 0...1,
            commit: commitOptics
          )
          DevelopSlider(
            title: "Creative vignette",
            value: $draft.vignetteAmount,
            range: 0...1,
            commit: commitEffects
          )
          Text("Lens profiles are not bundled in this pre-alpha build.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityIdentifier("optics-effects-controls")
      }

      DisclosureGroup("Calibration", isExpanded: $calibrationExpanded) {
        VStack(spacing: 8) {
          DevelopSlider(
            title: "Red",
            value: $draft.redGain,
            range: -1...1,
            commit: commitCalibration
          )
          DevelopSlider(
            title: "Green",
            value: $draft.greenGain,
            range: -1...1,
            commit: commitCalibration
          )
          DevelopSlider(
            title: "Blue",
            value: $draft.blueGain,
            range: -1...1,
            commit: commitCalibration
          )
        }
        .padding(.top, 8)
        .accessibilityIdentifier("calibration-controls")
      }

      DisclosureGroup("Black & White", isExpanded: $blackAndWhiteExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Convert to monochrome", isOn: $draft.blackAndWhiteEnabled)
            .onChange(of: draft.blackAndWhiteEnabled) { _, enabled in
              if enabled {
                commitBlackAndWhite()
              } else {
                Task { await workspace.clearDevelopOperation(.blackAndWhite) }
              }
            }
          if draft.blackAndWhiteEnabled {
            DevelopSlider(
              title: "Red mix",
              value: $draft.redWeight,
              range: 0...2,
              commit: commitBlackAndWhite
            )
            DevelopSlider(
              title: "Green mix",
              value: $draft.greenWeight,
              range: 0...2,
              commit: commitBlackAndWhite
            )
            DevelopSlider(
              title: "Blue mix",
              value: $draft.blueWeight,
              range: 0...2,
              commit: commitBlackAndWhite
            )
          }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("black-and-white-controls")
      }

      DisclosureGroup("HDR", isExpanded: $hdrExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Preserve extended range intent", isOn: $draft.hdrEnabled)
            .onChange(of: draft.hdrEnabled) { _, enabled in
              if enabled {
                Task {
                  await workspace.commitDevelopOperation(
                    .hdr(HDRAdjustmentV1(isEnabled: true, preservesExtendedRange: true))
                  )
                }
              } else {
                Task { await workspace.clearDevelopOperation(.hdr) }
              }
            }
          Text(
            "HDR gain-map export and display validation are not bundled in this pre-alpha build."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityIdentifier("hdr-controls")
      }
    }
    .disabled(workspace.selectedAsset == nil)
    .task(id: workspace.selectedAssetID) {
      draft = BaselineDevelopDraft(operations: workspace.currentDevelopOperations)
    }
    .onChange(of: workspace.currentRecipe?.revision) { _, _ in
      draft = BaselineDevelopDraft(operations: workspace.currentDevelopOperations)
    }
  }

  private func commitToneCurve() {
    Task { await workspace.commitDevelopOperation(.toneCurve(draft.toneCurve)) }
  }

  private func commitWhiteBalance() {
    Task { await workspace.commitDevelopOperation(.whiteBalance(draft.whiteBalance)) }
  }

  private func commitTransform() {
    Task { await workspace.commitDevelopOperation(.transform(draft.transform)) }
  }

  private func commitDetail() {
    Task { await workspace.commitDevelopOperation(.detail(draft.detail)) }
  }

  private func commitOptics() {
    Task { await workspace.commitDevelopOperation(.optics(draft.optics)) }
  }

  private func commitEffects() {
    Task { await workspace.commitDevelopOperation(.effects(draft.effects)) }
  }

  private func commitCalibration() {
    Task { await workspace.commitDevelopOperation(.calibration(draft.calibration)) }
  }

  private func commitBlackAndWhite() {
    guard draft.blackAndWhiteEnabled else { return }
    Task { await workspace.commitDevelopOperation(.blackAndWhite(draft.blackAndWhite)) }
  }
}

@MainActor
private struct DevelopSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let commit: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(title)
        .frame(width: 132, alignment: .leading)
        .lineLimit(1)
      Slider(value: $value, in: range) { editing in
        if !editing { commit() }
      }
      Text(value, format: .number.precision(.fractionLength(2)))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .trailing)
    }
    .accessibilityLabel(title)
  }
}

@MainActor
private struct ToneCurveGraph: View {
  let draft: BaselineDevelopDraft

  var body: some View {
    Canvas { context, size in
      var grid = Path()
      for index in 1..<4 {
        let fraction = CGFloat(index) / 4
        grid.move(to: CGPoint(x: size.width * fraction, y: 0))
        grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
        grid.move(to: CGPoint(x: 0, y: size.height * fraction))
        grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
      }
      context.stroke(grid, with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)

      let values = [
        draft.blackPoint,
        draft.curveShadows,
        draft.curveMidtones,
        draft.curveHighlights,
        draft.whitePoint,
      ]
      var curve = Path()
      for (index, value) in values.enumerated() {
        let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
        let y = size.height * (1 - CGFloat(value))
        let point = CGPoint(x: x, y: y)
        if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
      }
      context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
    }
    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct BaselineDevelopDraft: Equatable {
  var blackPoint = 0.0
  var curveShadows = 0.25
  var curveMidtones = 0.5
  var curveHighlights = 0.75
  var whitePoint = 1.0
  var temperature = 0.0
  var tint = 0.0
  var straightenDegrees = 0.0
  var flipHorizontal = false
  var flipVertical = false
  var sharpening = 0.0
  var noiseReduction = 0.0
  var vignetteCorrection = 0.0
  var vignetteAmount = 0.0
  var redGain = 0.0
  var greenGain = 0.0
  var blueGain = 0.0
  var blackAndWhiteEnabled = false
  var redWeight = 0.299
  var greenWeight = 0.587
  var blueWeight = 0.114
  var hdrEnabled = false

  init() {}

  init(operations: [EditOperation]) {
    self.init()
    for operation in operations {
      switch operation {
      case .toneCurve(let adjustment):
        blackPoint = adjustment.blackPoint
        curveShadows = adjustment.shadows
        curveMidtones = adjustment.midtones
        curveHighlights = adjustment.highlights
        whitePoint = adjustment.whitePoint
      case .whiteBalance(let adjustment):
        temperature = adjustment.temperature
        tint = adjustment.tint
      case .transform(let adjustment):
        straightenDegrees = adjustment.straightenDegrees
        flipHorizontal = adjustment.flipHorizontal
        flipVertical = adjustment.flipVertical
      case .detail(let adjustment):
        sharpening = adjustment.sharpening
        noiseReduction = adjustment.luminanceNoiseReduction
      case .optics(let adjustment): vignetteCorrection = adjustment.vignetteCorrection
      case .effects(let adjustment): vignetteAmount = adjustment.vignetteAmount
      case .calibration(let adjustment):
        redGain = adjustment.redGain
        greenGain = adjustment.greenGain
        blueGain = adjustment.blueGain
      case .blackAndWhite(let adjustment):
        blackAndWhiteEnabled = true
        redWeight = adjustment.redWeight
        greenWeight = adjustment.greenWeight
        blueWeight = adjustment.blueWeight
      case .hdr(let adjustment): hdrEnabled = adjustment.isEnabled
      default: break
      }
    }
  }

  var toneCurve: ToneCurveAdjustmentV1 {
    ToneCurveAdjustmentV1(
      blackPoint: blackPoint,
      shadows: curveShadows,
      midtones: curveMidtones,
      highlights: curveHighlights,
      whitePoint: whitePoint
    )!
  }

  var whiteBalance: WhiteBalanceAdjustmentV1 {
    WhiteBalanceAdjustmentV1(temperature: temperature, tint: tint)!
  }

  var transform: TransformAdjustmentV1 {
    TransformAdjustmentV1(
      straightenDegrees: straightenDegrees,
      flipHorizontal: flipHorizontal,
      flipVertical: flipVertical
    )!
  }

  var detail: DetailAdjustmentV1 {
    DetailAdjustmentV1(
      sharpening: sharpening,
      luminanceNoiseReduction: noiseReduction
    )!
  }

  var optics: OpticsAdjustmentV1 { OpticsAdjustmentV1(vignetteCorrection: vignetteCorrection)! }

  var effects: EffectsAdjustmentV1 { EffectsAdjustmentV1(vignetteAmount: vignetteAmount)! }

  var calibration: CalibrationAdjustmentV1 {
    CalibrationAdjustmentV1(redGain: redGain, greenGain: greenGain, blueGain: blueGain)!
  }

  var blackAndWhite: BlackAndWhiteAdjustmentV1 {
    BlackAndWhiteAdjustmentV1(
      redWeight: redWeight,
      greenWeight: greenWeight,
      blueWeight: blueWeight
    )!
  }
}
