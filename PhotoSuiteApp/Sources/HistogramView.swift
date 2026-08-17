// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI

/// A compact RGB and luminance histogram for the current bounded preview.
@MainActor
struct HistogramView: View {
  let histogram: RenderHistogram?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Histogram", systemImage: "chart.xyaxis.line")
          .font(.headline)
        Spacer()
        Text("Preview")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let histogram {
        HistogramPlot(histogram: histogram)
          .frame(height: 108)
          .accessibilityLabel("Preview histogram")
          .accessibilityValue("\(histogram.red.reduce(0, +)) pixels")
      } else {
        ContentUnavailableView(
          "Histogram Unavailable",
          systemImage: "chart.bar.xaxis",
          description: Text("Render a preview to view its RGB and luminance distribution.")
        )
        .frame(maxWidth: .infinity, minHeight: 108)
      }
    }
    .accessibilityIdentifier("preview-histogram")
  }
}

@MainActor
private struct HistogramPlot: View {
  let histogram: RenderHistogram

  var body: some View {
    Canvas { context, size in
      let maximum = max(
        1,
        histogram.red.max() ?? 0,
        histogram.green.max() ?? 0,
        histogram.blue.max() ?? 0,
        histogram.luminance.max() ?? 0
      )
      stroke(histogram.luminance, color: .white.opacity(0.82), maximum: maximum, in: size, context)
      stroke(histogram.red, color: .red.opacity(0.8), maximum: maximum, in: size, context)
      stroke(histogram.green, color: .green.opacity(0.8), maximum: maximum, in: size, context)
      stroke(histogram.blue, color: .blue.opacity(0.8), maximum: maximum, in: size, context)
    }
    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }

  private func stroke(
    _ bins: [UInt64],
    color: Color,
    maximum: UInt64,
    in size: CGSize,
    _ context: GraphicsContext
  ) {
    var path = Path()
    for index in bins.indices {
      let x = size.width * CGFloat(index) / CGFloat(RenderHistogram.binCount - 1)
      let proportion = CGFloat(Double(bins[index]) / Double(maximum))
      let point = CGPoint(x: x, y: size.height * (1 - proportion))
      if index == bins.startIndex {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    context.stroke(path, with: .color(color), lineWidth: 1)
  }
}
