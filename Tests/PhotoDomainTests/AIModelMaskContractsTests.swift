// SPDX-License-Identifier: MPL-2.0

import PhotoDomain
import XCTest

final class AIModelMaskContractsTests: XCTestCase {
  func testVisionBackedModelKindsUseDurableSubjectRecipeKind() {
    XCTAssertEqual(AIModelKind.subject.visionMaskKind, .subject)
    XCTAssertEqual(AIModelKind.people.visionMaskKind, .subject)
    XCTAssertNil(AIModelKind.sky.visionMaskKind)
    XCTAssertNil(AIModelKind.background.visionMaskKind)
    XCTAssertNil(AIModelKind.object.visionMaskKind)
    XCTAssertNil(AIModelKind.depth.visionMaskKind)
  }
}
