// SPDX-License-Identifier: MPL-2.0

import Foundation

public struct PixelDimensions: Codable, Hashable, Sendable {
  public let width: Int
  public let height: Int

  public init?(width: Int, height: Int) {
    guard width > 0, height > 0 else {
      return nil
    }

    self.width = width
    self.height = height
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let width = try container.decode(Int.self, forKey: .width)
    let height = try container.decode(Int.self, forKey: .height)

    guard let dimensions = Self(width: width, height: height) else {
      throw DecodingError.dataCorruptedError(
        forKey: width <= 0 ? .width : .height,
        in: container,
        debugDescription: "Pixel dimensions must be positive."
      )
    }

    self = dimensions
  }
}

public struct NormalizedRect: Codable, Hashable, Sendable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init?(x: Double, y: Double, width: Double, height: Double) {
    let values = [x, y, width, height]
    guard values.allSatisfy(\.isFinite),
      values.allSatisfy({ (0...1).contains($0) }),
      width > 0,
      height > 0,
      x + width <= 1,
      y + height <= 1
    else {
      return nil
    }

    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let x = try container.decode(Double.self, forKey: .x)
    let y = try container.decode(Double.self, forKey: .y)
    let width = try container.decode(Double.self, forKey: .width)
    let height = try container.decode(Double.self, forKey: .height)

    guard let rect = Self(x: x, y: y, width: width, height: height) else {
      throw DecodingError.dataCorruptedError(
        forKey: .width,
        in: container,
        debugDescription: "A normalized rectangle must be finite, positive, and inside unit bounds."
      )
    }

    self = rect
  }
}
