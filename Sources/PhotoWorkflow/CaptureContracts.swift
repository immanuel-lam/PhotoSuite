// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CatalogCore
import Foundation
import PhotoDomain

// MARK: - Camera discovery

/// A stable identifier supplied by ImageCaptureCore or by an installed camera adapter.
public struct CaptureDeviceID: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    self.rawValue = trimmed.isEmpty ? "unknown-camera" : trimmed
  }

  public var description: String { rawValue }
}

public enum CaptureDeviceState: Codable, Hashable, Sendable {
  case discovered
  case ready
  case capturing
  case unavailable(String)
  case failed(String)
}

public struct CaptureDeviceStatus: Codable, Hashable, Sendable, Identifiable {
  public let id: CaptureDeviceID
  public let name: String
  public let productKind: String?
  public let transportType: String?
  public let locationDescription: String?
  public let serialNumber: String?
  public let state: CaptureDeviceState
  public let hasOpenSession: Bool
  public let supportsTetheredCapture: Bool
  public let batteryLevel: Int?
  public let mediaFileCount: Int?

  public init(
    id: CaptureDeviceID,
    name: String,
    productKind: String?,
    transportType: String?,
    locationDescription: String?,
    serialNumber: String?,
    state: CaptureDeviceState,
    hasOpenSession: Bool,
    supportsTetheredCapture: Bool,
    batteryLevel: Int?,
    mediaFileCount: Int?
  ) {
    self.id = id
    self.name = name
    self.productKind = productKind
    self.transportType = transportType
    self.locationDescription = locationDescription
    self.serialNumber = serialNumber
    self.state = state
    self.hasOpenSession = hasOpenSession
    self.supportsTetheredCapture = supportsTetheredCapture
    self.batteryLevel = batteryLevel.flatMap { (0...100).contains($0) ? $0 : nil }
    self.mediaFileCount = mediaFileCount.flatMap { $0 >= 0 ? $0 : nil }
  }
}

public struct CaptureMediaItem: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let deviceID: CaptureDeviceID
  public let filename: String
  public let typeIdentifier: String?
  public let fileURL: URL?
  public let isRaw: Bool
  public let creationDate: Date?

  public init(
    id: String,
    deviceID: CaptureDeviceID,
    filename: String,
    typeIdentifier: String?,
    fileURL: URL?,
    isRaw: Bool,
    creationDate: Date?
  ) {
    self.id = id
    self.deviceID = deviceID
    self.filename = filename
    self.typeIdentifier = typeIdentifier
    self.fileURL = fileURL
    self.isRaw = isRaw
    self.creationDate = creationDate
  }
}

public enum CaptureDeviceChange: Codable, Hashable, Sendable {
  case added(CaptureDeviceStatus)
  case removed(CaptureDeviceID)
  case updated(CaptureDeviceStatus)
  case mediaAdded(deviceID: CaptureDeviceID, items: [CaptureMediaItem])
}

public enum CaptureDeviceError: Error, LocalizedError, Sendable, Equatable {
  case deviceNotFound(CaptureDeviceID)
  case captureUnavailable(CaptureDeviceID)
  case browserUnavailable
  case operationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .deviceNotFound(let id): "Camera \(id) was not found."
    case .captureUnavailable(let id): "Camera \(id) does not support tethered capture."
    case .browserUnavailable: "ImageCaptureCore is not available on this Mac."
    case .operationFailed(let message): message
    }
  }
}

/// The native discovery adapter is main-actor isolated because ImageCaptureCore delivers
/// delegate callbacks on the main thread.
@MainActor
public protocol CameraDeviceDiscovery: AnyObject {
  var devices: [CaptureDeviceStatus] { get }

  func start()
  func stop()
  func requestCapture(deviceID: CaptureDeviceID) throws
  func makeEventStream() -> AsyncStream<CaptureDeviceChange>
}

// MARK: - Watched-folder import

public enum CaptureImportDestination: Codable, Hashable, Sendable {
  /// Keep the source in place. The original remains immutable and is represented by a bookmark.
  case reference
  /// Copy to a PhotoSuite-managed folder before cataloguing the copy.
  case copy(to: URL)
}

public struct CaptureFolderConfiguration: Codable, Hashable, Sendable {
  public static let defaultExtensions: Set<String> = [
    "arw", "cr2", "cr3", "dng", "raf", "rw2", "nef", "orf", "raw",
    "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff",
  ]

  public let folderURL: URL
  public let bookmarkData: Data?
  public let allowedExtensions: Set<String>
  public let includeHiddenFiles: Bool
  public let settleInterval: TimeInterval
  public let pollInterval: TimeInterval
  public let destination: CaptureImportDestination

