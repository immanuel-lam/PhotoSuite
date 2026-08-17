// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class MaskGraphTests: XCTestCase {
  func testVersionOneMaskPrimitivesValidateTheirNormalizedInputs() throws {
    let origin = try XCTUnwrap(MaskPointV1(x: 0.1, y: 0.2))
    let end = try XCTUnwrap(MaskPointV1(x: 0.9, y: 0.8))
    let sample = try XCTUnwrap(MaskBrushSampleV1(point: origin, pressure: 0.7))
    let color = try XCTUnwrap(MaskColorSampleV1(red: 0.2, green: 0.4, blue: 0.8))

    XCTAssertNotNil(
      BrushMaskV1(samples: [sample], radius: 0.1, feather: 0.5, flow: 0.8)
    )
    XCTAssertNotNil(LinearGradientMaskV1(start: origin, end: end, feather: 0.4))
    XCTAssertNotNil(
      RadialGradientMaskV1(
        center: origin,
        radiusX: 0.3,
        radiusY: 0.2,
        rotationDegrees: -30,
        feather: 0.6
      )
    )
    XCTAssertNotNil(ColorRangeMaskV1(samples: [color], tolerance: 0.25, feather: 0.5))
    XCTAssertNotNil(LuminanceRangeMaskV1(lowerBound: 0.2, upperBound: 0.8, feather: 0.3))
    XCTAssertNotNil(DepthRangeMaskV1(nearBound: 0.1, farBound: 0.7, feather: 0.2))

    XCTAssertNil(MaskPointV1(x: -.infinity, y: 0))
    XCTAssertNil(MaskBrushSampleV1(point: origin, pressure: 1.01))
    XCTAssertNil(BrushMaskV1(samples: [], radius: 0.1, feather: 0.5, flow: 0.8))
    XCTAssertNil(LinearGradientMaskV1(start: origin, end: origin, feather: 0.4))
    XCTAssertNil(
      RadialGradientMaskV1(
        center: origin,
        radiusX: 0,
        radiusY: 0.2,
        rotationDegrees: 0,
        feather: 0.5
      )
    )
    XCTAssertNil(ColorRangeMaskV1(samples: [], tolerance: 0.25, feather: 0.5))
    XCTAssertNil(LuminanceRangeMaskV1(lowerBound: 0.8, upperBound: 0.2, feather: 0.3))
    XCTAssertNil(DepthRangeMaskV1(nearBound: 0.8, farBound: 0.2, feather: 0.2))
  }

  func testMaskGraphAppliesCompositionInStoredOrderAndTogglesInvert() throws {
    let brush = MaskPrimitiveV1.brush(
      try XCTUnwrap(
        BrushMaskV1(
          samples: [
            try XCTUnwrap(
              MaskBrushSampleV1(
                point: try XCTUnwrap(MaskPointV1(x: 0.2, y: 0.3)),
                pressure: 1
              )
            )
          ],
          radius: 0.1,
          feather: 0.5,
          flow: 1
        )
      )
    )
    let luminance = MaskPrimitiveV1.luminanceRange(
      try XCTUnwrap(
        LuminanceRangeMaskV1(lowerBound: 0.25, upperBound: 0.75, feather: 0.2)
      )
    )
    let depth = MaskPrimitiveV1.depthRange(
      try XCTUnwrap(DepthRangeMaskV1(nearBound: 0.1, farBound: 0.6, feather: 0.1))
    )
    let addID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    let subtractID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
    let intersectID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!

    let graph = MaskGraphV1()
      .applying(.add(id: addID, primitive: brush))
      .applying(.subtract(id: subtractID, primitive: luminance))
      .applying(.intersect(id: intersectID, primitive: depth))
      .applying(.invert)

    XCTAssertEqual(graph.components.map(\.id), [addID, subtractID, intersectID])
    XCTAssertEqual(graph.components.map(\.operation), [.add, .subtract, .intersect])
    XCTAssertTrue(graph.isInverted)
  }

  func testTypedGraphUsesStableVersionedJSONAndBridgesExistingMaskDefinition() throws {
    let start = try XCTUnwrap(MaskPointV1(x: 0.1, y: 0.2))
    let end = try XCTUnwrap(MaskPointV1(x: 0.8, y: 0.9))
    let linear = MaskPrimitiveV1.linearGradient(
      try XCTUnwrap(LinearGradientMaskV1(start: start, end: end, feather: 0.4))
    )
    let graph = MaskGraphV1().applying(
      .add(
        id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
        primitive: linear
      )
    )
    let definition = try MaskDefinition(
      id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
      kind: .linearGradient,
      name: "Horizon",
      graph: graph
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let graphData = try encoder.encode(graph)
    let decodedDefinitionGraph = try definition.decodeGraphPayload()

    XCTAssertEqual(
      String(decoding: graphData, as: UTF8.self),
      #"{"components":[{"id":"BBBBBBBB-0000-0000-0000-000000000001","operation":"add","primitive":{"kind":"linearGradient","value":{"end":{"x":0.8,"y":0.9},"feather":0.4,"start":{"x":0.1,"y":0.2}}}}],"isInverted":false,"schemaVersion":1}"#
    )
    XCTAssertEqual(decodedDefinitionGraph, .version1(graph))
    XCTAssertEqual(definition.schemaVersion, 1)
    XCTAssertEqual(definition.isInverted, graph.isInverted)
  }

  func testFutureGraphAndPrimitivePayloadsPreserveUnknownData() throws {
    let futureGraphData = Data(
      #"{"schemaVersion":2,"algorithm":"semantic-depth","threshold":9007199254740993}"#.utf8
    )
    let graphPayload = try JSONDecoder().decode(MaskGraphPayload.self, from: futureGraphData)
    let futurePrimitiveData = Data(
      #"{"kind":"futureRange","value":{"schemaVersion":3,"weight":9007199254740993}}"#.utf8
    )
    let primitive = try JSONDecoder().decode(MaskPrimitiveV1.self, from: futurePrimitiveData)

    let encodedGraph = try JSONEncoder().encode(graphPayload)
    let encodedPrimitive = try JSONEncoder().encode(primitive)

    XCTAssertEqual(
      try JSONDecoder().decode(MaskGraphPayload.self, from: encodedGraph),
      graphPayload
    )
    XCTAssertEqual(
      try JSONDecoder().decode(MaskPrimitiveV1.self, from: encodedPrimitive),
      primitive
    )
  }
}
