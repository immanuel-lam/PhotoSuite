// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class DevelopPresetTests: XCTestCase {
  func testDevelopPresetNormalizesNameAndPreservesOrderedUnknownOperations() throws {
    let virtualCopyID = UUID()
    let unknown = EditOperation.unknown(
      "vendor.futureDevelop",
      payload: [
        "enabled": .bool(true),
        "strength": .number(Decimal(string: "0.75")!),
      ]
    )
    let operations: [EditOperation] = [unknown, .exposureEV(1.25), .threeWayColorGrade(.neutral)]

    let preset = try XCTUnwrap(
      DevelopPreset(
        name: "  Cinematic   Warm  ",
        operations: operations,
        virtualCopyID: virtualCopyID,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 11)
      )
    )

    XCTAssertEqual(preset.name, "Cinematic Warm")
    XCTAssertEqual(preset.schemaVersion, DevelopPreset.currentSchemaVersion)
    XCTAssertEqual(preset.operations, operations)
    XCTAssertEqual(preset.virtualCopyID, virtualCopyID)

    let data = try JSONEncoder().encode(preset)
    let decoded = try JSONDecoder().decode(DevelopPreset.self, from: data)
    XCTAssertEqual(decoded, preset)
  }

  func testDevelopPresetRejectsInvalidNameSchemaAndOperationCount() {
    XCTAssertNil(DevelopPreset(name: "   ", operations: []))
    XCTAssertNil(DevelopPreset(name: "Preset", schemaVersion: 0, operations: []))
    XCTAssertNil(
      DevelopPreset(
        name: "Preset",
        operations: Array(repeating: .exposureEV(1), count: DevelopPreset.maximumOperationCount + 1)
      )
    )
  }
}
