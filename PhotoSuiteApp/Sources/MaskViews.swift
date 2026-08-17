// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoWorkflow
import SwiftUI

/// Compatibility entry point for callers that still use the original mask
/// controls name. The Develop inspector now uses the full authoring surface.
@MainActor
struct MaskControls: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    MaskAuthoringInspector(workspace: workspace)
  }
}
