// SPDX-License-Identifier: MPL-2.0

import Foundation
import XCTest

@testable import PhotoDomain

final class PhotoFaceTests: XCTestCase {
  func testFaceRegionAcceptsNormalizedBoundsAndRejectsInvalidGeometry() throws {
    let region = try XCTUnwrap(FaceRegion(x: 0.1, y: 0.2, width: 0.4, height: 0.5))

    XCTAssertEqual(region.x, 0.1)
    XCTAssertEqual(region.y, 0.2)
    XCTAssertEqual(region.width, 0.4)
    XCTAssertEqual(region.height, 0.5)
    XCTAssertNil(FaceRegion(x: -0.01, y: 0.2, width: 0.4, height: 0.5))
    XCTAssertNil(FaceRegion(x: 0.1, y: 0.2, width: 0, height: 0.5))
    XCTAssertNil(FaceRegion(x: 0.8, y: 0.2, width: 0.4, height: 0.5))
    XCTAssertNil(FaceRegion(x: .infinity, y: 0.2, width: 0.4, height: 0.5))
  }

  func testPhotoFaceNormalisesUserLabelAndRoundTripsDetectionSource() throws {
    let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let face = try XCTUnwrap(
      PhotoFace(
        assetID: assetID,
        region: try XCTUnwrap(FaceRegion(x: 0.2, y: 0.25, width: 0.3, height: 0.35)),
        label: "  Alex   ",
        confidence: 0.92,
        source: .vision,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )

    XCTAssertEqual(face.label, "Alex")
    XCTAssertEqual(face.source, .vision)
    XCTAssertEqual(face.confidence, 0.92)

    let encoded = try JSONEncoder().encode(face)
    let decoded = try JSONDecoder().decode(PhotoFace.self, from: encoded)
    XCTAssertEqual(decoded, face)
  }

  func testPhotoFaceAllowsUnlabeledAnnotationWithoutClaimingIdentity() throws {
    let face = try XCTUnwrap(
      PhotoFace(
        assetID: UUID(),
        region: try XCTUnwrap(FaceRegion(x: 0, y: 0, width: 0.2, height: 0.2)),
        label: nil,
        confidence: nil,
        source: .vision
      )
    )

    XCTAssertNil(face.label)
    XCTAssertEqual(face.source, .vision)
  }

  func testPhotoFaceRejectsInvalidLabelAndConfidenceDuringDecode() throws {
    let invalidLabel =
      #"{"id":"11111111-2222-3333-4444-555555555555","assetID":"11111111-2222-3333-4444-555555555556","region":{"x":0,"y":0,"width":0.2,"height":0.2},"label":"   ","source":"manual","createdAt":0,"updatedAt":0}"#
      .data(using: .utf8)!
    XCTAssertThrowsError(try JSONDecoder().decode(PhotoFace.self, from: invalidLabel))

    let invalidConfidence =
      #"{"id":"11111111-2222-3333-4444-555555555555","assetID":"11111111-2222-3333-4444-555555555556","region":{"x":0,"y":0,"width":0.2,"height":0.2},"confidence":1.1,"source":"manual","createdAt":0,"updatedAt":0}"#
      .data(using: .utf8)!
    XCTAssertThrowsError(try JSONDecoder().decode(PhotoFace.self, from: invalidConfidence))
  }
}
