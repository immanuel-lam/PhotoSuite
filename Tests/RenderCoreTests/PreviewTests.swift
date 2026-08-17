// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
    let decoder = try AppleRawDecoder()

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
    let decoder = try AppleRawDecoder()

    let image = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: 64
    )

    XCTAssertEqual(image.width, 8)
    XCTAssertEqual(image.height, 6)
  }

  func testPreviewScalesTheEditedGraph() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try AppleRawDecoder()
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
    let decoder = try AppleRawDecoder()

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

  func testRenderEngineProtocolReturnsBoundedPNGTransport() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let engine: any RenderEngine = CoreImageRenderEngine(decoder: try AppleRawDecoder())

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

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func makeRecipe(operations: [EditOperation] = []) -> EditRecipe {
    EditRecipe(
      assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      ),
      operations: operations
    )
  }
}
