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

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
    case rect
  }

  private enum Kind: String, Codable {
    case exposureEV
    case contrast
    case highlights
    case shadows
    case saturation
    case normalizedCrop
    case rotationDegrees
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)

    switch kind {
    case .exposureEV:
      self = .exposureEV(try container.decode(Double.self, forKey: .value))
    case .contrast:
      self = .contrast(try container.decode(Double.self, forKey: .value))
    case .highlights:
      self = .highlights(try container.decode(Double.self, forKey: .value))
    case .shadows:
      self = .shadows(try container.decode(Double.self, forKey: .value))
    case .saturation:
      self = .saturation(try container.decode(Double.self, forKey: .value))
    case .normalizedCrop:
      self = .normalizedCrop(try container.decode(NormalizedRect.self, forKey: .rect))
    case .rotationDegrees:
      self = .rotationDegrees(try container.decode(Double.self, forKey: .value))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .exposureEV(let value):
      try container.encode(Kind.exposureEV, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .contrast(let value):
      try container.encode(Kind.contrast, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .highlights(let value):
      try container.encode(Kind.highlights, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .shadows(let value):
      try container.encode(Kind.shadows, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .saturation(let value):
      try container.encode(Kind.saturation, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .normalizedCrop(let rect):
      try container.encode(Kind.normalizedCrop, forKey: .kind)
      try container.encode(rect, forKey: .rect)
    case .rotationDegrees(let value):
      try container.encode(Kind.rotationDegrees, forKey: .kind)
      try container.encode(value, forKey: .value)
    }
  }
}
