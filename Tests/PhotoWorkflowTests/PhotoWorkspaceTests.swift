// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

@MainActor
final class PhotoWorkspaceTests: XCTestCase {
  func testLiveSourceValidationChecksExistenceInsideBalancedSecurityScope() throws {
    let url = URL(fileURLWithPath: "/outside-container/photo.png")
    var isActive = false
    var stopCount = 0

    let validated = try PhotoWorkspaceComposition.validatedSourceURL(
      url,
      start: { candidate in
        XCTAssertEqual(candidate, url)
        isActive = true
        return true
      },
      stop: { candidate in
        XCTAssertEqual(candidate, url)
        isActive = false
        stopCount += 1
      },
      fileExists: { candidate in
        XCTAssertEqual(candidate, url)
        XCTAssertTrue(isActive)
        return true
      }
    )

    XCTAssertEqual(validated, url)
    XCTAssertFalse(isActive)
    XCTAssertEqual(stopCount, 1)
  }

  func testLiveSourceValidationStopsSecurityScopeWhenSourceIsMissing() {
    let url = URL(fileURLWithPath: "/outside-container/missing.png")
    var isActive = false
    var stopCount = 0

    XCTAssertThrowsError(
      try PhotoWorkspaceComposition.validatedSourceURL(
        url,
        start: { _ in
          isActive = true
          return true
        },
        stop: { _ in
          isActive = false
          stopCount += 1
        },
        fileExists: { _ in
          XCTAssertTrue(isActive)
          return false
        }
      )
    ) { error in
      XCTAssertEqual(error as? PhotoWorkspaceError, .sourceMissing(url))
    }
    XCTAssertFalse(isActive)
    XCTAssertEqual(stopCount, 1)
  }

  func testReopenSelectsFirstAvailableAssetAndRestoresItsLatestRecipe() async throws {
    let missing = makeAsset(name: "A-missing.raw", date: Date(timeIntervalSince1970: 20))
    let available = makeAsset(
      name: "B-available.jpg",
      date: Date(timeIntervalSince1970: 10),
      isMissing: true
    )
    let restored = makeRecipe(assetID: available.id, revision: 4, operations: [.exposureEV(0.75)])
    let catalog = CatalogSpy(assets: [missing, available], recipes: [available.id: restored])
    let access = SourceAccessSpy(missingAssetIDs: [missing.id])
    let renderer = ImmediateRenderer()
    let workspace = makeWorkspace(catalog: catalog, renderer: renderer, access: access)

    await workspace.reopen()

    XCTAssertEqual(workspace.assets.map(\.id), [missing.id, available.id])
    XCTAssertEqual(workspace.selectedAssetID, available.id)
    XCTAssertEqual(workspace.currentRecipe, restored)
    XCTAssertEqual(workspace.preview?.imageData, Data("preview-4".utf8))
    XCTAssertEqual(workspace.preview?.histogram?.red.reduce(0, +), 1)
    let missingUpdates = await catalog.missingUpdates()
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertEqual(missingUpdates, [missing.id: true, available.id: false])
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testReopenRepairsEmptyRAWPinWithMonotonicRecipeInsideSourceAccess() async throws {
    let asset = makeAsset(name: "legacy.png")
    let mask = MaskDefinition(
      schemaVersion: 1,
      kind: .subject,
      name: "Subject",
      isInverted: false,
      payload: Data([1, 2, 3])
    )
    let legacy = EditRecipe(
      assetID: asset.id,
      revision: 7,
      date: Date(timeIntervalSince1970: 7),
      pins: EnginePins(
        decoderIdentifier: "com.apple.ciraw",
        decoderVersion: "",
        renderSchemaVersion: 1,
        cameraProfileVersion: "legacy-profile",
        modelVersions: ["subject": "1"]
      ),
      operations: [.exposureEV(0.75), .rotationDegrees(90)],
      masks: [mask]
    )
    let correctedPins = EnginePins(
      decoderIdentifier: "com.apple.coreimage.common-image",
      decoderVersion: "system-default",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: legacy])
    let access = SourceAccessSpy()
    let phases = AccessPhaseRecorder()
    let renderer = RecipeRecordingRenderer(access: access)
    let workspace = PhotoWorkspace(
      catalog: catalog,
      renderer: renderer,
      exporter: ExporterSpy(),
      sourceAccess: access.operations,
      fingerprint: { _ in
        XCTFail("Pin recovery must not fingerprint or change the source.")
        throw TestError.unused
      },
      probe: { url in
        await phases.record("probe", active: access.isActive)
        XCTAssertEqual(url, asset.sourceURL)
        return SourceProbe(
          dimensions: asset.pixelDimensions!,
          pins: correctedPins,
          typeIdentifier: asset.typeIdentifier
        )
      },
      now: { Date(timeIntervalSince1970: 100) },
      previewDebounce: {}
    )

    await workspace.reopen()

    let recovered = try XCTUnwrap(workspace.currentRecipe)
    let savedRecipes = await catalog.savedRecipes()
    let saved = try XCTUnwrap(savedRecipes.last)
    let renderedRecipe = await renderer.lastRecipe()
    let rendered = try XCTUnwrap(renderedRecipe)
    let phaseValues = await phases.values()
    let renderAccess = await renderer.wasAccessActive()
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertEqual(recovered, saved)
    XCTAssertEqual(recovered, rendered)
    XCTAssertEqual(recovered.revision, 8)
    XCTAssertEqual(recovered.date, Date(timeIntervalSince1970: 100))
    XCTAssertEqual(recovered.pins, correctedPins)
    XCTAssertEqual(recovered.operations, legacy.operations)
    XCTAssertEqual(recovered.masks, legacy.masks)
    XCTAssertEqual(phaseValues, ["probe": true])
    XCTAssertTrue(renderAccess)
    XCTAssertEqual(activeAccessCount, 0)
    XCTAssertNil(workspace.errorMessage)
  }

  func testImportRetainsSuccessfulFilesWhenOneFingerprintFails() async throws {
    let firstURL = URL(fileURLWithPath: "/tmp/first.jpg")
    let failedURL = URL(fileURLWithPath: "/tmp/broken.raw")
    let thirdURL = URL(fileURLWithPath: "/tmp/third.png")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy()
    let renderer = ImmediateRenderer()
    let fingerprintRecorder = FingerprintRecorder(failingURL: failedURL)
    let workspace = makeWorkspace(
      catalog: catalog,
      renderer: renderer,
      access: access,
      fingerprint: { try await fingerprintRecorder.fingerprint($0) }
    )

    await workspace.importURLs([firstURL, failedURL, thirdURL])

    XCTAssertEqual(workspace.assets.map(\.sourceURL), [firstURL, thirdURL])
    XCTAssertEqual(workspace.selectedAssetID, workspace.assets.first?.id)
    XCTAssertEqual(workspace.itemErrors.map(\.sourceURL), [failedURL])
    let savedRevisions = await catalog.savedRecipes().map(\.revision)
    let persistedURLs = await access.persistedURLs()
    let activeAccessCount = await access.activeAccessCount()
    let fingerprintURLs = await fingerprintRecorder.urls()
    XCTAssertEqual(savedRevisions, [0, 0])
    XCTAssertEqual(persistedURLs, [firstURL, thirdURL])
    XCTAssertEqual(activeAccessCount, 0)
    XCTAssertEqual(fingerprintURLs, [firstURL, failedURL, thirdURL])
  }

  func testAcceptedEditsCreateOrderedMonotonicRecipesAndSupportUndoRedoReset() async throws {
    let asset = makeAsset(name: "edit.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.commitAdjustment(.saturation, value: 0.2)
    await workspace.commitAdjustment(.exposure, value: 1.25)
    await workspace.commitAdjustment(.contrast, value: -0.1)
    await workspace.rotateClockwise()

    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1.25), .contrast(-0.1), .saturation(0.2), .rotationDegrees(90)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 4)

