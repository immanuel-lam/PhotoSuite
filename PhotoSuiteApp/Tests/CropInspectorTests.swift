// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI
import Testing

@testable import PhotoSuite

struct CropInspectorTests {
  @Test
  func cropModelStartsAtTheFullImageAndBuildsAValidatedRect() throws {
    let model = CropInspectorModel()
    let rect = try #require(model.rect)

    #expect(rect == NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    #expect(model.validationMessage == nil)
  }

  @Test
  func cropModelRejectsOutOfBoundsCoordinatesAndDimensions() {
    var model = CropInspectorModel()
    model.x = 0.8
    model.width = 0.4

    #expect(model.rect == nil)
    #expect(model.validationMessage != nil)

    model.x = 0.1
    model.width = 0.4
    model.y = -0.01

    #expect(model.rect == nil)
  }

  @Test
  func cropAspectPresetsFitInsideTheUnitCanvas() throws {
    var model = CropInspectorModel(
      rect: try #require(NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.7))
    )

    model.apply(.square)
    let square = try #require(model.rect)
    #expect(square.width == square.height)
    #expect(square.x >= 0 && square.y >= 0)
    #expect(square.x + square.width <= 1)
    #expect(square.y + square.height <= 1)

    model.apply(.sixteenByNine)
    let widescreen = try #require(model.rect)
    #expect(abs((widescreen.width / widescreen.height) - (16.0 / 9.0)) < 0.000_001)
    #expect(widescreen.x + widescreen.width <= 1)
    #expect(widescreen.y + widescreen.height <= 1)

    model.apply(.original)
    #expect(model.rect == NormalizedRect(x: 0, y: 0, width: 1, height: 1))
  }

  @MainActor
  @Test
  func cropInspectorAndGlassFallbackContractsCompile() {
    _ = CropInspector.self
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
      _ = GlassEffectContainer(spacing: 6) {
        Button("Apply") {}
          .buttonStyle(.glassProminent)
      }
    }
  }

  @Test
  func cropAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.cropInspector == "crop-inspector")
    #expect(ModernUIAccessibility.cropAspectPicker == "crop-aspect-picker")
    #expect(ModernUIAccessibility.cropXField == "crop-x-field")
    #expect(ModernUIAccessibility.cropYField == "crop-y-field")
    #expect(ModernUIAccessibility.cropWidthField == "crop-width-field")
    #expect(ModernUIAccessibility.cropHeightField == "crop-height-field")
    #expect(ModernUIAccessibility.cropApplyButton == "crop-apply-button")
    #expect(ModernUIAccessibility.cropResetButton == "crop-reset-button")
    #expect(ModernUIAccessibility.cropRotateButton == "crop-rotate-button")
  }
}
