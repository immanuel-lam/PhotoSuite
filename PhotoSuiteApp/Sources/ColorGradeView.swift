// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI

/// An inspector-ready editor for a durable three-way colour grade.
@MainActor
struct ColorGradeView: View {
  @Binding var grade: ThreeWayColorGrade
  let onCommit: (ThreeWayColorGrade) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("Color Grade", systemImage: "circle.lefthalf.filled")
          .font(.headline)
        Spacer()
        Button("Reset") {
          grade = .neutral
          onCommit(.neutral)
        }
        .disabled(grade.isNeutral)
        .accessibilityIdentifier("color-grade-reset")
      }

      ColorGradeToneEditor(
        title: "Shadows",
        tone: toneBinding(\.shadows),
        onCommit: commit
      )
      ColorGradeToneEditor(
        title: "Midtones",
        tone: toneBinding(\.midtones),
        onCommit: commit
      )
      ColorGradeToneEditor(
        title: "Highlights",
        tone: toneBinding(\.highlights),
        onCommit: commit
      )
    }
    .accessibilityIdentifier("color-grade-editor")
  }

  private func toneBinding(
    _ keyPath: KeyPath<ThreeWayColorGrade, ThreeWayColorGrade.Tone>
  ) -> Binding<ThreeWayColorGrade.Tone> {
    Binding(
      get: { grade[keyPath: keyPath] },
      set: { tone in
        grade = ThreeWayColorGrade(
          shadows: keyPath == \.shadows ? tone : grade.shadows,
          midtones: keyPath == \.midtones ? tone : grade.midtones,
          highlights: keyPath == \.highlights ? tone : grade.highlights
        )!
      }
    )
  }

  private func commit() {
    onCommit(grade)
  }
}

@MainActor
private struct ColorGradeToneEditor: View {
  let title: String
  @Binding var tone: ThreeWayColorGrade.Tone
  let onCommit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline.weight(.medium))
      ColorGradeSlider(
        title: "Hue",
        value: componentBinding(\.hueDegrees),
        range: 0...360,
        format: .number.precision(.fractionLength(0)),
        onCommit: onCommit
      )
      ColorGradeSlider(
        title: "Chroma",
        value: componentBinding(\.chroma),
        range: 0...1,
        format: .number.precision(.fractionLength(2)),
        onCommit: onCommit
      )
      ColorGradeSlider(
        title: "Luminance",
        value: componentBinding(\.luminance),
        range: -1...1,
        format: .number.precision(.fractionLength(2)),
        onCommit: onCommit
      )
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(title) colour grade")
  }

  private func componentBinding(
    _ keyPath: KeyPath<ThreeWayColorGrade.Tone, Double>
  ) -> Binding<Double> {
    Binding(
      get: { tone[keyPath: keyPath] },
      set: { value in
        tone = ThreeWayColorGrade.Tone(
          hueDegrees: keyPath == \.hueDegrees ? value : tone.hueDegrees,
          chroma: keyPath == \.chroma ? value : tone.chroma,
          luminance: keyPath == \.luminance ? value : tone.luminance
        )!
      }
    )
  }
}

@MainActor
private struct ColorGradeSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let format: FloatingPointFormatStyle<Double>
  let onCommit: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(title).frame(width: 76, alignment: .leading)
      Slider(value: $value, in: range) { editing in
        if !editing { onCommit() }
      }
      .accessibilityLabel(title)
      Text(value, format: format)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 42, alignment: .trailing)
    }
  }
}
