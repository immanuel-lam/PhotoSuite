// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

/// Errors returned by the bounded XMP sidecar workflow.
///
/// These errors describe sidecar interchange and security-scope failures. They do not claim that
/// PhotoSuite can write embedded XMP or every IPTC/EXIF field supported by Lightroom.
public enum MetadataSidecarError: Error, Equatable, LocalizedError, Sendable {
  case noSelection
  case metadataStoreUnavailable
  case catalogUpdateFailed(String)
  case sourceScopeUnavailable(URL)
  case sidecarScopeUnavailable(URL)
  case malformed(URL)
  case invalidValue(URL)
  case writeFailed(URL)

  public var errorDescription: String? {
    switch self {
    case .noSelection:
      "Select a photograph before using XMP sidecar actions."
    case .metadataStoreUnavailable:
      "The current catalog does not support durable metadata editing."
    case .catalogUpdateFailed(let message):
      "The imported metadata could not be saved: \(message)"
    case .sourceScopeUnavailable(let url):
      "PhotoSuite could not obtain access to the source file: \(url.lastPathComponent)."
    case .sidecarScopeUnavailable(let url):
      "PhotoSuite could not obtain access to the XMP sidecar: \(url.lastPathComponent)."
    case .malformed(let url):
      "The XMP sidecar is malformed or uses an unsupported schema: \(url.lastPathComponent)."
    case .invalidValue(let url):
      "The XMP sidecar contains an invalid metadata value: \(url.lastPathComponent)."
    case .writeFailed(let url):
      "The XMP sidecar could not be written atomically: \(url.lastPathComponent)."
    }
  }
}

public struct MetadataSidecarExportResult: Equatable, Sendable {
  public let sourceURL: URL
  public let sidecarURL: URL

  public init(sourceURL: URL, sidecarURL: URL) {
    self.sourceURL = sourceURL
    self.sidecarURL = sidecarURL
  }
}

public struct MetadataSidecarImportResult: Equatable, Sendable {
  public let sidecarURL: URL
  public let metadata: PhotoMetadata

  public init(sidecarURL: URL, metadata: PhotoMetadata) {
    self.sidecarURL = sidecarURL
    self.metadata = metadata
  }
}

public enum MetadataSidecarStatus: Equatable, Sendable {
  case idle
  case exporting
  case exported(MetadataSidecarExportResult)
  case importing(URL)
  case imported(MetadataSidecarImportResult)
  case failed(MetadataSidecarError)

  public var message: String {
    switch self {
    case .idle:
      "XMP sidecars stay separate from the source file."
    case .exporting:
      "Writing XMP sidecar…"
    case .exported(let result):
      "XMP sidecar saved as \(result.sidecarURL.lastPathComponent)."
    case .importing:
      "Reading XMP sidecar…"
    case .imported(let result):
      "Imported metadata from \(result.sidecarURL.lastPathComponent)."
    case .failed(let error):
      error.localizedDescription
    }
  }
}

/// Performs security-scoped XMP sidecar interchange without opening or mutating the source file.
public struct MetadataSidecarService: Sendable {
  private let start: @Sendable (URL) async -> Bool
  private let stop: @Sendable (URL) async -> Void

  public init(sourceAccess: SourceAccessOperations) {
    self.start = sourceAccess.start
    self.stop = sourceAccess.stop
  }

  public func export(
    metadata: PhotoMetadata,
    for sourceURL: URL
  ) async throws -> MetadataSidecarExportResult {
    guard await start(sourceURL) else {
      throw MetadataSidecarError.sourceScopeUnavailable(sourceURL)
    }
    do {
      let sidecarURL = try XMPMetadataSidecar.write(metadata, for: sourceURL)
      await stop(sourceURL)
      return MetadataSidecarExportResult(sourceURL: sourceURL, sidecarURL: sidecarURL)
    } catch {
      await stop(sourceURL)
      throw map(error, url: XMPMetadataSidecar.sidecarURL(for: sourceURL))
    }
  }

  public func `import`(from sidecarURL: URL) async throws -> MetadataSidecarImportResult {
    guard await start(sidecarURL) else {
      throw MetadataSidecarError.sidecarScopeUnavailable(sidecarURL)
    }
    do {
      let metadata = try XMPMetadataSidecar.read(from: sidecarURL)
      await stop(sidecarURL)
      return MetadataSidecarImportResult(sidecarURL: sidecarURL, metadata: metadata)
    } catch {
      await stop(sidecarURL)
      throw map(error, url: sidecarURL)
    }
  }

  private func map(_ error: any Error, url: URL) -> MetadataSidecarError {
    switch error as? XMPMetadataSidecarError {
    case .malformed:
      .malformed(url)
    case .invalidValue:
      .invalidValue(url)
    case .writeFailed:
      .writeFailed(url)
    case nil:
      .writeFailed(url)
    }
  }
}
