// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct ToneCurveAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let blackPoint: Double
  public let shadows: Double
  public let midtones: Double
  public let highlights: Double
  public let whitePoint: Double

  public init?(
    blackPoint: Double,
    shadows: Double,
    midtones: Double,
    highlights: Double,
    whitePoint: Double
  ) {
    let values = [blackPoint, shadows, midtones, highlights, whitePoint]
    guard values.allSatisfy(DevelopAdjustmentValidation.isUnit) else { return nil }
    schemaVersion = 1
    self.blackPoint = blackPoint
    self.shadows = shadows
    self.midtones = midtones
    self.highlights = highlights
    self.whitePoint = whitePoint
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedToneCurve(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        blackPoint: values.blackPoint,
        shadows: values.shadows,
        midtones: values.midtones,
        highlights: values.highlights,
        whitePoint: values.whitePoint
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid tone curve adjustment") }
    self = validated
  }
}

public struct WhiteBalanceAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let temperature: Double
  public let tint: Double

  public init?(temperature: Double, tint: Double) {
    guard
      DevelopAdjustmentValidation.isNormalized(temperature),
      DevelopAdjustmentValidation.isNormalized(tint)
    else { return nil }
    schemaVersion = 1
    self.temperature = temperature
    self.tint = tint
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedWhiteBalance(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(temperature: values.temperature, tint: values.tint)
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid white balance adjustment") }
    self = validated
  }
}

public struct TransformAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let straightenDegrees: Double
  public let flipHorizontal: Bool
  public let flipVertical: Bool

  public init?(
    straightenDegrees: Double,
    flipHorizontal: Bool,
    flipVertical: Bool
  ) {
    guard straightenDegrees.isFinite, (-45...45).contains(straightenDegrees) else { return nil }
    schemaVersion = 1
    self.straightenDegrees = straightenDegrees
    self.flipHorizontal = flipHorizontal
    self.flipVertical = flipVertical
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedTransform(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        straightenDegrees: values.straightenDegrees,
        flipHorizontal: values.flipHorizontal,
        flipVertical: values.flipVertical
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid transform adjustment") }
    self = validated
  }
}

public struct DetailAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let sharpening: Double
  public let luminanceNoiseReduction: Double

  public init?(sharpening: Double, luminanceNoiseReduction: Double) {
    guard
      DevelopAdjustmentValidation.isUnit(sharpening),
      DevelopAdjustmentValidation.isUnit(luminanceNoiseReduction)
    else { return nil }
    schemaVersion = 1
    self.sharpening = sharpening
    self.luminanceNoiseReduction = luminanceNoiseReduction
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedDetail(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        sharpening: values.sharpening,
        luminanceNoiseReduction: values.luminanceNoiseReduction
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid detail adjustment") }
    self = validated
  }
}

public struct OpticsAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let vignetteCorrection: Double
  /// Bounded barrel or pincushion correction. Negative values contract the
  /// image and positive values expand it in the deterministic render graph.
  public let lensDistortion: Double
  /// A bounded chromatic-channel separation correction amount.
  public let chromaticAberration: Double
  /// A bounded colour-fringe suppression amount.
  public let defringe: Double
  /// The optional attribution-aware lens profile that supplied these values.
  ///
  /// The render graph consumes the normalized correction values above. This
  /// identifier keeps the selected profile durable without coupling the recipe
  /// to a particular lens database installation.
  public let lensProfileID: String?

  public init?(
    vignetteCorrection: Double,
    lensDistortion: Double = 0,
    chromaticAberration: Double = 0,
    defringe: Double = 0,
    lensProfileID: String? = nil
  ) {
    guard
      DevelopAdjustmentValidation.isUnit(vignetteCorrection),
      DevelopAdjustmentValidation.isNormalized(lensDistortion),
      DevelopAdjustmentValidation.isUnit(chromaticAberration),
      DevelopAdjustmentValidation.isUnit(defringe),
      DevelopAdjustmentValidation.isValidOptionalIdentifier(lensProfileID)
    else { return nil }
    schemaVersion = 1
    self.vignetteCorrection = vignetteCorrection
    self.lensDistortion = lensDistortion
    self.chromaticAberration = chromaticAberration
    self.defringe = defringe
    self.lensProfileID = lensProfileID?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedOptics(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        vignetteCorrection: values.vignetteCorrection,
        lensDistortion: values.lensDistortion ?? 0,
        chromaticAberration: values.chromaticAberration ?? 0,
        defringe: values.defringe ?? 0,
        lensProfileID: values.lensProfileID
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid optics adjustment") }
    self = validated
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(vignetteCorrection, forKey: .vignetteCorrection)
    // Omit neutral extensions so recipes written by the original version keep
    // their byte-stable payload while newer values remain durable.
    if lensDistortion != 0 { try container.encode(lensDistortion, forKey: .lensDistortion) }
    if chromaticAberration != 0 {
      try container.encode(chromaticAberration, forKey: .chromaticAberration)
    }
    if defringe != 0 { try container.encode(defringe, forKey: .defringe) }
    if let lensProfileID { try container.encode(lensProfileID, forKey: .lensProfileID) }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case vignetteCorrection
    case lensDistortion
    case chromaticAberration
    case defringe
    case lensProfileID
  }
}

