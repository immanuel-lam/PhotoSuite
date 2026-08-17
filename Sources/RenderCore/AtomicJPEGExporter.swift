// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

protocol AtomicFilePublishing: Sendable {
  func publish(temporaryURL: URL, destinationURL: URL) throws
}

protocol ExportPublicationGating: Sendable {
  func waitBeforePublication() async
}

protocol TemporaryFileRemoving: Sendable {
  func removeItem(at url: URL) throws
}

struct ImmediateExportPublicationGate: ExportPublicationGating {
  func waitBeforePublication() async {}
}

struct SystemTemporaryFileRemover: TemporaryFileRemoving {
  func removeItem(at url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }
}

struct SystemAtomicFilePublisher: AtomicFilePublishing {
  func publish(temporaryURL: URL, destinationURL: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destinationURL.path) {
      _ = try fileManager.replaceItemAt(
        destinationURL,
        withItemAt: temporaryURL,
        backupItemName: nil,
        options: []
      )
    } else {
      try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
  }
}

/// The default ImageIO-backed exporter. The historic type name is retained for
/// source compatibility; it now supports JPEG, PNG, HEIF, and TIFF requests.
public struct AtomicJPEGExporter: Exporter, Sendable {
  private let decoder: AppleRawDecoder
  private let publisher: any AtomicFilePublishing
  private let publicationGate: any ExportPublicationGating
  private let temporaryFileRemover: any TemporaryFileRemoving

  public init(decoder: AppleRawDecoder) {
    self.decoder = decoder
    self.publisher = SystemAtomicFilePublisher()
    self.publicationGate = ImmediateExportPublicationGate()
    self.temporaryFileRemover = SystemTemporaryFileRemover()
  }

  init(
    decoder: AppleRawDecoder,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating = ImmediateExportPublicationGate(),
    temporaryFileRemover: any TemporaryFileRemoving = SystemTemporaryFileRemover()
  ) {
    self.decoder = decoder
    self.publisher = publisher
    self.publicationGate = publicationGate
    self.temporaryFileRemover = temporaryFileRemover
  }

  public func export(_ request: ExportRequest) async throws -> ExportResult {
    try await decoder.exportImage(
      request,
      publisher: publisher,
      publicationGate: publicationGate,
      temporaryFileRemover: temporaryFileRemover
    )
  }
}

/// Executes export requests in order. Each output uses the wrapped exporter's
/// atomic publication boundary. Cancellation is checked before every request.
public struct AtomicBatchExporter: BatchExporter, Sendable {
  private let exporter: any Exporter

  public init(exporter: any Exporter) {
    self.exporter = exporter
  }

  public func export(_ request: BatchExportRequest) async throws -> BatchExportResult {
    var destinations: Set<URL> = []
    var results: [ExportResult] = []
    results.reserveCapacity(request.requests.count)

    for exportRequest in request.requests {
      let destination = exportRequest.destinationURL.standardizedFileURL.resolvingSymlinksInPath()
      guard destinations.insert(destination).inserted else {
        throw RenderCoreError.duplicateBatchDestination(exportRequest.destinationURL)
      }
    }

    for exportRequest in request.requests {
      try Task.checkCancellation()
      results.append(try await exporter.export(exportRequest))
    }

    return BatchExportResult(results: results)
  }
}
