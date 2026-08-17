// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

public enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
  case library
  case develop
  case deliver

  public var id: Self { self }
}

public enum AdjustmentKind: String, CaseIterable, Identifiable, Sendable {
  case exposure
  case contrast
  case highlights
  case shadows
  case saturation

  public var id: Self { self }
}

public struct SourceProbe: Hashable, Sendable {
  public let dimensions: PixelDimensions
  public let pins: EnginePins
  public let typeIdentifier: String?

  public init(dimensions: PixelDimensions, pins: EnginePins, typeIdentifier: String?) {
    self.dimensions = dimensions
    self.pins = pins
    self.typeIdentifier = typeIdentifier
  }
}

public struct SourceAccessOperations: Sendable {
  public let persist: @Sendable (UUID, URL) async throws -> Void
  public let resolve: @Sendable (PhotoAsset) async throws -> URL
  public let start: @Sendable (URL) async -> Bool
  public let stop: @Sendable (URL) async -> Void

  public init(
    persist: @escaping @Sendable (UUID, URL) async throws -> Void,
    resolve: @escaping @Sendable (PhotoAsset) async throws -> URL,
    start: @escaping @Sendable (URL) async -> Bool,
    stop: @escaping @Sendable (URL) async -> Void
  ) {
    self.persist = persist
    self.resolve = resolve
    self.start = start
    self.stop = stop
  }

  public static let unrestricted = SourceAccessOperations(
    persist: { _, _ in },
    resolve: { $0.sourceURL },
    start: { _ in true },
    stop: { _ in }
  )
}

public struct PreviewFrame: Hashable, Sendable {
  public let imageData: Data
  public let typeIdentifier: String
  public let pixelDimensions: PixelDimensions
  public let histogram: RenderHistogram?

  public init(
    imageData: Data,
    typeIdentifier: String,
    pixelDimensions: PixelDimensions,
    histogram: RenderHistogram? = nil
  ) {
    self.imageData = imageData
    self.typeIdentifier = typeIdentifier
    self.pixelDimensions = pixelDimensions
    self.histogram = histogram
  }

  init(_ result: RenderResult) {
    self.init(
      imageData: result.imageData,
      typeIdentifier: result.typeIdentifier,
      pixelDimensions: result.pixelDimensions,
      histogram: result.histogram
    )
  }
}

public struct WorkspaceItemError: Identifiable, Hashable, Sendable {
  public let id: UUID
  public let sourceURL: URL
  public let message: String

  public init(id: UUID = UUID(), sourceURL: URL, message: String) {
    self.id = id
    self.sourceURL = sourceURL
    self.message = message
  }
}

public enum PhotoWorkspaceError: Error, Equatable, LocalizedError, Sendable {
  case invalidAsset(URL)
  case recipeMissing(UUID)
  case sourceMissing(URL)
  case invalidSelection(UUID)
  case invalidAdjustment(String)
  case noSelection(operation: String)
  case unknownOperationsBlockEditing
  case operationFailed(operation: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .invalidAsset(let url): "Could not create an asset for \(url.lastPathComponent)."
    case .recipeMissing: "The selected photograph has no edit recipe."
    case .sourceMissing(let url): "The source file is missing: \(url.lastPathComponent)."
    case .invalidSelection: "The selected photograph is not in the catalog."
    case .invalidAdjustment(let name): "The \(name) adjustment value is invalid."
    case .noSelection(let operation): "Select a photograph before you use \(operation)."
    case .unknownOperationsBlockEditing:
      "This recipe contains edits from a newer version. PhotoSuite did not change it."
    case .operationFailed(let operation, let message): "\(operation): \(message)"
    }
  }
}
