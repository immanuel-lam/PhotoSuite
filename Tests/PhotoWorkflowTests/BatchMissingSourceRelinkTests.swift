// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

@MainActor
final class BatchMissingSourceRelinkTests: XCTestCase {
  func testFolderScanMatchesByFingerprintAndDisambiguatesByFilenameAfterMatch() async throws {
    let folder = try makeTemporaryFolder()
    let nestedFolder = folder.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
    let exactURL = folder.appendingPathComponent("target.jpg")
    let fallbackURL = nestedFolder.appendingPathComponent("other.jpg")
    let sameNameDifferentContentURL = folder.appendingPathComponent("other.jpg")
    try Data([1, 2, 3]).write(to: exactURL)
    try Data([1, 2, 3]).write(to: fallbackURL)
    try Data([8, 8, 8]).write(to: sameNameDifferentContentURL)

    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "a", count: 64),
        byteCount: 3,
        modificationDate: nil
      )
    )
    let differentFingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "b", count: 64),
        byteCount: 3,
        modificationDate: nil
      )
    )
    let exactAsset = makeAsset(
      id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", filename: "target.jpg", fingerprint: fingerprint)
    let fallbackAsset = makeAsset(
      id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", filename: "unseen.jpg", fingerprint: fingerprint)
    let access = BatchScopeRecorder()
    let service = BatchMissingSourceRelinkService(
      sourceAccess: SourceAccessOperations(
        persist: { _, _ in },
        resolve: { $0.sourceURL },
        start: { url in
          await access.started(url)
          return true
        },
        stop: { url in await access.stopped(url) }
      ),
      fingerprint: { url in
        if url == sameNameDifferentContentURL { return differentFingerprint }
        return fingerprint
      },
      relink: { asset, url, actual in
        await access.relinked(asset.id, url)
        return try XCTUnwrap(
          PhotoAsset(
            id: asset.id,
            sourceURL: url,
            filename: url.lastPathComponent,
            typeIdentifier: asset.typeIdentifier,
            fingerprint: actual,
            importDate: asset.importDate,
            captureDate: asset.captureDate,
            pixelDimensions: asset.pixelDimensions,
            rating: asset.rating,
            colorLabel: asset.colorLabel,
            isMissing: false,
            metadata: asset.metadata
          )
        )
      }
    )

    let result = try await service.relink(
      assets: [fallbackAsset, exactAsset],
      in: folder
    )

    XCTAssertEqual(result.scannedFileCount, 3)
    XCTAssertEqual(result.unmatched, [])
    XCTAssertEqual(result.failures, [])
    XCTAssertEqual(result.matched.map(\.assetID), [exactAsset.id, fallbackAsset.id])
    XCTAssertEqual(
      result.matched.first(where: { $0.assetID == exactAsset.id })?.replacementURL
        .lastPathComponent,
      exactURL.lastPathComponent
    )
    XCTAssertEqual(
      result.matched.first(where: { $0.assetID == fallbackAsset.id })?.replacementURL
        .lastPathComponent,
      fallbackURL.lastPathComponent
    )

    let started = await access.startedURLs()
    let canonicalStarted = Set(started.map(canonicalPath))
    let expectedStarted = Set(
      [folder, exactURL, fallbackURL, sameNameDifferentContentURL].map(canonicalPath)
    )
    XCTAssertEqual(canonicalStarted, expectedStarted)
    let startedCount = await access.startedCount()
    let stoppedCount = await access.stoppedCount()
    XCTAssertEqual(startedCount, stoppedCount)
  }

  func testFilenameAloneNeverRelinksWhenFingerprintDoesNotMatch() async throws {
    let folder = try makeTemporaryFolder()
    let candidateURL = folder.appendingPathComponent("original.jpg")
    try Data([4]).write(to: candidateURL)
    let expected = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "c", count: 64),
        byteCount: 20,
        modificationDate: nil
      )
    )
    let actual = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "d", count: 64),
        byteCount: 1,
        modificationDate: nil
      )
    )
    let asset = makeAsset(
      id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
      filename: "original.jpg",
      fingerprint: expected
    )
    let relinkCount = RelinkCountRecorder()
    let service = makeService(
      fingerprint: { _ in actual },
      relink: { _, _, _ in
        await relinkCount.increment()
        return asset
      }
    )

    let result = try await service.relink(assets: [asset], in: folder)

    XCTAssertEqual(result.matched, [])
    XCTAssertEqual(result.unmatched.map(\.assetID), [asset.id])
    let relinkCalls = await relinkCount.value()
    XCTAssertEqual(relinkCalls, 0)
  }

  func testAFailedCatalogRelinkIsReportedAndDoesNotCountAsSuccess() async throws {
    let folder = try makeTemporaryFolder()
    let successfulURL = folder.appendingPathComponent("success.jpg")
    let failedURL = folder.appendingPathComponent("failure.jpg")
    try Data([1]).write(to: successfulURL)
    try Data([2]).write(to: failedURL)
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "e", count: 64),
        byteCount: 1,
        modificationDate: nil
      )
    )
    let successfulAsset = makeAsset(
      id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
      filename: "success.jpg",
      fingerprint: fingerprint
    )
    let failedAsset = makeAsset(
      id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE",
      filename: "failure.jpg",
      fingerprint: fingerprint
    )
    let service = makeService(
      fingerprint: { _ in fingerprint },
      relink: { asset, url, actual in
        if asset.id == failedAsset.id {
          throw BatchRelinkTestError.catalogWriteFailed
        }
        return try XCTUnwrap(
          PhotoAsset(
            id: asset.id,
            sourceURL: url,
            filename: url.lastPathComponent,
            typeIdentifier: asset.typeIdentifier,
            fingerprint: actual,
            importDate: asset.importDate,
            captureDate: asset.captureDate,
            pixelDimensions: asset.pixelDimensions,
            isMissing: false,
            metadata: asset.metadata
          )
        )
      }
    )

    let result = try await service.relink(
      assets: [failedAsset, successfulAsset],
      in: folder
    )

    XCTAssertEqual(result.matched.map(\.assetID), [successfulAsset.id])
    XCTAssertEqual(result.unmatched, [])
    XCTAssertEqual(result.failures.compactMap(\.assetID), [failedAsset.id])
    XCTAssertEqual(
      result.failures.first?.candidateURL?.lastPathComponent, failedURL.lastPathComponent)
    XCTAssertTrue(result.failures.first?.message.contains("catalog") == true)
  }

  func testFolderScopeFailureStopsBeforeScanningCandidates() async throws {
    let folder = try makeTemporaryFolder()
    let candidateURL = folder.appendingPathComponent("candidate.jpg")
    try Data([1]).write(to: candidateURL)
    let access = BatchScopeRecorder()
    let service = BatchMissingSourceRelinkService(
      sourceAccess: SourceAccessOperations(
        persist: { _, _ in },
        resolve: { $0.sourceURL },
        start: { url in
          await access.started(url)
          return false
        },
        stop: { url in await access.stopped(url) }
      ),
      fingerprint: { _ in
        XCTFail("A candidate must not be fingerprinted when the folder scope fails.")
        return try XCTUnwrap(
          SourceFingerprint(
            sha256: String(repeating: "f", count: 64),
            byteCount: 1,
            modificationDate: nil
          )
        )
      },
      relink: { asset, _, _ in asset }
    )

    do {
      _ = try await service.relink(assets: [], in: folder)
      XCTFail("A folder without a security scope must be rejected.")
    } catch let error as BatchRelinkError {
      XCTAssertEqual(error, .folderScopeUnavailable(folder))
    }

    let startedURLs = await access.startedURLs()
    let stoppedURLs = await access.stoppedURLs()
    XCTAssertEqual(startedURLs, [folder])
    XCTAssertEqual(stoppedURLs, [])
  }

  func testResultCodableRoundTripPreservesTypedOutcomes() async throws {
    let folder = try makeTemporaryFolder()
    let candidateURL = folder.appendingPathComponent("photo.jpg")
    try Data([1]).write(to: candidateURL)
    let fingerprint = try XCTUnwrap(
      SourceFingerprint(
        sha256: String(repeating: "1", count: 64),
        byteCount: 1,
        modificationDate: nil
      )
    )
    let asset = makeAsset(
      id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
      filename: "photo.jpg",
      fingerprint: fingerprint
    )
    let result = try await makeService(
      fingerprint: { _ in fingerprint },
      relink: { asset, url, actual in
        try XCTUnwrap(
          PhotoAsset(
            id: asset.id,
            sourceURL: url,
            filename: url.lastPathComponent,
            typeIdentifier: asset.typeIdentifier,
            fingerprint: actual,
            importDate: asset.importDate,
            captureDate: asset.captureDate,
            pixelDimensions: asset.pixelDimensions,
            isMissing: false,
            metadata: asset.metadata
          )
        )
      }
    ).relink(assets: [asset], in: folder)
    let encoded = try JSONEncoder().encode(result)
    XCTAssertEqual(try JSONDecoder().decode(BatchRelinkResult.self, from: encoded), result)
  }
}

