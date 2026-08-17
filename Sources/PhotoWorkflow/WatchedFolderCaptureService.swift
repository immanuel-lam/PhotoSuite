// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CatalogCore
import Foundation
import PhotoDomain

public enum CaptureImportError: Error, LocalizedError, Sendable {
  case invalidFolder(URL)
  case securityScopeDenied(URL)
  case invalidAsset(URL)
  case copyFailed(URL, String)

  public var errorDescription: String? {
    switch self {
    case .invalidFolder(let url): "The watched folder is invalid: \(url.path)."
    case .securityScopeDenied(let url):
      "PhotoSuite could not access the watched folder: \(url.path)."
    case .invalidAsset(let url): "PhotoSuite could not create a catalog asset for \(url.path)."
    case .copyFailed(let url, let message): "Could not copy \(url.lastPathComponent): \(message)"
    }
  }
}

/// Imports files from a user-selected folder without modifying the originals. A scan is safe to
/// repeat: source fingerprints are checked against catalog assets before a new asset is created.
public actor WatchedFolderCaptureService {
  private struct FileObservation: Sendable {
    let info: CaptureFileInfo
    let firstObservedAt: Date
  }

  private let catalog: any CatalogStore
  private let sourceAccess: CaptureSourceAccess
  private let fileOperations: CaptureFolderFileOperations
  private let bookmarkOperations: CaptureBookmarkOperations
  private let fingerprint: @Sendable (URL) async throws -> SourceFingerprint
  private let probe: @Sendable (URL) async throws -> SourceProbe
  private let now: @Sendable () -> Date
  private let configuration: CaptureFolderConfiguration

  private var observations: [URL: FileObservation] = [:]
  private var watchTask: Task<Void, Never>?
  private var lastError: String?
  private var currentBookmarkData: Data?

  public init(
    configuration: CaptureFolderConfiguration,
    catalog: any CatalogStore,
    sourceAccess: CaptureSourceAccess = .securityScoped,
    fileOperations: CaptureFolderFileOperations = CaptureFolderFileOperations(),
    bookmarkOperations: CaptureBookmarkOperations = .securityScoped,
    fingerprint: @escaping @Sendable (URL) async throws -> SourceFingerprint = { url in
      try SourceFingerprinter.fingerprint(url: url)
    },
    probe: @escaping @Sendable (URL) async throws -> SourceProbe,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.configuration = configuration
    self.catalog = catalog
    self.sourceAccess = sourceAccess
    self.fileOperations = fileOperations
    self.bookmarkOperations = bookmarkOperations
    self.fingerprint = fingerprint
    self.probe = probe
    self.now = now
    currentBookmarkData = configuration.bookmarkData
  }

  deinit {
    watchTask?.cancel()
  }

  public func start() {
    guard watchTask == nil else { return }
    watchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          _ = try await self.scanOnce()
          await self.clearLastScanError()
        } catch is CancellationError {
          return
        } catch {
          await self.setLastScanError(error.localizedDescription)
        }

        do {
          try await Task.sleep(for: .seconds(self.configuration.pollInterval))
        } catch {
          return
        }
      }
    }
  }

  public func stop() async {
    guard let watchTask else { return }
    watchTask.cancel()
    await watchTask.value
    self.watchTask = nil
  }

  public func isRunning() -> Bool {
    watchTask != nil
  }

  public func lastScanErrorMessage() -> String? {
    lastError
  }

  /// A stale security-scoped bookmark is renewed by `SecurityScopedBookmarkStore`. The caller
  /// must persist this value in its catalog-side bookmark record.
  public func renewedBookmarkData() -> Data? {
    currentBookmarkData
  }

  public func scanOnce() async throws -> CaptureScanResult {
    try Task.checkCancellation()

    let resolved = try resolveFolder()
    let folderURL = resolved.url.standardizedFileURL
    guard folderURL.isFileURL else {
      throw CaptureImportError.invalidFolder(folderURL)
    }
    currentBookmarkData = resolved.renewedData ?? currentBookmarkData

    let started = sourceAccess.start(folderURL)
    guard started else {
      throw CaptureImportError.securityScopeDenied(folderURL)
    }
    defer { sourceAccess.stop(folderURL) }

    let entries = try fileOperations.listFiles(folderURL)
    let candidates = try stableCandidates(from: entries)
    let existingAssets = try await catalog.listAssets(
      CatalogAssetListRequest(order: .importDateDescending)
    ).assets
    // Modification time is useful for integrity diagnostics but is not part of duplicate
    // identity. A camera or file system can rewrite that value while keeping the same bytes.
    var knownFingerprintKeys = Set(existingAssets.map { fingerprintKey($0.fingerprint) })

    var imported: [PhotoAsset] = []
    var duplicates: [URL] = []
    var skipped: [URL] = []
    var pending: [URL] = []
    var failures: [CaptureImportFailure] = []

    for candidate in candidates {
      try Task.checkCancellation()
      guard candidate.isReady else {
        pending.append(candidate.url)
        continue
      }

      do {
        let sourceFingerprint = try await fingerprint(candidate.url)
        try Task.checkCancellation()
        if knownFingerprintKeys.contains(fingerprintKey(sourceFingerprint)) {
          duplicates.append(candidate.url)
          observations.removeValue(forKey: candidate.url)
          continue
        }

        let importURL: URL
        switch configuration.destination {
        case .reference:
          importURL = candidate.url
        case .copy(to: let destinationFolder):
          importURL = try copyToDestination(candidate.url, destinationFolder)
        }

        let sourceProbe = try await probe(importURL)
        guard
          let asset = PhotoAsset(
            sourceURL: importURL,
            filename: importURL.lastPathComponent,
            typeIdentifier: sourceProbe.typeIdentifier,
            fingerprint: sourceFingerprint,
            importDate: now(),
            captureDate: candidate.info.modificationDate,
            pixelDimensions: sourceProbe.dimensions
          )
        else {
          throw CaptureImportError.invalidAsset(importURL)
        }

        _ = try await catalog.upsertAsset(CatalogAssetUpsertRequest(asset: asset))
        let recipe = EditRecipe(assetID: asset.id, date: now(), pins: sourceProbe.pins)
        _ = try await catalog.saveRecipe(CatalogRecipeSaveRequest(recipe: recipe))

        var visibleAsset = asset
        do {
          try await sourceAccess.persist(asset.id, importURL)
        } catch {
          // The image is imported, but the next app launch cannot resolve the source safely. Keep
          // the catalog record and make that boundary explicit instead of silently losing it.
          visibleAsset =
            PhotoAsset(
              id: asset.id,
              sourceURL: asset.sourceURL,
              filename: asset.filename,
              typeIdentifier: asset.typeIdentifier,
              fingerprint: asset.fingerprint,
              importDate: asset.importDate,
              captureDate: asset.captureDate,
              pixelDimensions: asset.pixelDimensions,
              rating: asset.rating,
              colorLabel: asset.colorLabel,
              isMissing: true,
              metadata: asset.metadata
            ) ?? asset
          _ = try? await catalog.upsertAsset(CatalogAssetUpsertRequest(asset: visibleAsset))
          failures.append(
            CaptureImportFailure(
              sourceURL: importURL,
              message: "Bookmark: \(error.localizedDescription)"
            )
          )
        }

        imported.append(visibleAsset)
        knownFingerprintKeys.insert(fingerprintKey(sourceFingerprint))
        observations.removeValue(forKey: candidate.url)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        failures.append(
          CaptureImportFailure(sourceURL: candidate.url, message: error.localizedDescription)
        )
      }
    }

    skipped.append(contentsOf: candidates.filter { !$0.isSupported }.map(\.url))
    return CaptureScanResult(
      imported: imported,
      duplicates: duplicates,
      skipped: skipped,
      pending: pending,
      failures: failures,
      renewedBookmarkData: resolved.renewedData
    )
  }

  private struct Candidate: Sendable {
    let url: URL
    let info: CaptureFileInfo
    let isSupported: Bool
    let isReady: Bool
  }

  private func stableCandidates(from entries: [URL]) throws -> [Candidate] {
    var candidates: [Candidate] = []
    let currentDate = now()

    for entry in entries.sorted(by: {
      $0.path.localizedStandardCompare($1.path) == .orderedAscending
    }) {
      try Task.checkCancellation()
      let filename = entry.lastPathComponent
      if !configuration.includeHiddenFiles, filename.hasPrefix(".") {
        continue
      }
      let info = try fileOperations.fileInfo(entry)
      guard info.isRegularFile else { continue }

      let extensionName = entry.pathExtension.lowercased()
      guard configuration.allowedExtensions.contains(extensionName) else {
        candidates.append(Candidate(url: entry, info: info, isSupported: false, isReady: false))
        continue
      }

      let previous = observations[entry]
      let isUnchanged = previous?.info == info
      if !isUnchanged {
        observations[entry] = FileObservation(info: info, firstObservedAt: currentDate)
      }
      let firstObservedAt = observations[entry]?.firstObservedAt ?? currentDate
      let elapsed = max(0, currentDate.timeIntervalSince(firstObservedAt))
      let isReady = configuration.settleInterval == 0 || elapsed >= configuration.settleInterval
      candidates.append(Candidate(url: entry, info: info, isSupported: true, isReady: isReady))
    }

    return candidates
  }

  private func resolveFolder() throws -> ResolvedSecurityScopedBookmark {
    guard let bookmarkData = currentBookmarkData else {
      return ResolvedSecurityScopedBookmark(
        url: configuration.folderURL, isStale: false, renewedData: nil)
    }
    return try bookmarkOperations.resolve(bookmarkData)
  }

  private func fingerprintKey(_ fingerprint: SourceFingerprint) -> String {
    "\(fingerprint.sha256):\(fingerprint.byteCount)"
  }

  private func copyToDestination(_ sourceURL: URL, _ destinationFolder: URL) throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    var destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
    if fileManager.fileExists(atPath: destinationURL.path) {
      let baseName = sourceURL.deletingPathExtension().lastPathComponent
      let extensionName = sourceURL.pathExtension
      let suffix = UUID().uuidString.prefix(8)
      destinationURL = destinationFolder.appendingPathComponent(
        "\(baseName)-\(suffix).\(extensionName)"
      )
    }

    do {
      try fileOperations.copy(sourceURL, destinationURL)
      return destinationURL
    } catch {
      throw CaptureImportError.copyFailed(sourceURL, error.localizedDescription)
    }
  }

  private func clearLastScanError() {
    lastError = nil
  }

  private func setLastScanError(_ message: String) {
    lastError = message
  }
}
