// SPDX-License-Identifier: MPL-2.0

import Foundation

enum UnknownStringCodeCoding {
  struct DecodedCode {
    let value: String
    let isExplicitlyUnknown: Bool
  }

  private enum CodingKeys: String, CodingKey {
    case unknown
  }

  static func decode(from decoder: any Decoder) throws -> DecodedCode {
    if let container = try? decoder.singleValueContainer(),
      let value = try? container.decode(String.self)
    {
      return DecodedCode(value: value, isExplicitlyUnknown: false)
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    return DecodedCode(
      value: try container.decode(String.self, forKey: .unknown),
      isExplicitlyUnknown: true
    )
  }

  static func encodeKnown(_ value: String, to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

  static func encodeUnknown(
    _ value: String,
    reservedValues: Set<String>,
    to encoder: any Encoder
  ) throws {
    if reservedValues.contains(value) {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(value, forKey: .unknown)
    } else {
      try encodeKnown(value, to: encoder)
    }
  }
}

struct DynamicCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}
