// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct MaskPointV1: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double

  public init?(x: Double, y: Double) {
    guard MaskValueValidation.isUnit(x), MaskValueValidation.isUnit(y) else { return nil }
    self.x = x
    self.y = y
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedMaskPoint(from: decoder)
    guard let validated = Self(x: values.x, y: values.y) else {
      throw MaskValueValidation.corrupt(decoder, "Invalid normalized mask point")
    }
    self = validated
  }
}

public struct MaskBrushSampleV1: Codable, Hashable, Sendable {
  public let point: MaskPointV1
  public let pressure: Double

  public init?(point: MaskPointV1, pressure: Double) {
    guard MaskValueValidation.isUnit(pressure) else { return nil }
    self.point = point
    self.pressure = pressure
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedBrushSample(from: decoder)
    guard let validated = Self(point: values.point, pressure: values.pressure) else {
      throw MaskValueValidation.corrupt(decoder, "Invalid brush sample")
    }
    self = validated
  }
}

public struct BrushMaskV1: Codable, Hashable, Sendable {
  public let samples: [MaskBrushSampleV1]
  public let radius: Double
  public let feather: Double
  public let flow: Double

  public init?(
    samples: [MaskBrushSampleV1],
    radius: Double,
    feather: Double,
    flow: Double
  ) {
    guard
      !samples.isEmpty,
      MaskValueValidation.isPositiveUnit(radius),
      MaskValueValidation.isUnit(feather),
      MaskValueValidation.isUnit(flow)
    else { return nil }
    self.samples = samples
    self.radius = radius
    self.feather = feather
    self.flow = flow
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedBrushMask(from: decoder)
    guard
      let validated = Self(
        samples: values.samples,
        radius: values.radius,
        feather: values.feather,
        flow: values.flow
      )
    else { throw MaskValueValidation.corrupt(decoder, "Invalid brush mask") }
    self = validated
  }
}

public struct LinearGradientMaskV1: Codable, Hashable, Sendable {
  public let start: MaskPointV1
  public let end: MaskPointV1
  public let feather: Double

  public init?(start: MaskPointV1, end: MaskPointV1, feather: Double) {
    guard start != end, MaskValueValidation.isUnit(feather) else { return nil }
    self.start = start
    self.end = end
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedLinearGradient(from: decoder)
    guard let validated = Self(start: values.start, end: values.end, feather: values.feather)
    else { throw MaskValueValidation.corrupt(decoder, "Invalid linear gradient mask") }
    self = validated
  }
}

public struct RadialGradientMaskV1: Codable, Hashable, Sendable {
  public let center: MaskPointV1
  public let radiusX: Double
  public let radiusY: Double
  public let rotationDegrees: Double
  public let feather: Double

  public init?(
    center: MaskPointV1,
    radiusX: Double,
    radiusY: Double,
    rotationDegrees: Double,
    feather: Double
  ) {
    guard
      MaskValueValidation.isPositiveUnit(radiusX),
      MaskValueValidation.isPositiveUnit(radiusY),
      rotationDegrees.isFinite,
      (-180...180).contains(rotationDegrees),
      MaskValueValidation.isUnit(feather)
    else { return nil }
    self.center = center
    self.radiusX = radiusX
    self.radiusY = radiusY
    self.rotationDegrees = rotationDegrees
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedRadialGradient(from: decoder)
    guard
      let validated = Self(
        center: values.center,
        radiusX: values.radiusX,
        radiusY: values.radiusY,
        rotationDegrees: values.rotationDegrees,
        feather: values.feather
      )
    else { throw MaskValueValidation.corrupt(decoder, "Invalid radial gradient mask") }
    self = validated
  }
}

public struct MaskColorSampleV1: Codable, Hashable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init?(red: Double, green: Double, blue: Double) {
    guard
      MaskValueValidation.isUnit(red),
      MaskValueValidation.isUnit(green),
      MaskValueValidation.isUnit(blue)
    else { return nil }
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedColorSample(from: decoder)
    guard let validated = Self(red: values.red, green: values.green, blue: values.blue) else {
      throw MaskValueValidation.corrupt(decoder, "Invalid color sample")
    }
    self = validated
  }
}

