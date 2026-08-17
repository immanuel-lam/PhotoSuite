// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum MaskPrimitiveV1: Codable, Hashable, Sendable {
  case brush(BrushMaskV1)
  case linearGradient(LinearGradientMaskV1)
  case radialGradient(RadialGradientMaskV1)
  case colorRange(ColorRangeMaskV1)
  case luminanceRange(LuminanceRangeMaskV1)
  case depthRange(DepthRangeMaskV1)
  case unknown(String, payload: [String: JSONValue])

  private static let reservedKinds: Set<String> = [
    "brush",
    "linearGradient",
    "radialGradient",
    "colorRange",
    "luminanceRange",
    "depthRange",
  ]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let kindKey = DynamicCodingKey(stringValue: "kind")
    let valueKey = DynamicCodingKey(stringValue: "value")
    let decodedKind = try UnknownStringCodeCoding.decode(
      from: container.superDecoder(forKey: kindKey)
    )

    switch (decodedKind.value, decodedKind.isExplicitlyUnknown) {
    case ("brush", false):
      self = .brush(try container.decode(BrushMaskV1.self, forKey: valueKey))
    case ("linearGradient", false):
      self = .linearGradient(
        try container.decode(LinearGradientMaskV1.self, forKey: valueKey)
      )
    case ("radialGradient", false):
      self = .radialGradient(
        try container.decode(RadialGradientMaskV1.self, forKey: valueKey)
      )
    case ("colorRange", false):
      self = .colorRange(try container.decode(ColorRangeMaskV1.self, forKey: valueKey))
    case ("luminanceRange", false):
      self = .luminanceRange(
        try container.decode(LuminanceRangeMaskV1.self, forKey: valueKey)
      )
    case ("depthRange", false):
      self = .depthRange(try container.decode(DepthRangeMaskV1.self, forKey: valueKey))
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
    switch self {
    case .brush(let value):
      try container.encode("brush", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .linearGradient(let value):
      try container.encode("linearGradient", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .radialGradient(let value):
      try container.encode("radialGradient", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .colorRange(let value):
      try container.encode("colorRange", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .luminanceRange(let value):
      try container.encode("luminanceRange", forKey: kindKey)
      try container.encode(value, forKey: valueKey)
    case .depthRange(let value):
      try container.encode("depthRange", forKey: kindKey)
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

public enum MaskCombinationOperation: Codable, Hashable, Sendable {
  case add
  case subtract
  case intersect
  case unknown(String)

  public init(from decoder: any Decoder) throws {
    let decoded = try UnknownStringCodeCoding.decode(from: decoder)
    guard !decoded.isExplicitlyUnknown else {
      self = .unknown(decoded.value)
      return
    }
    switch decoded.value {
    case "add": self = .add
    case "subtract": self = .subtract
    case "intersect": self = .intersect
    default: self = .unknown(decoded.value)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .add: try UnknownStringCodeCoding.encodeKnown("add", to: encoder)
    case .subtract: try UnknownStringCodeCoding.encodeKnown("subtract", to: encoder)
    case .intersect: try UnknownStringCodeCoding.encodeKnown("intersect", to: encoder)
    case .unknown(let value):
      try UnknownStringCodeCoding.encodeUnknown(
        value,
        reservedValues: ["add", "subtract", "intersect"],
        to: encoder
      )
    }
  }
}

public struct MaskGraphComponentV1: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let operation: MaskCombinationOperation
  public let primitive: MaskPrimitiveV1

  public init(
    id: UUID,
    operation: MaskCombinationOperation,
    primitive: MaskPrimitiveV1
  ) {
    self.id = id
    self.operation = operation
    self.primitive = primitive
  }
}

public enum MaskGraphEditV1: Codable, Hashable, Sendable {
  case add(id: UUID, primitive: MaskPrimitiveV1)
  case subtract(id: UUID, primitive: MaskPrimitiveV1)
  case intersect(id: UUID, primitive: MaskPrimitiveV1)
  case invert
  case unknown(String, payload: [String: JSONValue])

  private static let reservedKinds: Set<String> = ["add", "subtract", "intersect", "invert"]

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let kindKey = DynamicCodingKey(stringValue: "kind")
    let idKey = DynamicCodingKey(stringValue: "id")
    let primitiveKey = DynamicCodingKey(stringValue: "primitive")
    let decodedKind = try UnknownStringCodeCoding.decode(
      from: container.superDecoder(forKey: kindKey)
    )
    switch (decodedKind.value, decodedKind.isExplicitlyUnknown) {
    case ("add", false):
      self = .add(
        id: try container.decode(UUID.self, forKey: idKey),
        primitive: try container.decode(MaskPrimitiveV1.self, forKey: primitiveKey)
      )
    case ("subtract", false):
      self = .subtract(
        id: try container.decode(UUID.self, forKey: idKey),
        primitive: try container.decode(MaskPrimitiveV1.self, forKey: primitiveKey)
      )
    case ("intersect", false):
      self = .intersect(
        id: try container.decode(UUID.self, forKey: idKey),
        primitive: try container.decode(MaskPrimitiveV1.self, forKey: primitiveKey)
      )
    case ("invert", false):
      self = .invert
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
    let idKey = DynamicCodingKey(stringValue: "id")
    let primitiveKey = DynamicCodingKey(stringValue: "primitive")
    switch self {
    case .add(let id, let primitive):
      try container.encode("add", forKey: kindKey)
      try container.encode(id, forKey: idKey)
      try container.encode(primitive, forKey: primitiveKey)
    case .subtract(let id, let primitive):
      try container.encode("subtract", forKey: kindKey)
      try container.encode(id, forKey: idKey)
      try container.encode(primitive, forKey: primitiveKey)
    case .intersect(let id, let primitive):
      try container.encode("intersect", forKey: kindKey)
      try container.encode(id, forKey: idKey)
      try container.encode(primitive, forKey: primitiveKey)
    case .invert:
      try container.encode("invert", forKey: kindKey)
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

public struct MaskGraphV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let components: [MaskGraphComponentV1]
  public let isInverted: Bool

  public init(components: [MaskGraphComponentV1] = [], isInverted: Bool = false) {
    schemaVersion = 1
    self.components = components
    self.isInverted = isInverted
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedMaskGraph(from: decoder)
    guard values.schemaVersion == 1 else {
      throw MaskValueValidation.corrupt(decoder, "Unsupported mask graph schema")
    }
    self.init(components: values.components, isInverted: values.isInverted)
  }

  public func applying(_ edit: MaskGraphEditV1) -> Self {
    switch edit {
    case .add(let id, let primitive):
      adding(id: id, operation: .add, primitive: primitive)
    case .subtract(let id, let primitive):
      adding(id: id, operation: .subtract, primitive: primitive)
    case .intersect(let id, let primitive):
      adding(id: id, operation: .intersect, primitive: primitive)
    case .invert:
      Self(components: components, isInverted: !isInverted)
    case .unknown:
      self
    }
  }

  private func adding(
    id: UUID,
    operation: MaskCombinationOperation,
    primitive: MaskPrimitiveV1
  ) -> Self {
    Self(
      components: components + [
        MaskGraphComponentV1(id: id, operation: operation, primitive: primitive)
      ],
      isInverted: isInverted
    )
  }
}

public enum MaskGraphPayload: Codable, Hashable, Sendable {
  case version1(MaskGraphV1)
  case unknown(schemaVersion: UInt?, payload: JSONValue)

  public init(from decoder: any Decoder) throws {
    let payload = try JSONValue(from: decoder)
    guard
      case .object(let object) = payload,
      case .number(let decimalVersion)? = object["schemaVersion"],
      let schemaVersion = UInt(NSDecimalNumber(decimal: decimalVersion).stringValue)
    else {
      self = .unknown(schemaVersion: nil, payload: payload)
      return
    }
    guard schemaVersion == 1 else {
      self = .unknown(schemaVersion: schemaVersion, payload: payload)
      return
    }
    let data = try JSONEncoder().encode(payload)
    self = .version1(try JSONDecoder().decode(MaskGraphV1.self, from: data))
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .version1(let graph): try graph.encode(to: encoder)
    case .unknown(_, let payload): try payload.encode(to: encoder)
    }
  }
}

extension MaskDefinition {
  public init(
    id: UUID = UUID(),
    kind: MaskKind,
    name: String?,
    graph: MaskGraphV1
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.init(
      id: id,
      schemaVersion: 1,
      kind: kind,
      name: name,
      isInverted: graph.isInverted,
      payload: try encoder.encode(graph)
    )
  }

  public func decodeGraphPayload() throws -> MaskGraphPayload {
    try JSONDecoder().decode(MaskGraphPayload.self, from: payload)
  }
}

private struct PersistedMaskGraph: Decodable {
  let schemaVersion: UInt
  let components: [MaskGraphComponentV1]
  let isInverted: Bool
}
