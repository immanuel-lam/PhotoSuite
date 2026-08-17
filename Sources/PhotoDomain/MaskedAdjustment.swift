// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A deterministic, non-AI local adjustment attached to a persisted mask.
///
/// The adjustment deliberately contains only operations that the version-one
/// render graph can evaluate locally. It does not represent healing, cloning,
/// generative removal, or model-produced masks.
public struct MaskedAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let maskID: UUID
  public let exposureEV: Double
  public let colorGrade: ThreeWayColorGrade

  public init?(
    maskID: UUID,
    exposureEV: Double = 0,
    colorGrade: ThreeWayColorGrade = .neutral
  ) {
    guard exposureEV.isFinite, (-16...16).contains(exposureEV) else { return nil }
    self.schemaVersion = 1
    self.maskID = maskID
    self.exposureEV = exposureEV
    self.colorGrade = colorGrade
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedMaskedAdjustment(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        maskID: values.maskID,
        exposureEV: values.exposureEV,
        colorGrade: values.colorGrade
      )
    else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Invalid masked adjustment")
      )
    }
    self = validated
  }

  public var isIdentity: Bool {
    exposureEV == 0 && colorGrade.isNeutral
  }
}

private struct PersistedMaskedAdjustment: Decodable {
  let schemaVersion: UInt
  let maskID: UUID
  let exposureEV: Double
  let colorGrade: ThreeWayColorGrade
}
