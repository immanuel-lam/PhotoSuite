// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

/// A successful member of a folder relink operation.
public struct BatchRelinkMatch: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let expectedFilename: String
  public let replacementURL: URL
  public let fingerprint: SourceFingerprint
  public let relinkedAsset: PhotoAsset

  public init(
    assetID: UUID,
    expectedFilename: String,
    replacementURL: URL,
    fingerprint: SourceFingerprint,
    relinkedAsset: PhotoAsset
  ) {
    self.assetID = assetID
    self.expectedFilename = expectedFilename
    self.replacementURL = replacementURL
    self.fingerprint = fingerprint
    self.relinkedAsset = relinkedAsset
  }
}

/// A missing catalog asset for which the selected folder contained no matching file.
public struct BatchRelinkUnmatched: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let expectedFilename: String

  public init(assetID: UUID, expectedFilename: String) {
    self.assetID = assetID
    self.expectedFilename = expectedFilename
  }
}

/// A candidate or catalog write which could not be completed. A failure never appears in
/// `BatchRelinkResult.matched`.
public struct BatchRelinkFailure: Codable, Hashable, Sendable {
  public let assetID: UUID?
  public let expectedFilename: String?
  public let candidateURL: URL?
  public let message: String

  public init(
    assetID: UUID?,
    expectedFilename: String?,
    candidateURL: URL?,
    message: String
  ) {
    self.assetID = assetID
    self.expectedFilename = expectedFilename
    self.candidateURL = candidateURL
    self.message = message
  }
}

/// The complete, serialisable outcome of scanning and applying a batch relink.
public struct BatchRelinkResult: Codable, Hashable, Sendable {
  public let folderURL: URL
  public let scannedFileCount: Int
  public let matched: [BatchRelinkMatch]
  public let unmatched: [BatchRelinkUnmatched]
  public let failures: [BatchRelinkFailure]

  public init(
    folderURL: URL,
    scannedFileCount: Int,
    matched: [BatchRelinkMatch],
    unmatched: [BatchRelinkUnmatched],
    failures: [BatchRelinkFailure]
  ) {
    self.folderURL = folderURL
    self.scannedFileCount = scannedFileCount
    self.matched = matched
    self.unmatched = unmatched
    self.failures = failures
  }
}

public enum BatchRelinkError: Error, Equatable, LocalizedError, Sendable {
  case invalidFolder(URL)
  case folderScopeUnavailable(URL)

  public var errorDescription: String? {
    switch self {
    case .invalidFolder:
      "Choose a local folder containing the missing source files."
    case .folderScopeUnavailable:
      "PhotoSuite could not access the selected folder. Choose it again from a local location."
    }
  }
}

/// Scans a selected folder and applies only fingerprint-verified relinks.
///
/// The folder and every candidate file are opened through the injected security-scope
/// operations. Candidate selection is based on SHA-256 and byte count. Filename is used
/// only to choose deterministically between candidates that already have the same content
/// fingerprint; it is never used as an identity by itself. The relink closure is expected
/// to perform one catalog transaction per asset and returns the durable catalog value only
/// after that transaction succeeds.
public struct BatchMissingSourceRelinkService: Sendable {
  public typealias Fingerprint = @Sendable (URL) async throws -> SourceFingerprint
  public typealias Relink =
    @Sendable (PhotoAsset, URL, SourceFingerprint) async throws -> PhotoAsset

  private let sourceAccess: SourceAccessOperations
  private let fingerprint: Fingerprint
  private let relink: Relink

  public init(
    sourceAccess: SourceAccessOperations,
    fingerprint: @escaping Fingerprint,
    relink: @escaping Relink
  ) {
    self.sourceAccess = sourceAccess
    self.fingerprint = fingerprint
    self.relink = relink
  }

  public func relink(
    assets: [PhotoAsset],
    in folderURL: URL
  ) async throws -> BatchRelinkResult {
    guard isDirectory(folderURL) else {
      throw BatchRelinkError.invalidFolder(folderURL)
    }

    let folderStarted = await sourceAccess.start(folderURL)
    guard folderStarted else {
      throw BatchRelinkError.folderScopeUnavailable(folderURL)
    }

    do {
      let result = try await performRelink(assets: assets, folderURL: folderURL)
      await sourceAccess.stop(folderURL)
      return result
    } catch {
      await sourceAccess.stop(folderURL)
      throw error
    }
  }

