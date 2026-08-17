// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

public enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
  case library
  case develop
  case deliver
  case workspace

  public var id: Self { self }
}

public enum ProfessionalTool: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case map
  case tether
  case print
  case book
  case slideshow
  case webGallery
  case plugins
  case adobeMigration

  public var id: Self { self }
}

public enum ProfessionalCapabilityBlocker: String, Codable, Hashable, Sendable {
  case locationMetadataUnavailable
  case selectionRequired
  case cameraAdapterRequired
  case bookExportUnavailable
  case webPublishingUnavailable
  case pluginHostUnavailable
  case adobeCatalogParserUnavailable
}

public enum ProfessionalCapabilityStatus: Codable, Hashable, Sendable {
  case available
  case previewOnly(ProfessionalCapabilityBlocker)
  case unavailable(ProfessionalCapabilityBlocker)
}

public struct PhotoCoordinate: Codable, Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init?(latitude: Double, longitude: Double) {
    guard latitude.isFinite, longitude.isFinite,
      (-90...90).contains(latitude),
      (-180...180).contains(longitude)
    else {
      return nil
    }
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct PhotoLocation: Codable, Hashable, Identifiable, Sendable {
  public let assetID: UUID
  public let filename: String
  public let coordinate: PhotoCoordinate

  public var id: UUID { assetID }

  public init(assetID: UUID, filename: String, coordinate: PhotoCoordinate) {
    self.assetID = assetID
    self.filename = filename
    self.coordinate = coordinate
  }
}

public enum AdjustmentKind: String, CaseIterable, Identifiable, Sendable {
  case exposure
  case contrast
  case highlights
  case shadows
  case saturation

  public var id: Self { self }
}

public enum DevelopAdjustmentFamily: String, CaseIterable, Identifiable, Sendable {
  case toneCurve
  case whiteBalance
  case transform
  case detail
  case optics
  case effects
  case calibration
  case blackAndWhite
  case hdr

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

public struct LibrarySmartFilter: Codable, Hashable, Sendable {
  public var minimumRating: Int
  public var colorLabels: Set<ColorLabel>
  public var showMissingOnly: Bool

  public init(
    minimumRating: Int = 0,
    colorLabels: Set<ColorLabel> = [],
    showMissingOnly: Bool = false
  ) {
    self.minimumRating = min(max(minimumRating, 0), 5)
    self.colorLabels = colorLabels
    self.showMissingOnly = showMissingOnly
  }

  public var isActive: Bool {
    minimumRating > 0 || !colorLabels.isEmpty || showMissingOnly
  }

  public func matches(_ asset: PhotoAsset) -> Bool {
    guard asset.rating >= minimumRating else { return false }
    if !colorLabels.isEmpty {
      guard let label = asset.colorLabel, colorLabels.contains(label) else { return false }
    }
    if showMissingOnly, !asset.isMissing { return false }
    return true
  }
}

public struct LibraryCollection: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var name: String
  public var assetIDs: [UUID]

  public init(id: UUID = UUID(), name: String, assetIDs: [UUID] = []) {
    self.id = id
    self.name = name
    self.assetIDs = assetIDs
  }
}

public struct LibraryStack: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var name: String
  public var assetIDs: [UUID]
  public var isExpanded: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    assetIDs: [UUID],
    isExpanded: Bool = true
  ) {
    self.id = id
    self.name = name
    self.assetIDs = assetIDs
    self.isExpanded = isExpanded
  }
}

public enum DeliverResize: Codable, Hashable, Sendable {
  case original
  case longEdge(Int)
  case dimensions(width: Int, height: Int)
}

public enum DeliverMetadata: String, Codable, CaseIterable, Hashable, Sendable {
  case basic
  case copyrightOnly
  case all
  case none
}

public enum DeliverWatermark: Codable, Hashable, Sendable {
  case none
  case text(String)
}

public enum DeliverOutputSharpening: String, Codable, CaseIterable, Hashable, Sendable {
  case none
  case screenStandard
  case screenHigh
  case printStandard
}

public struct DeliverOptions: Codable, Hashable, Sendable {
  public var resize: DeliverResize
  public var metadata: DeliverMetadata
  public var watermark: DeliverWatermark
  public var outputSharpening: DeliverOutputSharpening

  public init(
    resize: DeliverResize = .original,
    metadata: DeliverMetadata = .basic,
    watermark: DeliverWatermark = .none,
    outputSharpening: DeliverOutputSharpening = .none
  ) {
    self.resize = resize
    self.metadata = metadata
    self.watermark = watermark
    self.outputSharpening = outputSharpening
  }

  public var unsupportedFeatures: [String] {
    []
  }

  public var exportOptions: ExportOptions {
    ExportOptions(
      resize: {
        switch resize {
        case .original: .original
        case .longEdge(let pixels): .longEdge(pixels)
        case .dimensions(let width, let height): .dimensions(width: width, height: height)
        }
      }(),
      metadata: {
        switch metadata {
        case .basic: .basic
        case .copyrightOnly: .copyrightOnly
        case .all: .all
        case .none: .none
        }
      }(),
      watermark: {
        switch watermark {
        case .none: .none
        case .text(let value): .text(value)
        }
      }(),
      outputSharpening: {
        switch outputSharpening {
        case .none: .none
        case .screenStandard: .screenStandard
        case .screenHigh: .screenHigh
        case .printStandard: .printStandard
        }
      }()
    )
  }
}

public enum PhotoWorkspaceError: Error, Equatable, LocalizedError, Sendable {
  case invalidAsset(URL)
  case recipeMissing(UUID)
  case sourceMissing(URL)
  case invalidSelection(UUID)
  case invalidAdjustment(String)
  case invalidRating(Int)
  case noSelection(operation: String)
  case unknownOperationsBlockEditing
  case unsupportedDeliverOptions([String])
  case operationFailed(operation: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .invalidAsset(let url): "Could not create an asset for \(url.lastPathComponent)."
    case .recipeMissing: "The selected photograph has no edit recipe."
    case .sourceMissing(let url): "The source file is missing: \(url.lastPathComponent)."
    case .invalidSelection: "The selected photograph is not in the catalog."
    case .invalidAdjustment(let name): "The \(name) adjustment value is invalid."
    case .invalidRating(let rating): "Rating \(rating) is outside the range 0 through 5."
    case .noSelection(let operation): "Select a photograph before you use \(operation)."
    case .unknownOperationsBlockEditing:
      "This recipe contains edits from a newer version. PhotoSuite did not change it."
    case .unsupportedDeliverOptions(let features):
      "The current JPEG engine does not support: \(features.joined(separator: ", "))."
    case .operationFailed(let operation, let message): "\(operation): \(message)"
    }
  }
}
