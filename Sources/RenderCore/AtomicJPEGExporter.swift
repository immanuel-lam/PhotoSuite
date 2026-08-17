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

struct ImmediateExportPublicationGate: ExportPublicationGating {
  func waitBeforePublication() async {}
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

public struct AtomicJPEGExporter: Exporter, Sendable {
  private let decoder: AppleRawDecoder
  private let publisher: any AtomicFilePublishing
  private let publicationGate: any ExportPublicationGating

  public init(decoder: AppleRawDecoder) {
    self.decoder = decoder
    self.publisher = SystemAtomicFilePublisher()
    self.publicationGate = ImmediateExportPublicationGate()
  }

  init(
    decoder: AppleRawDecoder,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating = ImmediateExportPublicationGate()
  ) {
    self.decoder = decoder
    self.publisher = publisher
    self.publicationGate = publicationGate
  }

  public func export(_ request: ExportRequest) async throws -> ExportResult {
    try await decoder.exportJPEG(
      request,
      publisher: publisher,
      publicationGate: publicationGate
    )
  }
}
