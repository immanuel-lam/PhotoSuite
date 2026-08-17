// SPDX-License-Identifier: MPL-2.0

import CoreGraphics
import CryptoKit
import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class DevelopRenderTests: XCTestCase {
  func testVersionOneDevelopMappingsPinExactNormalizedEndpoints() {
    XCTAssertEqual(
      RecipeRenderContractV1.whiteBalanceTemperature(for: -1),
      3_000,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      RecipeRenderContractV1.whiteBalanceTemperature(for: 1),
      10_000,
      accuracy: 0.000_001
    )
    XCTAssertEqual(RecipeRenderContractV1.whiteBalanceTint(for: -1), -150)
    XCTAssertEqual(RecipeRenderContractV1.whiteBalanceTint(for: 1), 150)
    XCTAssertEqual(RecipeRenderContractV1.noiseLevel(for: 1), 0.1, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.sharpenRadius(for: 1), 3, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.sharpness(for: 1), 2, accuracy: 0.000_001)
    XCTAssertEqual(RecipeRenderContractV1.calibrationFactor(for: -1), 0.5)
    XCTAssertEqual(RecipeRenderContractV1.calibrationFactor(for: 1), 1.5)
  }

  func testOpticsAndEffectsMappingsPinSafeBoundedEndpoints() {
    XCTAssertEqual(RecipeRenderContractV1.lensDistortionScale(for: -1), -0.35)
    XCTAssertEqual(RecipeRenderContractV1.lensDistortionScale(for: 1), 0.35)
    XCTAssertEqual(
      RecipeRenderContractV1.chromaticAberrationOffset(for: 1, longestEdge: 1_000),
      20,
      accuracy: 0.000_001
    )
    XCTAssertEqual(RecipeRenderContractV1.defringeStrength(for: 1), 0.65)
    XCTAssertEqual(RecipeRenderContractV1.grainAmplitude(for: 1), 0.08)
    XCTAssertEqual(
      RecipeRenderContractV1.dehazeContrastFactor(for: -1),
      0.5,
      accuracy: 0.000_001
    )
    XCTAssertEqual(
      RecipeRenderContractV1.dehazeContrastFactor(for: 1),
      2,
      accuracy: 0.000_001
    )
    XCTAssertEqual(RecipeRenderContractV1.dehazeSaturationFactor(for: -1), 0.75)
    XCTAssertEqual(RecipeRenderContractV1.dehazeSaturationFactor(for: 1), 1.25)
  }

  func testToneCurveIdentityPreservesPixelsAndAdjustedCurveChangesPixels() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let identity = try XCTUnwrap(
      ToneCurveAdjustmentV1(
        blackPoint: 0,
        shadows: 0.25,
        midtones: 0.5,
        highlights: 0.75,
        whitePoint: 1
      )
    )
    let lifted = try XCTUnwrap(
      ToneCurveAdjustmentV1(
        blackPoint: 0.1,
        shadows: 0.35,
        midtones: 0.65,
        highlights: 0.85,
        whitePoint: 1
      )
    )

    let identityImage = try await render(fixture.source, operations: [.toneCurve(identity)])
    let liftedImage = try await render(fixture.source, operations: [.toneCurve(lifted)])

    XCTAssertEqual(try pixels(identityImage), try pixels(baseline))
    XCTAssertNotEqual(try pixels(liftedImage), try pixels(baseline))
  }

  func testWhiteBalanceAndCalibrationChangeChannelBalance() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let whiteBalance = try XCTUnwrap(
      WhiteBalanceAdjustmentV1(temperature: 0.8, tint: 0.5)
    )
    let calibration = try XCTUnwrap(
      CalibrationAdjustmentV1(redGain: 0.8, greenGain: 0, blueGain: -0.8)
    )

    let balanced = try await render(
      fixture.source,
      operations: [.whiteBalance(whiteBalance)]
    )
    let calibrated = try await render(
      fixture.source,
      operations: [.calibration(calibration)]
    )

    XCTAssertNotEqual(try pixels(balanced), try pixels(baseline))
    let basePixel = try middlePixel(baseline)
    let calibratedPixel = try middlePixel(calibrated)
    XCTAssertGreaterThan(calibratedPixel.red, basePixel.red)
    XCTAssertLessThan(calibratedPixel.blue, basePixel.blue)
  }

  func testBlackAndWhiteMixProducesNeutralRGBChannels() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let adjustment = try XCTUnwrap(
      BlackAndWhiteAdjustmentV1(redWeight: 0.3, greenWeight: 0.6, blueWeight: 0.1)
    )

    let image = try await render(fixture.source, operations: [.blackAndWhite(adjustment)])
    let pixel = try middlePixel(image)

    XCTAssertEqual(pixel.red, pixel.green, accuracy: 1)
    XCTAssertEqual(pixel.green, pixel.blue, accuracy: 1)
  }

  func testTransformFlipsPixelsAndStraightenUsesExpandedBounds() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let flip = try XCTUnwrap(
      TransformAdjustmentV1(
        straightenDegrees: 0,
        flipHorizontal: true,
        flipVertical: false
      )
    )
    let straighten = try XCTUnwrap(
      TransformAdjustmentV1(
        straightenDegrees: 10,
        flipHorizontal: false,
        flipVertical: false
      )
    )

    let flipped = try await render(fixture.source, operations: [.transform(flip)])
    let straightened = try await render(fixture.source, operations: [.transform(straighten)])
    let baselinePixels = try pixels(baseline)
    let flippedPixels = try pixels(flipped)

    XCTAssertEqual(
      DeterministicImageFixture.pixel(x: 0, y: 2, width: 8, in: flippedPixels).red,
      DeterministicImageFixture.pixel(x: 7, y: 2, width: 8, in: baselinePixels).red
    )
    XCTAssertGreaterThan(straightened.width, baseline.width)
    XCTAssertGreaterThan(straightened.height, baseline.height)
  }

  func testDetailOpticsAndEffectsProduceDeterministicPixelChanges() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let detail = try XCTUnwrap(
      DetailAdjustmentV1(sharpening: 1, luminanceNoiseReduction: 0.5)
    )
    let optics = try XCTUnwrap(OpticsAdjustmentV1(vignetteCorrection: 0.8))
    let effects = try XCTUnwrap(EffectsAdjustmentV1(vignetteAmount: 0.8))

    let detailed = try await render(fixture.source, operations: [.detail(detail)])
    let corrected = try await render(fixture.source, operations: [.optics(optics)])
    let vignetted = try await render(fixture.source, operations: [.effects(effects)])
    let baselineCorner = try cornerPixel(baseline)
    let correctedCorner = try cornerPixel(corrected)
    let vignettedCorner = try cornerPixel(vignetted)

    XCTAssertNotEqual(try pixels(detailed), try pixels(baseline))
    XCTAssertNotEqual(try pixels(corrected), try pixels(baseline))
    XCTAssertGreaterThanOrEqual(correctedCorner.red, baselineCorner.red)
    XCTAssertLessThan(vignettedCorner.red, baselineCorner.red)
  }

  func testExtendedOpticsAndEffectsProduceDeterministicPixelChanges() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let distortion = try XCTUnwrap(
      OpticsAdjustmentV1(
        vignetteCorrection: 0,
        lensDistortion: 0.8,
        chromaticAberration: 0,
        defringe: 0
      )
    )
    let aberration = try XCTUnwrap(
      OpticsAdjustmentV1(
        vignetteCorrection: 0,
        lensDistortion: 0,
        chromaticAberration: 0.8,
        defringe: 0
      )
    )
    let defringe = try XCTUnwrap(
      OpticsAdjustmentV1(
        vignetteCorrection: 0,
        lensDistortion: 0,
        chromaticAberration: 0,
        defringe: 0.8
      )
    )
    let grain = try XCTUnwrap(
      EffectsAdjustmentV1(vignetteAmount: 0, grainAmount: 0.8, dehaze: 0)
    )
    let dehaze = try XCTUnwrap(
      EffectsAdjustmentV1(vignetteAmount: 0, grainAmount: 0, dehaze: 0.8)
    )

    let distorted = try await render(fixture.source, operations: [.optics(distortion)])
    let aberrated = try await render(fixture.source, operations: [.optics(aberration)])
    let defringed = try await render(fixture.source, operations: [.optics(defringe)])
    let grained = try await render(fixture.source, operations: [.effects(grain)])
    let dehazed = try await render(fixture.source, operations: [.effects(dehaze)])
    let grainedAgain = try await render(fixture.source, operations: [.effects(grain)])

    XCTAssertNotEqual(try pixels(distorted), try pixels(baseline))
    XCTAssertNotEqual(try pixels(aberrated), try pixels(baseline))
    XCTAssertNotEqual(try pixels(defringed), try pixels(baseline))
    XCTAssertNotEqual(try pixels(grained), try pixels(baseline))
    XCTAssertNotEqual(try pixels(dehazed), try pixels(baseline))
    XCTAssertEqual(try pixels(grained), try pixels(grainedAgain))
  }

  func testHDRIntentIsRecognizedAndPreservesCurrentExtendedRangeGraphPixels() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let baseline = try await render(fixture.source)
    let adjustment = HDRAdjustmentV1(isEnabled: true, preservesExtendedRange: true)

    let adjusted = try await render(fixture.source, operations: [.hdr(adjustment)])

    XCTAssertEqual(try pixels(adjusted), try pixels(baseline))
  }

  func testColorGradeCompositeHasPinnedRenderDigest() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let tone = try XCTUnwrap(
      ToneCurveAdjustmentV1(
        blackPoint: 0.08,
        shadows: 0.3,
        midtones: 0.58,
        highlights: 0.82,
        whitePoint: 0.96
      )
    )
    let whiteBalance = try XCTUnwrap(WhiteBalanceAdjustmentV1(temperature: 0.2, tint: -0.1))
    let calibration = try XCTUnwrap(
      CalibrationAdjustmentV1(redGain: 0.15, greenGain: -0.05, blueGain: 0.1)
    )
    let blackAndWhite = try XCTUnwrap(
      BlackAndWhiteAdjustmentV1(redWeight: 0.25, greenWeight: 0.65, blueWeight: 0.1)
    )
    let grade = try XCTUnwrap(
      ThreeWayColorGrade(
        shadows: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 210, chroma: 0.08, luminance: -0.03)
        ),
        midtones: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 35, chroma: 0.05, luminance: 0)
        ),
        highlights: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 50, chroma: 0.1, luminance: 0.03)
        )
      )
    )

    let image = try await render(
      fixture.source,
      operations: [
        .threeWayColorGrade(grade),
        .toneCurve(tone),
        .whiteBalance(whiteBalance),
        .calibration(calibration),
        .blackAndWhite(blackAndWhite),
      ]
    )
    let digest = SHA256.hash(data: try pixels(image)).map { String(format: "%02x", $0) }.joined()

    XCTAssertEqual(digest, "d180ff4701710bc66ccbe119b10b74ffa02c74be00b160aaac6e2a7077e35818")
  }

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func render(
    _ source: URL,
    operations: [EditOperation] = []
  ) async throws -> CGImage {
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    return try await decoder.preview(
      sourceURL: source,
      recipe: EditRecipe(
        assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
        pins: EnginePins(
          decoderIdentifier: "com.apple.coreimage.common-image",
          decoderVersion: "system-default",
          renderSchemaVersion: 1,
          cameraProfileVersion: nil,
          modelVersions: [:]
        ),
        operations: operations
      ),
      maximumPixelDimension: nil
    )
  }

  private func pixels(_ image: CGImage) throws -> Data {
    try DeterministicImageFixture.rgba8Data(from: image)
  }

  private func middlePixel(
    _ image: CGImage
  ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    DeterministicImageFixture.pixel(
      x: image.width / 2,
      y: image.height / 2,
      width: image.width,
      in: try pixels(image)
    )
  }

  private func cornerPixel(
    _ image: CGImage
  ) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    DeterministicImageFixture.pixel(x: 0, y: 0, width: image.width, in: try pixels(image))
  }
}