  public init(
    folderURL: URL,
    bookmarkData: Data? = nil,
    allowedExtensions: Set<String> = CaptureFolderConfiguration.defaultExtensions,
    includeHiddenFiles: Bool = false,
    settleInterval: TimeInterval = 1.5,
    pollInterval: TimeInterval = 2.0,
    destination: CaptureImportDestination = .reference
  ) {
    self.folderURL = folderURL.standardizedFileURL
    self.bookmarkData = bookmarkData
    self.allowedExtensions = Set(allowedExtensions.map { $0.lowercased() })
    self.includeHiddenFiles = includeHiddenFiles
    self.settleInterval = max(0, settleInterval)
    self.pollInterval = max(0.01, pollInterval)
    self.destination = destination
  }
}

public struct CaptureSourceAccess: Sendable {
  public let persist: @Sendable (UUID, URL) async throws -> Void
  public let start: @Sendable (URL) -> Bool
  public let stop: @Sendable (URL) -> Void

  public init(
    persist: @escaping @Sendable (UUID, URL) async throws -> Void,
    start: @escaping @Sendable (URL) -> Bool,
    stop: @escaping @Sendable (URL) -> Void
  ) {
    self.persist = persist
    self.start = start
    self.stop = stop
  }

  public static let securityScoped = CaptureSourceAccess(
    persist: { _, _ in },
    start: { $0.startAccessingSecurityScopedResource() },
    stop: { $0.stopAccessingSecurityScopedResource() }
  )
}

public struct CaptureFileInfo: Hashable, Sendable {
  public let byteCount: UInt64
  public let modificationDate: Date?
  public let isRegularFile: Bool

  public init(byteCount: UInt64, modificationDate: Date?, isRegularFile: Bool) {
    self.byteCount = byteCount
    self.modificationDate = modificationDate
    self.isRegularFile = isRegularFile
  }
}

/// File-system operations are injected so import and recovery tests do not need a camera or
/// a special volume. The live implementation uses Foundation only.
public struct CaptureFolderFileOperations: Sendable {
  public let listFiles: @Sendable (URL) throws -> [URL]
  public let fileInfo: @Sendable (URL) throws -> CaptureFileInfo
  public let copy: @Sendable (URL, URL) throws -> Void

  public init(
    listFiles: @escaping @Sendable (URL) throws -> [URL] = { folderURL in
      try FileManager.default.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [
          .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
          .isHiddenKey,
        ],
        options: []
      )
    },
    fileInfo: @escaping @Sendable (URL) throws -> CaptureFileInfo = { url in
      let values = try url.resourceValues(forKeys: [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
      ])
      return CaptureFileInfo(
        byteCount: UInt64(max(0, values.fileSize ?? 0)),
        modificationDate: values.contentModificationDate,
        isRegularFile: values.isRegularFile ?? false
      )
    },
    copy: @escaping @Sendable (URL, URL) throws -> Void = { sourceURL, destinationURL in
      let fileManager = FileManager.default
      try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let temporaryURL = destinationURL.deletingLastPathComponent()
        .appendingPathComponent(".photosuite-copy-\(UUID().uuidString).tmp")
      defer { try? fileManager.removeItem(at: temporaryURL) }
      try fileManager.copyItem(at: sourceURL, to: temporaryURL)
      try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
  ) {
    self.listFiles = listFiles
    self.fileInfo = fileInfo
    self.copy = copy
  }
}

public struct CaptureBookmarkOperations: Sendable {
  public let resolve: @Sendable (Data) throws -> ResolvedSecurityScopedBookmark

  public init(
    resolve: @escaping @Sendable (Data) throws -> ResolvedSecurityScopedBookmark
  ) {
    self.resolve = resolve
  }

  public static let securityScoped = CaptureBookmarkOperations(
    resolve: { try SecurityScopedBookmarkStore.resolve(data: $0) }
  )
}

public struct CaptureImportFailure: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let sourceURL: URL
  public let message: String

  public init(id: UUID = UUID(), sourceURL: URL, message: String) {
    self.id = id
    self.sourceURL = sourceURL
    self.message = message
  }
}

public struct CaptureScanResult: Hashable, Sendable {
  public let imported: [PhotoAsset]
  public let duplicates: [URL]
  public let skipped: [URL]
  public let pending: [URL]
  public let failures: [CaptureImportFailure]
  public let renewedBookmarkData: Data?

  public init(
    imported: [PhotoAsset],
    duplicates: [URL],
    skipped: [URL],
    pending: [URL],
    failures: [CaptureImportFailure],
    renewedBookmarkData: Data?
  ) {
    self.imported = imported
    self.duplicates = duplicates
    self.skipped = skipped
    self.pending = pending
    self.failures = failures
    self.renewedBookmarkData = renewedBookmarkData
  }
}
