// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import PhotoDomain
import PhotoWorkflow
import RenderCore
import SwiftUI

/// The local AI surface is deliberately explicit about model-pack state.
/// Controls become active only after a signed, checksum-verified pack is
/// installed. This keeps the offline workflow honest while exposing the
/// complete Lightroom-style selection and enhancement surface.
@MainActor
struct AIModelControls: View {
  @Bindable var workspace: PhotoWorkspace
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
          AIModelActionRow(
            card: card,
            title: card.kind.displayName,
            symbol: card.kind.symbol,
            workspace: workspace
          )
        }

        Divider()

        ForEach(
          cards.filter {
            [.denoise, .superResolution, .lensBlur, .inpainting, .dustRemoval, .reflectionRemoval]
              .contains($0.kind)
          }
        ) {
          card in
          AIModelActionRow(
            card: card,
            title: card.kind.displayName,
            symbol: card.kind.symbol,
            workspace: workspace
          )
        }

        Text(
          "Apple Vision foreground, subject, and person masks run locally. Other model packs require a verified offline installation."
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
  let workspace: PhotoWorkspace
  @State private var isRunning = false
  @State private var statusMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
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
        Button(visionKind == nil ? "Install" : (isRunning ? "Running" : "Run")) {
          Task { await runVisionMask() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(visionKind == nil || workspace.preview == nil || isRunning)
        .help(
          visionKind == nil
            ? "Install a verified model pack to enable \(title.lowercased())"
            : "Run Apple Vision locally on the selected photograph"
        )
      }
      if let statusMessage {
        Text(statusMessage)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(visionKind == nil ? "Model pack not installed" : "Apple Vision available")
  }

  private var visionKind: VisionAIMaskKind? {
    switch card.kind {
    case .subject: .subject
    case .people: .person
    default: nil
    }
  }

  private func runVisionMask() async {
    guard
      let kind = visionKind,
      let asset = workspace.selectedAsset,
      let recipe = workspace.currentRecipe,
      let preview = workspace.preview,
      let dimensions = PixelDimensions(
        width: preview.pixelDimensions.width,
        height: preview.pixelDimensions.height
      ),
      let image = makeImageBuffer(preview.imageData, dimensions: dimensions)
    else {
      statusMessage = "Select a photograph with a rendered preview first."
      return
    }

    isRunning = true
    statusMessage = nil
    let identity = MaskRequestIdentity(
      revision: MaskRevisionIdentity(
        assetID: asset.id,
        maskID: UUID(),
        revision: recipe.revision
      ),
      requestID: UUID()
    )
    do {
      let result = try await VisionAIModelService().generateMask(
        VisionAIMaskRequest(identity: identity, image: image, kind: kind)
      )
      guard result.identity == identity else {
        statusMessage = "The local AI result was stale and was discarded."
        return
      }
      await workspace.applyGeneratedMask(
        result.mask,
        assetID: identity.revision.assetID,
        expectedRevision: identity.revision.revision
      )
      statusMessage = workspace.lastError?.localizedDescription ?? "Mask applied to the recipe."
    } catch {
      statusMessage = error.localizedDescription
    }
    isRunning = false
  }

  private func makeImageBuffer(_ data: Data, dimensions: PixelDimensions) -> ImageBuffer? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == dimensions.width,
      image.height == dimensions.height,
      let context = CGContext(
        data: nil,
        width: dimensions.width,
        height: dimensions.height,
        bitsPerComponent: 8,
        bytesPerRow: dimensions.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let contextData = context.data
    else {
      return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height))
    return ImageBuffer(
      data: Data(bytes: contextData, count: dimensions.width * dimensions.height * 4),
      dimensions: dimensions,
      bytesPerRow: UInt(dimensions.width * 4),
      pixelFormat: .rgba8,
      colorSpaceName: "sRGB"
    )
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