    await workspace.undo()
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1.25), .contrast(-0.1), .saturation(0.2)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 5)

    await workspace.redo()
    XCTAssertEqual(workspace.currentRecipe?.operations.last, .rotationDegrees(90))
    XCTAssertEqual(workspace.currentRecipe?.revision, 6)

    await workspace.resetEdits()
    XCTAssertEqual(workspace.currentRecipe?.operations, [])
    XCTAssertEqual(workspace.currentRecipe?.revision, 7)
    let revisions = await catalog.savedRecipes().map(\.revision)
    XCTAssertEqual(revisions, [1, 2, 3, 4, 5, 6, 7])
  }

  func testCommittingColorGradeCreatesOneOrderedRecipeRevision() async throws {
    let asset = makeAsset(name: "grade.jpg")
    let initial = makeRecipe(
      assetID: asset.id,
      operations: [.exposureEV(0.5), .rotationDegrees(90)]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    let grade = try makeColorGrade()
    await workspace.reopen()

    await workspace.commitColorGrade(grade)

    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(0.5), .threeWayColorGrade(grade), .rotationDegrees(90)]
    )
    let savedRevisions = await catalog.savedRecipes().map(\.revision)
    XCTAssertEqual(savedRevisions, [1])
  }

  func testCommittingCropReplacesTheCropCanonicallyAndRefreshesPreview() async throws {
    let asset = makeAsset(name: "crop.jpg")
    let oldCrop = try XCTUnwrap(NormalizedRect(x: 0.05, y: 0.1, width: 0.8, height: 0.75))
    let newCrop = try XCTUnwrap(NormalizedRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7))
    let initial = makeRecipe(
      assetID: asset.id,
      operations: [
        .rotationDegrees(90),
        .normalizedCrop(oldCrop),
        .exposureEV(0.5),
      ]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()
    await workspace.commitCrop(newCrop)

    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(0.5), .normalizedCrop(newCrop), .rotationDegrees(90)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(workspace.preview?.imageData, Data("preview-1".utf8))
    let savedRevisions = await catalog.savedRecipes().map(\.revision)
    XCTAssertEqual(savedRevisions, [1])

    await workspace.undo()

    XCTAssertEqual(workspace.currentRecipe?.operations, initial.operations)
    XCTAssertEqual(workspace.currentRecipe?.revision, 2)
    XCTAssertEqual(workspace.preview?.imageData, Data("preview-2".utf8))
  }

  func testResetCropKeepsOtherOperationsAndPersistsThroughReopen() async throws {
    let asset = makeAsset(name: "reset-crop.jpg")
    let crop = try XCTUnwrap(NormalizedRect(x: 0.1, y: 0.1, width: 0.75, height: 0.7))
    let initial = makeRecipe(
      assetID: asset.id,
      revision: 4,
      operations: [.exposureEV(0.25), .normalizedCrop(crop), .rotationDegrees(180)]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()
    await workspace.resetCrop()

    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(0.25), .rotationDegrees(180)]
    )
    XCTAssertEqual(workspace.currentRecipe?.revision, 5)

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()

    XCTAssertEqual(reopened.currentRecipe?.revision, 5)
    XCTAssertEqual(reopened.currentRecipe?.operations, workspace.currentRecipe?.operations)
  }

  func testInvalidNormalizedCropBoundsAreRejectedBeforeCommit() async throws {
    let asset = makeAsset(name: "invalid-crop.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)

    XCTAssertNil(NormalizedRect(x: -0.01, y: 0, width: 0.5, height: 0.5))
    XCTAssertNil(NormalizedRect(x: 0.75, y: 0, width: 0.5, height: 0.5))
    XCTAssertNil(NormalizedRect(x: 0, y: 0.75, width: 0.5, height: 0.5))

    await workspace.reopen()

    XCTAssertEqual(workspace.currentRecipe, initial)
    let savedRecipes = await catalog.savedRecipes()
    XCTAssertTrue(savedRecipes.isEmpty)
  }

  func testCropCommitDoesNotChangeSourceURLOrFingerprint() async throws {
    let asset = makeAsset(name: "immutable-crop.jpg")
    let crop = try XCTUnwrap(NormalizedRect(x: 0.15, y: 0.2, width: 0.65, height: 0.6))
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()
    await workspace.commitCrop(crop)

    let assetSnapshot = await catalog.assetSnapshot()
    let persistedAsset = try XCTUnwrap(assetSnapshot.first)
    XCTAssertEqual(persistedAsset.sourceURL, asset.sourceURL)
    XCTAssertEqual(persistedAsset.fingerprint, asset.fingerprint)
    XCTAssertEqual(workspace.selectedAsset?.sourceURL, asset.sourceURL)
    XCTAssertEqual(workspace.selectedAsset?.fingerprint, asset.fingerprint)
  }

  func testCommittingBaselineDevelopOperationReplacesItsFamilyAndPreservesOtherEdits() async throws
  {
    let asset = makeAsset(name: "baseline.jpg")
    let grade = try makeColorGrade()
    let previousWhiteBalance = try XCTUnwrap(
      WhiteBalanceAdjustmentV1(temperature: -0.2, tint: 0.1)
    )
    let nextWhiteBalance = try XCTUnwrap(
      WhiteBalanceAdjustmentV1(temperature: 0.35, tint: -0.15)
    )
    let initial = makeRecipe(
      assetID: asset.id,
      operations: [
        .threeWayColorGrade(grade),
        .whiteBalance(previousWhiteBalance),
      ]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.commitDevelopOperation(.whiteBalance(nextWhiteBalance))

    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.threeWayColorGrade(grade), .whiteBalance(nextWhiteBalance)]
    )
  }

  func testAllBaselineDevelopFamiliesPersistInCanonicalOrderAcrossReopen() async throws {
    let asset = makeAsset(name: "develop-families.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    let tone = try XCTUnwrap(
      ToneCurveAdjustmentV1(
        blackPoint: 0.05,
        shadows: 0.3,
        midtones: 0.6,
        highlights: 0.8,
        whitePoint: 0.98
      )
    )
    let whiteBalance = try XCTUnwrap(WhiteBalanceAdjustmentV1(temperature: 0.25, tint: -0.1))
    let transform = try XCTUnwrap(
      TransformAdjustmentV1(
        straightenDegrees: 8,
        flipHorizontal: true,
        flipVertical: false
      )
    )
    let detail = try XCTUnwrap(
      DetailAdjustmentV1(sharpening: 0.4, luminanceNoiseReduction: 0.2)
    )
    let optics = try XCTUnwrap(OpticsAdjustmentV1(vignetteCorrection: 0.2))
    let effects = try XCTUnwrap(EffectsAdjustmentV1(vignetteAmount: 0.3))
    let calibration = try XCTUnwrap(
      CalibrationAdjustmentV1(redGain: 0.1, greenGain: -0.05, blueGain: 0.2)
    )
    let blackAndWhite = try XCTUnwrap(
      BlackAndWhiteAdjustmentV1(redWeight: 0.3, greenWeight: 0.6, blueWeight: 0.1)
    )
    let hdr = HDRAdjustmentV1(isEnabled: true, preservesExtendedRange: true)
    let expected: [EditOperation] = [
      .toneCurve(tone),
      .whiteBalance(whiteBalance),
      .transform(transform),
      .detail(detail),
      .optics(optics),
      .effects(effects),
      .calibration(calibration),
      .blackAndWhite(blackAndWhite),
      .hdr(hdr),
    ]
    await workspace.reopen()

    for operation in expected.reversed() {
      await workspace.commitDevelopOperation(operation)
    }

    XCTAssertEqual(workspace.currentRecipe?.revision, 9)
    XCTAssertEqual(workspace.currentRecipe?.operations, expected)
    let savedRevisions = await catalog.savedRecipes().map(\.revision)
    XCTAssertEqual(savedRevisions, Array(1...9))

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()
    XCTAssertEqual(reopened.currentRecipe?.revision, 9)
    XCTAssertEqual(reopened.currentRecipe?.operations, expected)
  }

  func testExtendedOpticsAndEffectsCommitAndPreserveUnknownOperations() async throws {
    let asset = makeAsset(name: "extended-optics-effects.jpg")
    let future = EditOperation.unknown(
      "futureLensProfile",
      payload: ["algorithm": .string("v2"), "amount": .number(0.4)]
    )
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    let optics = try XCTUnwrap(
      OpticsAdjustmentV1(
        vignetteCorrection: 0.15,
        lensDistortion: -0.45,
        chromaticAberration: 0.35,
        defringe: 0.2
      )
    )
    let effects = try XCTUnwrap(
      EffectsAdjustmentV1(vignetteAmount: 0.1, grainAmount: 0.3, dehaze: 0.4)
    )

    await workspace.reopen()
    await workspace.commitDevelopOperation(.effects(effects))
    await workspace.commitDevelopOperation(.optics(optics))

    let expected: [EditOperation] = [.optics(optics), .effects(effects)]
    XCTAssertEqual(workspace.currentRecipe?.revision, 2)
    XCTAssertEqual(workspace.currentRecipe?.operations, expected)

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()
    XCTAssertEqual(reopened.currentRecipe?.operations, expected)
    XCTAssertEqual(reopened.currentRecipe?.revision, 2)

    let futureAsset = makeAsset(name: "future-optics-effects.jpg")
    let futureRecipe = makeRecipe(assetID: futureAsset.id, operations: [future])
    let futureCatalog = CatalogSpy(assets: [futureAsset], recipes: [futureAsset.id: futureRecipe])
    let futureWorkspace = makeWorkspace(catalog: futureCatalog)
    await futureWorkspace.reopen()
    await futureWorkspace.commitDevelopOperation(.optics(optics))
    XCTAssertEqual(futureWorkspace.currentRecipe?.operations, [future])
    XCTAssertEqual(futureWorkspace.currentRecipe?.revision, futureRecipe.revision)
    XCTAssertEqual(futureWorkspace.lastError, .unknownOperationsBlockEditing)
  }

  func testZeroValuedLensProfileIsDurableInsteadOfNeutral() async throws {
    let asset = makeAsset(name: "zero-lens-profile.jpg")
    let catalog = CatalogSpy(
      assets: [asset],
      recipes: [asset.id: makeRecipe(assetID: asset.id)]
    )
    let workspace = makeWorkspace(catalog: catalog)
    let profile = try XCTUnwrap(
      LensProfileV1(
        identifier: "fixture:neutral",
        maker: "Fixture",
        model: "Neutral",
        mount: nil,
        distortion: 0,
        vignetting: 0,
        chromaticAberration: 0,
        defringe: 0,
        attribution: .photosuite
      )
    )
    let optics = try XCTUnwrap(profile.opticsAdjustment())

    await workspace.reopen()
    await workspace.commitDevelopOperation(.optics(optics))

    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(workspace.currentRecipe?.operations, [.optics(optics)])

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()
    XCTAssertEqual(reopened.currentRecipe?.revision, 1)
    XCTAssertEqual(reopened.currentRecipe?.operations, [.optics(optics)])
  }

  func testRetouchDevelopOperationsCommitInCanonicalOrderAndSurviveReopen() async throws {
    let asset = makeAsset(name: "retouch-families.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    let source = try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.35))
    let target = try XCTUnwrap(RetouchPointV1(x: 0.72, y: 0.65))
    let sample = try XCTUnwrap(RetouchBrushSampleV1(point: target, pressure: 1))
    let brush = try XCTUnwrap(
      RetouchBrushV1(samples: [sample], radius: 0.16, feather: 0.3, flow: 0.9)
    )
    let clone = try XCTUnwrap(
      CloneAdjustmentV1(sourceAnchor: source, targetAnchor: target, brush: brush)
    )
    let healing = try XCTUnwrap(
      HealingAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush,
        blend: 1
      )
    )
    let redEye = try XCTUnwrap(
      RedEyeAdjustmentV1(center: target, radius: 0.12, feather: 0.4)
    )
    let expected: [EditOperation] = [.clone(clone), .healing(healing), .redEye(redEye)]

    await workspace.reopen()
    for operation in expected.reversed() {
      await workspace.commitDevelopOperation(operation)
    }

    XCTAssertEqual(workspace.currentRecipe?.revision, 3)
    XCTAssertEqual(workspace.currentRecipe?.operations, expected)
    XCTAssertEqual(workspace.currentDevelopOperations, expected)

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()
    XCTAssertEqual(reopened.currentRecipe?.revision, 3)
    XCTAssertEqual(reopened.currentRecipe?.operations, expected)
    XCTAssertEqual(reopened.currentDevelopOperations, expected)
  }

  func testClearingRetouchDevelopFamilyRemovesOnlySelectedOperationAndPersists() async throws {
    let asset = makeAsset(name: "retouch-clear.jpg")
    let source = try XCTUnwrap(RetouchPointV1(x: 0.1, y: 0.2))
    let target = try XCTUnwrap(RetouchPointV1(x: 0.8, y: 0.7))
    let sample = try XCTUnwrap(RetouchBrushSampleV1(point: target, pressure: 1))
    let brush = try XCTUnwrap(
      RetouchBrushV1(samples: [sample], radius: 0.14, feather: 0.2, flow: 0.85)
    )
    let clone = try XCTUnwrap(
      CloneAdjustmentV1(sourceAnchor: source, targetAnchor: target, brush: brush)
    )
    let healing = try XCTUnwrap(
      HealingAdjustmentV1(
        sourceAnchor: source,
        targetAnchor: target,
        brush: brush,
        blend: 1
      )
    )
    let redEye = try XCTUnwrap(
      RedEyeAdjustmentV1(center: target, radius: 0.1, feather: 0.25)
    )
    let initial = makeRecipe(
      assetID: asset.id,
      operations: [
        .exposureEV(0.5),
        .clone(clone),
        .healing(healing),
        .redEye(redEye),
      ]
    )
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.clearDevelopOperation(.healing)
    let afterHealing: [EditOperation] = [.exposureEV(0.5), .clone(clone), .redEye(redEye)]
    XCTAssertEqual(workspace.currentRecipe?.operations, afterHealing)
    XCTAssertEqual(workspace.currentRecipe?.revision, 1)

    let reopened = makeWorkspace(catalog: catalog)
    await reopened.reopen()
    XCTAssertEqual(reopened.currentRecipe?.operations, afterHealing)

    await reopened.clearDevelopOperation(.clone)
    XCTAssertEqual(
      reopened.currentRecipe?.operations,
      [.exposureEV(0.5), .redEye(redEye)] as [EditOperation]
    )
    XCTAssertEqual(reopened.currentRecipe?.revision, 2)

    await reopened.clearDevelopOperation(.redEye)
    XCTAssertEqual(
      reopened.currentRecipe?.operations,
      [.exposureEV(0.5)] as [EditOperation]
    )
    XCTAssertEqual(reopened.currentRecipe?.revision, 3)
  }

  func testMaskAuthoringPersistsVersionedGraphAndSupportsInvertAndRemove() async throws {
    let asset = makeAsset(name: "mask.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.addMask(kind: .brush, name: "Brush mask")
    let mask = try XCTUnwrap(workspace.currentMasks.first)
    let point = try XCTUnwrap(MaskPointV1(x: 0.5, y: 0.5))
    let sample = try XCTUnwrap(MaskBrushSampleV1(point: point, pressure: 1))
    let brush = try XCTUnwrap(
      BrushMaskV1(samples: [sample], radius: 0.2, feather: 0.4, flow: 1)
    )
    let graph = MaskGraphV1(
      components: [
        MaskGraphComponentV1(
          id: UUID(),
          operation: .add,
          primitive: .brush(brush)
        )
      ]
    )

    await workspace.replaceMaskGraph(id: mask.id, graph: graph)
    await workspace.toggleMaskInverted(id: mask.id)

    let updated = try XCTUnwrap(workspace.currentMasks.first)
    XCTAssertTrue(updated.isInverted)
    XCTAssertEqual(updated.schemaVersion, 1)
    XCTAssertEqual(try updated.decodeGraphPayload(), .version1(graph))
    XCTAssertEqual(workspace.currentRecipe?.revision, 3)

    await workspace.removeMask(id: mask.id)
    XCTAssertTrue(workspace.currentMasks.isEmpty)
    XCTAssertEqual(workspace.currentRecipe?.revision, 4)
  }

  func testGeneratedMaskRequiresCurrentAssetAndRecipeRevision() async throws {
    let asset = makeAsset(name: "vision.jpg")
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()
    let mask = MaskDefinition(
      schemaVersion: 1,
      kind: .subject,
      name: "Vision Subject",
      isInverted: false,
      payload: Data([1, 2, 3])
    )

    await workspace.applyGeneratedMask(mask, assetID: asset.id, expectedRevision: 0)
    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(workspace.currentMasks, [mask])

    await workspace.applyGeneratedMask(mask, assetID: asset.id, expectedRevision: 0)
    XCTAssertEqual(workspace.currentRecipe?.revision, 1)
    XCTAssertEqual(workspace.lastError, .staleAIResult)
  }

  func testLocalAIPreviewValidationUsesBalancedSourceAccess() async throws {
    let asset = makeAsset(name: "local-ai.jpg")
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let access = SourceAccessSpy()
    let workspace = makeWorkspace(catalog: catalog, access: access)
    await workspace.reopen()

    let prepared = try await workspace.prepareSelectedPreviewForLocalAI()

    XCTAssertEqual(prepared.pixelDimensions, workspace.preview?.pixelDimensions)
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testLocalAIPreviewValidationReportsMissingPreviewAsTypedWorkspaceError() async throws {
    let asset = makeAsset(name: "local-ai-without-preview.jpg")
    let workspace = makeWorkspace()
    workspace.assets = [asset]
    workspace.selectedAssetID = asset.id
    workspace.currentRecipe = makeRecipe(assetID: asset.id)

    do {
      _ = try await workspace.prepareSelectedPreviewForLocalAI()
      XCTFail("A local AI input requires a selected rendered preview.")
    } catch let error as PhotoWorkspaceError {
      XCTAssertEqual(error, .previewUnavailable)
    }
  }

  func testNewPreviewCancelsAndSuppressesStalePreview() async throws {
    let asset = makeAsset(name: "preview.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let renderer = ControllableRenderer()
    let workspace = makeWorkspace(catalog: catalog, renderer: renderer)

    let reopen = Task { await workspace.reopen() }
    await renderer.waitForRequestCount(1)
    await renderer.completeRequest(
      0,
      bytes: Data("initial".utf8),
      histogram: histogram(total: 1)
    )
    await reopen.value

    let first = Task { await workspace.refreshPreview() }
    await renderer.waitForRequestCount(2)
    let second = Task { await workspace.refreshPreview() }
    await renderer.waitForRequestCount(3)
    await renderer.completeRequest(
      2,
      bytes: Data("new".utf8),
      histogram: histogram(total: 3)
    )
    await renderer.completeRequest(
      1,
      bytes: Data("stale".utf8),
      histogram: histogram(total: 2)
    )
    await first.value
    await second.value

    XCTAssertEqual(workspace.preview?.imageData, Data("new".utf8))
    XCTAssertEqual(workspace.preview?.histogram?.red.reduce(0, +), 3)
    XCTAssertNil(workspace.errorMessage)
  }

  func testSelectingAnUncachedAssetClearsPreviousHistogramUntilItsPreviewArrives() async throws {
    let first = makeAsset(name: "first.jpg")
    let second = makeAsset(name: "second.jpg")
    let firstRecipe = makeRecipe(assetID: first.id)
    let secondRecipe = makeRecipe(assetID: second.id)
    let catalog = CatalogSpy(
      assets: [first, second],
      recipes: [first.id: firstRecipe, second.id: secondRecipe]
    )
    let renderer = ControllableRenderer()
    let workspace = makeWorkspace(catalog: catalog, renderer: renderer)

    let reopen = Task { await workspace.reopen() }
    await renderer.waitForRequestCount(1)
    await renderer.completeRequest(
      0,
      bytes: Data("first".utf8),
      histogram: histogram(total: 1)
    )
    await reopen.value
    XCTAssertEqual(workspace.preview?.histogram?.red.reduce(0, +), 1)

    let select = Task { await workspace.selectAsset(second.id) }
    await renderer.waitForRequestCount(2)
    XCTAssertNil(workspace.preview)
    await renderer.completeRequest(
      1,
      bytes: Data("second".utf8),
      histogram: histogram(total: 2)
    )
    await select.value

    XCTAssertEqual(workspace.preview?.histogram?.red.reduce(0, +), 2)
  }

  func testExportUsesSelectedAssetAndLatestDurableRecipe() async throws {
    let asset = makeAsset(name: "export.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let exporter = ExporterSpy()
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter)
    await workspace.reopen()
    await workspace.commitAdjustment(.exposure, value: 0.5)
    let destination = URL(fileURLWithPath: "/tmp/export.jpg")

    await workspace.exportJPEG(to: destination, quality: 0.82)

    let capturedRequest = await exporter.lastRequest()
    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(request.sourceURL, asset.sourceURL)
    XCTAssertEqual(request.recipe.revision, 1)
    XCTAssertEqual(request.recipe.operations, [.exposureEV(0.5)])
    XCTAssertEqual(request.destinationURL, destination)
    XCTAssertEqual(request.format, .jpeg)
    XCTAssertEqual(request.quality, 0.82)
    XCTAssertNotNil(workspace.lastExport)
  }

  func testBatchExportUsesFilteredAssetsLatestRecipesAndBalancesSourceAccess() async throws {
    let first = makeAsset(name: "first.jpg", rating: 4)
    let second = makeAsset(name: "second.jpg", rating: 3)
    let hidden = makeAsset(name: "hidden.jpg", rating: 1)
    let catalog = CatalogSpy(
      assets: [first, second, hidden],
      recipes: [
        first.id: makeRecipe(assetID: first.id, revision: 2),
        second.id: makeRecipe(assetID: second.id, revision: 5),
        hidden.id: makeRecipe(assetID: hidden.id, revision: 8),
      ]
    )
    let access = SourceAccessSpy()
    let exporter = ExporterSpy(access: access)
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter, access: access)
    await workspace.reopen()
    workspace.smartFilter = LibrarySmartFilter(minimumRating: 3)

    let destination = URL(fileURLWithPath: "/tmp/photosuite-batch")
    await workspace.exportBatch(to: destination, quality: 0.82)

    let requests = await exporter.requests()
    XCTAssertEqual(requests.map(\.recipe.assetID), [first.id, second.id])
    XCTAssertEqual(requests.map(\.recipe.revision), [2, 5])
    XCTAssertEqual(
      requests.map { $0.destinationURL.path },
      [
        "/tmp/photosuite-batch/first.jpg",
        "/tmp/photosuite-batch/second.jpg",
      ]
    )
    XCTAssertEqual(requests.map(\.quality), [0.82, 0.82])
    XCTAssertEqual(workspace.lastBatchExports.count, 2)
    XCTAssertNil(workspace.lastError)
    let activeAccessCount = await access.activeAccessCount()
    let accessObservations = await exporter.accessObservations()
    XCTAssertEqual(activeAccessCount, 0)
    XCTAssertEqual(accessObservations, [true, true])
  }

  func testBatchExportKeepsCompletedPrefixWhenLaterExportFails() async throws {
    let first = makeAsset(name: "first.jpg")
    let second = makeAsset(name: "second.jpg")
    let catalog = CatalogSpy(
      assets: [first, second],
      recipes: [
        first.id: makeRecipe(assetID: first.id),
        second.id: makeRecipe(assetID: second.id),
      ]
    )
    let access = SourceAccessSpy()
    let exporter = ExporterSpy(access: access, failingRequestIndex: 1)
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter, access: access)
    await workspace.reopen()

    await workspace.exportBatch(
      to: URL(fileURLWithPath: "/tmp/photosuite-batch-failure"),
      quality: 0.9
    )

    XCTAssertEqual(workspace.lastBatchExports.count, 1)
    XCTAssertEqual(workspace.lastExport, workspace.lastBatchExports.first)
    XCTAssertNotNil(workspace.lastError)
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testBookmarkFailureKeepsImportedAssetAndRevisionZeroRecipeVisibleAndMissing() async throws {
    let url = URL(fileURLWithPath: "/tmp/bookmark-failure.jpg")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy(failingPersistURLs: [url])
    let workspace = makeWorkspace(catalog: catalog, access: access)

    await workspace.importURLs([url])

    XCTAssertEqual(workspace.assets.count, 1)
    XCTAssertEqual(workspace.currentRecipe?.revision, 0)
    XCTAssertEqual(workspace.assets.first?.isMissing, true)
    let savedRecipeCount = await catalog.savedRecipes().count
    XCTAssertEqual(savedRecipeCount, 1)
    XCTAssertEqual(workspace.itemErrors.map(\.sourceURL), [url])
    XCTAssertNotNil(workspace.lastError)
  }

  func testFailedUndoRestoresHistoryAndCanRetry() async throws {
    let asset = makeAsset(name: "undo.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()
    await workspace.commitAdjustment(.exposure, value: 1)
    await catalog.failNextRecipeSave()

    await workspace.undo()

    XCTAssertEqual(workspace.currentRecipe?.operations, [.exposureEV(1)])
    XCTAssertTrue(workspace.canUndo)
    XCTAssertFalse(workspace.canRedo)
    XCTAssertNotNil(workspace.lastError)

    await workspace.undo()
    XCTAssertEqual(workspace.currentRecipe?.operations, [])
    XCTAssertEqual(workspace.currentRecipe?.revision, 2)
  }

  func testNoOpAndUnknownRecipeEditsDoNotCreateRevisions() async throws {
    let asset = makeAsset(name: "future.jpg")
    let unknown = EditOperation.unknown("futureTone", payload: ["amount": .number(1)])
    let initial = makeRecipe(assetID: asset.id, operations: [unknown])
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.commitAdjustment(.exposure, value: 0)

    XCTAssertEqual(workspace.currentRecipe?.operations, [unknown])
    let savedRecipeCount = await catalog.savedRecipes().count
    XCTAssertEqual(savedRecipeCount, 0)
    XCTAssertEqual(workspace.lastError, .unknownOperationsBlockEditing)
  }

  func testConcurrentEditsSerializeUniqueRevisions() async throws {
    let asset = makeAsset(name: "concurrent.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    async let exposure: Void = workspace.commitAdjustment(.exposure, value: 1)
    async let contrast: Void = workspace.commitAdjustment(.contrast, value: 0.2)
    _ = await (exposure, contrast)

    let saves = await catalog.savedRecipes()
    XCTAssertEqual(saves.map(\.revision), [1, 2])
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [.exposureEV(1), .contrast(0.2)]
    )
  }

  func testExportClearsPriorResultAndReportsNoSelectionAsTypedError() async throws {
    let asset = makeAsset(name: "export-failure.jpg")
    let initial = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: initial])
    let exporter = ExporterSpy()
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter)
    await workspace.reopen()
    await workspace.exportJPEG(to: URL(fileURLWithPath: "/tmp/ok.jpg"), quality: 0.9)
    XCTAssertNotNil(workspace.lastExport)
    await exporter.failExports()

    await workspace.exportJPEG(to: URL(fileURLWithPath: "/tmp/fail.jpg"), quality: 0.9)
    XCTAssertNil(workspace.lastExport)
    XCTAssertNotNil(workspace.lastError)

    let empty = makeWorkspace()
    await empty.exportJPEG(to: URL(fileURLWithPath: "/tmp/none.jpg"), quality: 0.9)
    XCTAssertEqual(empty.lastError, .noSelection(operation: "export"))
  }

  func testSourceAccessCoversImportRenderAndExportAndPreservesProbePinsAndFingerprint() async throws
  {
    let url = URL(fileURLWithPath: "/tmp/access.raw")
    let destination = URL(fileURLWithPath: "/tmp/access-export.jpg")
    let catalog = CatalogSpy()
    let access = SourceAccessSpy()
    let phases = AccessPhaseRecorder()
    let renderer = ImmediateRenderer(access: access)
    let exporter = ExporterSpy(access: access)
    let fingerprint = SourceFingerprint(
      sha256: String(repeating: "f", count: 64),
      byteCount: 9_007_199_254_740_993,
      modificationDate: Date(timeIntervalSince1970: 42)
    )!
    let pins = EnginePins(
      decoderIdentifier: "com.apple.ciraw",
      decoderVersion: "exact-system-version",
      renderSchemaVersion: 1,
      cameraProfileVersion: nil,
      modelVersions: [:]
    )
    let workspace = PhotoWorkspace(
      catalog: catalog,
      renderer: renderer,
      exporter: exporter,
      sourceAccess: access.operations,
      fingerprint: { sourceURL in
        await phases.record("fingerprint", active: access.isActive)
        XCTAssertEqual(sourceURL, url)
        return fingerprint
      },
      probe: { sourceURL in
        await phases.record("probe", active: access.isActive)
        XCTAssertEqual(sourceURL, url)
        return SourceProbe(
          dimensions: PixelDimensions(width: 30, height: 20)!,
          pins: pins,
          typeIdentifier: "public.camera-raw-image"
        )
      },
      previewDebounce: {}
    )

    await workspace.importURLs([url])
    await workspace.exportJPEG(to: destination, quality: 0.9)

    let assetSnapshot = await catalog.assetSnapshot()
    let savedRecipes = await catalog.savedRecipes()
    let phaseValues = await phases.values()
    let renderAccess = await renderer.wasAccessActive()
    let exportAccess = await exporter.wasAccessActive()
    let activeAccessCount = await access.activeAccessCount()
    let storedAsset = try XCTUnwrap(assetSnapshot.first)
    let storedRecipe = try XCTUnwrap(savedRecipes.first)
    XCTAssertEqual(storedAsset.fingerprint, fingerprint)
    XCTAssertEqual(storedRecipe.pins, pins)
    XCTAssertEqual(phaseValues, ["fingerprint": true, "probe": true])
    XCTAssertTrue(renderAccess)
    XCTAssertTrue(exportAccess)
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testRatingAndColourLabelPersistAndUpdateTheVisibleAsset() async throws {
    let asset = makeAsset(name: "rated.jpg")
    let recipe = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: recipe])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.setRating(4)
    await workspace.setColorLabel(.green)

    XCTAssertEqual(workspace.selectedAsset?.rating, 4)
    XCTAssertEqual(workspace.selectedAsset?.colorLabel, .green)
    let storedAssets = await catalog.assetSnapshot()
    let stored = try XCTUnwrap(storedAssets.first)
    XCTAssertEqual(stored.rating, 4)
    XCTAssertEqual(stored.colorLabel, .green)
  }

  func testMetadataEditorPersistsDurableMetadataAndKeepsSourceIdentity() async throws {
    let asset = makeAsset(name: "metadata.jpg")
    let originalFingerprint = asset.fingerprint
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    let metadata = try XCTUnwrap(
      PhotoMetadata(
        title: " Harbour at dusk ",
        creator: "Immanuel Lam",
        copyrightNotice: "© PhotoSuite",
        city: "Sydney",
        countryCode: "au",
        keywords: ["harbour", "Sydney", "harbour"]
      )
    )
    await workspace.updateSelectedMetadata(metadata)

    XCTAssertEqual(workspace.selectedAsset?.metadata, metadata)
    XCTAssertEqual(workspace.selectedAsset?.fingerprint, originalFingerprint)
    XCTAssertNil(workspace.lastError)
    let storedAssets = await catalog.assetSnapshot()
    let stored = try XCTUnwrap(storedAssets.first)
    XCTAssertEqual(stored.metadata, metadata)
    XCTAssertEqual(stored.fingerprint, originalFingerprint)
  }

  func testWorkspaceExportsSelectedMetadataToSidecarWithoutChangingSource() async throws {
    let name = "metadata-sidecar-export-\(UUID().uuidString).jpg"
    let sourceURL = URL(fileURLWithPath: "/tmp/\(name)")
    let sourceData = Data("source bytes remain immutable".utf8)
    try sourceData.write(to: sourceURL)
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: XMPMetadataSidecar.sidecarURL(for: sourceURL))
    }
    let asset = makeAsset(name: name)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()
    let metadata = try XCTUnwrap(PhotoMetadata(title: "Exported", keywords: ["Sydney"]))
    await workspace.updateSelectedMetadata(metadata)

    await workspace.exportSelectedMetadataSidecar()

    guard case .exported(let result) = workspace.metadataSidecarStatus else {
      XCTFail("Expected the selected metadata to export to an XMP sidecar.")
      return
    }
    XCTAssertEqual(result.sourceURL, sourceURL)
    XCTAssertEqual(try XMPMetadataSidecar.read(from: result.sidecarURL), metadata)
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertEqual(workspace.selectedAsset?.fingerprint, asset.fingerprint)
    XCTAssertNil(workspace.lastError)
  }

  func testWorkspaceImportsSidecarIntoCatalogWithoutChangingSourceIdentity() async throws {
    let name = "metadata-sidecar-import-\(UUID().uuidString).jpg"
    let sourceURL = URL(fileURLWithPath: "/tmp/\(name)")
    let sourceData = Data("source bytes remain immutable".utf8)
    try sourceData.write(to: sourceURL)
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: XMPMetadataSidecar.sidecarURL(for: sourceURL))
    }
    let asset = makeAsset(name: name)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()
    let metadata = try XCTUnwrap(
      PhotoMetadata(title: "Imported", creator: "Photographer", keywords: ["one", "two"]))
    let sidecarURL = try XMPMetadataSidecar.write(metadata, for: sourceURL)

    await workspace.importSelectedMetadataSidecar(from: sidecarURL)

    guard case .imported(let result) = workspace.metadataSidecarStatus else {
      XCTFail("Expected metadata to import from the selected XMP sidecar.")
      return
    }
    XCTAssertEqual(result.sidecarURL, sidecarURL)
    XCTAssertEqual(workspace.selectedAsset?.metadata, metadata)
    XCTAssertEqual(workspace.selectedAsset?.fingerprint, asset.fingerprint)
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertNil(workspace.lastError)
  }

  func testCollectionsStacksAndSmartFiltersComposeWithoutChangingAssets() async throws {
    let green = makeAsset(name: "green.jpg", rating: 4, colorLabel: .green)
    let red = makeAsset(name: "red.jpg", rating: 2, colorLabel: .red)
    let catalog = CatalogSpy(
      assets: [green, red],
      recipes: [
        green.id: makeRecipe(assetID: green.id),
        red.id: makeRecipe(assetID: red.id),
      ]
    )
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    let collection = workspace.createCollection(named: "Portfolio")
    workspace.addAsset(green.id, toCollection: collection.id)
    workspace.activeCollectionID = collection.id
    workspace.smartFilter = LibrarySmartFilter(minimumRating: 3, colorLabels: [.green])
    let stack = workspace.createStack(named: "Burst", assetIDs: [green.id, red.id])

    XCTAssertEqual(workspace.filteredAssets.map(\.id), [green.id])
    XCTAssertEqual(workspace.assets.count, 2)
    XCTAssertEqual(workspace.stack(containing: green.id)?.id, stack.id)
    workspace.toggleStack(stack.id)
    XCTAssertEqual(workspace.stack(containing: green.id)?.isExpanded, false)
  }

  func testReopenLoadsDurableCollectionsAndStacksWhenCatalogSupportsLibraryStore() async throws {
    let asset = makeAsset(name: "durable-library.jpg")
    let other = makeAsset(name: "other-library.jpg")
    let collection = try XCTUnwrap(
      PhotoCollection(
        name: "Portfolio",
        kind: .regular,
        assetIDs: [asset.id]
      )
    )
    let stack = try XCTUnwrap(
      PhotoStack(
        assetIDs: [asset.id],
        representativeAssetID: asset.id,
        isCollapsed: true
      )
    )
    let catalog = CatalogSpy(
      assets: [asset, other],
      recipes: [
        asset.id: makeRecipe(assetID: asset.id),
        other.id: makeRecipe(assetID: other.id),
      ],
      collections: [collection],
      stacks: [stack]
    )
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()

    XCTAssertEqual(workspace.durableCollections, [collection])
    XCTAssertEqual(workspace.durableStacks, [stack])
    workspace.activeCollectionID = collection.id
    XCTAssertEqual(workspace.filteredAssets.map(\.id), [asset.id])
  }

  func testReopenLoadsDurableFolderTreeFiltersDescendantsAndAssignsWithoutSourceMutation()
    async throws
  {
    let root = try XCTUnwrap(LibraryFolder(name: "2026"))
    let child = try XCTUnwrap(LibraryFolder(name: "Sydney", parentID: root.id))
    let asset = makeAsset(name: "foldered.jpg")
    let other = makeAsset(name: "other-folder.jpg")
    let catalog = CatalogSpy(
      assets: [asset, other],
      recipes: [
        asset.id: makeRecipe(assetID: asset.id),
        other.id: makeRecipe(assetID: other.id),
      ],
      folders: [root, child],
      assetFolders: [asset.id: child.id]
    )
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()

    XCTAssertEqual(workspace.folders, [root, child])
    workspace.selectFolder(root.id)
    XCTAssertEqual(workspace.filteredAssets.map(\.id), [asset.id])
    await workspace.assignAsset(other.id, toFolder: root.id)
    XCTAssertEqual(Set(workspace.filteredAssets.map(\.id)), Set([asset.id, other.id]))
    await workspace.assignAsset(asset.id, toFolder: nil)
    XCTAssertEqual(workspace.filteredAssets.map(\.id), [other.id])
    XCTAssertNil(workspace.activeCollectionID)
  }

  func testDurableFolderCreateAndDeleteUseCatalogBoundaries() async throws {
    let asset = makeAsset(name: "folder-actions.jpg")
    let catalog = CatalogSpy(
      assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)]
    )
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.createDurableFolder(named: "Projects")
    let folder = try XCTUnwrap(workspace.folders.first)
    await workspace.assignAsset(asset.id, toFolder: folder.id)
    await workspace.assignAsset(asset.id, toFolder: nil)
    await workspace.deleteDurableFolder(folder.id)

    XCTAssertTrue(workspace.folders.isEmpty)
    XCTAssertTrue(workspace.folderAssetIDs.isEmpty)
  }

  func testReopenLoadsKeywordsAndVirtualCopiesAndSwitchesRecipeHistory() async throws {
    let asset = makeAsset(name: "keywords-and-copy.jpg")
    let baseRecipe = makeRecipe(assetID: asset.id, revision: 2, operations: [.exposureEV(0.5)])
    let keyword = try XCTUnwrap(KeywordNode(name: "Portraits"))
    let copy = try XCTUnwrap(VirtualCopy(sourceAssetID: asset.id, name: "Monochrome"))
    let copyRecipe = EditRecipe(
      assetID: asset.id,
      virtualCopyID: copy.id,
      revision: 1,
      date: Date(timeIntervalSince1970: 4),
      pins: baseRecipe.pins,
      operations: [
        .blackAndWhite(
          try XCTUnwrap(
            BlackAndWhiteAdjustmentV1(redWeight: 0.3, greenWeight: 0.6, blueWeight: 0.1)
          ))
      ]
    )
    let catalog = CatalogSpy(
      assets: [asset],
      recipes: [asset.id: baseRecipe],
      keywords: [keyword],
      assetKeywords: [asset.id: [keyword.id]],
      virtualCopies: [copy],
      virtualCopyRecipes: [copy.id: copyRecipe]
    )
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()

    XCTAssertEqual(workspace.keywordNodes, [keyword])
    XCTAssertEqual(workspace.selectedAssetKeywords, [keyword])
    XCTAssertEqual(workspace.virtualCopies, [copy])
    XCTAssertNil(workspace.selectedVirtualCopyID)
    XCTAssertEqual(workspace.currentRecipe, baseRecipe)

    await workspace.selectVirtualCopy(copy.id)

    XCTAssertEqual(workspace.selectedVirtualCopyID, copy.id)
    XCTAssertEqual(workspace.currentRecipe, copyRecipe)

    await workspace.commitAdjustment(.exposure, value: 0.8)

    XCTAssertEqual(workspace.currentRecipe?.virtualCopyID, copy.id)
  }

  func testAssigningKeywordsAndCreatingVirtualCopyPersistsDurableRecords() async throws {
    let asset = makeAsset(name: "keyword-edit.jpg")
    let baseRecipe = makeRecipe(assetID: asset.id)
    let keyword = try XCTUnwrap(KeywordNode(name: "Travel"))
    let catalog = CatalogSpy(
      assets: [asset],
      recipes: [asset.id: baseRecipe],
      keywords: [keyword]
    )
    let workspace = makeWorkspace(catalog: catalog)
    await workspace.reopen()

    await workspace.assignKeywords(to: asset.id, keywordIDs: [keyword.id])
    XCTAssertEqual(workspace.selectedAssetKeywords, [keyword])

    await workspace.createVirtualCopy(named: "Warm")
    XCTAssertEqual(workspace.virtualCopies.count, 1)
    XCTAssertEqual(workspace.selectedVirtualCopyID, workspace.virtualCopies.first?.id)
    XCTAssertEqual(workspace.currentRecipe?.virtualCopyID, workspace.selectedVirtualCopyID)
  }

  func
    testWorkspaceReopensSavesAndAppliesDevelopPresetWithoutDroppingVirtualCopyOrUnknownOperations()
    async throws
  {
    let asset = makeAsset(name: "preset-workflow.jpg")
    let copy = try XCTUnwrap(VirtualCopy(sourceAssetID: asset.id, name: "Warm"))
    let unknown = EditOperation.unknown(
      "vendor.futureDevelop",
      payload: ["strength": .number(Decimal(string: "0.5")!)]
    )
    let baseRecipe = makeRecipe(
      assetID: asset.id,
      revision: 2,
      operations: [unknown, .exposureEV(0.25)]
    )
    let copyRecipe = EditRecipe(
      assetID: asset.id,
      virtualCopyID: copy.id,
      revision: 1,
      pins: baseRecipe.pins,
      operations: [
        .clone(
          try XCTUnwrap(
            CloneAdjustmentV1(
              sourceAnchor: try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.2)),
              targetAnchor: try XCTUnwrap(RetouchPointV1(x: 0.7, y: 0.7)),
              brush: try XCTUnwrap(
                RetouchBrushV1(
                  samples: [
                    try XCTUnwrap(
                      RetouchBrushSampleV1(
                        point: try XCTUnwrap(RetouchPointV1(x: 0.2, y: 0.2)), pressure: 1
                      )
                    )
                  ],
                  radius: 0.1,
                  feather: 0.5,
                  flow: 1
                )
              )
            )
          )
        )
      ]
    )
    let preset = try XCTUnwrap(
      DevelopPreset(
        name: "Warm",
        operations: [.unknown("vendor.preset", payload: ["enabled": .bool(true)]), .contrast(0.4)],
        virtualCopyID: copy.id
      )
    )
    let catalog = CatalogSpy(
      assets: [asset],
      recipes: [asset.id: baseRecipe],
      virtualCopies: [copy],
      virtualCopyRecipes: [copy.id: copyRecipe],
      presets: [preset]
    )
    let workspace = makeWorkspace(catalog: catalog)

    await workspace.reopen()

    XCTAssertEqual(workspace.developPresets, [preset])
    await workspace.selectVirtualCopy(copy.id)
    await workspace.saveDevelopPreset(named: "Saved copy")
    XCTAssertEqual(workspace.developPresets.count, 2)
    XCTAssertEqual(workspace.developPresets.last?.virtualCopyID, copy.id)

    await workspace.applyDevelopPreset(preset.id)
    XCTAssertEqual(workspace.currentRecipe?.virtualCopyID, copy.id)
    XCTAssertEqual(
      workspace.currentRecipe?.operations,
      [copyRecipe.operations[0], preset.operations[0], preset.operations[1]]
    )
  }

  func testDeliverOptionsReachTheExporter() async throws {
    let asset = makeAsset(name: "deliver.jpg")
    let recipe = makeRecipe(assetID: asset.id)
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: recipe])
    let exporter = ExporterSpy()
    let workspace = makeWorkspace(catalog: catalog, exporter: exporter)
    await workspace.reopen()
    let options = DeliverOptions(
      format: .png,
      resize: .longEdge(2_048),
      metadata: .copyrightOnly,
      watermark: .text("PhotoSuite"),
      outputSharpening: .screenStandard
    )

    await workspace.exportJPEG(
      to: URL(fileURLWithPath: "/tmp/unsupported.jpg"),
      quality: 0.9,
      options: options
    )

    let capturedRequest = await exporter.lastRequest()
    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(
      request.options,
      ExportOptions(
        resize: .longEdge(2_048),
        metadata: .copyrightOnly,
        watermark: .text("PhotoSuite"),
        outputSharpening: .screenStandard
      )
    )
    XCTAssertEqual(request.format, .png)
    XCTAssertNil(workspace.lastError)
  }

  func testProfessionalMapLoadsValidLocationsInsideSourceAccess() async throws {
    let asset = makeAsset(name: "geotagged.jpg")
    let catalog = CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    let access = SourceAccessSpy()
    let recorder = LocationProbeRecorder(access: access)
    let workspace = makeWorkspace(
      catalog: catalog,
      access: access,
      locationProbe: { url in try await recorder.probe(url) }
    )
    await workspace.reopen()

    await workspace.loadPhotoLocations()

    XCTAssertEqual(
      workspace.photoLocations,
      [
        PhotoLocation(
          assetID: asset.id,
          filename: asset.filename,
          coordinate: PhotoCoordinate(latitude: -33.8688, longitude: 151.2093)!
        )
      ]
    )
    XCTAssertEqual(workspace.professionalStatus(for: .map), .available)
    let accessWasActive = await recorder.wasAccessActive()
    let activeAccessCount = await access.activeAccessCount()
    XCTAssertTrue(accessWasActive)
    XCTAssertEqual(activeAccessCount, 0)
  }

  func testProfessionalToolsReportAvailableAndTypedUnavailableStates() async throws {
    let asset = makeAsset(name: "professional.jpg")
    let workspace = makeWorkspace(
      catalog: CatalogSpy(assets: [asset], recipes: [asset.id: makeRecipe(assetID: asset.id)])
    )
    await workspace.reopen()

    XCTAssertEqual(workspace.professionalStatus(for: .print), .available)
    XCTAssertEqual(
      workspace.professionalStatus(for: .tether),
      .previewOnly(.cameraAdapterRequired)
    )
    XCTAssertEqual(workspace.professionalStatus(for: .book), .available)
    XCTAssertEqual(workspace.professionalStatus(for: .webGallery), .available)
    XCTAssertEqual(
      workspace.professionalStatus(for: .plugins),
      .unavailable(.pluginHostUnavailable)
    )
    XCTAssertEqual(
      workspace.professionalStatus(for: .adobeMigration),
      .unavailable(.adobeCatalogParserUnavailable)
    )
  }
}

