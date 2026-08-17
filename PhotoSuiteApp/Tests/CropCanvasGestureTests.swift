// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import PhotoDomain
import SwiftUI
import Testing

@testable import PhotoSuite

struct CropCanvasGestureTests {
  @Test
  func movingTheCropRectangleUsesCanvasTranslationAndStaysInsideTheImage() throws {
    let start = try #require(NormalizedRect(x: 0.2, y: 0.25, width: 0.4, height: 0.3))
    let model = CropCanvasInteractionModel(rect: start)

    let moved = try #require(
      model.rect(
        after: CGSize(width: 40, height: -20),
        handle: .move,
        in: CGSize(width: 200, height: 200)
      )
    )

    #expect(moved == NormalizedRect(x: 0.4, y: 0.15, width: 0.4, height: 0.3))
  }

  @Test
  func cornerResizeChangesOnlyTheDraggedEdges() throws {
    let start = try #require(NormalizedRect(x: 0.2, y: 0.25, width: 0.4, height: 0.3))
    let model = CropCanvasInteractionModel(rect: start)

    let resized = try #require(
      model.rect(
        after: CGSize(width: 20, height: 10),
        handle: .bottomTrailing,
        in: CGSize(width: 200, height: 200)
      )
    )

    #expect(abs(resized.x - 0.2) < 0.000_001)
    #expect(abs(resized.y - 0.25) < 0.000_001)
    #expect(abs(resized.width - 0.5) < 0.000_001)
    #expect(abs(resized.height - 0.35) < 0.000_001)
  }

  @Test
  func aspectLockedCornerResizePreservesTheRequestedRatio() throws {
    let start = try #require(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
    let model = CropCanvasInteractionModel(rect: start, aspectRatio: 2)

    let resized = try #require(
      model.rect(
        after: CGSize(width: 20, height: 10),
        handle: .bottomTrailing,
        in: CGSize(width: 200, height: 200)
      )
    )

    #expect(abs((resized.width / resized.height) - 2) < 0.000_001)
    #expect(resized.x == start.x)
    #expect(resized.y == start.y)
  }

  @Test
  func settingAnAspectRatioFitsTheExistingCropWithoutLeavingImageBounds() throws {
    var model = CropCanvasInteractionModel(
      rect: try #require(NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.7))
    )

    model.setAspectRatio(0.5)
    let fitted = model.rect

    #expect(abs((fitted.width / fitted.height) - 0.5) < 0.000_001)
    #expect(fitted.x >= 0)
    #expect(fitted.y >= 0)
    #expect(fitted.x + fitted.width <= 1)
    #expect(fitted.y + fitted.height <= 1)
  }

  @Test
  func resizeClampsTheDraggedEdgesToTheImageBounds() throws {
    let start = try #require(NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
    let model = CropCanvasInteractionModel(rect: start)

    let resized = try #require(
      model.rect(
        after: CGSize(width: 200, height: 200),
        handle: .bottomTrailing,
        in: CGSize(width: 200, height: 200)
      )
    )

    #expect(resized.x == 0.2)
    #expect(resized.y == 0.2)
    #expect(resized.width == 0.8)
    #expect(resized.height == 0.8)
  }

  @Test
  func canvasPointConvertsOnlyInsideTheAspectFitImageRect() {
    let imageRect = CGRect(x: 50, y: 0, width: 100, height: 200)

    #expect(
      CropCanvasInteractionModel.normalizedPoint(CGPoint(x: 100, y: 100), in: imageRect)
        == CGPoint(x: 0.5, y: 0.5))
    #expect(
      CropCanvasInteractionModel.normalizedPoint(CGPoint(x: 10, y: 100), in: imageRect) == nil)
  }

  @MainActor
  @Test
  func cropCanvasOverlayAndGlassFallbackContractsCompile() {
    _ = CropCanvasOverlay.self
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
  }

  @Test
  func cropCanvasAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.cropCanvasOverlay == "crop-canvas-overlay")
    #expect(ModernUIAccessibility.cropCanvasToggle == "crop-canvas-toggle")
    #expect(ModernUIAccessibility.cropCanvasApply == "crop-canvas-apply")
    #expect(ModernUIAccessibility.cropCanvasCancel == "crop-canvas-cancel")
  }
}
