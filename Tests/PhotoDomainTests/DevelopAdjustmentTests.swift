// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class DevelopAdjustmentTests: XCTestCase {
  func testVersionOneDevelopPayloadsValidateAndRoundTripInStoredOrder() throws {
    let toneCurve = try XCTUnwrap(
      ToneCurveAdjustmentV1(
        blackPoint: 0.02,
        shadows: 0.2,
        midtones: 0.55,
        highlights: 0.8,
        whitePoint: 0.98
      )
    )
    let whiteBalance = try XCTUnwrap(
      WhiteBalanceAdjustmentV1(temperature: 0.25, tint: -0.1)
    )
    let transform = try XCTUnwrap(
      TransformAdjustmentV1(
        straightenDegrees: 2.5,
        flipHorizontal: true,
        flipVertical: false
      )
    )
    let detail = try XCTUnwrap(
      DetailAdjustmentV1(sharpening: 0.6, luminanceNoiseReduction: 0.35)
    )
    let optics = try XCTUnwrap(OpticsAdjustmentV1(vignetteCorrection: 0.4))
    let effects = try XCTUnwrap(EffectsAdjustmentV1(vignetteAmount: 0.3))
    let calibration = try XCTUnwrap(
      CalibrationAdjustmentV1(redGain: 0.1, greenGain: -0.2, blueGain: 0.3)
    )
    let blackAndWhite = try XCTUnwrap(
      BlackAndWhiteAdjustmentV1(redWeight: 0.3, greenWeight: 0.6, blueWeight: 0.1)
    )
    let hdr = HDRAdjustmentV1(isEnabled: true, preservesExtendedRange: true)
    let operations: [EditOperation] = [
      .toneCurve(toneCurve),
      .whiteBalance(whiteBalance),
      .transform(transform),
      .detail(detail),
      .optics(optics),
      .effects(effects),
      .calibration(calibration),
      .blackAndWhite(blackAndWhite),
      .hdr(hdr),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(operations)
    let decoded = try JSONDecoder().decode([EditOperation].self, from: data)

    XCTAssertEqual(decoded, operations)
    XCTAssertEqual(
      String(decoding: data, as: UTF8.self),
      #"[{"adjustment":{"blackPoint":0.02,"highlights":0.8,"midtones":0.55,"schemaVersion":1,"shadows":0.2,"whitePoint":0.98},"kind":"toneCurve"},{"adjustment":{"schemaVersion":1,"temperature":0.25,"tint":-0.1},"kind":"whiteBalance"},{"adjustment":{"flipHorizontal":true,"flipVertical":false,"schemaVersion":1,"straightenDegrees":2.5},"kind":"transform"},{"adjustment":{"luminanceNoiseReduction":0.35,"schemaVersion":1,"sharpening":0.6},"kind":"detail"},{"adjustment":{"schemaVersion":1,"vignetteCorrection":0.4},"kind":"optics"},{"adjustment":{"schemaVersion":1,"vignetteAmount":0.3},"kind":"effects"},{"adjustment":{"blueGain":0.3,"greenGain":-0.2,"redGain":0.1,"schemaVersion":1},"kind":"calibration"},{"adjustment":{"blueWeight":0.1,"greenWeight":0.6,"redWeight":0.3,"schemaVersion":1},"kind":"blackAndWhite"},{"adjustment":{"isEnabled":true,"preservesExtendedRange":true,"schemaVersion":1},"kind":"hdr"}]"#
    )
  }

  func testDevelopPayloadsRejectOutOfRangeInitializersAndPersistedJSON() throws {
    XCTAssertNil(
      ToneCurveAdjustmentV1(
        blackPoint: -.infinity,
        shadows: 0.25,
        midtones: 0.5,
        highlights: 0.75,
        whitePoint: 1
      )
    )
    XCTAssertNil(WhiteBalanceAdjustmentV1(temperature: 1.01, tint: 0))
    XCTAssertNil(
      TransformAdjustmentV1(
        straightenDegrees: 45.01,
        flipHorizontal: false,
        flipVertical: false
      )
    )
    XCTAssertNil(DetailAdjustmentV1(sharpening: 0, luminanceNoiseReduction: -.nan))
    XCTAssertNil(OpticsAdjustmentV1(vignetteCorrection: -0.01))
    XCTAssertNil(EffectsAdjustmentV1(vignetteAmount: 1.01))
    XCTAssertNil(CalibrationAdjustmentV1(redGain: 0, greenGain: 0, blueGain: 1.01))
    XCTAssertNil(BlackAndWhiteAdjustmentV1(redWeight: 0, greenWeight: 0, blueWeight: 0))

    let invalid = Data(
      #"{"schemaVersion":1,"temperature":2,"tint":0}"#.utf8
    )
    XCTAssertThrowsError(
      try JSONDecoder().decode(WhiteBalanceAdjustmentV1.self, from: invalid)
    )
  }

  func testOpticsAndEffectsExtendedFieldsValidateAndRoundTripWithoutChangingLegacyPayloads() throws
  {
    let optics = try XCTUnwrap(
      OpticsAdjustmentV1(
        vignetteCorrection: 0.35,
        lensDistortion: -0.6,
        chromaticAberration: 0.4,
        defringe: 0.25
      )
    )
    let effects = try XCTUnwrap(
      EffectsAdjustmentV1(
        vignetteAmount: 0.2,
        grainAmount: 0.45,
        dehaze: -0.3
      )
    )
    let data = try JSONEncoder().encode([EditOperation.optics(optics), .effects(effects)])
    let decoded = try JSONDecoder().decode([EditOperation].self, from: data)

    XCTAssertEqual(decoded, [.optics(optics), .effects(effects)])
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("lensDistortion"))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("chromaticAberration"))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("defringe"))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("grainAmount"))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("dehaze"))

    XCTAssertNil(
      OpticsAdjustmentV1(
        vignetteCorrection: 0,
        lensDistortion: -1.01,
        chromaticAberration: 0,
        defringe: 0
      )
    )
    XCTAssertNil(
      OpticsAdjustmentV1(
        vignetteCorrection: 0,
        lensDistortion: 0,
        chromaticAberration: 1.01,
        defringe: 0
      )
    )
    XCTAssertNil(
      EffectsAdjustmentV1(vignetteAmount: 0, grainAmount: 1.01, dehaze: 0)
    )
    XCTAssertNil(
      EffectsAdjustmentV1(vignetteAmount: 0, grainAmount: 0, dehaze: -1.01)
    )
  }

  func testLegacyOpticsAndEffectsPayloadsDecodeWithNeutralExtendedFields() throws {
    let data = Data(
      #"[{"kind":"optics","adjustment":{"schemaVersion":1,"vignetteCorrection":0.4}},{"kind":"effects","adjustment":{"schemaVersion":1,"vignetteAmount":0.3}}]"#
        .utf8
    )

    let decoded = try JSONDecoder().decode([EditOperation].self, from: data)
    guard case .optics(let optics) = decoded[0], case .effects(let effects) = decoded[1] else {
      XCTFail("Legacy payloads must remain typed optics and effects operations.")
      return
    }
    XCTAssertEqual(optics.lensDistortion, 0)
    XCTAssertEqual(optics.chromaticAberration, 0)
    XCTAssertEqual(optics.defringe, 0)
    XCTAssertEqual(effects.grainAmount, 0)
    XCTAssertEqual(effects.dehaze, 0)
  }

  func testKnownDevelopOperationWithFuturePayloadSchemaIsPreservedAsUnknown() throws {
    let future = Data(
      #"{"kind":"toneCurve","adjustment":{"schemaVersion":2,"algorithm":"adaptive","points":[0,0.5,1]}}"#
        .utf8
    )

    let operation = try JSONDecoder().decode(EditOperation.self, from: future)
    let reencoded = try JSONEncoder().encode(operation)
    let roundTripped = try JSONDecoder().decode(EditOperation.self, from: reencoded)

    XCTAssertEqual(
      operation,
      .unknown(
        "toneCurve",
        payload: [
          "adjustment": .object([
            "schemaVersion": .number(2),
            "algorithm": .string("adaptive"),
            "points": .array([.number(0), .number(0.5), .number(1)]),
          ])
        ]
      )
    )
    XCTAssertEqual(roundTripped, operation)
  }
}
