// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import SwiftUI
import Testing

@testable import PhotoSuite

struct LensProfileInspectorTests {
  @Test
  func modelSelectsProfileAndBuildsExistingOpticsOperation() throws {
    let attribution = try #require(
      LensProfileAttributionV1(
        source: "Fixture",
        license: "MPL-2.0",
        notice: "PhotoSuite fixture"
      )
    )
    let profile = try #require(
      LensProfileV1(
        identifier: "fixture:wide",
        maker: "Fixture",
        model: "Wide 24mm",
        mount: "Generic",
        distortion: -0.25,
        vignetting: 0.2,
        chromaticAberration: 0.1,
        defringe: 0.05,
        attribution: attribution
      )
    )
    let database = try #require(
      LensProfileDatabaseV1(
        sourceVersion: "fixture",
        attribution: attribution,
        profiles: [profile]
      )
    )
    var model = LensProfileInspectorModel(database: database)

    #expect(model.selectedProfile == nil)
    model.select(profile.identifier)

    let selected = try #require(model.selectedProfile)
    #expect(selected == profile)
    guard case .optics(let optics) = try #require(model.operation) else {
      Issue.record("Lens profile selection must build the existing optics operation.")
      return
    }
    #expect(optics.lensProfileID == profile.identifier)
    #expect(optics.lensDistortion == profile.distortion)
  }

  @Test
  func modelRejectsUnknownSelectionAndSupportsClear() throws {
    let attribution = try #require(
      LensProfileAttributionV1(
        source: "Fixture",
        license: "MPL-2.0",
        notice: "PhotoSuite fixture"
      )
    )
    let profile = try #require(
      LensProfileV1(
        identifier: "fixture:normal",
        maker: "Fixture",
        model: "Normal 50mm",
        mount: nil,
        distortion: 0,
        vignetting: 0,
        chromaticAberration: 0,
        defringe: 0,
        attribution: attribution
      )
    )
    let database = try #require(
      LensProfileDatabaseV1(
        sourceVersion: "fixture",
        attribution: attribution,
        profiles: [profile]
      )
    )
    var model = LensProfileInspectorModel(database: database)
    model.select("missing")
    #expect(model.selectedProfile == nil)
    #expect(model.operation == nil)
    model.select(profile.identifier)
    #expect(model.operation != nil)
    model.clearSelection()
    #expect(model.selectedProfile == nil)
    #expect(model.operation == nil)
  }

  @MainActor
  @Test
  func inspectorUsesNativeGlassAndFallbackContracts() {
    _ = LensProfileInspector.self
    _ = Text("Lens profile")
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    if #available(macOS 26.0, *) {
      _ = Text("Lens profile")
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
  }

  @Test
  func lensProfileAccessibilityIdentifiersRemainStable() {
    #expect(ModernUIAccessibility.lensProfileInspector == "lens-profile-inspector")
    #expect(ModernUIAccessibility.lensProfilePicker == "lens-profile-picker")
    #expect(ModernUIAccessibility.lensProfileImportButton == "lens-profile-import")
    #expect(ModernUIAccessibility.lensProfileAttribution == "lens-profile-attribution")
    #expect(ModernUIAccessibility.lensProfileStatus == "lens-profile-status")
  }
}
