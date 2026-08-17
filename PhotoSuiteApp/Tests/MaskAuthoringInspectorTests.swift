// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI
import Testing

@testable import PhotoSuite

struct MaskAuthoringInspectorTests {
  @Test
  func authoringCatalogListsManualToolsAndExplicitlyUnavailableSemanticTools() {
    #expect(
      MaskAuthoringTool.manualTools.map(\.kind) == [
        .brush,
        .linearGradient,
        .radialGradient,
        .colorRange,
        .luminanceRange,
        .depthRange,
      ])
    #expect(MaskAuthoringTool.subject.availability == .unavailable)
    #expect(MaskAuthoringTool.sky.availability == .unavailable)
    #expect(MaskAuthoringTool.background.availability == .unavailable)
    #expect(MaskAuthoringTool.object.availability == .unavailable)
    #expect(MaskAuthoringTool.depthRange.availability == .unavailable)
  }

  @Test
  func unavailableToolsCannotCreateDurableGraphs() {
    let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    #expect(
      MaskAuthoringModel.makeMask(
        kind: .depthRange,
        operation: .add,
        id: id
      ) == nil
    )
    #expect(
      MaskAuthoringModel.makeMask(
        kind: .subject,
        operation: .add,
        id: id
      ) == nil
    )
  }

  @Test
  func newMaskUsesVersionedGraphAndSelectedCombinationOperation() throws {
    let mask = try #require(
      MaskAuthoringModel.makeMask(
        kind: .radialGradient,
        operation: .subtract,
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
      )
    )

    #expect(mask.kind == .radialGradient)
    let graph = try #require(try mask.decodeGraphPayload().versionOne)
    #expect(graph.schemaVersion == 1)
    #expect(graph.components.count == 1)
    #expect(graph.components[0].operation == .subtract)
    if case .radialGradient(let radial) = graph.components[0].primitive {
      #expect(radial.center.x == 0.5)
      #expect(radial.center.y == 0.5)
    } else {
      Issue.record("The default radial mask must use a radial primitive.")
    }
  }

  @Test
  func compositionPreservesExistingComponentsAndCanInvert() throws {
    let id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let mask = try #require(MaskAuthoringModel.makeMask(kind: .brush, operation: .add, id: id))
    let composed = try #require(
      MaskAuthoringModel.append(
        to: mask,
        kind: .luminanceRange,
        operation: .intersect,
        componentID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
      )
    )
    let graph = try #require(try composed.decodeGraphPayload().versionOne)
    #expect(graph.components.count == 2)
    #expect(graph.components.map(\.operation) == [.add, .intersect])

    let inverted = try #require(MaskAuthoringModel.inverted(composed))
    #expect(inverted.isInverted)
    #expect(try inverted.decodeGraphPayload().versionOne?.isInverted == true)
  }

  @MainActor
  @Test
  func inspectorAndGlassFallbackContractsCompile() {
    _ = MaskAuthoringInspector.self
    _ = MaskCapabilityNotice(tool: .sky)
    _ = Text("Fallback")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

    if #available(macOS 26.0, *) {
      _ = Text("Glass")
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
      _ = GlassEffectContainer(spacing: 6) {
        Button("Add") {}
          .buttonStyle(.glass)
      }
    }
  }

  @Test
  func maskAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.maskAuthoringInspector == "mask-authoring-inspector")
    #expect(ModernUIAccessibility.maskAuthoringToolPicker == "mask-authoring-tool-picker")
    #expect(ModernUIAccessibility.maskAuthoringOperationPicker == "mask-authoring-operation-picker")
    #expect(ModernUIAccessibility.maskAuthoringUnavailable == "mask-authoring-unavailable")
  }
}

extension MaskGraphPayload {
  fileprivate var versionOne: MaskGraphV1? {
    guard case .version1(let graph) = self else { return nil }
    return graph
  }
}
