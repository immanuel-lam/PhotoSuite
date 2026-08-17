// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CatalogCore
import Foundation
import PhotoDomain

/// The three source-handling choices exposed by the Library import workflow.
///
/// `.add` keeps the selected file at its current URL. `.copy` and `.move` use a destination
/// folder and preserve the original filename where it is available. Moving is intentionally
/// explicit because it removes the original only after the destination has been verified.
public enum PhotoImportMode: Codable, Hashable, Sendable {
  case add
  case copy(to: URL)
  case move(to: URL)

  public var destinationFolder: URL? {
    switch self {
    case .add: nil
    case .copy(let url), .move(let url): url
    }
  }

  public var title: String {
    switch self {
    case .add: "Add"
    case .copy: "Copy"
    case .move: "Move"
    }
  }
}

/// The import duplicate policy compares only immutable content identity: SHA-256 and byte count.
/// File names and modification dates do not determine duplicate status.
public enum PhotoImportDuplicatePolicy: String, Codable, Hashable, Sendable {
  case skip
  case allow
}

public struct PhotoImportRequest: Codable, Hashable, Sendable {
  public let urls: [URL]
  public let mode: PhotoImportMode
  public let duplicatePolicy: PhotoImportDuplicatePolicy
  public let existingAssets: [PhotoAsset]

  public init(
    urls: [URL],
    mode: PhotoImportMode = .add,
    duplicatePolicy: PhotoImportDuplicatePolicy = .skip,
    existingAssets: [PhotoAsset] = []
  ) {
    self.urls = urls.map(\.standardizedFileURL)
    self.mode = mode
    self.duplicatePolicy = duplicatePolicy
    self.existingAssets = existingAssets
  }
}

public struct PhotoImportItem: Hashable, Sendable {
  public let sourceURL: URL
  public let catalogURL: URL
  public let fingerprint: SourceFingerprint

  public init(sourceURL: URL, catalogURL: URL, fingerprint: SourceFingerprint) {
    self.sourceURL = sourceURL
    self.catalogURL = catalogURL
    self.fingerprint = fingerprint
  }
}

public struct PhotoImportDuplicate: Hashable, Sendable {
  public let sourceURL: URL
  public let fingerprint: SourceFingerprint
  public let existingAssetID: UUID?
  public let existingSourceURL: URL?

  public init(
    sourceURL: URL,
    fingerprint: SourceFingerprint,
    existingAssetID: UUID? = nil,
    existingSourceURL: URL? = nil
  ) {
    self.sourceURL = sourceURL
    self.fingerprint = fingerprint
    self.existingAssetID = existingAssetID
    self.existingSourceURL = existingSourceURL
  }
}

public struct PhotoImportFailure: Hashable, Sendable {
  public let sourceURL: URL
  public let message: String

  public init(sourceURL: URL, message: String) {
    self.sourceURL = sourceURL
    self.message = message
  }
}

public struct PhotoImportResult: Hashable, Sendable {
  public let imported: [PhotoImportItem]
  public let duplicates: [PhotoImportDuplicate]
  public let failures: [PhotoImportFailure]

  public init(
    imported: [PhotoImportItem],
    duplicates: [PhotoImportDuplicate],
    failures: [PhotoImportFailure]
  ) {
    self.imported = imported
    self.duplicates = duplicates
    self.failures = failures
  }
}

/// Async security-scope boundary shared by the import service and the main workspace. The
/// existing capture adapter remains synchronous; the convenience initializer below preserves it
/// while allowing catalog-backed access to use its async bookmark operations.
public struct PhotoImportSourceAccess: Sendable {
  public let start: @Sendable (URL) async -> Bool
  public let stop: @Sendable (URL) async -> Void

  public init(
    start: @escaping @Sendable (URL) async -> Bool,
    stop: @escaping @Sendable (URL) async -> Void
  ) {
    self.start = start
    self.stop = stop
  }

  public init(captureAccess: CaptureSourceAccess) {
    self.init(
      start: { url in captureAccess.start(url) },
      stop: { url in captureAccess.stop(url) }
    )
  }

  public init(workspaceAccess: SourceAccessOperations) {
    self.init(start: workspaceAccess.start, stop: workspaceAccess.stop)
  }

