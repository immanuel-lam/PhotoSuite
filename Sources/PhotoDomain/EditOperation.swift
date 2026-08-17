// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum EditOperation: Codable, Hashable, Sendable {
  case exposureEV(Double)
  case contrast(Double)
  case highlights(Double)
  case shadows(Double)
  case saturation(Double)
  case normalizedCrop(NormalizedRect)
  case rotationDegrees(Double)
  case unknown(String, payload: [String: JSONValue])

  private static let reservedKinds: Set<String> = [
    "exposureEV",
    "contrast",
    "highlights",
    "shadows",
    "saturation",
    "normalizedCrop",
    "rotationDegrees",
  ]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let kindKey = DynamicCodingKey(stringValue: "kind")
    let valueKey = DynamicCodingKey(stringValue: "value")
    let rectKey = DynamicCodingKey(stringValue: "rect")
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
    case ("normalizedCrop", false):
      self = .normalizedCrop(try container.decode(NormalizedRect.self, forKey: rectKey))
    case ("rotationDegrees", false):
      self = .rotationDegrees(try container.decode(Double.self, forKey: valueKey))
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
    case .normalizedCrop(let rect):
      try container.encode("normalizedCrop", forKey: kindKey)
      try container.encode(rect, forKey: rectKey)
    case .rotationDegrees(let value):
      try container.encode("rotationDegrees", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
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
}
