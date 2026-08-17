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

    let firstEncoding = try encoder.encode(recipe)
    let secondEncoding = try encoder.encode(recipe)
    let decoded = try decoder.decode(EditRecipe.self, from: firstEncoding)

    XCTAssertEqual(firstEncoding, secondEncoding)
    XCTAssertEqual(decoded, recipe)
    XCTAssertEqual(decoded.operations, operations)
    XCTAssertEqual(decoded.masks.map(\.id), [mask.id])

    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: firstEncoding) as? [String: Any]
    )
    let encodedOperations = try XCTUnwrap(root["operations"] as? [[String: Any]])
    XCTAssertEqual(
      encodedOperations.compactMap { $0["kind"] as? String },
      [
        "exposureEV",
        "contrast",
        "highlights",
        "shadows",
        "saturation",
        "normalizedCrop",
        "rotationDegrees",
      ]
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