  private func performRelink(
    assets: [PhotoAsset],
    folderURL: URL
  ) async throws -> BatchRelinkResult {
    let candidateURLs = enumerateFiles(in: folderURL)
    var candidates: [Candidate] = []
    var failures: [BatchRelinkFailure] = []

    for url in candidateURLs {
      try Task.checkCancellation()
      let started = await sourceAccess.start(url)
      guard started else {
        failures.append(
          BatchRelinkFailure(
            assetID: nil,
            expectedFilename: nil,
            candidateURL: url,
            message: "The candidate file could not be opened in a security scope."
          )
        )
        continue
      }

      do {
        let sourceFingerprint = try await fingerprint(url)
        candidates.append(
          Candidate(url: url, fingerprint: sourceFingerprint)
        )
        await sourceAccess.stop(url)
      } catch is CancellationError {
        await sourceAccess.stop(url)
        throw CancellationError()
      } catch {
        await sourceAccess.stop(url)
        failures.append(
          BatchRelinkFailure(
            assetID: nil,
            expectedFilename: nil,
            candidateURL: url,
            message: "The candidate file could not be fingerprinted: \(error.localizedDescription)"
          )
        )
      }
    }

    var matched: [BatchRelinkMatch] = []
    var unmatched: [BatchRelinkUnmatched] = []
    let missingAssets =
      assets
      .filter(\.isMissing)
      .sorted { lhs, rhs in
        if lhs.filename != rhs.filename { return lhs.filename < rhs.filename }
        return lhs.id.uuidString < rhs.id.uuidString
      }

    for asset in missingAssets {
      try Task.checkCancellation()
      let matchingCandidates = candidates.filter {
        FingerprintIdentity($0.fingerprint) == FingerprintIdentity(asset.fingerprint)
      }
      guard !matchingCandidates.isEmpty else {
        unmatched.append(
          BatchRelinkUnmatched(assetID: asset.id, expectedFilename: asset.filename)
        )
        continue
      }

      let candidate = matchingCandidates.sorted { lhs, rhs in
        let lhsFilenameMatch = lhs.url.lastPathComponent == asset.filename
        let rhsFilenameMatch = rhs.url.lastPathComponent == asset.filename
        if lhsFilenameMatch != rhsFilenameMatch { return lhsFilenameMatch }
        return lhs.url.path < rhs.url.path
      }.first!

      let relinkStarted = await sourceAccess.start(candidate.url)
      guard relinkStarted else {
        failures.append(
          BatchRelinkFailure(
            assetID: asset.id,
            expectedFilename: asset.filename,
            candidateURL: candidate.url,
            message: "The matched file could not be reopened in a security scope."
          )
        )
        continue
      }

      do {
        let relinkedAsset = try await relink(asset, candidate.url, candidate.fingerprint)
        await sourceAccess.stop(candidate.url)
        matched.append(
          BatchRelinkMatch(
            assetID: asset.id,
            expectedFilename: asset.filename,
            replacementURL: candidate.url,
            fingerprint: candidate.fingerprint,
            relinkedAsset: relinkedAsset
          )
        )
      } catch is CancellationError {
        await sourceAccess.stop(candidate.url)
        throw CancellationError()
      } catch {
        await sourceAccess.stop(candidate.url)
        failures.append(
          BatchRelinkFailure(
            assetID: asset.id,
            expectedFilename: asset.filename,
            candidateURL: candidate.url,
            message: "The catalog could not save this relink: \(error.localizedDescription)"
          )
        )
      }
    }

    return BatchRelinkResult(
      folderURL: folderURL,
      scannedFileCount: candidateURLs.count,
      matched: matched,
      unmatched: unmatched,
      failures: failures
    )
  }

  private func isDirectory(_ url: URL) -> Bool {
    guard url.isFileURL, !url.path.isEmpty else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func enumerateFiles(in folderURL: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    let urls =
      FileManager.default.enumerator(
        at: folderURL,
        includingPropertiesForKeys: keys,
        options: options,
        errorHandler: { _, _ in true }
      )?.compactMap { item -> URL? in
        guard let url = item as? URL else { return nil }
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        guard values.isDirectory != true else { return nil }
        guard values.isRegularFile != false else { return nil }
        return url
      } ?? []
    return urls.sorted { $0.path < $1.path }
  }
}

private struct Candidate: Sendable {
  let url: URL
  let fingerprint: SourceFingerprint
}

private struct FingerprintIdentity: Hashable, Sendable {
  let sha256: String
  let byteCount: UInt64

  init(_ fingerprint: SourceFingerprint) {
    sha256 = fingerprint.sha256
    byteCount = fingerprint.byteCount
  }
}