  public static let securityScoped = PhotoImportSourceAccess(
    start: { url in url.startAccessingSecurityScopedResource() },
    stop: { url in url.stopAccessingSecurityScopedResource() }
  )
}

public enum PhotoImportError: Error, LocalizedError, Sendable, Equatable {
  case invalidSource(URL)
  case securityScopeDenied(URL)
  case invalidDestination(URL)
  case transferFailed(URL, String)
  case verificationFailed(URL)
  case removeFailed(URL, String)

  public var errorDescription: String? {
    switch self {
    case .invalidSource(let url): "The import source is not a readable file: \(url.path)."
    case .securityScopeDenied(let url):
      "PhotoSuite could not access the selected source: \(url.path)."
    case .invalidDestination(let url):
      "The import destination is not a file-system folder: \(url.path)."
    case .transferFailed(let url, let message):
      "Could not transfer \(url.lastPathComponent): \(message)"
    case .verificationFailed(let url):
      "The transferred file failed checksum verification: \(url.lastPathComponent)."
    case .removeFailed(let url, let message):
      "Could not remove the original after a verified move (\(url.lastPathComponent)): \(message)"
    }
  }
}

/// File-system operations used by import. The default copy writes to a temporary file in the
/// destination folder and publishes it with a same-volume rename, so readers never observe a
/// partially copied destination. Tests can inject a deterministic operation without touching the
/// real file system.
public struct PhotoImportFileOperations: Sendable {
  public let copyAtomically: @Sendable (URL, URL) throws -> Void
  public let remove: @Sendable (URL) throws -> Void

  public init(
    copyAtomically: @escaping @Sendable (URL, URL) throws -> Void = Self.defaultCopy,
    remove: @escaping @Sendable (URL) throws -> Void = { url in
      try FileManager.default.removeItem(at: url)
    }
  ) {
    self.copyAtomically = copyAtomically
    self.remove = remove
  }

  public static func defaultCopy(sourceURL: URL, destinationURL: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporaryURL = destinationURL.deletingLastPathComponent()
      .appendingPathComponent(".photosuite-import-\(UUID().uuidString).tmp")
    defer { try? fileManager.removeItem(at: temporaryURL) }
    try fileManager.copyItem(at: sourceURL, to: temporaryURL)
    if let handle = try? FileHandle(forWritingTo: temporaryURL) {
      try? handle.synchronize()
      try? handle.close()
    }
    try fileManager.moveItem(at: temporaryURL, to: destinationURL)
  }
}

