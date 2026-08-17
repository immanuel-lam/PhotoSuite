// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

final class DurableModelTests: XCTestCase {
  func testDurableDerivativePreservesIdentityAndUnknownKind() throws {
    let derivativeID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
    let derivative = DurableDerivative(
      id: derivativeID,
      schemaVersion: 1,
      assetID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
      recipeRevision: 4,
      kind: .unknown("future-proof-copy"),
      outputURL: URL(fileURLWithPath: "/Exports/result.dat"),
      typeIdentifier: "public.data",
      fingerprint: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let data = try JSONEncoder().encode(derivative)
    let decoded = try JSONDecoder().decode(DurableDerivative.self, from: data)

    XCTAssertEqual(decoded, derivative)
    XCTAssertEqual(decoded.id, derivativeID)
    XCTAssertEqual(decoded.kind, .unknown("future-proof-copy"))
  }

  func testCatalogJobPreservesIdentityAndVersionableEnumValues() throws {
    let jobID = UUID(uuidString: "87654321-4321-4321-4321-CBA987654321")!
    let job = CatalogJob(
      id: jobID,
      schemaVersion: 1,
      kind: .unknown("future-job"),
      state: .unknown("waiting-for-device"),
      assetIDs: [UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!],
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
      payload: Data([0xCA, 0xFE])
    )

    let data = try JSONEncoder().encode(job)
    let decoded = try JSONDecoder().decode(CatalogJob.self, from: data)

    XCTAssertEqual(decoded, job)
    XCTAssertEqual(decoded.id, jobID)
    XCTAssertEqual(decoded.kind, .unknown("future-job"))
    XCTAssertEqual(decoded.state, .unknown("waiting-for-device"))
  }
}