public struct ColorRangeMaskV1: Codable, Hashable, Sendable {
  public let samples: [MaskColorSampleV1]
  public let tolerance: Double
  public let feather: Double

  public init?(samples: [MaskColorSampleV1], tolerance: Double, feather: Double) {
    guard
      !samples.isEmpty,
      MaskValueValidation.isUnit(tolerance),
      MaskValueValidation.isUnit(feather)
    else { return nil }
    self.samples = samples
    self.tolerance = tolerance
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedColorRange(from: decoder)
    guard
      let validated = Self(
        samples: values.samples,
        tolerance: values.tolerance,
        feather: values.feather
      )
    else { throw MaskValueValidation.corrupt(decoder, "Invalid color range mask") }
    self = validated
  }
}

public struct LuminanceRangeMaskV1: Codable, Hashable, Sendable {
  public let lowerBound: Double
  public let upperBound: Double
  public let feather: Double

  public init?(lowerBound: Double, upperBound: Double, feather: Double) {
    guard
      MaskValueValidation.isUnit(lowerBound),
      MaskValueValidation.isUnit(upperBound),
      lowerBound <= upperBound,
      MaskValueValidation.isUnit(feather)
    else { return nil }
    self.lowerBound = lowerBound
    self.upperBound = upperBound
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedLuminanceRange(from: decoder)
    guard
      let validated = Self(
        lowerBound: values.lowerBound,
        upperBound: values.upperBound,
        feather: values.feather
      )
    else { throw MaskValueValidation.corrupt(decoder, "Invalid luminance range mask") }
    self = validated
  }
}

public struct DepthRangeMaskV1: Codable, Hashable, Sendable {
  public let nearBound: Double
  public let farBound: Double
  public let feather: Double

  public init?(nearBound: Double, farBound: Double, feather: Double) {
    guard
      MaskValueValidation.isUnit(nearBound),
      MaskValueValidation.isUnit(farBound),
      nearBound <= farBound,
      MaskValueValidation.isUnit(feather)
    else { return nil }
    self.nearBound = nearBound
    self.farBound = farBound
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedDepthRange(from: decoder)
    guard
      let validated = Self(
        nearBound: values.nearBound,
        farBound: values.farBound,
        feather: values.feather
      )
    else { throw MaskValueValidation.corrupt(decoder, "Invalid depth range mask") }
    self = validated
  }
}

enum MaskValueValidation {
  static func isUnit(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
  }

  static func isPositiveUnit(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value <= 1
  }

  static func corrupt(_ decoder: any Decoder, _ description: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
  }
}

private struct PersistedMaskPoint: Decodable {
  let x: Double
  let y: Double
}

private struct PersistedBrushSample: Decodable {
  let point: MaskPointV1
  let pressure: Double
}

private struct PersistedBrushMask: Decodable {
  let samples: [MaskBrushSampleV1]
  let radius: Double
  let feather: Double
  let flow: Double
}

private struct PersistedLinearGradient: Decodable {
  let start: MaskPointV1
  let end: MaskPointV1
  let feather: Double
}

private struct PersistedRadialGradient: Decodable {
  let center: MaskPointV1
  let radiusX: Double
  let radiusY: Double
  let rotationDegrees: Double
  let feather: Double
}

private struct PersistedColorSample: Decodable {
  let red: Double
  let green: Double
  let blue: Double
}

private struct PersistedColorRange: Decodable {
  let samples: [MaskColorSampleV1]
  let tolerance: Double
  let feather: Double
}

private struct PersistedLuminanceRange: Decodable {
  let lowerBound: Double
  let upperBound: Double
  let feather: Double
}

private struct PersistedDepthRange: Decodable {
  let nearBound: Double
  let farBound: Double
  let feather: Double
}
