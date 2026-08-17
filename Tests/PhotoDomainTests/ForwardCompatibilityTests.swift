// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class ForwardCompatibilityTests: XCTestCase {
  func testColorLabelKeepsItsPublicRawValueAPI() {
    XCTAssertEqual(ColorLabel(rawValue: "red"), .red)
    XCTAssertEqual(ColorLabel(rawValue: "orange"), .unknown("orange"))
    XCTAssertEqual(ColorLabel.unknown("red").rawValue, "red")
  }

  func testPhotoAssetPreservesUnknownFutureColorLabel() throws {
    let asset = try makeAsset(colorLabel: nil)
    let encoded = try JSONEncoder().encode(asset)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["colorLabel"] = "orange"
    let futureData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(PhotoAsset.self, from: futureData)
    let reencoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(PhotoAsset.self, from: reencoded)

    XCTAssertEqual(decoded.colorLabel, .unknown("orange"))
    XCTAssertEqual(roundTripped.colorLabel, .unknown("orange"))
  }

  func testUnknownCasesThatCollideWithReservedCodesRoundTripUnambiguously() throws {
    try assertCollisionRoundTrip(ColorLabel.unknown("red"), reservedCode: "red")
    try assertCollisionRoundTrip(MaskKind.unknown("brush"), reservedCode: "brush")
    try assertCollisionRoundTrip(
      DurableDerivativeKind.unknown("preview"),
      reservedCode: "preview"
    )
    try assertCollisionRoundTrip(
      CatalogJobKind.unknown("export"),
      reservedCode: "export"
    )
    try assertCollisionRoundTrip(
      CatalogJobState.unknown("queued"),
      reservedCode: "queued"
    )
    try assertCollisionRoundTrip(
      ImagePixelFormat.unknown("rgba8"),
      reservedCode: "rgba8"
    )
    try assertCollisionRoundTrip(ExportFormat.unknown("jpeg"), reservedCode: "jpeg")
    try assertCollisionRoundTrip(
      XPCResponseStatus.unknown("success"),
      reservedCode: "success"
    )
    try assertCollisionRoundTrip(
      CameraAdapterXPC.Operation.unknown("capture"),
      reservedCode: "capture"
    )
    try assertCollisionRoundTrip(
      PhotoPluginXPC.Operation.unknown("process"),
      reservedCode: "process"
    )
  }

  func testUnknownEditOperationThatCollidesWithReservedKindRoundTrips() throws {
    let operation = EditOperation.unknown(
      "contrast",
      payload: ["value": .number(42), "algorithm": .string("future")]
    )

    let data = try JSONEncoder().encode(operation)
    let decoded = try JSONDecoder().decode(EditOperation.self, from: data)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    XCTAssertEqual(decoded, operation)
    XCTAssertEqual(object["kind"] as? NSDictionary, ["unknown": "contrast"])
  }

  private func assertCollisionRoundTrip<Value>(
    _ value: Value,
    reservedCode: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws where Value: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)

    XCTAssertEqual(decoded, value, file: file, line: line)
    XCTAssertEqual(
      String(decoding: data, as: UTF8.self),
      #"{"unknown":"\#(reservedCode)"}"#,
      file: file,
      line: line
    )
  }

  private func makeAsset(colorLabel: ColorLabel?) throws -> PhotoAsset {
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "c", count: 64),
        byteCount: 1,
        modificationDate: nil
      )
    )
    return try XCTUnwrap(
      PhotoAsset(
        sourceURL: URL(fileURLWithPath: "/Pictures/future.CR3"),
        filename: "future.CR3",
        typeIdentifier: "com.canon.cr3-raw-image",
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1_700_000_000),
        captureDate: nil,
        pixelDimensions: nil,
        rating: 0,
        colorLabel: colorLabel,
        isMissing: false
      )
    )
  }
}