extension PhotoWorkspaceTests {
  private func makeWorkspace(
    catalog: any CatalogStore = CatalogSpy(),
    renderer: any RenderEngine = ImmediateRenderer(),
    exporter: any Exporter = ExporterSpy(),
    access: SourceAccessSpy = SourceAccessSpy(),
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint = { _ in
      SourceFingerprint(
        sha256: String(repeating: "a", count: 64), byteCount: 10, modificationDate: nil)!
    },
    locationProbe: @escaping @Sendable (URL) async throws -> PhotoCoordinate? = { _ in nil }
  ) -> PhotoWorkspace {
    PhotoWorkspace(
      catalog: catalog,
      renderer: renderer,
      exporter: exporter,
      sourceAccess: access.operations,
      fingerprint: fingerprint,
      probe: { url in
        SourceProbe(
          dimensions: PixelDimensions(width: 20, height: 10)!,
          pins: EnginePins(
            decoderIdentifier: url.pathExtension == "raw"
              ? "com.apple.ciraw" : "com.apple.coreimage.common-image",
            decoderVersion: url.pathExtension == "raw" ? "raw-v1" : "system-default",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: url.pathExtension == "raw" ? "public.camera-raw-image" : "public.image"
        )
      },
      locationProbe: locationProbe,
      now: { Date(timeIntervalSince1970: 100) },
      previewDebounce: {}
    )
  }

  private func makeAsset(
    name: String,
    date: Date = Date(timeIntervalSince1970: 1),
    isMissing: Bool = false,
    rating: Int = 0,
    colorLabel: ColorLabel? = nil
  ) -> PhotoAsset {
    PhotoAsset(
      sourceURL: URL(fileURLWithPath: "/tmp/\(name)"),
      filename: name,
      typeIdentifier: "public.image",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "b", count: 64),
        byteCount: 20,
        modificationDate: nil
      )!,
      importDate: date,
      captureDate: nil,
      pixelDimensions: PixelDimensions(width: 20, height: 10),
      rating: rating,
      colorLabel: colorLabel,
      isMissing: isMissing
    )!
  }

  private func makeRecipe(
    assetID: UUID,
    revision: UInt64 = 0,
    operations: [EditOperation] = []
  ) -> EditRecipe {
    EditRecipe(
      assetID: assetID,
      revision: revision,
      date: Date(timeIntervalSince1970: 1),
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      ),
      operations: operations
    )
  }

  private func makeColorGrade() throws -> ThreeWayColorGrade {
    try XCTUnwrap(
      ThreeWayColorGrade(
        shadows: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 220, chroma: 0.35, luminance: -0.1)
        ),
        midtones: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 35, chroma: 0.2, luminance: 0.05)
        ),
        highlights: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 55, chroma: 0.15, luminance: 0.1)
        )
      )
    )
  }

  private func histogram(total: UInt64) -> RenderHistogram {
    RenderHistogram(
      red: [UInt64](repeating: 0, count: 255) + [total],
      green: [UInt64](repeating: 0, count: 255) + [total],
      blue: [UInt64](repeating: 0, count: 255) + [total],
      luminance: [UInt64](repeating: 0, count: 255) + [total]
    )!
  }
}

