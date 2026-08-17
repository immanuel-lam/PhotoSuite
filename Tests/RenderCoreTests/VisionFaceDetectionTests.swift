// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class VisionFaceDetectionTests: XCTestCase {
  func testDetectorConvertsValidatedObservationsToUnlabeledFaces() async throws {
    let assetID = UUID()
    let image = makeImageBuffer()
    let region = try XCTUnwrap(FaceRegion(x: 0.2, y: 0.3, width: 0.25, height: 0.2))
    let observation = try XCTUnwrap(VisionFaceObservation(region: region, confidence: 0.93))
    let request = VisionFaceDetectionRequest(assetID: assetID, image: image)
    let service = VisionFaceDetectionService(detector: { _ in
      [observation]
    })

    let result = try await service.detectFaces(request)

    XCTAssertEqual(result.assetID, assetID)
    XCTAssertEqual(result.requestID, request.requestID)
    XCTAssertEqual(result.faces.count, 1)
    let face = try XCTUnwrap(result.faces.first)
    XCTAssertEqual(face.assetID, assetID)
    XCTAssertEqual(face.region, region)
    XCTAssertEqual(face.source, .vision)
    XCTAssertNil(face.label)
    XCTAssertEqual(try XCTUnwrap(face.confidence), 0.93, accuracy: 0.0001)
    XCTAssertTrue(result.accepts(request))
  }

  func testDetectorReturnsAnEmptyFaceSetWhenVisionFindsNothing() async throws {
    let request = VisionFaceDetectionRequest(assetID: UUID(), image: makeImageBuffer())
    let service = VisionFaceDetectionService(detector: { _ in [] })

    let result = try await service.detectFaces(request)

    XCTAssertTrue(result.faces.isEmpty)
  }

  func testNativeDetectorRejectsTruncatedImageWithTypedError() async throws {
    let dimensions = try XCTUnwrap(PixelDimensions(width: 2, height: 2))
    let image = ImageBuffer(
      data: Data(repeating: 0, count: 3),
      dimensions: dimensions,
      bytesPerRow: 8,
      pixelFormat: .rgba8,
      colorSpaceName: "sRGB"
    )
    let request = VisionFaceDetectionRequest(assetID: UUID(), image: image)
    let service = VisionFaceDetectionService()

    do {
      _ = try await service.detectFaces(request)
      XCTFail("The native detector must reject truncated pixel data.")
    } catch let error as VisionFaceDetectionError {
      guard case .invalidImageBuffer = error else {
        return XCTFail("Unexpected Vision face error: \(error)")
      }
    }
  }

  private func makeImageBuffer() -> ImageBuffer {
    let dimensions = PixelDimensions(width: 2, height: 2)!
    return ImageBuffer(
      data: Data(repeating: 255, count: 16),
      dimensions: dimensions,
      bytesPerRow: 8,
      pixelFormat: .rgba8,
      colorSpaceName: "sRGB"
    )
  }
}