public struct EffectsAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let vignetteAmount: Double
  /// A deterministic fine-grain amount in the range 0...1.
  public let grainAmount: Double
  /// A bounded local-contrast/dehaze amount in the range -1...1.
  public let dehaze: Double

  public init?(
    vignetteAmount: Double,
    grainAmount: Double = 0,
    dehaze: Double = 0
  ) {
    guard
      DevelopAdjustmentValidation.isUnit(vignetteAmount),
      DevelopAdjustmentValidation.isUnit(grainAmount),
      DevelopAdjustmentValidation.isNormalized(dehaze)
    else { return nil }
    schemaVersion = 1
    self.vignetteAmount = vignetteAmount
    self.grainAmount = grainAmount
    self.dehaze = dehaze
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedEffects(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        vignetteAmount: values.vignetteAmount,
        grainAmount: values.grainAmount ?? 0,
        dehaze: values.dehaze ?? 0
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid effects adjustment") }
    self = validated
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(vignetteAmount, forKey: .vignetteAmount)
    if grainAmount != 0 { try container.encode(grainAmount, forKey: .grainAmount) }
    if dehaze != 0 { try container.encode(dehaze, forKey: .dehaze) }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case vignetteAmount
    case grainAmount
    case dehaze
  }
}

public struct CalibrationAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let redGain: Double
  public let greenGain: Double
  public let blueGain: Double

  public init?(redGain: Double, greenGain: Double, blueGain: Double) {
    guard
      DevelopAdjustmentValidation.isNormalized(redGain),
      DevelopAdjustmentValidation.isNormalized(greenGain),
      DevelopAdjustmentValidation.isNormalized(blueGain)
    else { return nil }
    schemaVersion = 1
    self.redGain = redGain
    self.greenGain = greenGain
    self.blueGain = blueGain
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedCalibration(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        redGain: values.redGain,
        greenGain: values.greenGain,
        blueGain: values.blueGain
      )
    else { throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid calibration adjustment") }
    self = validated
  }
}

public struct BlackAndWhiteAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let redWeight: Double
  public let greenWeight: Double
  public let blueWeight: Double

  public init?(redWeight: Double, greenWeight: Double, blueWeight: Double) {
    let weights = [redWeight, greenWeight, blueWeight]
    guard
      weights.allSatisfy({ $0.isFinite && (0...2).contains($0) }),
      weights.reduce(0, +) > 0
    else { return nil }
    schemaVersion = 1
    self.redWeight = redWeight
    self.greenWeight = greenWeight
    self.blueWeight = blueWeight
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedBlackAndWhite(from: decoder)
    guard
      values.schemaVersion == 1,
      let validated = Self(
        redWeight: values.redWeight,
        greenWeight: values.greenWeight,
        blueWeight: values.blueWeight
      )
    else {
      throw DevelopAdjustmentValidation.corrupt(
        decoder,
        "Invalid black-and-white adjustment"
      )
    }
    self = validated
  }
}

public struct HDRAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let isEnabled: Bool
  public let preservesExtendedRange: Bool

  public init(isEnabled: Bool, preservesExtendedRange: Bool) {
    schemaVersion = 1
    self.isEnabled = isEnabled
    self.preservesExtendedRange = preservesExtendedRange
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedHDR(from: decoder)
    guard values.schemaVersion == 1 else {
      throw DevelopAdjustmentValidation.corrupt(decoder, "Invalid HDR adjustment")
    }
    self.init(
      isEnabled: values.isEnabled,
      preservesExtendedRange: values.preservesExtendedRange
    )
  }
}

private enum DevelopAdjustmentValidation {
  static func isUnit(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
  }

  static func isNormalized(_ value: Double) -> Bool {
    value.isFinite && (-1...1).contains(value)
  }

  static func isValidOptionalIdentifier(_ value: String?) -> Bool {
    guard let value else { return true }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 256
  }

  static func corrupt(_ decoder: any Decoder, _ description: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
  }
}

private struct PersistedToneCurve: Decodable {
  let schemaVersion: UInt
  let blackPoint: Double
  let shadows: Double
  let midtones: Double
  let highlights: Double
  let whitePoint: Double
}

private struct PersistedWhiteBalance: Decodable {
  let schemaVersion: UInt
  let temperature: Double
  let tint: Double
}

private struct PersistedTransform: Decodable {
  let schemaVersion: UInt
  let straightenDegrees: Double
  let flipHorizontal: Bool
  let flipVertical: Bool
}

private struct PersistedDetail: Decodable {
  let schemaVersion: UInt
  let sharpening: Double
  let luminanceNoiseReduction: Double
}

private struct PersistedOptics: Decodable {
  let schemaVersion: UInt
  let vignetteCorrection: Double
  let lensDistortion: Double?
  let chromaticAberration: Double?
  let defringe: Double?
  let lensProfileID: String?
}

private struct PersistedEffects: Decodable {
  let schemaVersion: UInt
  let vignetteAmount: Double
  let grainAmount: Double?
  let dehaze: Double?
}

private struct PersistedCalibration: Decodable {
  let schemaVersion: UInt
  let redGain: Double
  let greenGain: Double
  let blueGain: Double
}

private struct PersistedBlackAndWhite: Decodable {
  let schemaVersion: UInt
  let redWeight: Double
  let greenWeight: Double
  let blueWeight: Double
}

private struct PersistedHDR: Decodable {
  let schemaVersion: UInt
  let isEnabled: Bool
  let preservesExtendedRange: Bool
}
