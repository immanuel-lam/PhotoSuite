// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A normalized top-left image coordinate used by the local retouch tools.
public struct RetouchPointV1: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double

  public init?(x: Double, y: Double) {
    guard RetouchAdjustmentValidation.isUnit(x), RetouchAdjustmentValidation.isUnit(y) else {
      return nil
    }
    self.x = x
    self.y = y
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedRetouchPoint(from: decoder)
    guard let point = Self(x: values.x, y: values.y) else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid normalized retouch point")
    }
    self = point
  }
}

/// One pressure sample in a durable clone or healing brush stroke.
public struct RetouchBrushSampleV1: Codable, Hashable, Sendable {
  public let point: RetouchPointV1
  public let pressure: Double

  public init?(point: RetouchPointV1, pressure: Double) {
    guard RetouchAdjustmentValidation.isUnit(pressure) else { return nil }
    self.point = point
    self.pressure = pressure
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedRetouchBrushSample(from: decoder)
    guard let sample = Self(point: values.point, pressure: values.pressure) else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid retouch brush sample")
    }
    self = sample
  }
}

/// Version-one brush geometry shared by clone and healing operations.
public struct RetouchBrushV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let samples: [RetouchBrushSampleV1]
  public let radius: Double
  public let feather: Double
  public let flow: Double

  public init?(
    samples: [RetouchBrushSampleV1],
    radius: Double,
    feather: Double,
    flow: Double
  ) {
    guard
      !samples.isEmpty,
      samples.count <= 4_096,
      radius.isFinite, radius > 0, radius <= 0.5,
      RetouchAdjustmentValidation.isUnit(feather),
      RetouchAdjustmentValidation.isUnit(flow)
    else { return nil }
    schemaVersion = 1
    self.samples = samples
    self.radius = radius
    self.feather = feather
    self.flow = flow
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedRetouchBrush(from: decoder)
    guard
      values.schemaVersion == 1,
      let brush = Self(
        samples: values.samples,
        radius: values.radius,
        feather: values.feather,
        flow: values.flow
      )
    else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid retouch brush")
    }
    self = brush
  }
}

/// A deterministic source-patch copy. The source patch is translated from
/// `sourceAnchor` to `targetAnchor` and composited only through the brush.
public struct CloneAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let sourceAnchor: RetouchPointV1
  public let targetAnchor: RetouchPointV1
  public let brush: RetouchBrushV1

  public init?(
    sourceAnchor: RetouchPointV1,
    targetAnchor: RetouchPointV1,
    brush: RetouchBrushV1
  ) {
    schemaVersion = 1
    self.sourceAnchor = sourceAnchor
    self.targetAnchor = targetAnchor
    self.brush = brush
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedCloneAdjustment(from: decoder)
    guard
      values.schemaVersion == 1,
      let adjustment = Self(
        sourceAnchor: values.sourceAnchor,
        targetAnchor: values.targetAnchor,
        brush: values.brush
      )
    else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid clone adjustment")
    }
    self = adjustment
  }
}

/// A deterministic, bounded healing operation. Version one uses a translated
/// source patch with a small blur and controlled brush blend. It is not a
/// texture-aware or generative healing implementation.
public struct HealingAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let sourceAnchor: RetouchPointV1
  public let targetAnchor: RetouchPointV1
  public let brush: RetouchBrushV1
  public let blend: Double

  public init?(
    sourceAnchor: RetouchPointV1,
    targetAnchor: RetouchPointV1,
    brush: RetouchBrushV1,
    blend: Double
  ) {
    guard RetouchAdjustmentValidation.isUnit(blend) else { return nil }
    schemaVersion = 1
    self.sourceAnchor = sourceAnchor
    self.targetAnchor = targetAnchor
    self.brush = brush
    self.blend = blend
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedHealingAdjustment(from: decoder)
    guard
      values.schemaVersion == 1,
      let adjustment = Self(
        sourceAnchor: values.sourceAnchor,
        targetAnchor: values.targetAnchor,
        brush: values.brush,
        blend: values.blend
      )
    else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid healing adjustment")
    }
    self = adjustment
  }
}

/// A typed red-eye payload. The payload is durable and forward compatible;
/// version one keeps the render operation explicitly unsupported until a
/// colour-aware algorithm passes the release quality gates.
public struct RedEyeAdjustmentV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let center: RetouchPointV1
  public let radius: Double
  public let feather: Double

  public init?(
    center: RetouchPointV1,
    radius: Double,
    feather: Double
  ) {
    guard
      radius.isFinite, radius > 0, radius <= 0.5,
      RetouchAdjustmentValidation.isUnit(feather)
    else { return nil }
    schemaVersion = 1
    self.center = center
    self.radius = radius
    self.feather = feather
  }

  public init(from decoder: any Decoder) throws {
    let values = try PersistedRedEyeAdjustment(from: decoder)
    guard
      values.schemaVersion == 1,
      let adjustment = Self(
        center: values.center,
        radius: values.radius,
        feather: values.feather
      )
    else {
      throw RetouchAdjustmentValidation.corrupt(decoder, "Invalid red-eye adjustment")
    }
    self = adjustment
  }
}

private enum RetouchAdjustmentValidation {
  static func isUnit(_ value: Double) -> Bool {
    value.isFinite && (0...1).contains(value)
  }

  static func corrupt(_ decoder: any Decoder, _ description: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
  }
}

private struct PersistedRetouchPoint: Decodable {
  let x: Double
  let y: Double
}

private struct PersistedRetouchBrushSample: Decodable {
  let point: RetouchPointV1
  let pressure: Double
}

private struct PersistedRetouchBrush: Decodable {
  let schemaVersion: UInt
  let samples: [RetouchBrushSampleV1]
  let radius: Double
  let feather: Double
  let flow: Double
}

private struct PersistedCloneAdjustment: Decodable {
  let schemaVersion: UInt
  let sourceAnchor: RetouchPointV1
  let targetAnchor: RetouchPointV1
  let brush: RetouchBrushV1
}

private struct PersistedHealingAdjustment: Decodable {
  let schemaVersion: UInt
  let sourceAnchor: RetouchPointV1
  let targetAnchor: RetouchPointV1
  let brush: RetouchBrushV1
  let blend: Double
}

private struct PersistedRedEyeAdjustment: Decodable {
  let schemaVersion: UInt
  let center: RetouchPointV1
  let radius: Double
  let feather: Double
}
