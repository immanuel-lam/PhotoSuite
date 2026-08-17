// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

final class MetadataSidecarServiceTests: XCTestCase {
  func testExportUsesSecurityScopeAndLeavesSourceBytesUnchanged() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("capture.jpg")
    let sourceData = Data("immutable capture".utf8)
    try sourceData.write(to: sourceURL)
    let metadata = try XCTUnwrap(
      PhotoMetadata(title: "Harbour", creator: "PhotoSuite", keywords: ["Sydney"]))
    let scope = ScopeRecorder(allowed: true)

    let result = try await makeService(scope: scope).export(
      metadata: metadata,
      for: sourceURL
    )

    XCTAssertEqual(result.sourceURL, sourceURL)
    XCTAssertEqual(result.sidecarURL, directory.appendingPathComponent("capture.xmp"))
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertEqual(try XMPMetadataSidecar.read(from: result.sidecarURL), metadata)
    let events = await scope.events()
    XCTAssertEqual(events, [.start(sourceURL), .stop(sourceURL)])
  }

  func testExportRejectsUnavailableSecurityScopeBeforeWriting() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("capture.jpg")
    try Data("source".utf8).write(to: sourceURL)
    let sidecarURL = XMPMetadataSidecar.sidecarURL(for: sourceURL)
    let scope = ScopeRecorder(allowed: false)

    do {
      _ = try await makeService(scope: scope).export(metadata: .empty, for: sourceURL)
      XCTFail("Expected unavailable source scope to reject export.")
    } catch {
      XCTAssertEqual(error as? MetadataSidecarError, .sourceScopeUnavailable(sourceURL))
    }

    XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    let events = await scope.events()
    XCTAssertEqual(events, [.start(sourceURL)])
  }

  func testImportRejectsUnavailableSecurityScopeBeforeReading() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sidecarURL = directory.appendingPathComponent("capture.xmp")
    let sidecarXML =
      "<?xml version=\"1.0\"?><photosuite:metadata "
      + "xmlns:photosuite=\"https://photosuite.app/ns/1.0/\">"
      + "<photosuite:title>Title</photosuite:title></photosuite:metadata>"
    try Data(sidecarXML.utf8).write(to: sidecarURL)
    let scope = ScopeRecorder(allowed: false)

    do {
      _ = try await makeService(scope: scope).`import`(from: sidecarURL)
      XCTFail("Expected unavailable sidecar scope to reject import.")
    } catch {
      XCTAssertEqual(error as? MetadataSidecarError, .sidecarScopeUnavailable(sidecarURL))
    }

    let events = await scope.events()
    XCTAssertEqual(events, [.start(sidecarURL)])
  }

  func testImportUsesSecurityScopeAndReturnsMetadata() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("capture.arw")
    try Data("raw source".utf8).write(to: sourceURL)
    let sidecarURL = try XMPMetadataSidecar.write(
      PhotoMetadata(title: "Imported", keywords: ["one", "two"])!,
      for: sourceURL
    )
    let scope = ScopeRecorder(allowed: true)

    let result = try await makeService(scope: scope).`import`(from: sidecarURL)

    XCTAssertEqual(result.sidecarURL, sidecarURL)
    XCTAssertEqual(result.metadata.title, "Imported")
    XCTAssertEqual(result.metadata.keywords, ["one", "two"])
    let events = await scope.events()
    XCTAssertEqual(events, [.start(sidecarURL), .stop(sidecarURL)])
  }

  private func makeService(scope: ScopeRecorder) -> MetadataSidecarService {
    MetadataSidecarService(
      sourceAccess: SourceAccessOperations(
        persist: { _, _ in },
        resolve: { $0.sourceURL },
        start: { url in await scope.start(url) },
        stop: { url in await scope.stop(url) }
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-MetadataSidecar-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}

private actor ScopeRecorder {
  enum Event: Equatable, Sendable {
    case start(URL)
    case stop(URL)
  }

  private let allowed: Bool
  private var recordedEvents: [Event] = []

  init(allowed: Bool) {
    self.allowed = allowed
  }

  func start(_ url: URL) -> Bool {
    recordedEvents.append(.start(url))
    return allowed
  }

  func stop(_ url: URL) {
    recordedEvents.append(.stop(url))
  }

  func events() -> [Event] {
    recordedEvents
  }
}
