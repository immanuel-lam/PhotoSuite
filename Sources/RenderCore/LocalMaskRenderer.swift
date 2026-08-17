// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreImage
import Foundation
import PhotoDomain

/// Version-one deterministic mask rasterisation. The output is a single-channel
/// equivalent image (the coverage is repeated into RGB and alpha) in the input
/// image's extent. AI masks and depth maps are not available here; a depth range
/// uses the source luminance as a documented deterministic fallback.
enum LocalMaskRenderer {
  private static let brushKernel = CIColorKernel(
    source: """
      kernel vec4 brushMask(
        sampler image,
        vec2 point,
        vec2 imageSize,
        float radius,
        float feather,
        float flow,
        float pressure
      ) {
        vec4 pixel = sample(image, samplerCoord(image));
        vec2 normalized = destCoord() / imageSize;
        normalized.y = 1.0 - normalized.y;
        float distance = length(normalized - point);
        float inner = radius * max(0.0, 1.0 - feather);
        float t = clamp((distance - inner) / max(radius - inner, 0.0001), 0.0, 1.0);
        float coverage = (1.0 - (t * t * (3.0 - 2.0 * t))) * flow * pressure;
        coverage = clamp(coverage, 0.0, 1.0);
        return vec4(coverage, coverage, coverage, pixel.a * 0.0 + coverage);
      }
      """
  )

  private static let linearKernel = CIColorKernel(
    source: """
      kernel vec4 linearMask(
        sampler image,
        vec2 start,
        vec2 end,
        vec2 imageSize,
        float feather
      ) {
        vec2 normalized = destCoord() / imageSize;
        normalized.y = 1.0 - normalized.y;
        vec2 direction = end - start;
        float denominator = max(dot(direction, direction), 0.0001);
        float progress = dot(normalized - start, direction) / denominator;
        float coverage = 1.0 - clamp(progress, 0.0, 1.0);
        float softened = max(feather, 0.0001);
        coverage = smoothstep(0.0, softened, coverage) * (1.0 - smoothstep(1.0 - softened, 1.0, progress));
        coverage = clamp(coverage, 0.0, 1.0);
        return vec4(coverage, coverage, coverage, coverage);
      }
      """
  )

  private static let radialKernel = CIColorKernel(
    source: """
      kernel vec4 radialMask(
        sampler image,
        vec2 center,
        vec2 radii,
        vec2 imageSize,
        float rotation,
        float feather
      ) {
        vec2 normalized = destCoord() / imageSize;
        normalized.y = 1.0 - normalized.y;
        vec2 delta = normalized - center;
        float radians = rotation * 0.0174532925199433;
        float cosine = cos(radians);
        float sine = sin(radians);
        vec2 rotated = vec2(
          delta.x * cosine + delta.y * sine,
          -delta.x * sine + delta.y * cosine
        );
        float distance = length(rotated / radii);
        float inner = max(0.0, 1.0 - feather);
        float t = clamp((distance - inner) / max(1.0 - inner, 0.0001), 0.0, 1.0);
        float coverage = 1.0 - (t * t * (3.0 - 2.0 * t));
        coverage = clamp(coverage, 0.0, 1.0);
        return vec4(coverage, coverage, coverage, coverage);
      }
      """
  )

  private static let colorRangeKernel = CIColorKernel(
    source: """
      kernel vec4 colorRangeMask(
        sampler image,
        vec3 target,
        float tolerance,
        float feather
      ) {
        vec4 pixel = sample(image, samplerCoord(image));
        float distance = length(pixel.rgb - target);
        float outer = min(1.7320508, tolerance + max(feather, 0.0001));
        float coverage = 1.0 - smoothstep(tolerance, outer, distance);
        coverage = clamp(coverage, 0.0, 1.0);
        return vec4(coverage, coverage, coverage, coverage);
      }
      """
  )

