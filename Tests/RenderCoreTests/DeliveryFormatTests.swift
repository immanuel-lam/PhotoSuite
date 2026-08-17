// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ImageIO
import PhotoDomain
import UniformTypeIdentifiers
import XCTest

@testable import RenderCore

final class DeliveryFormatTests: XCTestCase {
  func testPNGExportPublishesResizedImageWithICCProfile() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(
      in: directory,
      width: 8,
      height: 6
    )
    let destination = directory.appendingPathComponent("export.png")
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder()
    )

    let result = try await exporter.export(
      ExportRequest(
        sourceURL: source,
        recipe: makeRecipe(),
        destinationURL: destination,
        format: .png,
        quality: nil,
        options: ExportOptions(resize: .longEdge(4), metadata: .none)
      )
    )

    let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.png.identifier)
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    XCTAssertEqual([image.width, image.height], [4, 3])
    let properties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
    )
    XCTAssertTrue(
      try XCTUnwrap(properties[kCGImagePropertyProfileName] as? String)
        .localizedCaseInsensitiveContains("srgb")
    )
    XCTAssertEqual(result.derivative.typeIdentifier, UTType.png.identifier)
  }

  func testTIFFExportRetainsAllowedMetadataAndHEIFUsesNativeType() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makeMetadataTIFF(in: directory)
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder()
    )

    let tiffDestination = directory.appendingPathComponent("export.tiff")
    _ = try await exporter.export(
      ExportRequest(
        sourceURL: source,
        recipe: makeRecipe(),
        destinationURL: tiffDestination,
        format: .tiff,
        quality: nil,
        options: ExportOptions(metadata: .all)
      )
    )
    let tiffSource = try XCTUnwrap(CGImageSourceCreateWithURL(tiffDestination as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(tiffSource) as String?, UTType.tiff.identifier)
    let tiffProperties = try XCTUnwrap(
      CGImageSourceCopyPropertiesAtIndex(tiffSource, 0, nil) as? [CFString: Any]
    )
    let tiffExif = try XCTUnwrap(
      tiffProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    )
    XCTAssertEqual(
      tiffExif[kCGImagePropertyExifLensModel] as? String,
      "PhotoSuite Test Lens"
    )

    let heifDestination = directory.appendingPathComponent("export.heic")
    _ = try await exporter.export(
      ExportRequest(
        sourceURL: source,
        recipe: makeRecipe(),
        destinationURL: heifDestination,
        format: .heif,
        quality: 0.8,
        options: ExportOptions(metadata: .none)
      )
    )
    let heifSource = try XCTUnwrap(CGImageSourceCreateWithURL(heifDestination as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(heifSource) as String?, UTType.heic.identifier)
  }

  func testPNGCancellationBeforePublicationKeepsExistingDestination() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let destination = directory.appendingPathComponent("cancelled.png")
    let original = Data("keep this output".utf8)
    try original.write(to: destination)
    let gate = HeldPublicationGate()
    let exporter = AtomicJPEGExporter(
      decoder: try DeterministicImageFixture.makeCommonImageDecoder(),
      publisher: SystemAtomicFilePublisher(),
      publicationGate: gate
    )
    let request = ExportRequest(
      sourceURL: source,
      recipe: makeRecipe(),
      destinationURL: destination,
      format: .png,
      quality: nil
    )
    let task = Task { try await exporter.export(request) }
    await gate.waitUntilEntered()
    task.cancel()
    await gate.release()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }
    XCTAssertEqual(try Data(contentsOf: destination), original)
    let siblings = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".photosuite-tmp-") })
  }

  func testBatchExportPublishesCompletedPrefixAndPreservesAtomicOutputs() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let first = directory.appendingPathComponent("first.png")
    let second = directory.appendingPathComponent("second.tiff")
    let exporter = AtomicBatchExporter(
      exporter: AtomicJPEGExporter(
        decoder: try DeterministicImageFixture.makeCommonImageDecoder()
      )
    )

    let result = try await exporter.export(
      BatchExportRequest(
        requests: [
          ExportRequest(
            sourceURL: source,
            recipe: makeRecipe(),
            destinationURL: first,
            format: .png,
            quality: nil
          ),
          ExportRequest(
            sourceURL: source,
            recipe: makeRecipe(),
            destinationURL: second,
            format: .tiff,
            quality: nil
          ),
        ]
      )
    )

    XCTAssertEqual(result.results.count, 2)
    XCTAssertEqual(result.results.map(\.derivative.outputURL), [first, second])
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    let siblings = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
    XCTAssertFalse(siblings.contains { $0.lastPathComponent.contains(".photosuite-tmp-") })
  }

  func testBatchExportChecksCancellationBeforePublication() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let destination = directory.appendingPathComponent("cancelled.png")
    let exporter = AtomicBatchExporter(
      exporter: AtomicJPEGExporter(
        decoder: try DeterministicImageFixture.makeCommonImageDecoder()
      )
    )
    let request = BatchExportRequest(
      requests: [
        ExportRequest(
          sourceURL: source,
          recipe: makeRecipe(),
          destinationURL: destination,
          format: .png,
          quality: nil
        )
      ]
    )
    let task = Task {
      try await exporter.export(request)
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  func testBatchExportRejectsDuplicateDestinationsBeforeRendering() async throws {
    let directory = try DeterministicImageFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try DeterministicImageFixture.makePNG(in: directory)
    let destination = directory.appendingPathComponent("duplicate.png")
    let exporter = AtomicBatchExporter(
      exporter: AtomicJPEGExporter(
        decoder: try DeterministicImageFixture.makeCommonImageDecoder()
      )
    )
    let request = ExportRequest(
      sourceURL: source,
      recipe: makeRecipe(),
      destinationURL: destination,
      format: .png,
      quality: nil
    )

    do {
      _ = try await exporter.export(BatchExportRequest(requests: [request, request]))
      XCTFail("Expected duplicate destination error")
    } catch let error as RenderCoreError {
      XCTAssertEqual(error, .duplicateBatchDestination(destination))
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  private func makeRecipe() -> EditRecipe {
    EditRecipe(
      assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
      revision: 1,
      pins: EnginePins(
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )
  }
}

private actor HeldPublicationGate: ExportPublicationGating {
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
    if entered { return }
    await withCheckedContinuation { continuation in
      enteredContinuations.append(continuation)
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