private actor CatalogSpy: MetadataCatalogStore, LibraryCatalogStore {
  private var storedAssets: [PhotoAsset]
  private var recipes: [UUID: EditRecipe]
  private var storedCollections: [PhotoCollection]
  private var storedStacks: [PhotoStack]
  private var storedFolders: [LibraryFolder] = []
  private var assetFolderIDs: [UUID: UUID] = [:]
  private var storedKeywords: [KeywordNode] = []
  private var assetKeywordIDs: [UUID: [UUID]] = [:]
  private var storedVirtualCopies: [VirtualCopy] = []
  private var virtualCopyRecipes: [UUID: EditRecipe] = [:]
  private var storedDevelopPresets: [DevelopPreset] = []
  private var recipeSaves: [EditRecipe] = []
  private var missing: [UUID: Bool] = [:]
  private var shouldFailNextRecipeSave = false

  init(
    assets: [PhotoAsset] = [],
    recipes: [UUID: EditRecipe] = [:],
    collections: [PhotoCollection] = [],
    stacks: [PhotoStack] = [],
    folders: [LibraryFolder] = [],
    assetFolders: [UUID: UUID] = [:],
    keywords: [KeywordNode] = [],
    assetKeywords: [UUID: [UUID]] = [:],
    virtualCopies: [VirtualCopy] = [],
    virtualCopyRecipes: [UUID: EditRecipe] = [:],
    presets: [DevelopPreset] = []
  ) {
    storedAssets = assets
    self.recipes = recipes
    storedCollections = collections
    storedStacks = stacks
    storedFolders = folders
    assetFolderIDs = assetFolders
    storedKeywords = keywords
    assetKeywordIDs = assetKeywords
    storedVirtualCopies = virtualCopies
    self.virtualCopyRecipes = virtualCopyRecipes
    storedDevelopPresets = presets
  }

  func upsertAsset(_ request: CatalogAssetUpsertRequest) async throws -> CatalogAssetUpsertResult {
    storedAssets.removeAll { $0.id == request.asset.id }
    storedAssets.append(request.asset)
    return CatalogAssetUpsertResult(asset: request.asset)
  }

  func fetchAsset(_ request: CatalogAssetFetchRequest) async throws -> CatalogAssetFetchResult {
    CatalogAssetFetchResult(asset: storedAssets.first { $0.id == request.assetID })
  }

  func listAssets(_ request: CatalogAssetListRequest) async throws -> CatalogAssetListResult {
    CatalogAssetListResult(assets: storedAssets)
  }

  func searchAssets(_ request: CatalogAssetSearchRequest) async throws -> CatalogAssetSearchResult {
    CatalogAssetSearchResult(
      assets: storedAssets.filter { $0.filename.localizedCaseInsensitiveContains(request.query) })
  }

  func saveRecipe(_ request: CatalogRecipeSaveRequest) async throws -> CatalogRecipeSaveResult {
    if shouldFailNextRecipeSave {
      shouldFailNextRecipeSave = false
      throw TestError.recipeSave
    }
    if let virtualCopyID = request.recipe.virtualCopyID {
      virtualCopyRecipes[virtualCopyID] = request.recipe
    } else {
      recipes[request.recipe.assetID] = request.recipe
    }
    recipeSaves.append(request.recipe)
    return CatalogRecipeSaveResult(recipe: request.recipe)
  }

  func latestRecipe(_ request: CatalogLatestRecipeRequest) async throws -> CatalogLatestRecipeResult
  {
    CatalogLatestRecipeResult(
      recipe: request.virtualCopyID.flatMap { virtualCopyRecipes[$0] } ?? recipes[request.assetID]
    )
  }

  func markAssetMissing(_ request: CatalogMarkMissingRequest) async throws
    -> CatalogMarkMissingResult
  {
    missing[request.assetID] = request.isMissing
    let old = storedAssets.first { $0.id == request.assetID }!
    let asset = PhotoAsset(
      id: old.id,
      sourceURL: old.sourceURL,
      filename: old.filename,
      typeIdentifier: old.typeIdentifier,
      fingerprint: old.fingerprint,
      importDate: old.importDate,
      captureDate: old.captureDate,
      pixelDimensions: old.pixelDimensions,
      rating: old.rating,
      colorLabel: old.colorLabel,
      isMissing: request.isMissing
    )!
    storedAssets.removeAll { $0.id == request.assetID }
    storedAssets.append(asset)
    return CatalogMarkMissingResult(asset: asset)
  }

  func relinkAsset(_ request: CatalogRelinkAssetRequest) async throws -> CatalogRelinkAssetResult {
    throw TestError.unused
  }

  func checkIntegrity(_ request: CatalogIntegrityRequest) async throws -> CatalogIntegrityResult {
    CatalogIntegrityResult(isValid: true, messages: [])
  }

  func backup(_ request: CatalogBackupRequest) async throws -> CatalogBackupResult {
    CatalogBackupResult(destinationURL: request.destinationURL)
  }

  func updateMetadata(
    _ request: CatalogAssetMetadataUpdateRequest
  ) async throws -> CatalogAssetMetadataUpdateResult {
    guard let old = storedAssets.first(where: { $0.id == request.assetID }),
      let updated = PhotoAsset(
        id: old.id,
        sourceURL: old.sourceURL,
        filename: old.filename,
        typeIdentifier: old.typeIdentifier,
        fingerprint: old.fingerprint,
        importDate: old.importDate,
        captureDate: old.captureDate,
        pixelDimensions: old.pixelDimensions,
        rating: old.rating,
        colorLabel: old.colorLabel,
        isMissing: old.isMissing,
        metadata: request.metadata
      )
    else {
      throw TestError.unused
    }
    storedAssets.removeAll { $0.id == updated.id }
    storedAssets.append(updated)
    return CatalogAssetMetadataUpdateResult(asset: updated)
  }

  func saveMetadataPreset(
    _ request: CatalogMetadataPresetSaveRequest
  ) async throws -> CatalogMetadataPresetSaveResult {
    CatalogMetadataPresetSaveResult(preset: request.preset)
  }

  func listMetadataPresets(
    _ request: CatalogMetadataPresetListRequest
  ) async throws -> CatalogMetadataPresetListResult {
    CatalogMetadataPresetListResult(presets: [])
  }

  func deleteMetadataPreset(
    _ request: CatalogMetadataPresetDeleteRequest
  ) async throws -> CatalogMetadataPresetDeleteResult {
    CatalogMetadataPresetDeleteResult(presetID: request.presetID)
  }

  func applyMetadataPreset(
    _ request: CatalogApplyMetadataPresetRequest
  ) async throws -> CatalogApplyMetadataPresetResult {
    throw TestError.unused
  }

  func saveCollection(_ request: CatalogCollectionSaveRequest) async throws
    -> CatalogCollectionSaveResult
  {
    storedCollections.removeAll { $0.id == request.collection.id }
    storedCollections.append(request.collection)
    return CatalogCollectionSaveResult(collection: request.collection)
  }

  func listCollections(_ request: CatalogCollectionListRequest) async throws
    -> CatalogCollectionListResult
  {
    CatalogCollectionListResult(collections: storedCollections)
  }

  func deleteCollection(_ request: CatalogCollectionDeleteRequest) async throws
    -> CatalogCollectionDeleteResult
  {
    storedCollections.removeAll { $0.id == request.collectionID }
    return CatalogCollectionDeleteResult(collectionID: request.collectionID)
  }

  func listCollectionAssets(_ request: CatalogCollectionAssetsRequest) async throws
    -> CatalogCollectionAssetsResult
  {
    let ids = Set(storedCollections.first { $0.id == request.collectionID }?.assetIDs ?? [])
    return CatalogCollectionAssetsResult(assets: storedAssets.filter { ids.contains($0.id) })
  }

  func saveStack(_ request: CatalogStackSaveRequest) async throws -> CatalogStackSaveResult {
    storedStacks.removeAll { $0.id == request.stack.id }
    storedStacks.append(request.stack)
    return CatalogStackSaveResult(stack: request.stack)
  }

  func listStacks(_ request: CatalogStackListRequest) async throws -> CatalogStackListResult {
    CatalogStackListResult(stacks: storedStacks)
  }

  func deleteStack(_ request: CatalogStackDeleteRequest) async throws -> CatalogStackDeleteResult {
    storedStacks.removeAll { $0.id == request.stackID }
    return CatalogStackDeleteResult(stackID: request.stackID)
  }

  func listStackAssets(_ request: CatalogStackAssetsRequest) async throws
    -> CatalogStackAssetsResult
  {
    let ids = Set(storedStacks.first { $0.id == request.stackID }?.assetIDs ?? [])
    return CatalogStackAssetsResult(assets: storedAssets.filter { ids.contains($0.id) })
  }

  func saveKeywordNode(_ request: CatalogKeywordNodeSaveRequest) async throws
    -> CatalogKeywordNodeSaveResult
  {
    storedKeywords.removeAll { $0.id == request.keyword.id }
    storedKeywords.append(request.keyword)
    return CatalogKeywordNodeSaveResult(keyword: request.keyword)
  }

  func listKeywordNodes(_ request: CatalogKeywordNodeListRequest) async throws
    -> CatalogKeywordNodeListResult
  {
    CatalogKeywordNodeListResult(keywords: storedKeywords)
  }

  func deleteKeywordNode(_ request: CatalogKeywordNodeDeleteRequest) async throws
    -> CatalogKeywordNodeDeleteResult
  {
    storedKeywords.removeAll { $0.id == request.keywordID }
    return CatalogKeywordNodeDeleteResult(keywordID: request.keywordID)
  }

  func setAssetKeywords(_ request: CatalogAssetKeywordSetRequest) async throws
    -> CatalogAssetKeywordSetResult
  {
    assetKeywordIDs[request.assetID] = request.keywordIDs
    return CatalogAssetKeywordSetResult(
      assetID: request.assetID,
      keywordIDs: request.keywordIDs
    )
  }

  func listAssetKeywords(_ request: CatalogAssetKeywordListRequest) async throws
    -> CatalogAssetKeywordListResult
  {
    let ids = Set(assetKeywordIDs[request.assetID] ?? [])
    return CatalogAssetKeywordListResult(keywords: storedKeywords.filter { ids.contains($0.id) })
  }

  func saveVirtualCopy(_ request: CatalogVirtualCopySaveRequest) async throws
    -> CatalogVirtualCopySaveResult
  {
    storedVirtualCopies.removeAll { $0.id == request.virtualCopy.id }
    storedVirtualCopies.append(request.virtualCopy)
    return CatalogVirtualCopySaveResult(virtualCopy: request.virtualCopy)
  }

  func listVirtualCopies(_ request: CatalogVirtualCopyListRequest) async throws
    -> CatalogVirtualCopyListResult
  {
    CatalogVirtualCopyListResult(virtualCopies: storedVirtualCopies)
  }

  func deleteVirtualCopy(_ request: CatalogVirtualCopyDeleteRequest) async throws
    -> CatalogVirtualCopyDeleteResult
  {
    storedVirtualCopies.removeAll { $0.id == request.virtualCopyID }
    return CatalogVirtualCopyDeleteResult(virtualCopyID: request.virtualCopyID)
  }

  func saveDevelopPreset(
    _ request: CatalogDevelopPresetSaveRequest
  ) async throws -> CatalogDevelopPresetSaveResult {
    storedDevelopPresets.removeAll { $0.id == request.preset.id }
    storedDevelopPresets.append(request.preset)
    return CatalogDevelopPresetSaveResult(preset: request.preset)
  }

  func listDevelopPresets(
    _ request: CatalogDevelopPresetListRequest
  ) async throws -> CatalogDevelopPresetListResult {
    CatalogDevelopPresetListResult(presets: storedDevelopPresets)
  }

  func deleteDevelopPreset(
    _ request: CatalogDevelopPresetDeleteRequest
  ) async throws -> CatalogDevelopPresetDeleteResult {
    storedDevelopPresets.removeAll { $0.id == request.presetID }
    return CatalogDevelopPresetDeleteResult(presetID: request.presetID)
  }

  func applyDevelopPreset(
    _ request: CatalogApplyDevelopPresetRequest
  ) async throws -> CatalogApplyDevelopPresetResult {
    guard let preset = storedDevelopPresets.first(where: { $0.id == request.presetID }) else {
      throw TestError.unused
    }
    let virtualCopyID = request.virtualCopyID ?? preset.virtualCopyID
    let current = virtualCopyID.flatMap { virtualCopyRecipes[$0] } ?? recipes[request.assetID]
    guard let current else { throw TestError.unused }
    let retained = current.operations.filter { operation in
      switch operation {
      case .exposureEV, .contrast, .highlights, .shadows, .saturation,
        .threeWayColorGrade, .toneCurve, .whiteBalance, .transform, .detail,
        .optics, .effects, .calibration, .blackAndWhite, .hdr:
        return false
      case .maskedAdjustment, .clone, .healing, .redEye, .normalizedCrop,
        .rotationDegrees, .unknown:
        return true
      }
    }
    let recipe = EditRecipe(
      assetID: request.assetID,
      virtualCopyID: virtualCopyID ?? current.virtualCopyID,
      revision: current.revision + 1,
      pins: current.pins,
      operations: retained + preset.operations,
      masks: current.masks
    )
    _ = try await saveRecipe(.init(recipe: recipe))
    return CatalogApplyDevelopPresetResult(recipe: recipe)
  }

  func saveFolder(_ request: CatalogFolderSaveRequest) async throws -> CatalogFolderSaveResult {
    storedFolders.removeAll { $0.id == request.folder.id }
    storedFolders.append(request.folder)
    return CatalogFolderSaveResult(folder: request.folder)
  }

  func listFolders(_ request: CatalogFolderListRequest) async throws -> CatalogFolderListResult {
    CatalogFolderListResult(folders: storedFolders)
  }

  func deleteFolder(_ request: CatalogFolderDeleteRequest) async throws -> CatalogFolderDeleteResult
  {
    storedFolders.removeAll { $0.id == request.folderID }
    assetFolderIDs = assetFolderIDs.filter { $0.value != request.folderID }
    return CatalogFolderDeleteResult(folderID: request.folderID)
  }

  func setAssetFolder(
    _ request: CatalogAssetFolderSetRequest
  ) async throws -> CatalogAssetFolderSetResult {
    if let folderID = request.folderID {
      guard storedFolders.contains(where: { $0.id == folderID }) else { throw TestError.unused }
      assetFolderIDs[request.assetID] = folderID
    } else {
      assetFolderIDs.removeValue(forKey: request.assetID)
    }
    return CatalogAssetFolderSetResult(assetID: request.assetID, folderID: request.folderID)
  }

  func listAssetFolder(_ request: CatalogAssetFolderRequest) async throws
    -> CatalogAssetFolderResult
  {
    CatalogAssetFolderResult(assetID: request.assetID, folderID: assetFolderIDs[request.assetID])
  }

  func listFolderAssets(_ request: CatalogFolderAssetsRequest) async throws
    -> CatalogFolderAssetsResult
  {
    let ids = Set(assetFolderIDs.compactMap { $0.value == request.folderID ? $0.key : nil })
    return CatalogFolderAssetsResult(assets: storedAssets.filter { ids.contains($0.id) })
  }

  func savedRecipes() -> [EditRecipe] { recipeSaves }
  func missingUpdates() -> [UUID: Bool] { missing }
  func failNextRecipeSave() { shouldFailNextRecipeSave = true }
  func assetSnapshot() -> [PhotoAsset] { storedAssets }
}

