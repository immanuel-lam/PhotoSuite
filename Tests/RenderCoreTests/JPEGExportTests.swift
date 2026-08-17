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
    let decoder = try AppleRawDecoder()
    let exporter = AtomicJPEGExporter(decoder: decoder)
    let crop = try XCTUnwrap(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
    let recipe = makeRecipe(operations: [.normalizedCrop(crop), .rotationDegrees(90)])
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

  func testExportAtomicallyReplacesExistingDestinationWithoutTemporarySibling() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("replace.jpg")
    try Data("old destination".utf8).write(to: destination)
    let decoder = try AppleRawDecoder()
    let exporter = AtomicJPEGExporter(decoder: decoder)

    _ = try await exporter.export(
      makeRequest(source: fixture.source, destination: destination)
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
    let decoder = try AppleRawDecoder()
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
      decoder: try AppleRawDecoder(),
      publisher: SystemAtomicFilePublisher(),
      publicationGate: gate
    )
    let request = makeRequest(source: fixture.source, destination: destination)

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

  func testSuccessfulExportDoesNotChangeSourceChecksum() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("immutable.jpg")
    let checksum = try DeterministicImageFixture.checksum(of: fixture.source)
    let exporter = AtomicJPEGExporter(decoder: try AppleRawDecoder())

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
      decoder: try AppleRawDecoder(),
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
    let exporter = AtomicJPEGExporter(decoder: try AppleRawDecoder())

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
    let exporter = AtomicJPEGExporter(decoder: try AppleRawDecoder())

    await assertExportError(
      exporter,
      request: ExportRequest(
        sourceURL: fixture.source,
        recipe: makeRecipe(),
        destinationURL: destination,
        format: .heif,
        quality: 0.9
      ),
      expected: .unsupportedExportFormat("heif")
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
  }

  func testExportRejectsDecoderIdentifierAndVersionPinMismatches() async throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let destination = fixture.directory.appendingPathComponent("pin-mismatch.jpg")
    let exporter = AtomicJPEGExporter(decoder: try AppleRawDecoder())
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
    recipe: EditRecipe? = nil
  ) -> ExportRequest {
    ExportRequest(
      sourceURL: source,
      recipe: recipe ?? makeRecipe(),
      destinationURL: destination,
      format: .jpeg,
      quality: 0.9
    )
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