  private static let luminanceRangeKernel = CIColorKernel(
    source: """
      kernel vec4 luminanceRangeMask(
        sampler image,
        float lower,
        float upper,
        float feather
      ) {
        vec4 pixel = sample(image, samplerCoord(image));
        float luminance = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
        float softness = max(feather, 0.0001);
        float lowerCoverage = smoothstep(max(0.0, lower - softness), lower + softness, luminance);
        float upperCoverage = 1.0 - smoothstep(upper - softness, min(1.0, upper + softness), luminance);
        float coverage = clamp(lowerCoverage * upperCoverage, 0.0, 1.0);
        return vec4(coverage, coverage, coverage, coverage);
      }
      """
  )

  static func apply(
    _ image: CIImage,
    graph: MaskGraphV1,
    definitionIsInverted: Bool,
    index: Int
  ) throws -> CIImage {
    var coverage: CIImage?
    for component in graph.components {
      let primitive = try rasterize(
        component.primitive,
        image: image,
        index: index
      )
      if let existing = coverage {
        coverage = try combine(
          existing,
          primitive,
          operation: component.operation,
          extent: image.extent,
          index: index
        )
      } else {
        switch component.operation {
        case .add:
          coverage = primitive
        case .subtract:
          coverage = try invert(primitive, extent: image.extent, index: index)
        case .intersect:
          coverage = primitive
        case .unknown:
          throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
        }
      }
    }

    guard var result = coverage else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    // MaskDefinition.isInverted is the current durable toggle. The graph's
    // isInverted field is retained for forward-compatible graph round trips,
    // but the definition value must win because workspace toggles update it
    // without rewriting the graph payload.
    if definitionIsInverted {
      result = try invert(result, extent: image.extent, index: index)
    }
    return result.cropped(to: image.extent)
  }

