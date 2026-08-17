// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class LensProfileTests: XCTestCase {
  func testLensProfileMapsValidatedCorrectionsToDurableOptics() throws {
    let attribution = try XCTUnwrap(
      LensProfileAttributionV1(
        source: "Lensfun",
        license: "CC BY-SA 3.0",
        notice: "Lensfun contributors",
        sourceURL: "https://lensfun.github.io/"
      )
    )
    let profile = try XCTUnwrap(
      LensProfileV1(
        identifier: "lensfun:canon|ef 35mm f/2|canon ef",
        maker: "Canon",
        model: "EF 35mm f/2",
        mount: "Canon EF",
        distortion: -0.42,
        vignetting: 0.31,
        chromaticAberration: 0.18,
        defringe: 0.12,
        attribution: attribution
      )
    )

    let optics = try XCTUnwrap(profile.opticsAdjustment())
    XCTAssertEqual(optics.lensProfileID, profile.identifier)
    XCTAssertEqual(optics.lensDistortion, -0.42)
    XCTAssertEqual(optics.vignetteCorrection, 0.31)
    XCTAssertEqual(optics.chromaticAberration, 0.18)
    XCTAssertEqual(optics.defringe, 0.12)
  }

  func testLensProfileRejectsInvalidValuesAndMissingAttribution() {
    let attribution = LensProfileAttributionV1(
      source: "Lensfun",
      license: "CC BY-SA 3.0",
      notice: "Lensfun contributors"
    )
    XCTAssertNotNil(attribution)
    XCTAssertNil(
      LensProfileV1(
        identifier: " ",
        maker: "Canon",
        model: "EF 35mm f/2",
        mount: nil,
        distortion: 0,
        vignetting: 0,
        chromaticAberration: 0,
        defringe: 0,
        attribution: attribution!
      )
    )
    XCTAssertNil(
      LensProfileV1(
        identifier: "lensfun:invalid",
        maker: "Canon",
        model: "EF 35mm f/2",
        mount: nil,
        distortion: 1.01,
        vignetting: 0,
        chromaticAberration: 0,
        defringe: 0,
        attribution: attribution!
      )
    )
    XCTAssertNil(
      LensProfileAttributionV1(
        source: "Lensfun",
        license: "CC BY-SA 3.0",
        notice: " "
      )
    )
  }

  func testLensfunXMLLoaderReadsCalibrationsAndCarriesAttribution() throws {
    let xml = Data(
      #"""
      <?xml version="1.0" encoding="UTF-8"?>
      <lensdatabase version="2">
        <lens>
          <maker>Example Camera</maker>
          <model>Example 35mm f/2</model>
          <mount>Example EF</mount>
          <calibration>
            <distortion model="ptlens" focal="35" k1="-0.08" k2="0.01" />
            <tca model="poly3" focal="35" vr="0.001" vb="-0.002" />
            <vignetting model="pa" focal="35" aperture="2" distance="1000" k1="-0.22" k2="0.04" />
          </calibration>
        </lens>
      </lensdatabase>
      """#.data(using: .utf8)!
    )
    let attribution = try XCTUnwrap(
      LensProfileAttributionV1(
        source: "Lensfun",
        license: "CC BY-SA 3.0",
        notice: "Lensfun contributors"
      )
    )

    let database = try LensProfileXMLLoader.load(data: xml, attribution: attribution)
    XCTAssertEqual(database.sourceVersion, "2")
    XCTAssertEqual(database.profiles.count, 1)
    XCTAssertEqual(database.profiles[0].maker, "Example Camera")
    XCTAssertEqual(database.profiles[0].model, "Example 35mm f/2")
    XCTAssertEqual(database.profiles[0].mount, "Example EF")
    XCTAssertLessThan(database.profiles[0].distortion, 0)
    XCTAssertGreaterThan(database.profiles[0].vignetting, 0)
    XCTAssertGreaterThan(database.profiles[0].chromaticAberration, 0)
    XCTAssertEqual(database.attribution, attribution)
  }

  func testLensfunXMLLoaderRejectsMalformedOrEmptyDatabase() throws {
    let attribution = try XCTUnwrap(
      LensProfileAttributionV1(
        source: "Lensfun",
        license: "CC BY-SA 3.0",
        notice: "Lensfun contributors"
      )
    )
    XCTAssertThrowsError(
      try LensProfileXMLLoader.load(data: Data("<lensdatabase>".utf8), attribution: attribution)
    ) { error in
      guard case LensProfileXMLLoaderError.parseFailed = error else {
        XCTFail("Malformed XML must report a typed parse failure.")
        return
      }
    }
    let empty = Data(#"<lensdatabase version="2"></lensdatabase>"#.utf8)
    XCTAssertThrowsError(
      try LensProfileXMLLoader.load(data: empty, attribution: attribution)
    ) { error in
      guard case LensProfileXMLLoaderError.noProfiles = error else {
        XCTFail("An empty database must report a typed no-profiles failure.")
        return
      }
    }
  }

  func testLensProfileDatabaseSearchIsStableAndCaseInsensitive() throws {
    let attribution = try XCTUnwrap(
      LensProfileAttributionV1(
        source: "Fixture",
        license: "MPL-2.0",
        notice: "PhotoSuite fixture"
      )
    )
    let first = try XCTUnwrap(
      LensProfileV1(
        identifier: "fixture:z",
        maker: "Acme",
        model: "Wide 24mm",
        mount: "Mount A",
        distortion: 0.1,
        vignetting: 0.1,
        chromaticAberration: 0.1,
        defringe: 0.1,
        attribution: attribution
      )
    )
    let second = try XCTUnwrap(
      LensProfileV1(
        identifier: "fixture:a",
        maker: "Acme",
        model: "Portrait 85mm",
        mount: "Mount A",
        distortion: 0.1,
        vignetting: 0.1,
        chromaticAberration: 0.1,
        defringe: 0.1,
        attribution: attribution
      )
    )
    let database = try XCTUnwrap(
      LensProfileDatabaseV1(
        sourceVersion: "fixture",
        attribution: attribution,
        profiles: [first, second]
      )
    )

    XCTAssertEqual(database.search("ACME").map(\.identifier), ["fixture:a", "fixture:z"])
    XCTAssertEqual(database.search("portrait").map(\.model), ["Portrait 85mm"])
    XCTAssertEqual(database.search("unknown"), [])
  }

  func testLensProfileAndDatabaseRoundTripProvenance() throws {
    let attribution = try XCTUnwrap(
      LensProfileAttributionV1(
        source: "Fixture",
        license: "CC BY-SA 3.0",
        notice: "Fixture attribution",
        sourceURL: "https://example.invalid/lensfun.xml"
      )
    )
    let profile = try XCTUnwrap(
      LensProfileV1(
        identifier: "fixture:round-trip",
        maker: "Maker",
        model: "Model",
        mount: nil,
        distortion: 0.2,
        vignetting: 0.3,
        chromaticAberration: 0.4,
        defringe: 0.5,
        attribution: attribution
      )
    )
    let database = try XCTUnwrap(
      LensProfileDatabaseV1(
        sourceVersion: "2",
        attribution: attribution,
        profiles: [profile]
      )
    )

    let data = try JSONEncoder().encode(database)
    XCTAssertEqual(try JSONDecoder().decode(LensProfileDatabaseV1.self, from: data), database)
  }
}
