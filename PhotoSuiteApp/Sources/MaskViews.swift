// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct MaskControls: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var expanded = true
  @State private var selectedKind: MaskKind = .brush

  private let kinds: [MaskKind] = [
    .brush,
    .linearGradient,
    .radialGradient,
    .colorRange,
    .luminanceRange,
    .depthRange,
  ]

  var body: some View {
    DisclosureGroup("Masks", isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Picker("Mask type", selection: $selectedKind) {
            ForEach(kinds, id: \.self) { kind in
              Text(kind.title).tag(kind)
            }
          }
          .labelsHidden()

          Button {
            Task { await workspace.addMask(kind: selectedKind, name: selectedKind.title) }
          } label: {
            Label("Add", systemImage: "plus")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .accessibilityIdentifier("mask-add-button")
        }

        if workspace.currentMasks.isEmpty {
          Text("Create a local mask to target adjustments without changing the original file.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          ForEach(workspace.currentMasks) { mask in
            MaskRow(workspace: workspace, mask: mask)
          }
        }

        Text(
          "Brush, gradient, colour, luminance, and depth graphs are stored in the recipe. Rasterisation and model-generated selections require a verified local model pack."
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)
    }
    .accessibilityIdentifier("mask-controls")
  }
}

@MainActor
private struct MaskRow: View {
  @Bindable var workspace: PhotoWorkspace
  let mask: MaskDefinition

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Image(systemName: mask.kind.symbol)
          .frame(width: 20)
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(mask.name ?? mask.kind.title)
            .font(.callout.weight(.medium))
          Text(mask.kind.title + (mask.isInverted ? " · Inverted" : ""))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await workspace.toggleMaskInverted(id: mask.id) }
        } label: {
          Image(systemName: mask.isInverted ? "circle.lefthalf.filled" : "circle")
        }
        .buttonStyle(.plain)
        .help(mask.isInverted ? "Use mask normally" : "Invert mask")
        .accessibilityLabel(mask.isInverted ? "Use mask normally" : "Invert mask")

        Button(role: .destructive) {
          Task { await workspace.removeMask(id: mask.id) }
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .help("Delete mask")
        .accessibilityLabel("Delete mask")
      }

      Button("Add centred brush sample") {
        guard
          let point = MaskPointV1(x: 0.5, y: 0.5),
          let sample = MaskBrushSampleV1(point: point, pressure: 1),
          let brush = BrushMaskV1(samples: [sample], radius: 0.2, feather: 0.5, flow: 1)
        else { return }
        let graph = MaskGraphV1(
          components: [
            MaskGraphComponentV1(
              id: UUID(),
              operation: .add,
              primitive: .brush(brush)
            )
          ],
          isInverted: mask.isInverted
        )
        Task { await workspace.replaceMaskGraph(id: mask.id, graph: graph) }
      }
      .buttonStyle(.link)
      .font(.caption)
      .disabled(mask.kind != .brush)
    }
    .padding(10)
    .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
  }
}

extension MaskKind {
  fileprivate var title: String {
    switch self {
    case .brush: "Brush"
    case .linearGradient: "Linear gradient"
    case .radialGradient: "Radial gradient"
    case .luminanceRange: "Luminance range"
    case .colorRange: "Colour range"
    case .depthRange: "Depth range"
    case .subject: "Subject"
    case .sky: "Sky"
    case .background: "Background"
    case .object: "Object"
    case .unknown(let value): value
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .brush: "paintbrush.pointed"
    case .linearGradient: "rectangle.lefthalf.inset.filled"
    case .radialGradient: "circle.dashed"
    case .luminanceRange: "sun.max"
    case .colorRange: "eyedropper"
    case .depthRange: "square.3.layers.3d"
    case .subject, .background, .object: "person.crop.rectangle"
    case .sky: "cloud.sun"
    case .unknown: "questionmark"
    }
  }
}