  static func blend(
    foreground: CIImage,
    background: CIImage,
    mask: CIImage,
    index: Int
  ) throws -> CIImage {
    guard let filter = CIFilter(name: "CIBlendWithMask") else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "maskedAdjustment")
    }
    filter.setValue(foreground, forKey: kCIInputImageKey)
    filter.setValue(background, forKey: kCIInputBackgroundImageKey)
    filter.setValue(mask, forKey: kCIInputMaskImageKey)
    guard let output = filter.outputImage else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "maskedAdjustment")
    }
    return output.cropped(to: background.extent)
  }

  private static func rasterize(
    _ primitive: MaskPrimitiveV1,
    image: CIImage,
    index: Int
  ) throws -> CIImage {
    switch primitive {
    case .brush(let brush):
      var result: CIImage?
      for sample in brush.samples {
        guard let kernel = brushKernel else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "brushMask")
        }
        guard
          let sampleMask = kernel.apply(
            extent: image.extent,
            arguments: [
              image,
              point(sample.point),
              size(of: image),
              brush.radius,
              brush.feather,
              brush.flow,
              sample.pressure,
            ]
          )
        else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "brushMask")
        }
        result =
          try result.map {
            try combine($0, sampleMask, operation: .add, extent: image.extent, index: index)
          } ?? sampleMask
      }
      guard let result else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "brushMask")
      }
      return result

    case .linearGradient(let gradient):
      guard let kernel = linearKernel else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "linearMask")
      }
      guard
        let output = kernel.apply(
          extent: image.extent,
          arguments: [
            image,
            point(gradient.start),
            point(gradient.end),
            size(of: image),
            gradient.feather,
          ]
        )
      else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "linearMask")
      }
      return output

    case .radialGradient(let gradient):
      guard let kernel = radialKernel else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "radialMask")
      }
      guard
        let output = kernel.apply(
          extent: image.extent,
          arguments: [
            image,
            point(gradient.center),
            CIVector(x: gradient.radiusX, y: gradient.radiusY),
            size(of: image),
            gradient.rotationDegrees,
            gradient.feather,
          ]
        )
      else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "radialMask")
      }
      return output

    case .colorRange(let range):
      var result: CIImage?
      for sample in range.samples {
        guard let kernel = colorRangeKernel else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "colorMask")
        }
        guard
          let sampleMask = kernel.apply(
            extent: image.extent,
            arguments: [
              image,
              CIVector(x: sample.red, y: sample.green, z: sample.blue),
              range.tolerance,
              range.feather,
            ]
          )
        else {
          throw RenderCoreError.invalidOperationValue(index: index, operation: "colorMask")
        }
        result =
          try result.map {
            try combine($0, sampleMask, operation: .add, extent: image.extent, index: index)
          } ?? sampleMask
      }
      guard let result else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "colorMask")
      }
      return result

    case .luminanceRange(let range):
      return try luminanceMask(
        image: image,
        lower: range.lowerBound,
        upper: range.upperBound,
        feather: range.feather,
        index: index
      )

    case .depthRange(let range):
      // No depth attachment exists in ImageBuffer/CIImage yet. Luminance is a
      // stable fallback so a depth-range recipe remains deterministic instead
      // of silently becoming a full-image adjustment.
      return try luminanceMask(
        image: image,
        lower: range.nearBound,
        upper: range.farBound,
        feather: range.feather,
        index: index
      )

    case .unknown:
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
  }

  private static func luminanceMask(
    image: CIImage,
    lower: Double,
    upper: Double,
    feather: Double,
    index: Int
  ) throws -> CIImage {
    guard let kernel = luminanceRangeKernel else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "luminanceMask")
    }
    guard
      let output = kernel.apply(
        extent: image.extent,
        arguments: [image, lower, upper, feather]
      )
    else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "luminanceMask")
    }
    return output
  }

  private static func combine(
    _ left: CIImage,
    _ right: CIImage,
    operation: MaskCombinationOperation,
    extent: CGRect,
    index: Int
  ) throws -> CIImage {
    let filterName: String
    switch operation {
    case .add: filterName = "CIMaximumCompositing"
    case .intersect: filterName = "CIMinimumCompositing"
    case .subtract:
      let inverted = try invert(right, extent: extent, index: index)
      guard let filter = CIFilter(name: "CIBlendWithMask") else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
      }
      let clear = CIImage(color: .clear).cropped(to: extent)
      filter.setValue(left, forKey: kCIInputImageKey)
      filter.setValue(clear, forKey: kCIInputBackgroundImageKey)
      filter.setValue(inverted, forKey: kCIInputMaskImageKey)
      guard let output = filter.outputImage else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
      }
      return output.cropped(to: extent)
    case .unknown:
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    guard let filter = CIFilter(name: filterName) else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    filter.setValue(right, forKey: kCIInputImageKey)
    filter.setValue(left, forKey: kCIInputBackgroundImageKey)
    guard let output = filter.outputImage else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    return output.cropped(to: extent)
  }

  private static func invert(_ image: CIImage, extent: CGRect, index: Int) throws -> CIImage {
    guard let filter = CIFilter(name: "CIColorMatrix") else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(x: -1, y: 0, z: 0, w: 0), forKey: "inputRVector")
    filter.setValue(CIVector(x: 0, y: -1, z: 0, w: 0), forKey: "inputGVector")
    filter.setValue(CIVector(x: 0, y: 0, z: -1, w: 0), forKey: "inputBVector")
    filter.setValue(CIVector(x: 0, y: 0, z: 0, w: -1), forKey: "inputAVector")
    filter.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputBiasVector")
    guard let output = filter.outputImage else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "mask")
    }
    return output.cropped(to: extent)
  }

  private static func point(_ point: MaskPointV1) -> CIVector {
    CIVector(x: point.x, y: point.y)
  }

  private static func size(of image: CIImage) -> CIVector {
    CIVector(x: image.extent.width, y: image.extent.height)
  }
}
