// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain

/// The single-asset contract used by the Library relink action.
///
/// A relink only changes the catalog pointer and its security-scoped bookmark. The
/// original source file and all edit recipes remain untouched. The replacement must
/// have the same content fingerprint as the missing source.
public struct MissingSourceRelinkPlan: Hashable, Sendable {
  public let assetID: UUID
  public let expectedFilename: String
  public let expectedFingerprint: SourceFingerprint
  public let isMissing: Bool

  public init(asset: PhotoAsset) {
    assetID = asset.id
    expectedFilename = asset.filename
    expectedFingerprint = asset.fingerprint
    isMissing = asset.isMissing
  }

  public func validate(
    replacementURL: URL,
    actualFingerprint: SourceFingerprint
  ) throws {
    guard isMissing else {
      throw MissingSourceRelinkError.assetNotMissing(assetID)
    }
    guard replacementURL.isFileURL, !replacementURL.path.isEmpty else {
      throw MissingSourceRelinkError.invalidReplacementURL(replacementURL)
    }
    // The modification date can change when a file is copied. Content identity is
    // therefore based on the digest and byte count, not on the source timestamp.
    guard
      actualFingerprint.sha256 == expectedFingerprint.sha256,
      actualFingerprint.byteCount == expectedFingerprint.byteCount
    else {
      throw MissingSourceRelinkError.fingerprintMismatch(
        expected: expectedFingerprint,
        actual: actualFingerprint
      )
    }
  }
}

public enum MissingSourceRelinkError: Error, Equatable, LocalizedError, Sendable {
  case assetNotFound(UUID)
  case assetNotMissing(UUID)
  case invalidReplacementURL(URL)
  case sourceScopeUnavailable(URL)
  case fingerprintMismatch(expected: SourceFingerprint, actual: SourceFingerprint)

  public var errorDescription: String? {
    switch self {
    case .assetNotFound:
      "The photograph is no longer available in the current catalog."
    case .assetNotMissing:
      "This photograph is already available. Relink is only for missing sources."
    case .invalidReplacementURL:
      "Choose a local photograph file, not a folder or a remote location."
    case .sourceScopeUnavailable:
      "PhotoSuite could not access the selected file. Choose it again from a local folder."
    case .fingerprintMismatch:
      "The selected file is not an unchanged copy of the missing source. Choose the original file."
    }
  }
}
