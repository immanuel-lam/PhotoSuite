// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum EditOperation: Codable, Hashable, Sendable {
  case exposureEV(Double)
  case contrast(Double)
  case highlights(Double)
  case shadows(Double)
  case saturation(Double)
  case threeWayColorGrade(ThreeWayColorGrade)
  case maskedAdjustment(MaskedAdjustmentV1)
  case clone(CloneAdjustmentV1)
  case healing(HealingAdjustmentV1)
  case redEye(RedEyeAdjustmentV1)
  case normalizedCrop(NormalizedRect)
  case rotationDegrees(Double)
  case toneCurve(ToneCurveAdjustmentV1)
  case whiteBalance(WhiteBalanceAdjustmentV1)
  case transform(TransformAdjustmentV1)
  case detail(DetailAdjustmentV1)
  case optics(OpticsAdjustmentV1)
  case effects(EffectsAdjustmentV1)
  case calibration(CalibrationAdjustmentV1)
  case blackAndWhite(BlackAndWhiteAdjustmentV1)
  case hdr(HDRAdjustmentV1)
  case unknown(String, payload: [String: JSONValue])

  private static let reservedKinds: Set<String> = [
    "exposureEV",
    "contrast",
    "highlights",
    "shadows",
    "saturation",
    "threeWayColorGrade",
    "maskedAdjustment",
    "clone",
    "healing",
    "redEye",
    "normalizedCrop",
    "rotationDegrees",
    "toneCurve",
    "whiteBalance",
    "transform",
    "detail",
    "optics",
    "effects",
    "calibration",
    "blackAndWhite",
    "hdr",
  ]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let kindKey = DynamicCodingKey(stringValue: "kind")
    let valueKey = DynamicCodingKey(stringValue: "value")
    let rectKey = DynamicCodingKey(stringValue: "rect")
    let gradeKey = DynamicCodingKey(stringValue: "grade")
    let adjustmentKey = DynamicCodingKey(stringValue: "adjustment")
    let decodedKind = try UnknownStringCodeCoding.decode(
      from: container.superDecoder(forKey: kindKey)
    )

    switch (decodedKind.value, decodedKind.isExplicitlyUnknown) {
    case ("exposureEV", false):
      self = .exposureEV(try container.decode(Double.self, forKey: valueKey))
    case ("contrast", false):
      self = .contrast(try container.decode(Double.self, forKey: valueKey))
    case ("highlights", false):
      self = .highlights(try container.decode(Double.self, forKey: valueKey))
    case ("shadows", false):
      self = .shadows(try container.decode(Double.self, forKey: valueKey))
    case ("saturation", false):
      self = .saturation(try container.decode(Double.self, forKey: valueKey))
    case ("threeWayColorGrade", false):
      self = .threeWayColorGrade(try container.decode(ThreeWayColorGrade.self, forKey: gradeKey))
    case ("maskedAdjustment", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .maskedAdjustment(
        try container.decode(MaskedAdjustmentV1.self, forKey: adjustmentKey)
      )
    case ("clone", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .clone(try container.decode(CloneAdjustmentV1.self, forKey: adjustmentKey))
    case ("healing", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .healing(try container.decode(HealingAdjustmentV1.self, forKey: adjustmentKey))
    case ("redEye", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .redEye(try container.decode(RedEyeAdjustmentV1.self, forKey: adjustmentKey))
    case ("normalizedCrop", false):
      self = .normalizedCrop(try container.decode(NormalizedRect.self, forKey: rectKey))
    case ("rotationDegrees", false):
      self = .rotationDegrees(try container.decode(Double.self, forKey: valueKey))
    case ("toneCurve", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .toneCurve(try container.decode(ToneCurveAdjustmentV1.self, forKey: adjustmentKey))
    case ("whiteBalance", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .whiteBalance(
        try container.decode(WhiteBalanceAdjustmentV1.self, forKey: adjustmentKey)
      )
    case ("transform", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .transform(
        try container.decode(TransformAdjustmentV1.self, forKey: adjustmentKey)
      )
    case ("detail", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .detail(try container.decode(DetailAdjustmentV1.self, forKey: adjustmentKey))
    case ("optics", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .optics(try container.decode(OpticsAdjustmentV1.self, forKey: adjustmentKey))
    case ("effects", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .effects(try container.decode(EffectsAdjustmentV1.self, forKey: adjustmentKey))
    case ("calibration", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .calibration(
        try container.decode(CalibrationAdjustmentV1.self, forKey: adjustmentKey)
      )
    case ("blackAndWhite", false)
    where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .blackAndWhite(
        try container.decode(BlackAndWhiteAdjustmentV1.self, forKey: adjustmentKey)
      )
    case ("hdr", false) where Self.hasVersionOneAdjustment(container, key: adjustmentKey):
      self = .hdr(try container.decode(HDRAdjustmentV1.self, forKey: adjustmentKey))
    default:
      var payload: [String: JSONValue] = [:]
      for key in container.allKeys where key != kindKey {
        payload[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
      }
      self = .unknown(decodedKind.value, payload: payload)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    let kindKey = DynamicCodingKey(stringValue: "kind")
    let valueKey = DynamicCodingKey(stringValue: "value")
    let rectKey = DynamicCodingKey(stringValue: "rect")
    let gradeKey = DynamicCodingKey(stringValue: "grade")
    let adjustmentKey = DynamicCodingKey(stringValue: "adjustment")

    switch self {
    case .exposureEV(let value):
      try container.encode("exposureEV", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .contrast(let value):
      try container.encode("contrast", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .highlights(let value):
      try container.encode("highlights", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .shadows(let value):
      try container.encode("shadows", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .saturation(let value):
      try container.encode("saturation", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .threeWayColorGrade(let grade):
      try container.encode("threeWayColorGrade", forKey: kindKey)
      try container.encode(grade, forKey: gradeKey)
    case .maskedAdjustment(let adjustment):
      try container.encode("maskedAdjustment", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .clone(let adjustment):
      try container.encode("clone", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .healing(let adjustment):
      try container.encode("healing", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .redEye(let adjustment):
      try container.encode("redEye", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .normalizedCrop(let rect):
      try container.encode("normalizedCrop", forKey: kindKey)
      try container.encode(rect, forKey: rectKey)
    case .rotationDegrees(let value):
      try container.encode("rotationDegrees", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .toneCurve(let adjustment):
      try container.encode("toneCurve", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .whiteBalance(let adjustment):
      try container.encode("whiteBalance", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .transform(let adjustment):
      try container.encode("transform", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .detail(let adjustment):
      try container.encode("detail", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .optics(let adjustment):
      try container.encode("optics", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .effects(let adjustment):
      try container.encode("effects", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .calibration(let adjustment):
      try container.encode("calibration", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .blackAndWhite(let adjustment):
      try container.encode("blackAndWhite", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .hdr(let adjustment):
      try container.encode("hdr", forKey: kindKey)
      try container.encode(adjustment, forKey: adjustmentKey)
    case .unknown(let kind, let payload):
      for (key, value) in payload where key != kindKey.stringValue {
        try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
      }
      try UnknownStringCodeCoding.encodeUnknown(
        kind,
        reservedValues: Self.reservedKinds,
        to: container.superEncoder(forKey: kindKey)
      )
    }
  }

  private static func hasVersionOneAdjustment(
    _ container: KeyedDecodingContainer<DynamicCodingKey>,
    key: DynamicCodingKey
  ) -> Bool {
    guard
      let value = try? container.decode(JSONValue.self, forKey: key),
      case .object(let object) = value,
      case .number(let version)? = object["schemaVersion"]
    else { return false }
    return version == 1
  }
}
