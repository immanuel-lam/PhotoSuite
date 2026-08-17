// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import PhotoDomain
import UniformTypeIdentifiers
import XCTest

@testable import RenderCore

final class JPEGExportTests: XCTestCase {
  func testExportWritesTaggedSRGBJPEGFromSameFullResolutionGraph() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("export.jpg")
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let exporter = AtomicJPEGExporter(decoder: decoder)
    let crop = try XCTUnwrap(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
    let recipe = makeRecipe(
      operations: [
        .threeWayColorGrade(try makeColorGrade()),
        .normalizedCrop(crop),
        .rotationDegrees(90),
      ]
    )
    let preview = try await decoder.preview(
      sourceURL: fixture.source,
      recipe: recipe,
      maximumPixelDimension: nil
    )

    let result = try await exporter.export(
      ExportRequest(
        sourceURL: fixture.source,
        recipe: recipe,
        destinationURL: destination,
        format: .jpeg,
        quality: 0.9
      )
    )

    let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual([image.width, image.height], [preview.width, preview.height])
    XCTAssertEqual(try XCTUnwrap(image.colorSpace).model, .rgb)
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
    let profileName = try XCTUnwrap(properties[kCGImagePropertyProfileName] as? String)
    XCTAssertTrue(profileName.localizedCaseInsensitiveContains("srgb"))
    XCTAssertEqual(result.derivative.outputURL, destination)
    XCTAssertEqual(result.derivative.typeIdentifier, UTType.jpeg.identifier)
    XCTAssertEqual(result.derivative.kind, .export)
    XCTAssertNotNil(result.derivative.fingerprint)
  }

