// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI

/// The local AI surface is deliberately explicit about model-pack state.
/// Controls become active only after a signed, checksum-verified pack is
/// installed. This keeps the offline workflow honest while exposing the
/// complete Lightroom-style selection and enhancement surface.
@MainActor
struct AIModelControls: View {
  @State private var expanded = false
  private let cards = AIModelCatalog.defaultCards

  var body: some View {
    DisclosureGroup("Local AI", isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Runs on this Mac. No photographs are uploaded.")
          .font(.caption)
          .foregroundStyle(.secondary)

        ForEach(
          cards.filter { [.subject, .sky, .background, .people, .landscape].contains($0.kind) }
        ) {
          card in
          AIModelActionRow(card: card, title: card.kind.displayName, symbol: card.kind.symbol)
        }

        Divider()

        ForEach(
          cards.filter {
            [.denoise, .superResolution, .lensBlur, .inpainting, .dustRemoval, .reflectionRemoval]
              .contains($0.kind)
          }
        ) {
          card in
          AIModelActionRow(card: card, title: card.kind.displayName, symbol: card.kind.symbol)
        }

        Text(
          "Signed model packs are not installed in this pre-alpha build. Install a verified pack to enable these actions."
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 8)
    }
    .accessibilityIdentifier("local-ai-controls")
  }
}

@MainActor
private struct AIModelActionRow: View {
  let card: AIModelCard
  let title: String
  let symbol: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .frame(width: 20)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text("Model pack \(card.version) · \(card.minimumMemoryMB) MB")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      Button("Install") {}
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
        .help("Install a signed model pack to enable \(title.lowercased())")
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue("Model pack not installed")
  }
}

extension AIModelKind {
  fileprivate var displayName: String {
    switch self {
    case .subject: "Select Subject"
    case .sky: "Select Sky"
    case .background: "Select Background"
    case .object: "Select Object"
    case .people: "Select People"
    case .landscape: "Select Landscape"
    case .depth: "Depth Mask"
    case .denoise: "Denoise"
    case .superResolution: "Super Resolution"
    case .lensBlur: "Lens Blur"
    case .inpainting: "Generative Remove"
    case .dustRemoval: "Dust Detection"
    case .reflectionRemoval: "Reflection Removal"
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .subject, .people: "person.crop.rectangle"
    case .sky: "cloud.sun"
    case .background, .landscape: "mountain.2"
    case .object: "cube"
    case .depth: "square.3.layers.3d"
    case .denoise: "wand.and.stars"
    case .superResolution: "arrow.up.left.and.arrow.down.right"
    case .lensBlur: "camera.aperture"
    case .inpainting: "eraser"
    case .dustRemoval: "sparkles"
    case .reflectionRemoval: "rectangle.on.rectangle"
    }
  }
}