extension BatchMissingSourceRelinkTests {
  fileprivate func makeTemporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("photosuite-batch-relink-(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
  }

  fileprivate func makeAsset(id: String, filename: String, fingerprint: SourceFingerprint)
    -> PhotoAsset
  {
    PhotoAsset(
      id: UUID(uuidString: id)!,
      sourceURL: URL(fileURLWithPath: "/Volumes/Archive/(filename)"),
      filename: filename,
      typeIdentifier: "public.jpeg",
      fingerprint: fingerprint,
      importDate: Date(timeIntervalSince1970: 1),
      captureDate: nil,
      pixelDimensions: PixelDimensions(width: 20, height: 10)!,
      isMissing: true
    )!
  }

  fileprivate func canonicalPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
  }

  fileprivate func makeService(
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint,
    relink: @escaping @Sendable (PhotoAsset, URL, SourceFingerprint) async throws -> PhotoAsset
  ) -> BatchMissingSourceRelinkService {
    BatchMissingSourceRelinkService(
      sourceAccess: .unrestricted,
      fingerprint: fingerprint,
      relink: relink
    )
  }
}

private actor BatchScopeRecorder {
  private var startedValues: [URL] = []
  private var stoppedValues: [URL] = []
  private var relinkedValues: [(UUID, URL)] = []

  func started(_ url: URL) { startedValues.append(url) }
  func stopped(_ url: URL) { stoppedValues.append(url) }
  func relinked(_ assetID: UUID, _ url: URL) { relinkedValues.append((assetID, url)) }
  func startedURLs() -> [URL] { startedValues }
  func stoppedURLs() -> [URL] { stoppedValues }
  func startedCount() -> Int { startedValues.count }
  func stoppedCount() -> Int { stoppedValues.count }
}

private actor RelinkCountRecorder {
  private var count = 0

  func increment() { count += 1 }
  func value() -> Int { count }
}

private enum BatchRelinkTestError: Error {
  case catalogWriteFailed
}
