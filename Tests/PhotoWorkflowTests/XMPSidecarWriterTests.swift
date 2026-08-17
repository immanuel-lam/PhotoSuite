// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

final class XMPSidecarWriterTests: XCTestCase {
  func testWriteAndReadRoundTripEscapesFieldsAndPreservesSourceBytes() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.jpg")
    let sourceData = Data("immutable-source".utf8)
    try sourceData.write(to: sourceURL)
    let metadata = try XCTUnwrap(
      PhotoMetadata(
        title: "A <title> & more",
        description: "Line with \"quotes\"",
        creator: "Photographer",
        copyrightNotice: "© 2026",
        city: "Sydney",
        countryCode: "au",
        cameraMake: "Camera & Co",
        exposureTime: 1.0 / 125.0,
        aperture: 2.8,
        iso: 400,
        focalLengthMillimeters: 50,
        gpsLatitude: -33.8688,
        gpsLongitude: 151.2093,
        keywords: ["Travel", "Sydney"]
      )
    )

    let sidecarURL = try XMPMetadataSidecar.write(metadata, for: sourceURL)

    XCTAssertEqual(sidecarURL, directory.appendingPathComponent("source.xmp"))
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    let xml = try String(contentsOf: sidecarURL, encoding: .utf8)
    XCTAssertTrue(xml.contains("&lt;title&gt; &amp; more"))
    XCTAssertTrue(xml.contains("photosuite:keyword"))
    XCTAssertEqual(try XMPMetadataSidecar.read(from: sidecarURL), metadata)
  }

  func testMalformedSidecarAndInvalidDestinationReturnTypedErrors() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let malformedURL = directory.appendingPathComponent("bad.xmp")
    try Data("not xml".utf8).write(to: malformedURL)

    XCTAssertThrowsError(try XMPMetadataSidecar.read(from: malformedURL)) { error in
      XCTAssertEqual(error as? XMPMetadataSidecarError, .malformed)
    }

    let sourceURL = directory.appendingPathComponent("source.jpg")
    try Data("source".utf8).write(to: sourceURL)
    let missingDirectorySource = directory.appendingPathComponent("missing/source.jpg")
    XCTAssertThrowsError(
      try XMPMetadataSidecar.write(.empty, for: missingDirectorySource)
    ) { error in
      XCTAssertEqual(error as? XMPMetadataSidecarError, .writeFailed)
    }
    XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-XMP-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
