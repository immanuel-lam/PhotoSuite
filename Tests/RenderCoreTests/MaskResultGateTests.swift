// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import RenderCore

final class MaskResultGateTests: XCTestCase {
  func testResultIsCurrentOnlyWhenAssetMaskRevisionAndRequestIdentitiesMatch() {
    let assetID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!
    let maskID = UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!
    let requestID = UUID(uuidString: "CCCCCCCC-3333-3333-3333-333333333333")!
    let current = MaskRequestIdentity(
      revision: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 9),
      requestID: requestID
    )

    XCTAssertTrue(MaskResultGate.accepts(result(for: current), for: current))
    XCTAssertFalse(
      MaskResultGate.accepts(
        result(
          for: MaskRequestIdentity(
            revision: current.revision,
            requestID: UUID(uuidString: "CCCCCCCC-3333-3333-3333-333333333334")!
          )
        ),
        for: current
      )
    )
    XCTAssertFalse(
      MaskResultGate.accepts(
        result(
          for: MaskRequestIdentity(
            revision: MaskRevisionIdentity(assetID: assetID, maskID: maskID, revision: 8),
            requestID: requestID
          )
        ),
        for: current
      )
    )
    XCTAssertFalse(
      MaskResultGate.accepts(
        result(
          for: MaskRequestIdentity(
            revision: MaskRevisionIdentity(assetID: assetID, maskID: UUID(), revision: 9),
            requestID: requestID
          )
        ),
        for: current
      )
    )
    XCTAssertFalse(
      MaskResultGate.accepts(
        result(
          for: MaskRequestIdentity(
            revision: MaskRevisionIdentity(assetID: UUID(), maskID: maskID, revision: 9),
            requestID: requestID
          )
        ),
        for: current
      )
    )
  }

  private func result(for identity: MaskRequestIdentity) -> MaskOperationResult {
    MaskOperationResult(requestIdentity: identity, records: [])
  }
}
