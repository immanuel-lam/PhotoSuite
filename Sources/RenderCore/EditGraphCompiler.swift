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

  static func whiteBalanceTemperature(for normalizedValue: Double) -> Double {
    6_500 + normalizedValue * 3_500
  }

  static func whiteBalanceTint(for normalizedValue: Double) -> Double {
    normalizedValue * 150
  }

  static func noiseLevel(for amount: Double) -> Double {
    amount * 0.1
  }

  static func sharpenRadius(for amount: Double) -> Double {
    1 + 2 * amount
  }

  static func sharpness(for amount: Double) -> Double {
    2 * amount
  }

  static func calibrationFactor(for gain: Double) -> Double {
    1 + gain * 0.5
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
        let exposure = Float(delta)
        guard delta.isFinite, exposure.isFinite else {
          throw invalid(index, "exposureEV")
        }
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = exposure
        image = try output(of: filter, index: index, operation: "exposureEV")

      case .contrast(let delta):
        try validateNormalized(delta, index: index, operation: "contrast")
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = Float(RecipeRenderContractV1.contrastFactor(for: delta))
        filter.saturation = 1
        filter.brightness = 0
        image = try output(of: filter, index: index, operation: "contrast")

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
        image = try output(of: filter, index: index, operation: "saturation")

      case .threeWayColorGrade(let grade):
        image = try ThreeWayColorGradeRenderer.apply(image, grade: grade, index: index)

      case .maskedAdjustment(let adjustment):
        guard let mask = recipe.masks.first(where: { $0.id == adjustment.maskID }) else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "maskedAdjustment")
        }
        guard case .version1(let graph) = try mask.decodeGraphPayload() else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "maskedAdjustment")
        }
        let maskImage = try LocalMaskRenderer.apply(
          image,
          graph: graph,
          definitionIsInverted: mask.isInverted,
          index: index
        )
        var localImage = image
        if adjustment.exposureEV != 0 {
          let filter = CIFilter.exposureAdjust()
          filter.inputImage = localImage
          filter.ev = Float(adjustment.exposureEV)
          localImage = try output(of: filter, index: index, operation: "maskedExposure")
        }
        localImage = try ThreeWayColorGradeRenderer.apply(
          localImage,
          grade: adjustment.colorGrade,
          index: index
        )
        image = try LocalMaskRenderer.blend(
          foreground: localImage,
          background: image,
          mask: maskImage,
          index: index
        )

      case .normalizedCrop(let crop):
        image = try cropImage(image, crop: crop, index: index)

      case .rotationDegrees(let degrees):
        guard degrees.isFinite else {
          throw invalid(index, "rotationDegrees")
        }
        image = try rotateImage(image, degrees: degrees, index: index)

      case .toneCurve(let adjustment):
        image = try toneCurveImage(image, adjustment: adjustment, index: index)

      case .whiteBalance(let adjustment):
        image = try whiteBalanceImage(image, adjustment: adjustment, index: index)

      case .transform(let adjustment):
        image = try transformImage(image, adjustment: adjustment, index: index)

      case .detail(let adjustment):
        image = try detailImage(image, adjustment: adjustment, index: index)

      case .optics(let adjustment):
        image = try vignetteImage(
          image,
          intensity: -adjustment.vignetteCorrection,
          index: index,
          operation: "optics"
        )

      case .effects(let adjustment):
        image = try vignetteImage(
          image,
          intensity: adjustment.vignetteAmount,
          index: index,
          operation: "effects"
        )

      case .calibration(let adjustment):
        image = try calibrationImage(image, adjustment: adjustment, index: index)

      case .blackAndWhite(let adjustment):
        image = try blackAndWhiteImage(image, adjustment: adjustment, index: index)

      case .hdr:
        // Version 1 records HDR intent. The current extended-range graph already
        // preserves available headroom and does not add an HDR output transform.
        break

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

  private static func toneCurveImage(
    _ image: CIImage,
    adjustment: ToneCurveAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    if adjustment.blackPoint == 0,
      adjustment.shadows == 0.25,
      adjustment.midtones == 0.5,
      adjustment.highlights == 0.75,
      adjustment.whitePoint == 1
    {
      return image
    }
    let filter = CIFilter.toneCurve()
    filter.inputImage = image
    filter.point0 = CGPoint(x: 0, y: adjustment.blackPoint)
    filter.point1 = CGPoint(x: 0.25, y: adjustment.shadows)
    filter.point2 = CGPoint(x: 0.5, y: adjustment.midtones)
    filter.point3 = CGPoint(x: 0.75, y: adjustment.highlights)
    filter.point4 = CGPoint(x: 1, y: adjustment.whitePoint)
    if #available(macOS 26, *) {
      filter.extrapolate = true
    }
    return try output(of: filter, index: index, operation: "toneCurve")
  }

  private static func whiteBalanceImage(
    _ image: CIImage,
    adjustment: WhiteBalanceAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    guard adjustment.temperature != 0 || adjustment.tint != 0 else { return image }
    let filter = CIFilter.temperatureAndTint()
    filter.inputImage = image
    filter.neutral = CIVector(x: 6_500, y: 0)
    filter.targetNeutral = CIVector(
      x: RecipeRenderContractV1.whiteBalanceTemperature(for: adjustment.temperature),
      y: RecipeRenderContractV1.whiteBalanceTint(for: adjustment.tint)
    )
    return try output(of: filter, index: index, operation: "whiteBalance")
  }

  private static func transformImage(
    _ image: CIImage,
    adjustment: TransformAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    var transformed = image
    if adjustment.flipHorizontal || adjustment.flipVertical {
      let extent = transformed.extent
      let flip = CGAffineTransform(
        a: adjustment.flipHorizontal ? -1 : 1,
        b: 0,
        c: 0,
        d: adjustment.flipVertical ? -1 : 1,
        tx: adjustment.flipHorizontal ? extent.width : 0,
        ty: adjustment.flipVertical ? extent.height : 0
      )
      transformed = normalizeOrigin(transformed.transformed(by: flip))
    }
    guard adjustment.straightenDegrees != 0 else { return transformed }
    return try rotateImage(
      transformed,
      degrees: adjustment.straightenDegrees,
      index: index,
      operation: "transform"
    )
  }

  private static func detailImage(
    _ image: CIImage,
    adjustment: DetailAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    var adjusted = image
    if adjustment.luminanceNoiseReduction > 0 {
      let filter = CIFilter.noiseReduction()
      filter.inputImage = adjusted
      filter.noiseLevel = Float(
        RecipeRenderContractV1.noiseLevel(for: adjustment.luminanceNoiseReduction)
      )
      filter.sharpness = 0
      adjusted = try output(of: filter, index: index, operation: "detail")
    }
    if adjustment.sharpening > 0 {
      let filter = CIFilter.sharpenLuminance()
      filter.inputImage = adjusted
      filter.radius = Float(RecipeRenderContractV1.sharpenRadius(for: adjustment.sharpening))
      filter.sharpness = Float(RecipeRenderContractV1.sharpness(for: adjustment.sharpening))
      adjusted = try output(of: filter, index: index, operation: "detail")
    }
    return adjusted
  }

  private static func vignetteImage(
    _ image: CIImage,
    intensity: Double,
    index: Int,
    operation: String
  ) throws -> CIImage {
    guard intensity != 0 else { return image }
    let filter = CIFilter.vignette()
    filter.inputImage = image
    filter.intensity = Float(intensity)
    filter.radius = 1
    return try output(of: filter, index: index, operation: operation)
  }

  private static func calibrationImage(
    _ image: CIImage,
    adjustment: CalibrationAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    guard adjustment.redGain != 0 || adjustment.greenGain != 0 || adjustment.blueGain != 0
    else { return image }
    let filter = CIFilter.colorMatrix()
    filter.inputImage = image
    filter.rVector = CIVector(
      x: RecipeRenderContractV1.calibrationFactor(for: adjustment.redGain),
      y: 0,
      z: 0,
      w: 0
    )
    filter.gVector = CIVector(
      x: 0,
      y: RecipeRenderContractV1.calibrationFactor(for: adjustment.greenGain),
      z: 0,
      w: 0
    )
    filter.bVector = CIVector(
      x: 0,
      y: 0,
      z: RecipeRenderContractV1.calibrationFactor(for: adjustment.blueGain),
      w: 0
    )
    filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    return try output(of: filter, index: index, operation: "calibration")
  }

  private static func blackAndWhiteImage(
    _ image: CIImage,
    adjustment: BlackAndWhiteAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    let sum = adjustment.redWeight + adjustment.greenWeight + adjustment.blueWeight
    let mix = CIVector(
      x: adjustment.redWeight / sum,
      y: adjustment.greenWeight / sum,
      z: adjustment.blueWeight / sum,
      w: 0
    )
    let filter = CIFilter.colorMatrix()
    filter.inputImage = image
    filter.rVector = mix
    filter.gVector = mix
    filter.bVector = mix
    filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    filter.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    return try output(of: filter, index: index, operation: "blackAndWhite")
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
    index: Int,
    operation: String = "rotationDegrees"
  ) throws -> CIImage {
    let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
    let positiveDegrees = normalizedDegrees < 0 ? normalizedDegrees + 360 : normalizedDegrees
    let extent = image.extent
    let width = extent.width
    let height = extent.height
    let transform: CGAffineTransform

    if positiveDegrees == 0 {
      return image
    } else if positiveDegrees == 90 {
      transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
    } else if positiveDegrees == 180 {
      transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
    } else if positiveDegrees == 270 {
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
    let boundingBox = extent.applying(transform).integral
    guard validExtent(boundingBox) else {
      throw invalid(index, operation)
    }
    let transparentCanvas = CIImage(color: .clear).cropped(to: boundingBox)
    return
      rotated
      .composited(over: transparentCanvas)
      .cropped(to: boundingBox)
      .transformed(
        by: CGAffineTransform(
          translationX: -boundingBox.minX,
          y: -boundingBox.minY
        )
      )
  }

  private static func output(
    of filter: CIFilter,
    index: Int,
    operation: String
  ) throws -> CIImage {
    guard let output = filter.outputImage, validExtent(output.extent) else {
      throw invalid(index, operation)
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

  private static func invalid(_ index: Int, _ operation: String) -> RenderCoreError {
    .invalidOperationValue(index: index, operation: operation)
  }
}
