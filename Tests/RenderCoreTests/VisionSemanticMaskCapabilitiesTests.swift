// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class VisionSemanticMaskCapabilitiesTests: XCTestCase {
  func testNativeVisionBoundaryIsExplicitForSemanticKindsBeyondCurrentProvider() {
    XCTAssertEqual(
      VisionSemanticMaskService.capabilities.map(\.kind),
      [.sky, .object, .background, .landscape, .depth]
    )

    let sky = VisionSemanticMaskService.capability(for: .sky)
    XCTAssertEqual(sky.status, .unavailableNativeAPI)
    XCTAssertFalse(sky.isAvailable)
    XCTAssertTrue(sky.reason.contains("system Vision"))

    let object = VisionSemanticMaskService.capability(for: .object)
    XCTAssertEqual(object.status, .requiresOptionalModelPack)
    XCTAssertFalse(object.isAvailable)
    XCTAssertTrue(object.reason.contains("model pack"))
  }

  func testServiceReturnsTypedUnavailableResultWithoutApplyingAnEdit() async throws {
    let request = VisionSemanticMaskRequest(
      identity: makeIdentity(revision: 6),
      image: makeImage(),
      kind: .sky
    )

    let result = await VisionSemanticMaskService().generateMask(request)

    XCTAssertEqual(result.identity, request.identity)
    XCTAssertEqual(result.kind, .sky)
    XCTAssertEqual(result.modelIdentifier, request.modelIdentifier)
    XCTAssertEqual(result.modelVersion, request.modelVersion)
    XCTAssertEqual(result.status, .unavailable)
    XCTAssertEqual(result.capability.status, .unavailableNativeAPI)
    XCTAssertNil(result.mask)
    XCTAssertFalse(result.applied)
    XCTAssertTrue(MaskResultGate.accepts(result, for: request.identity))
  }

  func testOptionalModelPackPathReturnsStableNoOpResultAndRoundTrips() throws {
    let identity = makeIdentity(revision: 7)
    let capability = VisionSemanticMaskService.capability(for: .object)
    let result = VisionSemanticMaskResult.noOp(
      identity: identity,
      kind: .object,
      capability: capability
    )

    XCTAssertEqual(result.status, .noOp)
    XCTAssertNil(result.mask)
    XCTAssertFalse(result.applied)
    XCTAssertTrue(MaskResultGate.accepts(result, for: identity))

    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(VisionSemanticMaskResult.self, from: encoded)
    XCTAssertEqual(decoded, result)
  }

  func testResultGateRejectsAStaleSemanticMaskResponse() {
    let current = makeIdentity(revision: 8)
    let stale = VisionSemanticMaskResult.unavailable(
      identity: makeIdentity(revision: 7),
      kind: .background,
      capability: VisionSemanticMaskService.capability(for: .background)
    )

    XCTAssertFalse(MaskResultGate.accepts(stale, for: current))
  }

  private func makeIdentity(revision: UInt64) -> MaskRequestIdentity {
    MaskRequestIdentity(
      revision: MaskRevisionIdentity(
        assetID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        maskID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        revision: revision
      ),
      requestID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    )
  }

  private func makeImage() -> ImageBuffer {
    ImageBuffer(
      data: Data(repeating: 0, count: 16),
      dimensions: PixelDimensions(width: 2, height: 2)!,
      bytesPerRow: 8,
      pixelFormat: .rgba8,
      colorSpaceName: "sRGB"
    )
  }
}
