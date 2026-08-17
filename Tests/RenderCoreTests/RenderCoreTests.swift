// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest

@testable import RenderCore

final class RenderCoreTests: XCTestCase {
  func testRenderErrorsProvideUsefulLocalizedDescriptions() {
    let emptyPin = RenderCoreError.unsupportedDecoderVersion("")
    let renderFailed = RenderCoreError.renderFailed
    let localizedEmptyPin: any LocalizedError = emptyPin
    let localizedRenderFailure: any LocalizedError = renderFailed

    XCTAssertEqual(
      localizedEmptyPin.errorDescription,
      "The pinned RAW decoder version is empty and is not supported."
    )
    XCTAssertEqual(
      localizedRenderFailure.errorDescription,
      "The image could not be rendered."
    )
  }
}
