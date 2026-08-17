// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain

public enum MaskResultGate {
  public static func accepts(
    _ result: MaskOperationResult,
    for currentIdentity: MaskRequestIdentity
  ) -> Bool {
    result.requestIdentity == currentIdentity
  }
}
