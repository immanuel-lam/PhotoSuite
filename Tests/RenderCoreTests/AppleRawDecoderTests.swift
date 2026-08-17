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
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let colorSpace = await decoder.workingColorSpace

    XCTAssertTrue(CGColorSpaceUsesExtendedRange(colorSpace))
  }

  func testCommonImageFallbackReturnsOrientedPixelsAndStableDecoderIdentity() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory, name: "common.dng")
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let result = try await decoder.decode(RawDecodeRequest(sourceURL: source))

    XCTAssertEqual(result.image.dimensions, PixelDimensions(width: 8, height: 6))
    XCTAssertEqual(result.image.pixelFormat, .rgba8)
    XCTAssertEqual(result.image.bytesPerRow, 32)
    XCTAssertEqual(result.image.data.count, 8 * 6 * 4)
    XCTAssertEqual(result.decoderIdentifier, "com.apple.coreimage.common-image")
    XCTAssertEqual(result.decoderVersion, "system-default")
  }

  func testCapabilitiesComeFromCIRAWFilterWithoutGlobalDecoderVersionClaim() async throws {
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let result = try await decoder.capabilities(RawCapabilityRequest())

    XCTAssertEqual(result.supportedCameraModels, CIRAWFilter.supportedCameraModels)
    XCTAssertTrue(result.supportedDecoderVersions.isEmpty)
  }

  func testCommonImageCapabilityRequestDoesNotClaimRAWDecoderVersions() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

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
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let result = try await decoder.decode(RawDecodeRequest(sourceURL: source))

    XCTAssertEqual(result.image.dimensions, PixelDimensions(width: 3, height: 2))
    for x in 0..<3 {
      let bottom = DeterministicImageFixture.pixel(
        x: x,
        y: 0,
        width: 3,
        in: result.image.data
      )
      let top = DeterministicImageFixture.pixel(
        x: x,
        y: 1,
        width: 3,
        in: result.image.data
      )
      XCTAssertGreaterThan(bottom.red, bottom.blue)
      XCTAssertGreaterThan(top.blue, top.red)
    }
  }

  func testCreatedRAWFilterIsAuthorityIndependentOfFilenameExtension() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let imageURL = try DeterministicImageFixture.makePNG(in: directory)
    let image = try XCTUnwrap(CIImage(contentsOf: imageURL))
    let source = directory.appendingPathComponent("camera-payload.bin")
    try Data("provider owns RAW identification".utf8).write(to: source)
    let filter = StubAppleRAWFilter(
      supportedDecoderVersions: ["raw-v1", "raw-v2"],
      decoderVersion: "raw-v1",
      outputImage: image
    )
    let decoder = try AppleRawDecoder(
      rawFilterProvider: StubAppleRAWFilterProvider(filter: filter)
    )

    let capabilities = try await decoder.capabilities(
      RawCapabilityRequest(sourceURL: source)
    )

    let result = try await decoder.decode(
      RawDecodeRequest(sourceURL: source, decoderVersion: "raw-v2")
    )

    XCTAssertEqual(capabilities.supportedDecoderVersions, ["raw-v1", "raw-v2"])
    XCTAssertEqual(result.decoderIdentifier, "com.apple.ciraw")
    XCTAssertEqual(result.decoderVersion, "raw-v2")
    XCTAssertEqual(result.image.dimensions, PixelDimensions(width: 8, height: 6))
  }

  func testCreatedRAWFilterWithMissingOutputIsCorruptWithoutCommonFallback() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let filter = StubAppleRAWFilter(
      supportedDecoderVersions: ["raw-v1"],
      decoderVersion: "raw-v1",
      outputImage: nil
    )
    let decoder = try AppleRawDecoder(
      rawFilterProvider: StubAppleRAWFilterProvider(filter: filter)
    )

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
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

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
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

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

private final class StubAppleRAWFilter: AppleRAWFilterAccess {
  let supportedDecoderVersions: [String]
  private(set) var decoderVersion: String
  let outputImage: CIImage?
  let properties: [AnyHashable: Any] = [:]

  init(
    supportedDecoderVersions: [String],
    decoderVersion: String,
    outputImage: CIImage?
  ) {
    self.supportedDecoderVersions = supportedDecoderVersions
    self.decoderVersion = decoderVersion
    self.outputImage = outputImage
  }

  func selectDecoderVersion(_ version: String) -> Bool {
    guard supportedDecoderVersions.contains(version) else { return false }
    decoderVersion = version
    return true
  }
}

private struct StubAppleRAWFilterProvider: AppleRAWFilterProviding {
  let filter: StubAppleRAWFilter

  func makeFilter(imageURL: URL) -> (any AppleRAWFilterAccess)? {
    filter
  }
}
