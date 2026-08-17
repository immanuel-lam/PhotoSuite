// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CatalogCore
import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

final class ImportManagementTests: XCTestCase {
  func testImportModeAndRequestRoundTripPreservesMoveIntent() throws {
    let request = PhotoImportRequest(
      urls: [URL(fileURLWithPath: "/Volumes/Card/IMG_0001.CR3")],
      mode: .move(to: URL(fileURLWithPath: "/Volumes/PhotoLibrary/Originals")),
      duplicatePolicy: .skip
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(PhotoImportRequest.self, from: data)

    XCTAssertEqual(decoded, request)
    XCTAssertEqual(decoded.mode.title, "Move")
  }

  func testAddModeReferencesTheOriginalAndLeavesItsBytesUntouched() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("add.jpg")
    let bytes = Data("add-source".utf8)
    try bytes.write(to: source)
    let access = ImportAccessRecorder()

    let result = try await PhotoImportService(
      sourceAccess: access.operations
    ).import(
      PhotoImportRequest(urls: [source], mode: .add)
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.imported[0].sourceURL, source)
    XCTAssertEqual(result.imported[0].catalogURL, source)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertEqual(access.started, [source])
    XCTAssertEqual(access.stopped, [source])
  }

  func testCopyModeUsesAnAtomicDestinationAndPreservesTheOriginal() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("copy.ARW")
    let destination = fixture.root.appendingPathComponent("managed")
    let bytes = Data(repeating: 17, count: 512)
    try bytes.write(to: source)
    let access = ImportAccessRecorder()

    let result = try await PhotoImportService(sourceAccess: access.operations).import(
      PhotoImportRequest(urls: [source], mode: .copy(to: destination))
    )

    XCTAssertEqual(result.imported.count, 1)
    let copiedURL = try XCTUnwrap(result.imported.first?.catalogURL)
    XCTAssertEqual(
      copiedURL.deletingLastPathComponent().standardizedFileURL,
      destination.standardizedFileURL
    )
    XCTAssertEqual(try Data(contentsOf: copiedURL), bytes)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
  }

  func testMoveModeIsExplicitAndRemovesTheOriginalOnlyAfterVerifiedCopy() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("move.RAF")
    let destination = fixture.root.appendingPathComponent("managed")
    let bytes = Data(repeating: 29, count: 256)
    try bytes.write(to: source)
    let access = ImportAccessRecorder()

    let result = try await PhotoImportService(sourceAccess: access.operations).import(
      PhotoImportRequest(urls: [source], mode: .move(to: destination))
    )

    let movedURL = try XCTUnwrap(result.imported.first?.catalogURL)
    XCTAssertEqual(try Data(contentsOf: movedURL), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertEqual(result.imported.first?.fingerprint.byteCount, UInt64(bytes.count))
  }

  func testDuplicatePolicySkipsASecondSourceWithTheSameFingerprintBeforeTransfer() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("duplicate.jpg")
    try Data("same-bytes".utf8).write(to: source)
    let fingerprint = try SourceFingerprinter.fingerprint(url: source)
    let existing = try XCTUnwrap(
      PhotoAsset(
        sourceURL: fixture.root.appendingPathComponent("existing.jpg"),
        filename: "existing.jpg",
        typeIdentifier: "public.jpeg",
        fingerprint: fingerprint,
        importDate: Date(timeIntervalSince1970: 1),
        captureDate: nil,
        pixelDimensions: nil
      )
    )
    let operations = ImportFileOperationRecorder()

    let result = try await PhotoImportService(
      fileOperations: operations.operations
    ).import(
      PhotoImportRequest(
        urls: [source],
        mode: .copy(to: fixture.root.appendingPathComponent("managed")),
        existingAssets: [existing]
      )
    )

    XCTAssertTrue(result.imported.isEmpty)
    XCTAssertEqual(result.duplicates.count, 1)
    XCTAssertEqual(result.duplicates[0].existingAssetID, existing.id)
    XCTAssertTrue(operations.copies.isEmpty)
  }

  func testCancellationStopsSecurityScopeAndDoesNotMutateSource() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("cancel.jpg")
    let bytes = Data(repeating: 3, count: 128)
    try bytes.write(to: source)
    let access = ImportAccessRecorder()
    let service = PhotoImportService(
      sourceAccess: access.operations,
      fingerprint: { _ in
        try await Task.sleep(for: .seconds(30))
        return SourceFingerprint(
          sha256: String(repeating: "a", count: 64), byteCount: 128, modificationDate: nil
        )!
      }
    )

    let request = PhotoImportRequest(urls: [source], mode: .move(to: fixture.root))
    let task = Task { try await service.import(request) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("A cancelled import must throw CancellationError.")
    } catch is CancellationError {
      // Expected.
    }
    XCTAssertEqual(access.started, [source])
    XCTAssertEqual(access.stopped, [source])
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  func testFailedVerificationRollsBackTheDestinationAndKeepsMoveSource() async throws {
    let fixture = try ImportFixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("verify.jpg")
    try Data("source".utf8).write(to: source)
    let destinationFolder = fixture.root.appendingPathComponent("managed")
    let operations = PhotoImportFileOperations(
      copyAtomically: { sourceURL, destinationURL in
        try FileManager.default.createDirectory(
          at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("tampered".utf8).write(to: destinationURL)
      }
    )

    let access = ImportAccessRecorder()
    let result = try await PhotoImportService(
      sourceAccess: access.operations,
      fileOperations: operations
    ).import(
      PhotoImportRequest(urls: [source], mode: .move(to: destinationFolder))
    )

    XCTAssertTrue(result.imported.isEmpty)
    XCTAssertEqual(result.failures.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: destinationFolder.appendingPathComponent("verify.jpg").path
      )
    )
  }
}

private final class ImportFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuiteImportTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

private final class ImportAccessRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var started: [URL] = []
  private(set) var stopped: [URL] = []

  var operations: CaptureSourceAccess {
    CaptureSourceAccess(
      persist: { _, _ in },
      start: { [weak self] url in
        self?.lock.lock()
        self?.started.append(url)
        self?.lock.unlock()
        return true
      },
      stop: { [weak self] url in
        self?.lock.lock()
        self?.stopped.append(url)
        self?.lock.unlock()
      }
    )
  }
}

private final class ImportFileOperationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var copies: [(URL, URL)] = []

  var operations: PhotoImportFileOperations {
    PhotoImportFileOperations(
      copyAtomically: { [weak self] source, destination in
        self?.lock.lock()
        self?.copies.append((source, destination))
        self?.lock.unlock()
      }
    )
  }
}
