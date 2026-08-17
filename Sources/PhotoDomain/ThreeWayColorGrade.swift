// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A durable three-way colour grade. Hue is measured in degrees and chroma and
/// luminance are normalized controls. A neutral grade is an exact identity.
public struct ThreeWayColorGrade: Codable, Hashable, Sendable {
  public struct Tone: Codable, Hashable, Sendable {
    public let hueDegrees: Double
    public let chroma: Double
    public let luminance: Double

    public init?(hueDegrees: Double, chroma: Double, luminance: Double) {
      guard
        hueDegrees.isFinite, (0...360).contains(hueDegrees),
        chroma.isFinite, (0...1).contains(chroma),
        luminance.isFinite, (-1...1).contains(luminance)
      else {
        return nil
      }
      self.hueDegrees = hueDegrees
      self.chroma = chroma
      self.luminance = luminance
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let hueDegrees = try container.decode(Double.self, forKey: .hueDegrees)
      let chroma = try container.decode(Double.self, forKey: .chroma)
      let luminance = try container.decode(Double.self, forKey: .luminance)
      guard let tone = Self(hueDegrees: hueDegrees, chroma: chroma, luminance: luminance) else {
        throw DecodingError.dataCorruptedError(
          forKey: .hueDegrees,
          in: container,
          debugDescription: "Three-way colour grade tone values are out of range."
        )
      }
      self = tone
    }

    public var isNeutral: Bool { chroma == 0 && luminance == 0 }
  }

  public let shadows: Tone
  public let midtones: Tone
  public let highlights: Tone

  public init?(shadows: Tone, midtones: Tone, highlights: Tone) {
    self.shadows = shadows
    self.midtones = midtones
    self.highlights = highlights
  }

  public static let neutral = ThreeWayColorGrade(
    shadows: Tone(hueDegrees: 0, chroma: 0, luminance: 0)!,
    midtones: Tone(hueDegrees: 0, chroma: 0, luminance: 0)!,
    highlights: Tone(hueDegrees: 0, chroma: 0, luminance: 0)!
  )!

  public var isNeutral: Bool {
    shadows.isNeutral && midtones.isNeutral && highlights.isNeutral
  }
}
