// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class ServiceAndXPCTests: XCTestCase {
  func testRepresentativeServiceRequestsAndResultsMeetValueContract() throws {
    let asset = try makeAsset()
    let recipe = EditRecipe(assetID: asset.id, date: asset.importDate, pins: makePins())
    let dimensions = try XCTUnwrap(PixelDimensions(width: 2, height: 1))
    let image = ImageBuffer(
      data: Data(repeating: 0x7F, count: 16),
      dimensions: dimensions,
      bytesPerRow: 16,
      pixelFormat: .rgba16Float,
      colorSpaceName: "extended-linear-display-p3"
    )
    let job = CatalogJob(
      schemaVersion: 1,
      kind: .generatePreview,
      state: .queued,
      assetIDs: [asset.id],
      createdAt: asset.importDate,
      updatedAt: asset.importDate,
      payload: Data()
    )
    let mask = MaskDefinition(
      schemaVersion: 1,
      kind: .subject,
      name: nil,
      isInverted: false,
      payload: Data([0x01])
    )
    let derivative = DurableDerivative(
      schemaVersion: 1,
      assetID: asset.id,
      recipeRevision: recipe.revision,
      kind: .export,
      outputURL: URL(fileURLWithPath: "/Exports/output.jpg"),
      typeIdentifier: "public.jpeg",
      fingerprint: nil,
      createdAt: asset.importDate
    )

    try assertValueContract(CatalogAssetUpsertRequest(asset: asset))
    try assertValueContract(CatalogAssetUpsertResult(asset: asset))
    try assertValueContract(
      RawDecodeRequest(sourceURL: asset.sourceURL, decoderVersion: "9")
    )
    try assertValueContract(
      RawDecodeResult(
        image: image,
        metadata: ["camera": "Test Camera"],
        decoderIdentifier: "com.apple.ciraw",
        decoderVersion: "9"
      )
    )
    try assertValueContract(
      RenderRequest(
        sourceURL: asset.sourceURL,
        recipe: recipe,
        maximumPixelDimension: 2_048,
        outputColorSpaceName: "display-p3"
      )
    )
    try assertValueContract(
      RenderResult(
        imageData: Data([0xFF, 0xD8, 0xFF]),
        typeIdentifier: "public.jpeg",
        pixelDimensions: dimensions
      )
    )
    try assertValueContract(JobEnqueueRequest(job: job))
    try assertValueContract(JobEnqueueResult(job: job))
    try assertValueContract(
      AIModelRequest(
        assetID: asset.id,
        image: image,
        maskKind: .subject,
        modelIdentifier: "subject-segmentation"
      )
    )
    try assertValueContract(AIModelResult(mask: mask, modelVersion: "2.1"))
    try assertValueContract(
      CodecEncodeRequest(
        image: image,
        typeIdentifier: "public.jpeg",
        quality: 0.9
      )
    )
    try assertValueContract(
      CodecEncodeResult(data: Data([0xFF, 0xD8, 0xFF]), typeIdentifier: "public.jpeg")
    )
    try assertValueContract(
      ExportRequest(
        sourceURL: asset.sourceURL,
        recipe: recipe,
        destinationURL: derivative.outputURL,
        format: .jpeg,
        quality: 0.9
      )
    )
    try assertValueContract(ExportResult(derivative: derivative))
  }

  func testCameraAdapterXPCRequestPreservesVersionCorrelationAndOpaquePayload() throws {
    let requestID = UUID(uuidString: "11111111-AAAA-BBBB-CCCC-222222222222")!
    let envelope = CameraAdapterXPC.RequestEnvelope(
      schemaVersion: 3,
      requestID: requestID,
      operation: .unknown("future-camera-command"),
      payload: Data([0x00, 0x7F, 0xFF])
    )

    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(
      CameraAdapterXPC.RequestEnvelope.self,
      from: data
    )

    XCTAssertEqual(decoded, envelope)
    XCTAssertEqual(decoded.requestID, requestID)
    XCTAssertEqual(decoded.schemaVersion, 3)
    XCTAssertEqual(decoded.operation, .unknown("future-camera-command"))
    XCTAssertEqual(decoded.payload, Data([0x00, 0x7F, 0xFF]))
  }

  func testLegacyExportRequestWithoutOptionsDecodesWithSafeDefaults() throws {
    let request = ExportRequest(
      sourceURL: URL(fileURLWithPath: "/tmp/source.raw"),
      recipe: EditRecipe(
        assetID: UUID(),
        pins: EnginePins(
          decoderIdentifier: "com.apple.coreimage.common-image",
          decoderVersion: "system-default",
          renderSchemaVersion: 1,
          cameraProfileVersion: nil,
          modelVersions: [:]
        )
      ),
      destinationURL: URL(fileURLWithPath: "/tmp/output.jpg"),
      format: .jpeg,
      quality: 0.9
    )
    let encoded = try JSONEncoder().encode(request)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "options")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ExportRequest.self, from: legacyData)

    XCTAssertEqual(decoded.options, ExportOptions())
  }

  func testPhotoPluginXPCResponsePreservesOpaquePayloadAndStructuredError() throws {
    let requestID = UUID(uuidString: "33333333-AAAA-BBBB-CCCC-444444444444")!
    let envelope = PhotoPluginXPC.ResponseEnvelope(
      schemaVersion: 2,
      requestID: requestID,
      status: .failure,
      payload: Data([0xCA, 0xFE]),
      error: XPCErrorPayload(
        code: "plugin.failed",
        message: "Plugin could not process the request.",
        details: Data([0x01])
      )
    )

    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(PhotoPluginXPC.ResponseEnvelope.self, from: data)

    XCTAssertEqual(decoded, envelope)
    XCTAssertEqual(decoded.requestID, requestID)
    XCTAssertEqual(decoded.payload, Data([0xCA, 0xFE]))
    XCTAssertEqual(decoded.error?.details, Data([0x01]))
  }

  private func assertValueContract<Value>(
    _ value: Value,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws where Value: Codable & Hashable & Sendable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    XCTAssertEqual(decoded, value, file: file, line: line)
  }

  private func makeAsset() throws -> PhotoAsset {
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "b", count: 64),
        byteCount: 16,
        modificationDate: nil
      )
    )
    return try XCTUnwrap(
      PhotoAsset(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        sourceURL: URL(fileURLWithPath: "/Pictures/input.CR3"),
        filename: "input.CR3",
        typeIdentifier: "com.canon.cr3-raw-image",
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        rating: 0,
        colorLabel: nil,
        isMissing: false
      )
    )
  }

  private func makePins() -> EnginePins {
    EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "9",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
  }
}
