// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

public enum RenderCoreError: Error, Equatable, Sendable {
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
  case invalidDestination(URL)
  case sourceDestinationConflict(URL)
  case jpegEncodingFailed(URL)
  case atomicWriteFailed(URL)
  case cleanupFailed(operation: String, primaryError: String, cleanupError: String)
  case renderFailed
}