private actor SourceAccessSpy {
  private var missingAssetIDs: Set<UUID>
  private var persisted: [URL] = []
  private var active = 0
  private let failingPersistURLs: Set<URL>

  init(missingAssetIDs: Set<UUID> = [], failingPersistURLs: Set<URL> = []) {
    self.missingAssetIDs = missingAssetIDs
    self.failingPersistURLs = failingPersistURLs
  }

  nonisolated var operations: SourceAccessOperations {
    SourceAccessOperations(
      persist: { [self] _, url in try await recordPersist(url) },
      resolve: { [self] asset in
        if await isMissing(asset.id) { throw TestError.missing }
        return asset.sourceURL
      },
      start: { [self] url in
        await start(url)
        return true
      },
      stop: { [self] url in await stop(url) }
    )
  }

  private func recordPersist(_ url: URL) throws {
    if failingPersistURLs.contains(url) { throw TestError.bookmark }
    persisted.append(url)
  }
  private func isMissing(_ id: UUID) -> Bool { missingAssetIDs.contains(id) }
  private func start(_ url: URL) { active += 1 }
  private func stop(_ url: URL) { active -= 1 }
  func persistedURLs() -> [URL] { persisted }
  func activeAccessCount() -> Int { active }
  var isActive: Bool { active > 0 }
}

