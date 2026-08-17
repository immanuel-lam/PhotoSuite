// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoDomain

/// The durable version-1 recipe render contract.
///
/// Operations execute in stored order. Exposure is a finite EV delta. Contrast,
/// highlights, shadows, and saturation are finite deltas in `-1...1` with zero
/// identity. Contrast maps through `pow(4, delta)` and saturation through
/// `1 + delta`. Highlight and shadow polynomials use `k = 0.75`. Crop coordinates
/// have a top-left origin; left/top use `floor` and right/bottom use `ceil`.
/// Quarter turns use exact integer transforms. Other rotations use the full
/// integral bounding box and keep transparent corners for the output stage.
enum RecipeRenderContractV1 {
  static let schemaVersion: UInt = 1
  static let toneCoefficient = 0.75

  static func contrastFactor(for delta: Double) -> Double {
    pow(4, delta)
  }

  static func saturationFactor(for delta: Double) -> Double {
    1 + delta
  }
}

enum EditGraphCompiler {
  static func compile(_ input: CIImage, recipe: EditRecipe) throws -> CIImage {
    guard recipe.pins.renderSchemaVersion == RecipeRenderContractV1.schemaVersion else {
      throw RenderCoreError.unsupportedRenderSchemaVersion(
        recipe.pins.renderSchemaVersion
      )
    }

    var image = normalizeOrigin(input)
    for (index, operation) in recipe.operations.enumerated() {
      switch operation {
      case .exposureEV(let delta):
        guard delta.isFinite else {
          throw invalid(index, "exposureEV")
        }
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = Float(delta)
        image = try output(of: filter)

      case .contrast(let delta):
        try validateNormalized(delta, index: index, operation: "contrast")
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = Float(RecipeRenderContractV1.contrastFactor(for: delta))
        filter.saturation = 1
        filter.brightness = 0
        image = try output(of: filter)

      case .highlights(let delta):
        try validateNormalized(delta, index: index, operation: "highlights")
        image = try polynomialImage(
          image,
          coefficients: highlightCoefficients(delta),
          index: index,
          operation: "highlights"
        )

      case .shadows(let delta):
        try validateNormalized(delta, index: index, operation: "shadows")
        image = try polynomialImage(
          image,
          coefficients: shadowCoefficients(delta),
          index: index,
          operation: "shadows"
        )

      case .saturation(let delta):
        try validateNormalized(delta, index: index, operation: "saturation")
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = 1
        filter.saturation = Float(RecipeRenderContractV1.saturationFactor(for: delta))
        filter.brightness = 0
        image = try output(of: filter)

      case .normalizedCrop(let crop):
        image = try cropImage(image, crop: crop, index: index)

      case .rotationDegrees(let degrees):
        guard degrees.isFinite else {
          throw invalid(index, "rotationDegrees")
        }
        image = try rotateImage(image, degrees: degrees, index: index)

      case .unknown(let kind, _):
        throw RenderCoreError.unsupportedOperation(index: index, kind: kind)
      }
    }
    return image
  }

  private static func validateNormalized(
    _ delta: Double,
    index: Int,
    operation: String
  ) throws {
    guard delta.isFinite, (-1...1).contains(delta) else {
      throw invalid(index, operation)
    }
  }

  private static func polynomialImage(
    _ image: CIImage,
    coefficients: CIVector,
    index: Int,
    operation: String
  ) throws -> CIImage {
    let filter = CIFilter.colorPolynomial()
    filter.inputImage = image
    filter.redCoefficients = coefficients
    filter.greenCoefficients = coefficients
    filter.blueCoefficients = coefficients
    filter.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
    guard let output = filter.outputImage else {
      throw invalid(index, operation)
    }
    return output
  }

  private static func highlightCoefficients(_ delta: Double) -> CIVector {
    let amount = RecipeRenderContractV1.toneCoefficient * delta
    return CIVector(x: 0, y: 1, z: amount, w: -amount)
  }

  private static func shadowCoefficients(_ delta: Double) -> CIVector {
    let amount = RecipeRenderContractV1.toneCoefficient * delta
    return CIVector(x: 0, y: 1 + amount, z: -2 * amount, w: amount)
  }

  private static func cropImage(
    _ image: CIImage,
    crop: NormalizedRect,
    index: Int
  ) throws -> CIImage {
    let extent = image.extent
    let left = floor(crop.x * extent.width)
    let top = floor(crop.y * extent.height)
    let right = ceil((crop.x + crop.width) * extent.width)
    let bottom = ceil((crop.y + crop.height) * extent.height)
    let clampedLeft = max(0, min(extent.width, left))
    let clampedTop = max(0, min(extent.height, top))
    let clampedRight = max(clampedLeft, min(extent.width, right))
    let clampedBottom = max(clampedTop, min(extent.height, bottom))
    let rect = CGRect(
      x: extent.minX + clampedLeft,
      y: extent.minY + extent.height - clampedBottom,
      width: clampedRight - clampedLeft,
      height: clampedBottom - clampedTop
    )
    guard rect.width >= 1, rect.height >= 1 else {
      throw invalid(index, "normalizedCrop")
    }
    return normalizeOrigin(image.cropped(to: rect))
  }

  private static func rotateImage(
    _ image: CIImage,
    degrees: Double,
    index: Int
  ) throws -> CIImage {
    let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
    let positiveDegrees = normalizedDegrees < 0 ? normalizedDegrees + 360 : normalizedDegrees
    let extent = image.extent
    let width = extent.width
    let height = extent.height
    let transform: CGAffineTransform

    if approximatelyEqual(positiveDegrees, 0) || approximatelyEqual(positiveDegrees, 360) {
      return image
    } else if approximatelyEqual(positiveDegrees, 90) {
      transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
    } else if approximatelyEqual(positiveDegrees, 180) {
      transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
    } else if approximatelyEqual(positiveDegrees, 270) {
      transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
    } else {
      let radians = positiveDegrees * .pi / 180
      let cosine = cos(radians)
      let sine = sin(radians)
      let centerX = width / 2
      let centerY = height / 2
      transform = CGAffineTransform(
        a: cosine,
        b: sine,
        c: -sine,
        d: cosine,
        tx: centerX - cosine * centerX + sine * centerY,
        ty: centerY - sine * centerX - cosine * centerY
      )
    }

    let rotated = image.transformed(by: transform)
    let boundingBox = rotated.extent.integral
    guard validExtent(boundingBox) else {
      throw invalid(index, "rotationDegrees")
    }
    return
      rotated
      .cropped(to: boundingBox)
      .transformed(
        by: CGAffineTransform(
          translationX: -boundingBox.minX,
          y: -boundingBox.minY
        )
      )
  }

  private static func output(of filter: CIFilter) throws -> CIImage {
    guard let output = filter.outputImage else {
      throw RenderCoreError.renderFailed
    }
    return output
  }

  private static func normalizeOrigin(_ image: CIImage) -> CIImage {
    let extent = image.extent
    guard extent.minX != 0 || extent.minY != 0 else { return image }
    return image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
  }

  private static func validExtent(_ extent: CGRect) -> Bool {
    extent.origin.x.isFinite
      && extent.origin.y.isFinite
      && extent.width.isFinite
      && extent.height.isFinite
      && !extent.isEmpty
      && extent.width > 0
      && extent.height > 0
  }

  private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 0.000_000_1
  }

  private static func invalid(_ index: Int, _ operation: String) -> RenderCoreError {
    .invalidOperationValue(index: index, operation: operation)
  }
}
