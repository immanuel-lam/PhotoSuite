// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class EditRecipeTests: XCTestCase {
  private let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  private let recipeDate = Date(timeIntervalSince1970: 1_700_000_000)

  func testDefaultRecipeStartsAtRevisionZeroWithNoEditsAndRoundTrips() throws {
    let recipe = EditRecipe(assetID: assetID, date: recipeDate, pins: makePins())

    XCTAssertEqual(recipe.revision, 0)
    XCTAssertTrue(recipe.operations.isEmpty)
    XCTAssertTrue(recipe.masks.isEmpty)

    let (encoder, decoder) = makeJSONCoders()
    let data = try encoder.encode(recipe)
    let decoded = try decoder.decode(EditRecipe.self, from: data)

    XCTAssertEqual(decoded, recipe)
  }

  func testThreeWayColorGradeValidatesAndRoundTripsAsADurableOperation() throws {
    let shadows = try XCTUnwrap(
      ThreeWayColorGrade.Tone(hueDegrees: 240, chroma: 0.4, luminance: -0.2)
    )
    let midtones = try XCTUnwrap(
      ThreeWayColorGrade.Tone(hueDegrees: 30, chroma: 0.2, luminance: 0.1)
    )
    let highlights = try XCTUnwrap(
      ThreeWayColorGrade.Tone(hueDegrees: 60, chroma: 0.3, luminance: 0.25)
    )
    let grade = try XCTUnwrap(
      ThreeWayColorGrade(shadows: shadows, midtones: midtones, highlights: highlights)
    )
    let operation = EditOperation.threeWayColorGrade(grade)

    XCTAssertTrue(ThreeWayColorGrade.neutral.isNeutral)
    XCTAssertNil(ThreeWayColorGrade.Tone(hueDegrees: -0.1, chroma: 0, luminance: 0))
    XCTAssertNil(ThreeWayColorGrade.Tone(hueDegrees: 0, chroma: 1.01, luminance: 0))
    XCTAssertNil(ThreeWayColorGrade.Tone(hueDegrees: 0, chroma: 0, luminance: -1.01))
    XCTAssertEqual(
      try JSONDecoder().decode(EditOperation.self, from: JSONEncoder().encode(operation)), operation
    )
  }

  func testJSONRoundTripPreservesOperationOrderAndExplicitDiscriminators() throws {
    let crop = try XCTUnwrap(NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
    let operations: [EditOperation] = [
      .exposureEV(1.25),
      .contrast(-0.2),
      .highlights(-0.4),
      .shadows(0.3),
      .saturation(0.15),
      .normalizedCrop(crop),
      .rotationDegrees(90),
      .unknown(
        "futureToneMap",
        payload: [
          "parameters": .object([
            "enabled": .bool(true),
            "mode": .string("filmic"),
            "shoulder": .number(0.75),
          ]),
          "weights": .array([.number(0.25), .number(0.75)]),
        ]
      ),
    ]
    let mask = MaskDefinition(
      id: UUID(uuidString: "AAAAAAAA-2222-3333-4444-BBBBBBBBBBBB")!,
      schemaVersion: 1,
      kind: .subject,
      name: "Subject",
      isInverted: false,
      payload: Data([0x01, 0x02, 0x03])
    )
    let recipe = EditRecipe(
      assetID: assetID,
      revision: 7,
      date: recipeDate,
      pins: makePins(),
      operations: operations,
      masks: [mask]
    )
    let (encoder, decoder) = makeJSONCoders()

    let encoded = try encoder.encode(recipe)
    let expectedJSON =
      #"{"assetID":"11111111-2222-3333-4444-555555555555","date":1700000000000,"masks":[{"id":"AAAAAAAA-2222-3333-4444-BBBBBBBBBBBB","isInverted":false,"kind":"subject","name":"Subject","payload":"AQID","schemaVersion":1}],"operations":[{"kind":"exposureEV","value":1.25},{"kind":"contrast","value":-0.2},{"kind":"highlights","value":-0.4},{"kind":"shadows","value":0.3},{"kind":"saturation","value":0.15},{"kind":"normalizedCrop","rect":{"height":0.6,"width":0.7,"x":0.1,"y":0.2}},{"kind":"rotationDegrees","value":90},{"kind":"futureToneMap","parameters":{"enabled":true,"mode":"filmic","shoulder":0.75},"weights":[0.25,0.75]}],"pins":{"cameraProfileVersion":"camera-standard-3","decoderIdentifier":"com.apple.ciraw","decoderVersion":"9","modelVersions":{"sky-segmentation":"1.4","subject-segmentation":"2.1"},"renderSchemaVersion":1},"revision":7}"#
    let decoded = try decoder.decode(EditRecipe.self, from: encoded)

    XCTAssertEqual(String(decoding: encoded, as: UTF8.self), expectedJSON)
    XCTAssertEqual(decoded, recipe)
    XCTAssertEqual(decoded.operations, operations)
    XCTAssertEqual(decoded.masks.map(\.id), [mask.id])
  }

  func testUnknownEditOperationPreservesNestedPayloadFromPersistedJSON() throws {
    let encoded = Data(
      #"{"kind":"futureLocalAdjustment","enabled":true,"parameters":{"amount":0.8,"mode":"adaptive"},"points":[[0.1,0.2],[0.8,0.9]]}"#
        .utf8
    )
    let expected = EditOperation.unknown(
      "futureLocalAdjustment",
      payload: [
        "enabled": .bool(true),
        "parameters": .object([
          "amount": .number(0.8),
          "mode": .string("adaptive"),
        ]),
        "points": .array([
          .array([.number(0.1), .number(0.2)]),
          .array([.number(0.8), .number(0.9)]),
        ]),
      ]
    )

    let decoded = try JSONDecoder().decode(EditOperation.self, from: encoded)
    let reencoded = try JSONEncoder().encode(decoded)

    XCTAssertEqual(decoded, expected)
    XCTAssertEqual(
      try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary,
      try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
    )
  }

  func testUnknownEditOperationPreservesIntegerAboveDoublePrecision() throws {
    let encoded = Data(
      #"{"kind":"futureSequence","sequence":9007199254740993}"#.utf8
    )
    let operation = try JSONDecoder().decode(EditOperation.self, from: encoded)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let reencoded = try encoder.encode(operation)

    XCTAssertEqual(
      String(decoding: reencoded, as: UTF8.self),
      #"{"kind":"futureSequence","sequence":9007199254740993}"#
    )
  }

  func testUnknownMaskKindSurvivesJSONRoundTrip() throws {
    let encoded = Data(#""future-model-mask""#.utf8)

    let kind = try JSONDecoder().decode(MaskKind.self, from: encoded)
    let reencoded = try JSONEncoder().encode(kind)

    XCTAssertEqual(kind, .unknown("future-model-mask"))
    XCTAssertEqual(reencoded, encoded)
  }

  private func makePins() -> EnginePins {
    EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "9",
      renderSchemaVersion: 1,
      cameraProfileVersion: "camera-standard-3",
      modelVersions: [
        "subject-segmentation": "2.1",
        "sky-segmentation": "1.4",
      ]
    )
  }

  private func makeJSONCoders() -> (JSONEncoder, JSONDecoder) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return (encoder, decoder)
  }
}
