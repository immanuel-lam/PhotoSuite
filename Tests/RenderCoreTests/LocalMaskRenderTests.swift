// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class LocalMaskRenderTests: XCTestCase {
  func testMaskedAdjustmentIsVersionedAndRoundTrips() throws {
    let maskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let adjustment = try XCTUnwrap(
      MaskedAdjustmentV1(maskID: maskID, exposureEV: 0.5, colorGrade: .neutral)
    )
    let operation = EditOperation.maskedAdjustment(adjustment)
    let encoded = try JSONEncoder().encode(operation)
    let decoded = try JSONDecoder().decode(EditOperation.self, from: encoded)

    XCTAssertEqual(decoded, operation)
    XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"maskedAdjustment\""))
    XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"schemaVersion\":1"))
  }

  func testBrushMaskExposureIsRestrictedToPaintedRegion() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let point = try XCTUnwrap(MaskPointV1(x: 0.5, y: 0.5))
    let sample = try XCTUnwrap(MaskBrushSampleV1(point: point, pressure: 1))
    let brush = try XCTUnwrap(
      BrushMaskV1(samples: [sample], radius: 0.3, feather: 0.1, flow: 1)
    )
    let maskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let graph = MaskGraphV1(
      components: [
        MaskGraphComponentV1(
          id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
          operation: .add,
          primitive: .brush(brush)
        )
      ]
    )
    let mask = try MaskDefinition(id: maskID, kind: .brush, name: "Brush", graph: graph)
    let adjustment = try XCTUnwrap(
      MaskedAdjustmentV1(maskID: maskID, exposureEV: 1, colorGrade: .neutral)
    )

    let baseline = try await render(fixture.source)
    let adjusted = try await render(
      fixture.source,
      operations: [.maskedAdjustment(adjustment)],
      masks: [mask]
    )

    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let adjustedData = try DeterministicImageFixture.rgba8Data(from: adjusted)
    let centre = DeterministicImageFixture.pixel(
      x: baseline.width / 2,
      y: baseline.height / 2,
      width: baseline.width,
      in: adjustedData
    )
    let corner = DeterministicImageFixture.pixel(
      x: 0,
      y: 0,
      width: baseline.width,
      in: adjustedData
    )
    let baselineCentre = DeterministicImageFixture.pixel(
      x: baseline.width / 2,
      y: baseline.height / 2,
      width: baseline.width,
      in: baselineData
    )
    let baselineCorner = DeterministicImageFixture.pixel(
      x: 0,
      y: 0,
      width: baseline.width,
      in: baselineData
    )

    XCTAssertGreaterThan(centre.red, baselineCentre.red)
    XCTAssertGreaterThan(centre.green, baselineCentre.green)
    XCTAssertEqual(corner.red, baselineCorner.red, accuracy: 2)
    XCTAssertEqual(corner.green, baselineCorner.green, accuracy: 2)
  }

  func testMaskDefinitionInversionMovesAdjustmentOutsideThePaintedRegion() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let point = try XCTUnwrap(MaskPointV1(x: 0.5, y: 0.5))
    let sample = try XCTUnwrap(MaskBrushSampleV1(point: point, pressure: 1))
    let brush = try XCTUnwrap(
      BrushMaskV1(samples: [sample], radius: 0.3, feather: 0, flow: 1)
    )
    let maskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let graph = MaskGraphV1(
      components: [
        MaskGraphComponentV1(
          id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
          operation: .add,
          primitive: .brush(brush)
        )
      ]
    )
    let mask = MaskDefinition(
      id: maskID,
      schemaVersion: 1,
      kind: .brush,
      name: "Inverted brush",
      isInverted: true,
      payload: try JSONEncoder().encode(graph)
    )
    let adjustment = try XCTUnwrap(
      MaskedAdjustmentV1(maskID: maskID, exposureEV: 1, colorGrade: .neutral)
    )

    let baseline = try await render(fixture.source)
    let adjusted = try await render(
      fixture.source,
      operations: [.maskedAdjustment(adjustment)],
      masks: [mask]
    )
    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let adjustedData = try DeterministicImageFixture.rgba8Data(from: adjusted)
    let baselineCentre = DeterministicImageFixture.pixel(
      x: baseline.width / 2,
      y: baseline.height / 2,
      width: baseline.width,
      in: baselineData
    )
    let adjustedCentre = DeterministicImageFixture.pixel(
      x: baseline.width / 2,
      y: baseline.height / 2,
      width: baseline.width,
      in: adjustedData
    )
    let baselineCorner = DeterministicImageFixture.pixel(
      x: 0,
      y: 0,
      width: baseline.width,
      in: baselineData
    )
    let adjustedCorner = DeterministicImageFixture.pixel(
      x: 0,
      y: 0,
      width: baseline.width,
      in: adjustedData
    )

    XCTAssertEqual(adjustedCentre.red, baselineCentre.red, accuracy: 2)
    XCTAssertGreaterThan(adjustedCorner.red, baselineCorner.red)
  }

  func testAllLocalMaskPrimitivesProduceDeterministicCompositeDigest() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let maskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let pointA = try XCTUnwrap(MaskPointV1(x: 0.1, y: 0.1))
    let pointB = try XCTUnwrap(MaskPointV1(x: 0.8, y: 0.8))
    let sample = try XCTUnwrap(MaskBrushSampleV1(point: pointA, pressure: 1))
    let red = try XCTUnwrap(MaskColorSampleV1(red: 0.5, green: 0.5, blue: 0.1))
    let primitives: [MaskPrimitiveV1] = [
      .brush(try XCTUnwrap(BrushMaskV1(samples: [sample], radius: 0.35, feather: 0.2, flow: 0.8))),
      .linearGradient(
        try XCTUnwrap(LinearGradientMaskV1(start: pointA, end: pointB, feather: 0.2))
      ),
      .radialGradient(
        try XCTUnwrap(
          RadialGradientMaskV1(
            center: try XCTUnwrap(MaskPointV1(x: 0.5, y: 0.5)),
            radiusX: 0.4,
            radiusY: 0.3,
            rotationDegrees: 20,
            feather: 0.25
          )
        )
      ),
      .colorRange(try XCTUnwrap(ColorRangeMaskV1(samples: [red], tolerance: 0.7, feather: 0.2))),
      .luminanceRange(
        try XCTUnwrap(LuminanceRangeMaskV1(lowerBound: 0.2, upperBound: 0.8, feather: 0.2))
      ),
      .depthRange(
        try XCTUnwrap(DepthRangeMaskV1(nearBound: 0.25, farBound: 0.75, feather: 0.2))
      ),
    ]
    let components = primitives.enumerated().map { offset, primitive in
      MaskGraphComponentV1(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!,
        operation: offset == 0 ? .add : .intersect,
        primitive: primitive
      )
    }
    let mask = try MaskDefinition(
      id: maskID,
      kind: .brush,
      name: "Composite local mask",
      graph: MaskGraphV1(components: components)
    )
    let grade = try XCTUnwrap(
      ThreeWayColorGrade(
        shadows: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 220, chroma: 0.35, luminance: 0.04)
        ),
        midtones: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 35, chroma: 0.2, luminance: 0.01)
        ),
        highlights: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 55, chroma: 0.3, luminance: -0.02)
        )
      )
    )
    let adjustment = try XCTUnwrap(
      MaskedAdjustmentV1(maskID: maskID, exposureEV: 0.75, colorGrade: grade)
    )
    let rendered = try await render(
      fixture.source,
      operations: [.maskedAdjustment(adjustment)],
      masks: [mask]
    )
    let digest = SHA256.hash(data: try DeterministicImageFixture.rgba8Data(from: rendered))
      .map { String(format: "%02x", $0) }
      .joined()

    XCTAssertEqual(digest, "2c2eb8ab14d0ed2496f150b8731da157fcf942fbb57f514cb3cd234ffa8a9c0d")
  }

  func testStaleMaskResultIsRejectedForLocalAdjustmentRequests() {
    let assetID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let maskID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let requestID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    let current = MaskRequestIdentity(
      revision: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 4),
      requestID: requestID
    )
    let stale = MaskOperationResult(
      requestIdentity: MaskRequestIdentity(
        revision: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 3),
        requestID: requestID
      ),
      records: []
    )

    XCTAssertFalse(MaskResultGate.accepts(stale, for: current))
  }

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func render(
    _ source: URL,
    operations: [EditOperation] = [],
    masks: [MaskDefinition] = []
  ) async throws -> CGImage {
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    return try await decoder.preview(
      sourceURL: source,
      recipe: EditRecipe(
        assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
        pins: EnginePins(
          decoderIdentifier: "com.apple.coreimage.common-image",
          decoderVersion: "system-default",
          renderSchemaVersion: 1,
          cameraProfileVersion: nil,
          modelVersions: [:]
        ),
        operations: operations,
        masks: masks
      ),
      maximumPixelDimension: nil
    )
  }
}
