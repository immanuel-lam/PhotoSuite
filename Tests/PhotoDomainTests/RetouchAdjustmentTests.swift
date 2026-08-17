// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class RetouchAdjustmentTests: XCTestCase {
  func testRetouchPayloadsRoundTripInStoredOrder() throws {
    let source = try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.35))
    let target = try XCTUnwrap(RetouchPointV1(x: 0.72, y: 0.65))
    let sample = try XCTUnwrap(
      RetouchBrushSampleV1(
        point: target,
        pressure: 0.85
      )
    )
    let brush = try XCTUnwrap(
      RetouchBrushV1(
        samples: [sample],
        radius: 0.16,
        feather: 0.3,
        flow: 0.9
      )
    )
    let clone = try XCTUnwrap(
      CloneAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush
      )
    )
    let healing = try XCTUnwrap(
      HealingAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush,
        blend: 0.75
      )
    )
    let redEye = try XCTUnwrap(
      RedEyeAdjustmentV1(
        center: target,
        radius: 0.05,
        feather: 0.2
      )
    )
    let operations: [EditOperation] = [
      .clone(clone),
      .healing(healing),
      .redEye(redEye),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(operations)
    let decoded = try JSONDecoder().decode([EditOperation].self, from: data)

    XCTAssertEqual(decoded, operations)
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("\"clone\""))
    XCTAssertTrue(json.contains("\"healing\""))
    XCTAssertTrue(json.contains("\"redEye\""))
    XCTAssertTrue(json.contains("\"schemaVersion\":1"))
  }

  func testRetouchPayloadsRejectInvalidValues() throws {
    XCTAssertNil(RetouchPointV1(x: -0.01, y: 0.5))
    XCTAssertNil(RetouchPointV1(x: 0.5, y: 1.01))
    XCTAssertNil(RetouchBrushV1(samples: [], radius: 0.1, feather: 0, flow: 1))
    XCTAssertNil(
      RetouchBrushV1(
        samples: [
          try XCTUnwrap(
            RetouchBrushSampleV1(
              point: try XCTUnwrap(RetouchPointV1(x: 0.5, y: 0.5)),
              pressure: 1
            )
          )
        ],
        radius: 0,
        feather: 0,
        flow: 1
      )
    )
    XCTAssertNil(
      RedEyeAdjustmentV1(
        center: try XCTUnwrap(RetouchPointV1(x: 0.5, y: 0.5)),
        radius: 1.01,
        feather: 0.2
      )
    )
    XCTAssertNil(
      HealingAdjustmentV1(
        sourceAnchor: try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.2)),
        targetAnchor: try XCTUnwrap(RetouchPointV1(x: 0.8, y: 0.8)),
        brush: try XCTUnwrap(
          RetouchBrushV1(
            samples: [
              try XCTUnwrap(
                RetouchBrushSampleV1(
                  point: try XCTUnwrap(RetouchPointV1(x: 0.8, y: 0.8)),
                  pressure: 1
                )
              )
            ],
            radius: 0.2,
            feather: 0.2,
            flow: 1
          )
        ),
        blend: 1.01
      )
    )
  }

  func testRetouchPayloadRejectsFutureSchema() throws {
    let data = Data(
      "{\"schemaVersion\":2,\"sourceAnchor\":{\"x\":0.2,\"y\":0.2},\"targetAnchor\":{\"x\":0.8,\"y\":0.8},\"brush\":{\"schemaVersion\":1,\"samples\":[],\"radius\":0.2,\"feather\":0,\"flow\":1}}"
        .utf8
    )

    XCTAssertThrowsError(try JSONDecoder().decode(CloneAdjustmentV1.self, from: data))
  }
}
