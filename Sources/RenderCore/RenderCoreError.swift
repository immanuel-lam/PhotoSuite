// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum RenderCoreError: Error, Equatable, LocalizedError, Sendable {
  case metalUnavailable
  case colorSpaceUnavailable(String)
  case unreadableSource(URL)
  case unsupportedSource(URL)
  case corruptSource(URL)
  case decoderIdentifierMismatch(expected: String, actual: String)
  case decoderVersionMismatch(expected: String, actual: String)
  case unsupportedDecoderVersion(String)
  case unsupportedRenderSchemaVersion(UInt)
  case invalidMaximumPixelDimension(Int)
  case invalidOperationValue(index: Int, operation: String)
  case unsupportedOperation(index: Int, kind: String)
  case unsupportedExportFormat(String)
  case unsupportedOutputColorSpace(String)
  case invalidJPEGQuality(Double)
  case invalidExportResize(String)
  case invalidWatermark(String)
  case invalidDestination(URL)
  case sourceDestinationConflict(URL)
  case jpegEncodingFailed(URL)
  case atomicWriteFailed(URL)
  case cleanupFailed(operation: String, primaryError: String, cleanupError: String)
  case renderFailed

  public var errorDescription: String? {
    switch self {
    case .metalUnavailable:
      "A Metal device is not available."
    case .colorSpaceUnavailable(let name):
      "The required color space is not available: \(name)."
    case .unreadableSource(let url):
      "The source image cannot be read: \(url.lastPathComponent)."
    case .unsupportedSource(let url):
      "The source image format is not supported: \(url.lastPathComponent)."
    case .corruptSource(let url):
      "The source image is corrupt: \(url.lastPathComponent)."
    case .decoderIdentifierMismatch(let expected, let actual):
      "The pinned decoder \(expected) does not match the available decoder \(actual)."
    case .decoderVersionMismatch(let expected, let actual):
      "The pinned decoder version \(expected) does not match the available version \(actual)."
    case .unsupportedDecoderVersion(let version) where version.isEmpty:
      "The pinned RAW decoder version is empty and is not supported."
    case .unsupportedDecoderVersion(let version):
      "The pinned RAW decoder version is not supported: \(version)."
    case .unsupportedRenderSchemaVersion(let version):
      "Render schema version \(version) is not supported."
    case .invalidMaximumPixelDimension(let dimension):
      "The preview pixel limit is invalid: \(dimension)."
    case .invalidOperationValue(let index, let operation):
      "Edit operation \(index) has an invalid \(operation) value."
    case .unsupportedOperation(let index, let kind):
      "Edit operation \(index) is not supported: \(kind)."
    case .unsupportedExportFormat(let format):
      "The export format is not supported: \(format)."
    case .unsupportedOutputColorSpace(let name):
      "The output color space is not supported: \(name)."
    case .invalidJPEGQuality(let quality):
      "The JPEG quality is invalid: \(quality)."
    case .invalidDestination(let url):
      "The export destination is invalid: \(url.lastPathComponent)."
    case .sourceDestinationConflict:
      "The export destination cannot replace the source image."
    case .jpegEncodingFailed(let url):
      "JPEG encoding failed for \(url.lastPathComponent)."
    case .atomicWriteFailed(let url):
      "The export could not be published to \(url.lastPathComponent)."
    case .cleanupFailed(let operation, let primaryError, let cleanupError):
      "\(operation) failed after \(primaryError). Cleanup also failed: \(cleanupError)"
    case .renderFailed:
      "The image could not be rendered."
    }
  }
}
