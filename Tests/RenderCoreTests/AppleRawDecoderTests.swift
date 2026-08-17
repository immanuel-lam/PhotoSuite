// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotoDomain
import XCTest

@testable import RenderCore

final class AppleRawDecoderTests: XCTestCase {
  func testWorkingColorSpaceUsesExtendedRange() async throws {
    let decoder = try AppleRawDecoder()

    let colorSpace = await decoder.workingColorSpace

    XCTAssertTrue(CGColorSpaceUsesExtendedRange(colorSpace))
  }

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

  func testCommonImageCapabilityRequestDoesNotClaimRAWDecoderVersions() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let decoder = try AppleRawDecoder()

    let result = try await decoder.capabilities(RawCapabilityRequest(sourceURL: source))

    XCTAssertEqual(result.supportedCameraModels, CIRAWFilter.supportedCameraModels)
    XCTAssertTrue(result.supportedDecoderVersions.isEmpty)
  }

  func testCommonImageFallbackAppliesOrientationMetadataToPixels() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makeOrientedTIFF(in: directory)
    let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    )
    XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
    let decoder = try AppleRawDecoder()

    let result = try await decoder.decode(RawDecodeRequest(sourceURL: source))

    XCTAssertEqual(result.image.dimensions, PixelDimensions(width: 3, height: 2))
    let rowDominance = (0..<2).map { row -> String in
      let pixels = (0..<3).map {
        DeterministicImageFixture.pixel(
          x: $0,
          y: row,
          width: 3,
          in: result.image.data
        )
      }
      let red = pixels.reduce(0) { $0 + Int($1.red) }
      let blue = pixels.reduce(0) { $0 + Int($1.blue) }
      return red > blue ? "red" : "blue"
    }
    XCTAssertEqual(Set(rowDominance), Set(["red", "blue"]))
  }

  func testCreatedRAWFilterReportsItsExactVersionsAndInvalidOutputIsCorrupt() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("invalid.dng")
    try Data("not a valid raw payload".utf8).write(to: source)
    let raw = try XCTUnwrap(CIRAWFilter(imageURL: source))
    let exactVersions = raw.supportedDecoderVersions.map(\.rawValue)
    let decoder = try AppleRawDecoder()

    let capabilities = try await decoder.capabilities(
      RawCapabilityRequest(sourceURL: source)
    )

    XCTAssertEqual(capabilities.supportedDecoderVersions, exactVersions)
    do {
      _ = try await decoder.decode(RawDecodeRequest(sourceURL: source))
      XCTFail("Expected corrupt RAW error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .corruptSource(source))
    }
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
    let capabilities = try await decoder.capabilities(
      RawCapabilityRequest(sourceURL: source)
    )

    XCTAssertEqual(result.decoderIdentifier, "com.apple.ciraw")
    XCTAssertEqual(result.decoderVersion, exactVersion)
    XCTAssertEqual(
      capabilities.supportedDecoderVersions,
      raw.supportedDecoderVersions.map(\.rawValue)
    )
    XCTAssertGreaterThan(result.image.data.count, 0)
  }
}
