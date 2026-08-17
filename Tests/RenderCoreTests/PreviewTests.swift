// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import PhotoDomain
import UniformTypeIdentifiers
import XCTest

@testable import RenderCore

final class PreviewTests: XCTestCase {
  func testPreviewFitsBoundWithoutChangingAspectRatio() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: 4
    )

    XCTAssertEqual(image.width, 4)
    XCTAssertEqual(image.height, 3)
  }

  func testPreviewNeverUpscales() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: 64
    )

    XCTAssertEqual(image.width, 8)
    XCTAssertEqual(image.height, 6)
  }

  func testPreviewDoesNotChangeSourceChecksum() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let checksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    _ = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(
        operations: [
          .exposureEV(0.5),
          .threeWayColorGrade(try makeColorGrade()),
          .rotationDegrees(45),
        ]
      ),
      maximumPixelDimension: 4
    )

    XCTAssertEqual(try DeterministicImageFixture.checksum(of: fixture.source), checksum)
  }

  func testPreviewScalesTheEditedGraph() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let leftHalf = try XCTUnwrap(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(
        operations: [.normalizedCrop(leftHalf), .rotationDegrees(90)]
      ),
      maximumPixelDimension: 3
    )

    XCTAssertEqual(image.width, 3)
    XCTAssertEqual(image.height, 2)
  }

  func testPreviewRejectsNonpositiveBound() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        maximumPixelDimension: 0
      )
      XCTFail("Expected invalid maximum error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .invalidMaximumPixelDimension(0))
    }
  }

  func testPreviewRejectsCommonImageDecoderVersionMismatch() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let recipe = EditRecipe(
      assetID: UUID(),
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "future-common-decoder",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: recipe,
        maximumPixelDimension: nil
      )
      XCTFail("Expected decoder version mismatch")
    } catch let error as RenderCoreError {
      XCTAssertEqual(
        error,
        .decoderVersionMismatch(
          expected: "future-common-decoder",
          actual: "system-default"
        )
      )
    }
  }

  func testPreviewRejectsDecoderIdentifierMismatch() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let recipe = EditRecipe(
      assetID: UUID(),
      pins: EnginePins(
        decoderIdentifier: "com.example.future-decoder",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: recipe,
        maximumPixelDimension: nil
      )
      XCTFail("Expected decoder identifier mismatch")
    } catch let error as RenderCoreError {
      XCTAssertEqual(
        error,
        .decoderIdentifierMismatch(
          expected: "com.example.future-decoder",
          actual: "com.apple.coreimage.common-image"
        )
      )
    }
  }

  func testRenderEngineProtocolReturnsBoundedPNGTransport() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let engine: any RenderEngine = CoreImageRenderEngine(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    let result = try await engine.render(
      RenderRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        maximumPixelDimension: 4,
        outputColorSpaceName: "extended-linear-display-p3"
      )
    )

    XCTAssertEqual(result.typeIdentifier, UTType.png.identifier)
    XCTAssertEqual(result.pixelDimensions, PixelDimensions(width: 4, height: 3))
    let imageSource = try XCTUnwrap(
      CGImageSourceCreateWithData(result.imageData as CFData, nil)
    )
    XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.png.identifier)
  }

  func testRenderHistogramUses256BinsAndKnownSRGBPixels() throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(
      in: directory,
      name: "known.png",
      width: 2,
      height: 2,
      pixels: [
        0, 0, 0, 255,
        255, 0, 0, 255,
        0, 255, 0, 255,
        0, 0, 255, 255,
      ]
    )

    let histogram = try RenderHistogramBuilder.make(from: Data(contentsOf: source))

    XCTAssertEqual(histogram.red.count, RenderHistogram.binCount)
    XCTAssertEqual(histogram.green.count, RenderHistogram.binCount)
    XCTAssertEqual(histogram.blue.count, RenderHistogram.binCount)
    XCTAssertEqual(histogram.luminance.count, RenderHistogram.binCount)
    XCTAssertEqual(histogram.red[0], 3)
    XCTAssertEqual(histogram.red[255], 1)
    XCTAssertEqual(histogram.green[0], 3)
    XCTAssertEqual(histogram.green[255], 1)
    XCTAssertEqual(histogram.blue[0], 3)
    XCTAssertEqual(histogram.blue[255], 1)
    XCTAssertEqual(histogram.luminance[0], 1)
    XCTAssertEqual(histogram.luminance[54], 1)
    XCTAssertEqual(histogram.luminance[182], 1)
    XCTAssertEqual(histogram.luminance[18], 1)
  }

  func testRenderEngineIncludesHistogramForFinalBoundedPreview() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let engine = CoreImageRenderEngine(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    let result = try await engine.render(
      RenderRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(operations: [.threeWayColorGrade(.neutral)]),
        maximumPixelDimension: 4,
        outputColorSpaceName: "extended-linear-display-p3"
      )
    )

    let histogram = try XCTUnwrap(result.histogram)
    XCTAssertEqual(histogram.red.reduce(0, +), 12)
    XCTAssertEqual(histogram.green.reduce(0, +), 12)
    XCTAssertEqual(histogram.blue.reduce(0, +), 12)
    XCTAssertEqual(histogram.luminance.reduce(0, +), 12)
    XCTAssertEqual(
      histogram,
      try RenderHistogramBuilder.make(from: result.imageData)
    )
  }

  func testRenderEngineChecksCancellationBeforeHistogramPublication() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let engine = CoreImageRenderEngine(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())
    let request = RenderRequest(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: 4,
      outputColorSpaceName: "extended-linear-display-p3"
    )
    let task = Task { try await engine.render(request) }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }
  }

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func makeRecipe(operations: [EditOperation] = []) -> EditRecipe {
    EditRecipe(
      assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      ),
      operations: operations
    )
  }

  private func makeColorGrade() throws -> ThreeWayColorGrade {
    try XCTUnwrap(
      ThreeWayColorGrade(
        shadows: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 230, chroma: 0.25, luminance: -0.1)
        ),
        midtones: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 30, chroma: 0.2, luminance: 0)
        ),
        highlights: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 50, chroma: 0.15, luminance: 0.1)
        )
      )
    )
  }
}
