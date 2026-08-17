// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class VisionAIMaskServiceTests: XCTestCase {
  func testVisionProviderAdvertisesOnlyImplementedOfflineKinds() {
    XCTAssertEqual(
      VisionAIModelService.supportedMaskKinds,
      [.foreground, .subject, .person]
    )
    XCTAssertFalse(VisionAIModelService.supports(.sky))
    XCTAssertFalse(VisionAIModelService.supports(.object))
    XCTAssertFalse(VisionAIModelService.supports(MaskKind.depthRange))
  }

  func testVisionResultCarriesIdentityAndMaskResultGateRejectsStaleRevision() throws {
    let identity = makeIdentity(revision: 4)
    let mask = MaskDefinition(
      id: identity.revision.maskID,
      schemaVersion: 1,
      kind: .subject,
      name: "Vision subject",
      isInverted: false,
      payload: Data([1, 2, 3])
    )
    let result = VisionAIMaskResult(
      identity: identity,
      kind: .subject,
      mask: mask,
      modelIdentifier: "com.apple.Vision.foreground-instance-mask",
      modelVersion: "1"
    )

    XCTAssertTrue(MaskResultGate.accepts(result, for: identity))
    XCTAssertFalse(
      MaskResultGate.accepts(
        result,
        for: MaskRequestIdentity(
          revision: MaskRevisionIdentity(
            assetID: identity.revision.assetID,
            maskID: identity.revision.maskID,
            revision: 3
          ),
          requestID: identity.requestID
        )
      )
    )
    XCTAssertEqual(result.identity, identity)
  }

  func testVisionPayloadRoundTripsAsDurableGrayscaleCoverage() throws {
    let dimensions = try XCTUnwrap(PixelDimensions(width: 3, height: 2))
    let payload = try XCTUnwrap(
      VisionAIMaskPayloadV1(
        kind: .person,
        dimensions: dimensions,
        bytesPerRow: 3,
        coverage: Data([0, 16, 255, 255, 64, 0])
      )
    )

    let encoded = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(VisionAIMaskPayloadV1.self, from: encoded)
    XCTAssertEqual(decoded, payload)
    XCTAssertEqual(decoded.coverage.count, 6)
    XCTAssertEqual(decoded.dimensions, dimensions)
    XCTAssertEqual(decoded.bytesPerRow, 3)
  }

  func testVisionSubjectFixtureProducesMaskOrExplicitlySkipsWhenVisionHasNoSemanticResult()
    async throws
  {
    let fixture = makeFixture()
    let request = VisionAIMaskRequest(
      identity: makeIdentity(revision: 1),
      image: fixture,
      kind: .subject
    )

    do {
      let result = try await VisionAIModelService().generateMask(request)
      let payload = try result.decodePayload()

      XCTAssertEqual(result.identity, request.identity)
      XCTAssertEqual(payload.kind, .subject)
      XCTAssertEqual(payload.dimensions, fixture.dimensions)
      XCTAssertEqual(payload.bytesPerRow, fixture.dimensions.width)
      XCTAssertEqual(payload.coverage.count, fixture.dimensions.width * fixture.dimensions.height)
      XCTAssertTrue(payload.coverage.contains(where: { $0 > 0 }))
      XCTAssertTrue(MaskResultGate.accepts(result, for: request.identity))
    } catch let error as VisionAIMaskError where error.shouldSkipDeterministicFixture {
      throw XCTSkip(error.localizedDescription)
    }
  }

  func testVisionPersonFixtureProducesMaskOrExplicitlySkipsWhenVisionHasNoPerson() async throws {
    let fixture = makeFixture()
    let request = VisionAIMaskRequest(
      identity: makeIdentity(revision: 2),
      image: fixture,
      kind: .person
    )

    do {
      let result = try await VisionAIModelService().generateMask(request)
      let payload = try result.decodePayload()

      XCTAssertEqual(result.identity, request.identity)
      XCTAssertEqual(payload.kind, .person)
      XCTAssertEqual(payload.dimensions, fixture.dimensions)
      XCTAssertEqual(payload.bytesPerRow, fixture.dimensions.width)
      XCTAssertEqual(payload.coverage.count, fixture.dimensions.width * fixture.dimensions.height)
      XCTAssertTrue(MaskResultGate.accepts(result, for: request.identity))
    } catch let error as VisionAIMaskError where error.shouldSkipDeterministicFixture {
      throw XCTSkip(error.localizedDescription)
    }
  }

  func testLegacyAIModelServiceRejectsUnimplementedKindsWithoutNetworkAccess() async throws {
    let dimensions = try XCTUnwrap(PixelDimensions(width: 2, height: 2))
    let request = AIModelRequest(
      assetID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      image: ImageBuffer(
        data: Data(repeating: 0, count: 16),
        dimensions: dimensions,
        bytesPerRow: 8,
        pixelFormat: .rgba8,
        colorSpaceName: "sRGB"
      ),
      maskKind: .sky,
      modelIdentifier: "vision.sky.v1"
    )

    do {
      _ = try await (VisionAIModelService() as any AIModelService).generateMask(request)
      XCTFail("Sky masks are not implemented by the Vision-only provider")
    } catch let error as VisionAIMaskError {
      XCTAssertEqual(error, .unsupportedMaskKind("sky"))
    }
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

  private func makeFixture() -> ImageBuffer {
    let width = 64
    let height = 64
    var data = Data(repeating: 0, count: width * height * 4)
    data.withUnsafeMutableBytes { rawBuffer in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      for y in 0..<height {
        for x in 0..<width {
          let offset = (y * width + x) * 4
          let centralSquare = (16..<48).contains(x) && (16..<48).contains(y)
          bytes[offset] = centralSquare ? 245 : 12
          bytes[offset + 1] = centralSquare ? 80 : 12
          bytes[offset + 2] = centralSquare ? 32 : 12
          bytes[offset + 3] = 255
        }
      }
    }
    return ImageBuffer(
      data: data,
      dimensions: PixelDimensions(width: width, height: height)!,
      bytesPerRow: UInt(width * 4),
      pixelFormat: .rgba8,
      colorSpaceName: "sRGB"
    )
  }
}
