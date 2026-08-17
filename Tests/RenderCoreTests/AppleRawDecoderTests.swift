// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreImage
import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class AppleRawDecoderTests: XCTestCase {
  func testCommonImageFallbackReturnsOrientedPixelsAndStableDecoderIdentity() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let decoder = try AppleRawDecoder()

    let result = try await decoder.decode(RawDecodeRequest(sourceURL: source))

    XCTAssertEqual(result.image.dimensions, PixelDimensions(width: 8, height: 6))
    XCTAssertEqual(result.image.pixelFormat, .rgba8)
    XCTAssertEqual(result.image.bytesPerRow, 32)
    XCTAssertEqual(result.image.data.count, 8 * 6 * 4)
    XCTAssertEqual(result.decoderIdentifier, "com.apple.coreimage.common-image")
    XCTAssertEqual(result.decoderVersion, "system-default")
  }

  func testCapabilitiesComeFromCIRAWFilterWithoutGlobalDecoderVersionClaim() async throws {
    let decoder = try AppleRawDecoder()

    let result = try await decoder.capabilities(RawCapabilityRequest())

    XCTAssertEqual(result.supportedCameraModels, CIRAWFilter.supportedCameraModels)
    XCTAssertTrue(result.supportedDecoderVersions.isEmpty)
  }

  func testRecognizedTruncatedImageReportsCorruptSource() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("corrupt.png")
    try Data([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]).write(to: source)
    let decoder = try AppleRawDecoder()

    do {
      _ = try await decoder.decode(RawDecodeRequest(sourceURL: source))
      XCTFail("Expected corrupt source error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .corruptSource(source))
    }
  }

  func testArbitraryNonImageReportsUnsupportedSource() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("not-an-image.bin")
    try Data("not an image".utf8).write(to: source)
    let decoder = try AppleRawDecoder()

    do {
      _ = try await decoder.decode(RawDecodeRequest(sourceURL: source))
      XCTFail("Expected unsupported source error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .unsupportedSource(source))
    }
  }

  func testLicensedRAWFixtureUsesExactSupportedDecoderPinWhenAvailable() async throws {
    guard
      let fixturePath = ProcessInfo.processInfo.environment["PHOTOSUITE_LICENSED_RAW_FIXTURE"],
      !fixturePath.isEmpty
    else {
      throw XCTSkip(
        "No redistribution-safe licensed RAW fixture was supplied in PHOTOSUITE_LICENSED_RAW_FIXTURE."
      )
    }
    let source = URL(fileURLWithPath: fixturePath)
    let raw = try XCTUnwrap(CIRAWFilter(imageURL: source))
    let exactVersion = raw.decoderVersion.rawValue
    XCTAssertTrue(raw.supportedDecoderVersions.contains { $0.rawValue == exactVersion })
    let decoder = try AppleRawDecoder()

    let result = try await decoder.decode(
      RawDecodeRequest(sourceURL: source, decoderVersion: exactVersion)
    )

    XCTAssertEqual(result.decoderIdentifier, "com.apple.ciraw")
    XCTAssertEqual(result.decoderVersion, exactVersion)
    XCTAssertGreaterThan(result.image.data.count, 0)
  }
}
