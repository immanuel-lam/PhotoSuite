// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class PhotoMetadataTests: XCTestCase {
  func testMetadataNormalisesDescriptiveFieldsAndKeywords() throws {
    let metadata = try XCTUnwrap(
      PhotoMetadata(
        title: "  Harbour at dusk  ",
        headline: " Sydney harbour ",
        description: "  A long exposure.\n  ",
        creator: "  Alex Photographer ",
        credit: " Studio ",
        source: " Camera 1 ",
        copyrightNotice: "  Copyright 2026 Alex Photographer ",
        rightsUsageTerms: "  Editorial use only ",
        city: " Sydney ",
        stateProvince: " NSW ",
        country: " Australia ",
        countryCode: " au ",
        cameraMake: " Sony ",
        cameraModel: " ILCE-7M4 ",
        lensModel: " FE 24-70mm F2.8 GM II ",
        exposureTime: 1.0 / 30.0,
        aperture: 2.8,
        iso: 400,
        focalLengthMillimeters: 50,
        gpsLatitude: -33.8568,
        gpsLongitude: 151.2153,
        keywords: ["  Sydney ", "sydney", "  long\texposure ", "", "harbour"]
      )
    )

    XCTAssertEqual(metadata.title, "Harbour at dusk")
    XCTAssertEqual(metadata.description, "A long exposure.")
    XCTAssertEqual(metadata.countryCode, "AU")
    XCTAssertEqual(metadata.keywords, ["Sydney", "long exposure", "harbour"])
    XCTAssertEqual(metadata.iso, 400)
    XCTAssertEqual(metadata.gpsLatitude, -33.8568)
    XCTAssertEqual(metadata.gpsLongitude, 151.2153)
  }

  func testMetadataRejectsInvalidExifRanges() {
    XCTAssertNil(PhotoMetadata(gpsLatitude: 91))
    XCTAssertNil(PhotoMetadata(gpsLongitude: -181))
    XCTAssertNil(PhotoMetadata(exposureTime: 0))
    XCTAssertNil(PhotoMetadata(aperture: -1))
    XCTAssertNil(PhotoMetadata(iso: 0))
    XCTAssertNil(PhotoMetadata(focalLengthMillimeters: 0))
  }

  func testPhotoAssetMetadataRoundTripsAndMissingMetadataUsesEmptyValue() throws {
    let metadata = try XCTUnwrap(PhotoMetadata(title: "Title", keywords: ["keyword"]))
    let asset = try XCTUnwrap(
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/tmp/metadata.jpg"),
        filename: "metadata.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: try XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "a", count: 64), byteCount: 1, modificationDate: nil
          )
        ),
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        metadata: metadata
      )
    )
    let data = try JSONEncoder().encode(asset)
    let decoded = try JSONDecoder().decode(PhotoAsset.self, from: data)
    XCTAssertEqual(decoded.metadata, metadata)

    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "metadata")
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    let legacyAsset = try JSONDecoder().decode(PhotoAsset.self, from: legacyData)
    XCTAssertEqual(legacyAsset.metadata, PhotoMetadata.empty)
  }
}