private actor FingerprintRecorder {
  private let failingURL: URL
  private var recorded: [URL] = []

  init(failingURL: URL) { self.failingURL = failingURL }

  func fingerprint(_ url: URL) throws -> SourceFingerprint {
    recorded.append(url)
    if url == failingURL { throw TestError.fingerprint }
    return SourceFingerprint(
      sha256: String(repeating: url == recorded.first ? "c" : "d", count: 64),
      byteCount: 30,
      modificationDate: nil
    )!
  }

  func urls() -> [URL] { recorded }
}

private actor ImmediateRenderer: RenderEngine {
  private let access: SourceAccessSpy?
  private var accessWasActive = false

  init(access: SourceAccessSpy? = nil) { self.access = access }

  func render(_ request: RenderRequest) async throws -> RenderResult {
    if let access { accessWasActive = await access.isActive }
    return RenderResult(
      imageData: Data("preview-\(request.recipe.revision)".utf8),
      typeIdentifier: "public.png",
      pixelDimensions: PixelDimensions(width: 20, height: 10)!,
      histogram: RenderHistogram(
        red: [UInt64](repeating: 0, count: 255) + [1],
        green: [UInt64](repeating: 0, count: 255) + [1],
        blue: [UInt64](repeating: 0, count: 255) + [1],
        luminance: [UInt64](repeating: 0, count: 255) + [1]
      )
    )
  }

  func wasAccessActive() -> Bool { accessWasActive }
}