/// A cancellable, security-scoped import transaction. Non-cancellation failures are reported per
/// source so a batch can continue; cancellation propagates and always releases the active scope.
public actor PhotoImportService {
  private let sourceAccess: PhotoImportSourceAccess
  private let fileOperations: PhotoImportFileOperations
  private let fingerprint: @Sendable (URL) async throws -> SourceFingerprint

  public init(
    sourceAccess: PhotoImportSourceAccess = .securityScoped,
    fileOperations: PhotoImportFileOperations = PhotoImportFileOperations(),
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint = { url in
      try SourceFingerprinter.fingerprint(url: url)
    }
  ) {
    self.sourceAccess = sourceAccess
    self.fileOperations = fileOperations
    self.fingerprint = fingerprint
  }

  public init(
    sourceAccess: CaptureSourceAccess,
    fileOperations: PhotoImportFileOperations = PhotoImportFileOperations(),
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint = { url in
      try SourceFingerprinter.fingerprint(url: url)
    }
  ) {
    self.init(
      sourceAccess: PhotoImportSourceAccess(captureAccess: sourceAccess),
      fileOperations: fileOperations,
      fingerprint: fingerprint
    )
  }

  public func `import`(_ request: PhotoImportRequest) async throws -> PhotoImportResult {
    var imported: [PhotoImportItem] = []
    var duplicates: [PhotoImportDuplicate] = []
    var failures: [PhotoImportFailure] = []
    var knownAssets: [String: PhotoAsset] = [:]
    var knownURLs: [String: URL] = [:]

    for asset in request.existingAssets {
      knownAssets[fingerprintKey(asset.fingerprint)] = asset
    }

    for sourceURL in request.urls {
      try Task.checkCancellation()
      let started = await sourceAccess.start(sourceURL)
      guard started else {
        failures.append(
          PhotoImportFailure(
            sourceURL: sourceURL,
            message: PhotoImportError.securityScopeDenied(sourceURL).localizedDescription
          )
        )
        continue
      }
      var transferURL: URL?
      do {
        guard sourceURL.isFileURL else {
          throw PhotoImportError.invalidSource(sourceURL)
        }
        let sourceFingerprint = try await fingerprint(sourceURL)
        try Task.checkCancellation()
        let key = fingerprintKey(sourceFingerprint)

        if request.duplicatePolicy == .skip {
          if let existingAsset = knownAssets[key] {
            duplicates.append(
              PhotoImportDuplicate(
                sourceURL: sourceURL,
                fingerprint: sourceFingerprint,
                existingAssetID: existingAsset.id,
                existingSourceURL: existingAsset.sourceURL
              )
            )
            await sourceAccess.stop(sourceURL)
            continue
          }
          if let previousURL = knownURLs[key] {
            duplicates.append(
              PhotoImportDuplicate(
                sourceURL: sourceURL,
                fingerprint: sourceFingerprint,
                existingSourceURL: previousURL
              )
            )
            await sourceAccess.stop(sourceURL)
            continue
          }
        }

        let catalogURL = try destinationURL(for: sourceURL, mode: request.mode)
        if catalogURL.standardizedFileURL != sourceURL.standardizedFileURL {
          transferURL = catalogURL
          do {
            try fileOperations.copyAtomically(sourceURL, catalogURL)
          } catch is CancellationError {
            try? fileOperations.remove(catalogURL)
            throw CancellationError()
          } catch {
            try? fileOperations.remove(catalogURL)
            throw PhotoImportError.transferFailed(sourceURL, error.localizedDescription)
          }

          try Task.checkCancellation()
          let destinationFingerprint = try await fingerprint(catalogURL)
          guard sameContent(sourceFingerprint, destinationFingerprint) else {
            try? fileOperations.remove(catalogURL)
            throw PhotoImportError.verificationFailed(catalogURL)
          }

          if case .move = request.mode {
            try Task.checkCancellation()
            do {
              try fileOperations.remove(sourceURL)
            } catch {
              try? fileOperations.remove(catalogURL)
              throw PhotoImportError.removeFailed(sourceURL, error.localizedDescription)
            }
          }
        }

        imported.append(
          PhotoImportItem(
            sourceURL: sourceURL,
            catalogURL: catalogURL,
            fingerprint: sourceFingerprint
          )
        )
        knownURLs[key] = catalogURL
        await sourceAccess.stop(sourceURL)
      } catch is CancellationError {
        if let transferURL {
          try? fileOperations.remove(transferURL)
        }
        await sourceAccess.stop(sourceURL)
        throw CancellationError()
      } catch {
        await sourceAccess.stop(sourceURL)
        failures.append(
          PhotoImportFailure(sourceURL: sourceURL, message: error.localizedDescription)
        )
      }
    }

    return PhotoImportResult(imported: imported, duplicates: duplicates, failures: failures)
  }

  private func destinationURL(for sourceURL: URL, mode: PhotoImportMode) throws -> URL {
    guard let destinationFolder = mode.destinationFolder else { return sourceURL }
    guard destinationFolder.isFileURL else {
      throw PhotoImportError.invalidDestination(destinationFolder)
    }
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    let original = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
    guard fileManager.fileExists(atPath: original.path) else { return original }
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    for index in 2...10_000 {
      let suffix = pathExtension.isEmpty ? "-\(index)" : "-\(index).\(pathExtension)"
      let candidate = destinationFolder.appendingPathComponent("\(baseName)\(suffix)")
      if !fileManager.fileExists(atPath: candidate.path) { return candidate }
    }
    throw PhotoImportError.invalidDestination(destinationFolder)
  }

  private func fingerprintKey(_ fingerprint: SourceFingerprint) -> String {
    "\(fingerprint.sha256):\(fingerprint.byteCount)"
  }

  private func sameContent(_ lhs: SourceFingerprint, _ rhs: SourceFingerprint) -> Bool {
    lhs.sha256 == rhs.sha256 && lhs.byteCount == rhs.byteCount
  }
}
