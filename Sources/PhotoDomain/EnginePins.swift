// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct EnginePins: Codable, Hashable, Sendable {
  public let decoderIdentifier: String
  public let decoderVersion: String
  public let renderSchemaVersion: UInt
  public let cameraProfileVersion: String?
  public let modelVersions: [String: String]

  public init(
    decoderIdentifier: String,
    decoderVersion: String,
    renderSchemaVersion: UInt,
    cameraProfileVersion: String?,
    modelVersions: [String: String]
  ) {
    self.decoderIdentifier = decoderIdentifier
    self.decoderVersion = decoderVersion
    self.renderSchemaVersion = renderSchemaVersion
    self.cameraProfileVersion = cameraProfileVersion
    self.modelVersions = modelVersions
  }
}
