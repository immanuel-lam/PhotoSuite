// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class RenderGraphTests: XCTestCase {
  func testVersionOneContrastAndSaturationMappingsKeepExactEndpointsAndIdentity() {
    XCTAssertEqual(RecipeRenderContractV1.contrastFactor(for: -1), 0.25, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.contrastFactor(for: 0), 1, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.contrastFactor(for: 1), 4, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.saturationFactor(for: -1), 0, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.saturationFactor(for: 0), 1, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.saturationFactor(for: 1), 2, accuracy: 0.000_001)
  }

  func testExposureChangesRenderedPixel() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let exposed = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.exposureEV(1)]),
      maximumPixelDimension: nil
    )

    let baselinePixel = try middlePixel(of: baseline)
    let exposedPixel = try middlePixel(of: exposed)
    XCTAssertGreaterThan(exposedPixel.red, baselinePixel.red)
    XCTAssertGreaterThan(exposedPixel.green, baselinePixel.green)
  }

  func testNormalizedZeroAdjustmentsAreIdentityOperations() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let adjusted = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(
        operations: [.contrast(0), .highlights(0), .shadows(0), .saturation(0)]
      ),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(
      try DeterministicImageFixture.rgba8Data(from: adjusted),
      try DeterministicImageFixture.rgba8Data(from: baseline)
    )
  }

  func testNeutralThreeWayColorGradeIsAnExactIdentityOperation() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let graded = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.threeWayColorGrade(.neutral)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(
      try DeterministicImageFixture.rgba8Data(from: graded),
      try DeterministicImageFixture.rgba8Data(from: baseline)
    )
  }

  func testShadowColorGradeHasItsLargestEffectInShadows() async throws {
    let fixture = try makeTonalFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let grade = try makeGrade(shadows: .init(hueDegrees: 0, chroma: 0, luminance: 0.25))
    let graded = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.threeWayColorGrade(grade)]),
      maximumPixelDimension: nil
    )

    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let gradedData = try DeterministicImageFixture.rgba8Data(from: graded)
    let darkLift =
      Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: baselineData).red)
    let brightLift =
      Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: baselineData).red)

    XCTAssertGreaterThan(darkLift, brightLift)
    XCTAssertEqual(darkLift, 85)
  }

  func testMidtoneColorGradeHasItsLargestEffectInMidtones() async throws {
    let fixture = try makeTonalFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let grade = try makeGrade(midtones: .init(hueDegrees: 0, chroma: 0, luminance: 0.25))
    let graded = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.threeWayColorGrade(grade)]),
      maximumPixelDimension: nil
    )

    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let gradedData = try DeterministicImageFixture.rgba8Data(from: graded)
    let midLift =
      Int(DeterministicImageFixture.pixel(x: 1, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 1, y: 0, width: 3, in: baselineData).red)
    let darkLift =
      Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: baselineData).red)
    let brightLift =
      Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: baselineData).red)

    XCTAssertGreaterThan(midLift, darkLift)
    XCTAssertGreaterThan(midLift, brightLift)
    XCTAssertEqual(midLift, 37)
  }

  func testHighlightColorGradeHasItsLargestEffectInHighlights() async throws {
    let fixture = try makeTonalFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let grade = try makeGrade(highlights: .init(hueDegrees: 0, chroma: 0, luminance: 0.25))
    let graded = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.threeWayColorGrade(grade)]),
      maximumPixelDimension: nil
    )

    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let gradedData = try DeterministicImageFixture.rgba8Data(from: graded)
    let darkLift =
      Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: baselineData).red)
    let brightLift =
      Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: gradedData).red)
      - Int(DeterministicImageFixture.pixel(x: 2, y: 0, width: 3, in: baselineData).red)

    XCTAssertGreaterThan(brightLift, darkLift)
    XCTAssertEqual(brightLift, 12)
  }

  func testShadowHueAndChromaBiasTheSelectedColourChannels() async throws {
    let fixture = try makeTonalFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let grade = try makeGrade(shadows: .init(hueDegrees: 240, chroma: 0.5, luminance: 0))
    let graded = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.threeWayColorGrade(grade)]),
      maximumPixelDimension: nil
    )

    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let gradedData = try DeterministicImageFixture.rgba8Data(from: graded)
    let baselinePixel = DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: baselineData)
    let gradedPixel = DeterministicImageFixture.pixel(x: 0, y: 0, width: 3, in: gradedData)
    let redDelta = Int(gradedPixel.red) - Int(baselinePixel.red)
    let blueDelta = Int(gradedPixel.blue) - Int(baselinePixel.blue)

    XCTAssertGreaterThan(blueDelta, redDelta)
  }

  func testHighlightAndShadowDeltasSelectDifferentTonalRanges() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let highlights = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.highlights(1)]),
      maximumPixelDimension: nil
    )
    let shadows = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.shadows(1)]),
      maximumPixelDimension: nil
    )
    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let highlightData = try DeterministicImageFixture.rgba8Data(from: highlights)
    let shadowData = try DeterministicImageFixture.rgba8Data(from: shadows)
    let darkBase = DeterministicImageFixture.pixel(x: 0, y: 0, width: 8, in: baselineData)
    let brightBase = DeterministicImageFixture.pixel(x: 7, y: 5, width: 8, in: baselineData)
    let darkHighlight = DeterministicImageFixture.pixel(x: 0, y: 0, width: 8, in: highlightData)
    let brightHighlight = DeterministicImageFixture.pixel(x: 7, y: 5, width: 8, in: highlightData)
    let darkShadow = DeterministicImageFixture.pixel(x: 0, y: 0, width: 8, in: shadowData)
    let brightShadow = DeterministicImageFixture.pixel(x: 7, y: 5, width: 8, in: shadowData)
    let brightHighlightLift = Int(brightHighlight.red) - Int(brightBase.red)
    let darkHighlightLift = Int(darkHighlight.red) - Int(darkBase.red)
    let darkShadowLift = Int(darkShadow.red) - Int(darkBase.red)
    let brightShadowLift = Int(brightShadow.red) - Int(brightBase.red)

    XCTAssertGreaterThan(brightHighlightLift, darkHighlightLift)
    XCTAssertGreaterThan(darkShadowLift, brightShadowLift)
  }

  func testCropUsesTopLeftFloorCeilEdgesAndExactDimensions() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let crop = try XCTUnwrap(NormalizedRect(x: 0.24, y: 0, width: 0.51, height: 0.5))

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.normalizedCrop(crop)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(image.width, 5)
    XCTAssertEqual(image.height, 3)
  }

  func testQuarterTurnRotationUsesExactDimensions() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let quarter = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.rotationDegrees(90)]),
      maximumPixelDimension: nil
    )
    let half = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.rotationDegrees(180)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(quarter.width, 6)
    XCTAssertEqual(quarter.height, 8)
    XCTAssertEqual(half.width, 8)
    XCTAssertEqual(half.height, 6)
  }

  func testThreeQuarterTurnUsesExactDimensions() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.rotationDegrees(270)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual([image.width, image.height], [6, 8])
  }

  func testArbitraryRotationUsesFullIntegralBoundingBox() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.rotationDegrees(45)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual([image.width, image.height], [10, 10])
  }

  func testNearQuarterTurnUsesArbitraryRotationPath() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let recipe = makeRecipe(operations: [.rotationDegrees(90.000_000_05)])
    let sourceImage = try XCTUnwrap(
      CIImage(contentsOf: fixture.source, options: [.applyOrientationProperty: true])
    )
    let compiled = try EditGraphCompiler.compile(sourceImage, recipe: recipe)
    XCTAssertEqual([Int(compiled.extent.width), Int(compiled.extent.height)], [8, 10])

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: recipe,
      maximumPixelDimension: nil
    )

    XCTAssertEqual([image.width, image.height], [8, 10])
  }

  func testRecipeOrderChangesGeometry() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let leftHalf = try XCTUnwrap(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))

    let cropThenRotate = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.normalizedCrop(leftHalf), .rotationDegrees(90)]),
      maximumPixelDimension: nil
    )
    let rotateThenCrop = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.rotationDegrees(90), .normalizedCrop(leftHalf)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual([cropThenRotate.width, cropThenRotate.height], [6, 4])
    XCTAssertEqual([rotateThenCrop.width, rotateThenCrop.height], [3, 8])
  }

  func testRecipeOrderChangesRenderedPixelsAtEqualDimensions() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let exposureThenHighlights = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.exposureEV(0.5), .highlights(0.75)]),
      maximumPixelDimension: nil
    )
    let highlightsThenExposure = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.highlights(0.75), .exposureEV(0.5)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(exposureThenHighlights.width, highlightsThenExposure.width)
    XCTAssertEqual(exposureThenHighlights.height, highlightsThenExposure.height)
    XCTAssertNotEqual(
      try DeterministicImageFixture.rgba8Data(from: exposureThenHighlights),
      try DeterministicImageFixture.rgba8Data(from: highlightsThenExposure)
    )
  }

  func testUnknownOperationReturnsIndexedTypedError() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: makeRecipe(
          operations: [.exposureEV(0), .unknown("futureTone", payload: [:])]
        ),
        maximumPixelDimension: nil
      )
      XCTFail("Expected unsupported operation error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .unsupportedOperation(index: 1, kind: "futureTone"))
    }
  }

  func testNormalizedDeltaOutsideUnitRangeReturnsIndexedTypedError() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: makeRecipe(operations: [.contrast(1.01)]),
        maximumPixelDimension: nil
      )
      XCTFail("Expected invalid operation value error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .invalidOperationValue(index: 0, operation: "contrast"))
    }
  }

  func testExposureThatOverflowsFloatReturnsIndexedTypedError() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: makeRecipe(operations: [.exposureEV(Double.greatestFiniteMagnitude)]),
        maximumPixelDimension: nil
      )
      XCTFail("Expected invalid exposure value")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .invalidOperationValue(index: 0, operation: "exposureEV"))
    }
  }

  func testUnsupportedRenderSchemaVersionReturnsTypedError() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let recipe = EditRecipe(
      assetID: UUID(),
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 2,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: recipe,
        maximumPixelDimension: nil
      )
      XCTFail("Expected unsupported render schema error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .unsupportedRenderSchemaVersion(2))
    }
  }

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func makeTonalFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    let pixels: [UInt8] = [
      64, 64, 64, 255,
      188, 188, 188, 255,
      243, 243, 243, 255,
    ]
    return (
      directory,
      try DeterministicImageFixture.makePNG(
        in: directory,
        name: "tonal.png",
        width: 3,
        height: 1,
        pixels: pixels
      )
    )
  }

  private func makeRecipe(operations: [EditOperation] = []) -> EditRecipe {
    EditRecipe(
      assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      ),
      operations: operations
    )
  }

  private func middlePixel(
    of image: CGImage
  ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    let data = try DeterministicImageFixture.rgba8Data(from: image)
    return DeterministicImageFixture.pixel(
      x: image.width / 2,
      y: image.height / 2,
      width: image.width,
      in: data
    )
  }

  private func makeGrade(
    shadows: ThreeWayColorGrade.Tone? = nil,
    midtones: ThreeWayColorGrade.Tone? = nil,
    highlights: ThreeWayColorGrade.Tone? = nil
  ) throws -> ThreeWayColorGrade {
    try XCTUnwrap(
      ThreeWayColorGrade(
        shadows: shadows ?? .init(hueDegrees: 0, chroma: 0, luminance: 0)!,
        midtones: midtones ?? .init(hueDegrees: 0, chroma: 0, luminance: 0)!,
        highlights: highlights ?? .init(hueDegrees: 0, chroma: 0, luminance: 0)!
      )
    )
  }
}