  func testExportResizeLongEdgeProducesExpectedDimensionsWithoutUpscaling() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("resized.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(
      ExportRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        destinationURL: destination,
        format: .jpeg,
        quality: 0.9,
        options: ExportOptions(resize: .longEdge(4))
      )
    )

    let source = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual([image.width, image.height], [4, 3])
  }

  func testAllMetadataRetainsEXIFAndSRGBProfileWhileNoneRemovesSourceMetadata() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makeMetadataTIFF(in: directory)
    let allDestination = directory.appendingPathComponent("all-metadata.jpg")
    let basicDestination = directory.appendingPathComponent("basic-metadata.jpg")
    let copyrightDestination = directory.appendingPathComponent("copyright-metadata.jpg")
    let noneDestination = directory.appendingPathComponent("no-metadata.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: basicDestination,
        options: ExportOptions(metadata: .basic)
      )
    )
    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: copyrightDestination,
        options: ExportOptions(metadata: .copyrightOnly)
      )
    )
    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: allDestination,
        options: ExportOptions(metadata: .all)
      )
    )
    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: noneDestination,
        options: ExportOptions(metadata: .none)
      )
    )

    let allProperties = try imageProperties(at: allDestination)
    let allExif = try XCTUnwrap(allProperties[kCGImagePropertyExifDictionary] as? [CFString: Any])
    XCTAssertEqual(allExif[kCGImagePropertyExifLensModel] as? String, "PhotoSuite Test Lens")
    XCTAssertEqual(
      allExif[kCGImagePropertyExifDateTimeOriginal] as? String,
      "2024:01:02 03:04:05"
    )
    XCTAssertNotNil(allProperties[kCGImagePropertyGPSDictionary])
    XCTAssertTrue(
      try XCTUnwrap(allProperties[kCGImagePropertyProfileName] as? String)
        .localizedCaseInsensitiveContains("srgb")
    )

    let basicProperties = try imageProperties(at: basicDestination)
    let basicExif = try XCTUnwrap(
      basicProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    )
    XCTAssertEqual(basicExif[kCGImagePropertyExifLensModel] as? String, "PhotoSuite Test Lens")
    XCTAssertNil(basicProperties[kCGImagePropertyGPSDictionary])

    let copyrightProperties = try imageProperties(at: copyrightDestination)
    let copyrightExif = copyrightProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    XCTAssertNil(copyrightExif?[kCGImagePropertyExifLensModel])
    XCTAssertNil(copyrightProperties[kCGImagePropertyGPSDictionary])
    let copyrightTIFF = try XCTUnwrap(
      copyrightProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    )
    XCTAssertEqual(
      copyrightTIFF[kCGImagePropertyTIFFArtist] as? String,
      "PhotoSuite Test Artist"
    )
    XCTAssertEqual(
      copyrightTIFF[kCGImagePropertyTIFFCopyright] as? String,
      "PhotoSuite Test Copyright"
    )

    let noneProperties = try imageProperties(at: noneDestination)
    let noneExif = noneProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    XCTAssertNil(noneExif?[kCGImagePropertyExifLensModel])
    XCTAssertNil(noneExif?[kCGImagePropertyExifDateTimeOriginal])
    XCTAssertNil(noneProperties[kCGImagePropertyGPSDictionary])
    let noneTIFF = noneProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    XCTAssertNil(noneTIFF?[kCGImagePropertyTIFFArtist])
    XCTAssertNil(noneTIFF?[kCGImagePropertyTIFFCopyright])
    XCTAssertTrue(
      try XCTUnwrap(noneProperties[kCGImagePropertyProfileName] as? String)
        .localizedCaseInsensitiveContains("srgb")
    )
  }

  func testTextWatermarkChangesBottomRightPixelsWithoutChangingDimensions() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makeMetadataTIFF(
      in: directory,
      width: 320,
      height: 240
    )
    let sourceChecksum = try DeterministicImageFixture.checksum(of: source)
    let plainDestination = directory.appendingPathComponent("plain.jpg")
    let watermarkedDestination = directory.appendingPathComponent("watermarked.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(makeRequest(source: source, destination: plainDestination))
    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: watermarkedDestination,
        options: ExportOptions(metadata: .none, watermark: .text("PhotoSuite"))
      )
    )

    let plain = try decodedImage(at: plainDestination)
    let watermarked = try decodedImage(at: watermarkedDestination)
    XCTAssertEqual([watermarked.width, watermarked.height], [plain.width, plain.height])
    let plainPixels = try DeterministicImageFixture.rgba8Data(from: plain)
    let watermarkedPixels = try DeterministicImageFixture.rgba8Data(from: watermarked)
    XCTAssertGreaterThan(
      pixelDifferenceCount(
        plainPixels,
        watermarkedPixels,
        width: plain.width,
        xRange: 160..<320,
        yRange: 140..<240
      ),
      100
    )
    let watermarkedProperties = try imageProperties(at: watermarkedDestination)
    let watermarkedExif =
      watermarkedProperties[kCGImagePropertyExifDictionary]
      as? [CFString: Any]
    XCTAssertNil(watermarkedExif?[kCGImagePropertyExifLensModel])
    XCTAssertNil(watermarkedProperties[kCGImagePropertyGPSDictionary])
    XCTAssertEqual(try DeterministicImageFixture.checksum(of: source), sourceChecksum)
  }

  func testOutputSharpeningChangesRenderedPixelsWithoutChangingDimensions() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(
      in: directory,
      width: 160,
      height: 120
    )
    let plainDestination = directory.appendingPathComponent("unsharpened.jpg")
    let sharpenedDestination = directory.appendingPathComponent("sharpened.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(makeRequest(source: source, destination: plainDestination))
    _ = try await exporter.export(
      makeRequest(
        source: source,
        destination: sharpenedDestination,
        options: ExportOptions(outputSharpening: .screenHigh)
      )
    )

    let plain = try decodedImage(at: plainDestination)
    let sharpened = try decodedImage(at: sharpenedDestination)
    XCTAssertEqual([sharpened.width, sharpened.height], [plain.width, plain.height])
    XCTAssertGreaterThan(
      pixelDifferenceCount(
        try DeterministicImageFixture.rgba8Data(from: plain),
        try DeterministicImageFixture.rgba8Data(from: sharpened),
        width: plain.width,
        xRange: 0..<plain.width,
        yRange: 0..<plain.height,
        threshold: 2
      ),
      100
    )
  }

  func testExportAtomicallyReplacesExistingDestinationWithoutTemporarySibling() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("replace.jpg")
    try Data("old destination".utf8).write(to: destination)
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let exporter = AtomicJPEGExporter(decoder: decoder)

    _ = try await exporter.export(
      makeRequest(
        source: fixture.source,
        destination: destination,
        recipe: makeRecipe(operations: [.threeWayColorGrade(try makeColorGrade())])
      )
    )

    let finalData = try Data(contentsOf: destination)
    XCTAssertNotEqual(finalData, Data("old destination".utf8))
    XCTAssertNotNil(CGImageSourceCreateWithData(finalData as CFData, nil))
    let siblings = try FileManager.default.contentsOfDirectory(
      at: fixture.directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".photosuite-tmp-") })
  }

  func testPublicationFailureKeepsDestinationAndSourceAndRemovesTemporarySibling() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("failure.jpg")
    let oldDestination = Data("keep this destination".utf8)
    try oldDestination.write(to: destination)
    let sourceChecksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let decoder = try DeterministicImageFixture.makeCommonImageDecoder()
    let exporter = AtomicJPEGExporter(
      decoder: decoder,
      publisher: FailingAtomicFilePublisher()
    )

    do {
      _ = try await exporter.export(
        makeRequest(source: fixture.source, destination: destination)
      )
      XCTFail("Expected atomic write error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .atomicWriteFailed(destination))
    }

    XCTAssertEqual(try Data(contentsOf: destination), oldDestination)
    XCTAssertEqual(try DeterministicImageFixture.checksum(of: fixture.source), sourceChecksum)
    let siblings = try FileManager.default.contentsOfDirectory(
      at: fixture.directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".photosuite-tmp-") })
  }

  func testCancellationImmediatelyBeforePublicationKeepsOldDestination() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("cancelled.jpg")
    let oldDestination = Data("old destination must survive cancellation".utf8)
    try oldDestination.write(to: destination)
    let gate = SuspendedPublicationGate()
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder(),
      publisher: SystemAtomicFilePublisher(),
      publicationGate: gate
    )
    let request = makeRequest(
      source: fixture.source,
      destination: destination,
      options: ExportOptions(
        resize: .longEdge(4),
        metadata: .none,
        watermark: .text("W"),
        outputSharpening: .screenStandard
      )
    )

    let exportTask = Task {
      try await exporter.export(request)
    }
    await gate.waitUntilEntered()
    exportTask.cancel()
    await gate.release()

    do {
      _ = try await exportTask.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(try Data(contentsOf: destination), oldDestination)
    let siblings = try FileManager.default.contentsOfDirectory(
      at: fixture.directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".photosuite-tmp-") })
  }

  func testCancellationCleanupFailureReturnsFusedTypedError() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("cleanup-failure.jpg")
    let oldDestination = Data("old destination must survive cleanup failure".utf8)
    try oldDestination.write(to: destination)
    let gate = SuspendedPublicationGate()
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder(),
      publisher: SystemAtomicFilePublisher(),
      publicationGate: gate,
      temporaryFileRemover: FailingTemporaryFileRemover()
    )
    let request = makeRequest(source: fixture.source, destination: destination)
    let exportTask = Task { try await exporter.export(request) }
    await gate.waitUntilEntered()
    exportTask.cancel()
    await gate.release()

    do {
      _ = try await exportTask.value
      XCTFail("Expected fused cleanup error")
    } catch let error as RenderCoreError {
      guard case .cleanupFailed(let operation, let primaryError, let cleanupError) = error else {
        return XCTFail("Expected typed cleanup error, got \(error)")
      }
      XCTAssertEqual(operation, "export.temporary.remove")
      XCTAssertTrue(primaryError.contains("Cancellation"))
      XCTAssertTrue(cleanupError.contains("injected cleanup failure"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    XCTAssertEqual(try Data(contentsOf: destination), oldDestination)
  }

  func testSuccessfulExportDoesNotChangeSourceChecksum() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("immutable.jpg")
    let checksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(
      makeRequest(source: fixture.source, destination: destination)
    )

    XCTAssertEqual(try DeterministicImageFixture.checksum(of: fixture.source), checksum)
  }

  func testDerivativeFingerprintUsesValidatedTemporaryBytesWithoutRereadingDestination()
    async throws
  {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("mutated-after-publication.jpg")
    let archive = fixture.directory.appendingPathComponent("validated-temporary.jpg")
    let tamperedDestination = Data("publisher changed destination after moving it".utf8)
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder(),
      publisher: ArchivingMutatingPublisher(
        archiveURL: archive,
        replacementData: tamperedDestination
      )
    )

    let result = try await exporter.export(
      makeRequest(source: fixture.source, destination: destination)
    )

    let fingerprint = try XCTUnwrap(result.derivative.fingerprint)
    let archivedData = try Data(contentsOf: archive)
    XCTAssertEqual(fingerprint.sha256, try DeterministicImageFixture.checksum(of: archive))
    XCTAssertEqual(fingerprint.byteCount, UInt64(archivedData.count))
    XCTAssertEqual(try Data(contentsOf: destination), tamperedDestination)
  }

  func testArbitraryRotationCompositesTransparentCornersOverBlack() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("rotation.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    _ = try await exporter.export(
      makeRequest(
        source: fixture.source,
        destination: destination,
        recipe: makeRecipe(operations: [.rotationDegrees(45)])
      )
    )

    let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    let pixels = try DeterministicImageFixture.rgba8Data(from: image)
    let corner = DeterministicImageFixture.pixel(x: 0, y: 0, width: image.width, in: pixels)
    XCTAssertLessThan(corner.red, 24)
    XCTAssertLessThan(corner.green, 24)
    XCTAssertLessThan(corner.blue, 24)
  }

  func testExportRejectsUnsupportedFormatQualityAndSourceDestinationCollision() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("invalid.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    await assertExportError(
      exporter,
      request: ExportRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        destinationURL: destination,
        format: .unknown("avif"),
        quality: 0.9
      ),
      expected: .unsupportedExportFormat("avif")
    )
    await assertExportError(
      exporter,
      request: ExportRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        destinationURL: destination,
        format: .jpeg,
        quality: 1.1
      ),
      expected: .invalidJPEGQuality(1.1)
    )
    await assertExportError(
      exporter,
      request: makeRequest(source: fixture.source, destination: fixture.source),
      expected: .sourceDestinationConflict(fixture.source)
    )
    await assertExportError(
      exporter,
      request: makeRequest(
        source: fixture.source,
        destination: destination,
        options: ExportOptions(resize: .dimensions(width: 0, height: 10))
      ),
      expected: .invalidExportResize("Width and height must be greater than zero.")
    )
  }

  func testExportRejectsOversizedWatermarkWithoutPublishingOrChangingSource() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("invalid-watermark.jpg")
    let sourceChecksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())

    await assertExportError(
      exporter,
      request: makeRequest(
        source: fixture.source,
        destination: destination,
        options: ExportOptions(watermark: .text(String(repeating: "W", count: 257)))
      ),
      expected: .invalidWatermark("Text watermarks must contain at most 256 characters.")
    )

    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try DeterministicImageFixture.checksum(of: fixture.source), sourceChecksum)
  }

  func testExportRejectsDecoderIdentifierAndVersionPinMismatches() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("pin-mismatch.jpg")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder())
    let wrongIdentifierRecipe = EditRecipe(
      assetID: UUID(),
      pins: EnginePins(
        decoderIdentifier: "com.example.wrong",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )
    let wrongVersionRecipe = EditRecipe(
      assetID: UUID(),
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "future-common-decoder",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )

    await assertExportError(
      exporter,
      request: makeRequest(
        source: fixture.source,
        destination: destination,
        recipe: wrongIdentifierRecipe
      ),
      expected: .decoderIdentifierMismatch(
        expected: "com.example.wrong",
        actual: "com.apple.coreimage.common-image"
      )
    )
    await assertExportError(
      exporter,
      request: makeRequest(
        source: fixture.source,
        destination: destination,
        recipe: wrongVersionRecipe
      ),
      expected: .decoderVersionMismatch(
        expected: "future-common-decoder",
        actual: "system-default"
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  private func makeFixture() throws -> (directory: URL, source: URL) {
    let directory = try DeterministicImageFixture.makeDirectory()
    return (directory, try DeterministicImageFixture.makePNG(in: directory))
  }

  private func makeRequest(
    source: URL,
    destination: URL,
    recipe: EditRecipe? = nil,
    options: ExportOptions = ExportOptions()
  ) -> ExportRequest {
    ExportRequest(
      sourceURL: source,
      recipe: recipe ?? makeRecipe(),
      destinationURL: destination,
      format: .jpeg,
      quality: 0.9,
      options: options
    )
  }

  private func imageProperties(at url: URL) throws -> [CFString: Any] {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )
  }

  private func decodedImage(at url: URL) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  private func pixelDifferenceCount(
    _ lhs: Data,
    _ rhs: Data,
    width: Int,
    xRange: Range<Int>,
    yRange: Range<Int>,
    threshold: Int = 8
  ) -> Int {
    var count = 0
    for y in yRange {
      for x in xRange {
        let offset = (y * width + x) * 4
        if abs(Int(lhs[offset]) - Int(rhs[offset])) > threshold
          || abs(Int(lhs[offset + 1]) - Int(rhs[offset + 1])) > threshold
          || abs(Int(lhs[offset + 2]) - Int(rhs[offset + 2])) > threshold
        {
          count += 1
        }
      }
    }
    return count
  }

  private func makeRecipe(operations: [EditOperation] = []) -> EditRecipe {
    EditRecipe(
      assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
      revision: 3,
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
          ThreeWayColorGrade.Tone(hueDegrees: 230, chroma: 0.25, luminance: -0.1)
        ),
        midtones: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 30, chroma: 0.2, luminance: 0)
        ),
        highlights: try XCTUnwrap(
          ThreeWayColorGrade.Tone(hueDegrees: 50, chroma: 0.15, luminance: 0.1)
        )
      )
    )
  }

  private func assertExportError(
    _ exporter: AtomicJPEGExporter,
    request: ExportRequest,
    expected: RenderCoreError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await exporter.export(request)
      XCTFail("Expected export error", file: file, line: line)
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }
}

private struct FailingAtomicFilePublisher: AtomicFilePublishing {
  func publish(temporaryURL: URL, destinationURL: URL) throws {
    throw Failure.expected
  }

  enum Failure: Error {
    case expected
  }
}

private struct ArchivingMutatingPublisher: AtomicFilePublishing {
  let archiveURL: URL
  let replacementData: Data

  func publish(temporaryURL: URL, destinationURL: URL) throws {
    try FileManager.default.copyItem(at: temporaryURL, to: archiveURL)
    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    try replacementData.write(to: destinationURL)
  }
}

private struct FailingTemporaryFileRemover: TemporaryFileRemoving {
  func removeItem(at url: URL) throws {
    throw Failure.injectedCleanupFailure
  }

  enum Failure: Error, CustomStringConvertible {
    case injectedCleanupFailure

    var description: String { "injected cleanup failure" }
  }
}

private actor SuspendedPublicationGate: ExportPublicationGating {
  private var entered = false
  private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func waitBeforePublication() async {
    entered = true
    for continuation in enteredContinuations {
      continuation.resume()
    }
    enteredContinuations.removeAll()
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { continuation in
      enteredContinuations.append(continuation)
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
