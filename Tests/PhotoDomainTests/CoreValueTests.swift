// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class CoreValueTests: XCTestCase {
  private let validDigest = String(repeating: "a", count: 64)

  func testSourceFingerprintAcceptsCanonicalSHA256() throws {
    let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: validDigest,
        byteCount: 4_096,
        modificationDate: modificationDate
      )
    )

    XCTAssertEqual(fingerprint.sha256, validDigest)
    XCTAssertEqual(fingerprint.byteCount, 4_096)
    XCTAssertEqual(fingerprint.modificationDate, modificationDate)
  }

  func testSourceFingerprintRejectsNonCanonicalDigests() {
    let invalidDigests = [
      String(repeating: "a", count: 63),
      String(repeating: "a", count: 65),
      String(repeating: "g", count: 64),
      String(repeating: "A", count: 64),
    ]

    for digest in invalidDigests {
      XCTAssertNil(
        SourceFingerprint(sha256: digest, byteCount: 1, modificationDate: nil),
        "Expected rejection for digest: \(digest)"
      )
    }
  }

  func testSourceFingerprintRejectsInvalidDigestDuringJSONDecode() {
    let invalidJSON = Data(
      #"{"sha256":"not-a-digest","byteCount":1,"modificationDate":null}"#.utf8
    )

    XCTAssertThrowsError(try JSONDecoder().decode(SourceFingerprint.self, from: invalidJSON))
  }

  func testPixelDimensionsRequirePositiveValues() throws {
    XCTAssertNotNil(PixelDimensions(width: 6_000, height: 4_000))
    XCTAssertNil(PixelDimensions(width: 0, height: 4_000))
    XCTAssertNil(PixelDimensions(width: 6_000, height: -1))
  }

  func testNormalizedRectAcceptsOnlyFiniteRectanglesInsideUnitBounds() throws {
    let rect = try XCTUnwrap(NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
    XCTAssertEqual(rect.x, 0.1)
    XCTAssertEqual(rect.y, 0.2)
    XCTAssertEqual(rect.width, 0.7)
    XCTAssertEqual(rect.height, 0.6)

    XCTAssertNil(NormalizedRect(x: .nan, y: 0, width: 1, height: 1))
    XCTAssertNil(NormalizedRect(x: 0, y: 0, width: 0, height: 1))
    XCTAssertNil(NormalizedRect(x: 0, y: 0, width: 1.1, height: 1))
    XCTAssertNil(NormalizedRect(x: 0.8, y: 0, width: 0.3, height: 1))
  }

  func testNormalizedRectRejectsInvalidValuesDuringJSONDecode() {
    let invalidJSON = Data(#"{"x":0.8,"y":0,"width":0.3,"height":1}"#.utf8)

    XCTAssertThrowsError(try JSONDecoder().decode(NormalizedRect.self, from: invalidJSON))
  }

  func testPhotoAssetPreservesStableIdentityAcrossJSONRoundTrip() throws {
    let assetID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(sha256: validDigest, byteCount: 42, modificationDate: nil)
    )
    let dimensions = try XCTUnwrap(PixelDimensions(width: 6_000, height: 4_000))
    let asset = try XCTUnwrap(
      PhotoAsset(
        id: assetID,
        sourceURL: URL(fileURLWithPath: "/Pictures/input.CR3"),
        filename: "input.CR3",
        typeIdentifier: "com.canon.cr3-raw-image",
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: Date(timeIntervalSince1970: 1_600_000_000),
        pixelDimensions: dimensions,
        rating: 5,
        colorLabel: .green,
        isMissing: false
      )
    )

    let data = try JSONEncoder().encode(asset)
    let decoded = try JSONDecoder().decode(PhotoAsset.self, from: data)

    XCTAssertEqual(decoded, asset)
    XCTAssertEqual(decoded.id, assetID)
  }

  func testPhotoAssetRejectsRatingOutsideZeroThroughFive() throws {
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(sha256: validDigest, byteCount: 42, modificationDate: nil)
    )
    let commonArguments: (Int) -> PhotoAsset? = { rating in
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/Pictures/input.CR3"),
        filename: "input.CR3",
        typeIdentifier: nil,
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        rating: rating,
        colorLabel: nil,
        isMissing: false
      )
    }

    XCTAssertNotNil(commonArguments(0))
    XCTAssertNotNil(commonArguments(5))
    XCTAssertNil(commonArguments(-1))
    XCTAssertNil(commonArguments(6))
  }

  func testPhotoAssetRejectsInvalidRatingDuringJSONDecode() throws {
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(sha256: validDigest, byteCount: 42, modificationDate: nil)
    )
    let validAsset = try XCTUnwrap(
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/Pictures/input.CR3"),
        filename: "input.CR3",
        typeIdentifier: nil,
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        rating: 0,
        colorLabel: nil,
        isMissing: false
      )
    )
    let encoded = try JSONEncoder().encode(validAsset)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    var invalidObject = object
    invalidObject["rating"] = 6
    let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)

    XCTAssertThrowsError(try JSONDecoder().decode(PhotoAsset.self, from: invalidData))
  }
}
