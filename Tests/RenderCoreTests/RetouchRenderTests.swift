// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class RetouchRenderTests: XCTestCase {
  func testCloneRetouchCopiesTheSourceIntoThePaintedRegion() async throws {
    let fixture = try makeSplitFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let sourceChecksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let source = try XCTUnwrap(RetouchPointV1(x: 0.25, y: 0.5))
    let target = try XCTUnwrap(RetouchPointV1(x: 0.75, y: 0.5))
    let brush = try XCTUnwrap(
      RetouchBrushV1(
        samples: [
          try XCTUnwrap(RetouchBrushSampleV1(point: target, pressure: 1))
        ],
        radius: 0.22,
        feather: 0,
        flow: 1
      )
    )
    let adjustment = try XCTUnwrap(
      CloneAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush
      )
    )
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let cloned = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.clone(adjustment)]),
      maximumPixelDimension: nil
    )
    let baselineData = try DeterministicImageFixture.rgba8Data(from: baseline)
    let clonedData = try DeterministicImageFixture.rgba8Data(from: cloned)
    let baselineTarget = DeterministicImageFixture.pixel(
      x: 6,
      y: 3,
      width: baseline.width,
      in: baselineData
    )
    let clonedTarget = DeterministicImageFixture.pixel(
      x: 6,
      y: 3,
      width: cloned.width,
      in: clonedData
    )

    XCTAssertLessThan(clonedTarget.red, baselineTarget.red)
    XCTAssertGreaterThan(clonedTarget.blue, baselineTarget.blue)
    XCTAssertEqual(
      DeterministicImageFixture.pixel(x: 0, y: 0, width: baseline.width, in: clonedData).red,
      DeterministicImageFixture.pixel(x: 0, y: 0, width: baseline.width, in: baselineData).red,
      accuracy: 1
    )
    XCTAssertEqual(sourceChecksum, try DeterministicImageFixture.checksum(of: fixture.source))
  }

  func testHealingRetouchIsDeterministicAndKeepsSourceImmutable() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let original = try Data(contentsOf: fixture.source)
    let source = try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.35))
    let target = try XCTUnwrap(RetouchPointV1(x: 0.78, y: 0.65))
    let brush = try XCTUnwrap(
      RetouchBrushV1(
        samples: [
          try XCTUnwrap(RetouchBrushSampleV1(point: target, pressure: 0.9))
        ],
        radius: 0.2,
        feather: 0.25,
        flow: 1
      )
    )
    let adjustment = try XCTUnwrap(
      HealingAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush,
        blend: 0.8
      )
    )
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let baseline = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(),
      maximumPixelDimension: nil
    )
    let first = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.healing(adjustment)]),
      maximumPixelDimension: nil
    )
    let second = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: makeRecipe(operations: [.healing(adjustment)]),
      maximumPixelDimension: nil
    )

    XCTAssertEqual(
      try DeterministicImageFixture.rgba8Data(from: first),
      try DeterministicImageFixture.rgba8Data(from: second)
    )
    XCTAssertEqual(original, try Data(contentsOf: fixture.source))
    XCTAssertNotEqual(
      try DeterministicImageFixture.rgba8Data(from: first),
      try DeterministicImageFixture.rgba8Data(from: baseline)
    )
  }

  func testRedEyePayloadIsTypedButRenderReportsUnsupportedOperation() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let redEye = try XCTUnwrap(
      RedEyeAdjustmentV1(
        center: try XCTUnwrap(RetouchPointV1(x: 0.5, y: 0.5)),
        radius: 0.08,
        feather: 0.25
      )
    )
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()

    do {
      _ = try await decoder.preview(
        sourceURL: fixture.source,
        recipe: makeRecipe(operations: [.redEye(redEye)]),
        maximumPixelDimension: nil
      )
      XCTFail("Red-eye must remain explicitly unsupported until its algorithm is verified.")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .unsupportedOperation(index: 0, kind: "redEye"))
    }
  }

  func testRetouchResultGateRejectsStaleRevision() {
    let requestID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let assetID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let current = RetouchRequestIdentity(
      assetID: assetID,
      recipeRevision: 4,
      requestID: requestID
    )
    let stale = RetouchRequestIdentity(
      assetID: assetID,
      recipeRevision: 3,
      requestID: requestID
    )

    XCTAssertTrue(RetouchResultGate.accepts(result: current, for: current))
    XCTAssertFalse(RetouchResultGate.accepts(result: stale, for: current))
  }

  func testRetouchRenderHonoursCancellationBeforePublication() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let sourceURL = fixture.source
    let recipe = makeRecipe()
    let task = Task {
      try await decoder.preview(
        sourceURL: sourceURL,
        recipe: recipe,
        maximumPixelDimension: nil
      )
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }
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

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func makeSplitFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    let pixels = (0..<6).flatMap { _ in
      (0..<8).flatMap { x -> [UInt8] in
        if x < 4 {
          return [30, 70, 210, 255]
        }
        return [220, 40, 20, 255]
      }
    }
    let source = try DeterministicImageFixture.makePNG(
      in: directory,
      width: 8,
      height: 6,
      pixels: pixels
    )
    return (directory, source)
  }
}