private actor RecipeRecordingRenderer: RenderEngine {
  private let access: SourceAccessSpy
  private var recipe: EditRecipe?
  private var accessWasActive = false

  init(access: SourceAccessSpy) { self.access = access }

  func render(_ request: RenderRequest) async throws -> RenderResult {
    recipe = request.recipe
    accessWasActive = await access.isActive
    return RenderResult(
      imageData: Data("recovered-preview".utf8),
      typeIdentifier: "public.png",
      pixelDimensions: PixelDimensions(width: 20, height: 10)!
    )
  }

  func lastRecipe() -> EditRecipe? { recipe }
  func wasAccessActive() -> Bool { accessWasActive }
}

private actor ControllableRenderer: RenderEngine {
  private var continuations: [CheckedContinuation<RenderResult, any Error>] = []

  func render(_ request: RenderRequest) async throws -> RenderResult {
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitForRequestCount(_ count: Int) async {
    while continuations.count < count { await Task.yield() }
  }

  func completeRequest(_ index: Int, bytes: Data, histogram: RenderHistogram? = nil) {
    continuations[index].resume(
      returning: RenderResult(
        imageData: bytes,
        typeIdentifier: "public.png",
        pixelDimensions: PixelDimensions(width: 20, height: 10)!,
        histogram: histogram
      )
    )
  }
}

private actor ExporterSpy: Exporter {
  private var request: ExportRequest?
  private var recordedRequests: [ExportRequest] = []
  private var shouldFail = false
  private let access: SourceAccessSpy?
  private var accessWasActive = false
  private var recordedAccessStates: [Bool] = []
  private let failingRequestIndex: Int?

  init(access: SourceAccessSpy? = nil, failingRequestIndex: Int? = nil) {
    self.access = access
    self.failingRequestIndex = failingRequestIndex
  }

  func export(_ request: ExportRequest) async throws -> ExportResult {
    self.request = request
    recordedRequests.append(request)
    if let access { accessWasActive = await access.isActive }
    if let access { recordedAccessStates.append(await access.isActive) }
    if shouldFail || failingRequestIndex == recordedRequests.count - 1 { throw TestError.export }
    return ExportResult(
      derivative: DurableDerivative(
        schemaVersion: 1,
        assetID: request.recipe.assetID,
        recipeRevision: request.recipe.revision,
        kind: .export,
        outputURL: request.destinationURL,
        typeIdentifier: "public.jpeg",
        fingerprint: SourceFingerprint(
          sha256: String(repeating: "e", count: 64),
          byteCount: 100,
          modificationDate: nil
        )!,
        createdAt: Date(timeIntervalSince1970: 100)
      )
    )
  }

  func lastRequest() -> ExportRequest? { request }
  func requests() -> [ExportRequest] { recordedRequests }
  func failExports() { shouldFail = true }
  func wasAccessActive() -> Bool { accessWasActive }
  func accessObservations() -> [Bool] { recordedAccessStates }
}

private actor AccessPhaseRecorder {
  private var recorded: [String: Bool] = [:]

  func record(_ phase: String, active: Bool) { recorded[phase] = active }
  func values() -> [String: Bool] { recorded }
}

private actor LocationProbeRecorder {
  private let access: SourceAccessSpy
  private var accessWasActive = false

  init(access: SourceAccessSpy) { self.access = access }

  func probe(_ url: URL) async throws -> PhotoCoordinate? {
    accessWasActive = await access.isActive
    return PhotoCoordinate(latitude: -33.8688, longitude: 151.2093)
  }

  func wasAccessActive() -> Bool { accessWasActive }
}

private enum TestError: Error {
  case fingerprint
  case missing
  case unused
  case bookmark
  case recipeSave
  case export
}
