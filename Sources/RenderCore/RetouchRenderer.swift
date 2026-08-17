// SPDX-License-Identifier: MPL-2.0

import CoreGraphics
import CoreImage
import Foundation
import PhotoDomain

/// Identity carried by an asynchronous retouch request. A result is accepted
/// only when both the asset revision and request token still match the draft.
public struct RetouchRequestIdentity: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let recipeRevision: UInt64
  public let requestID: UUID

  public init(assetID: UUID, recipeRevision: UInt64, requestID: UUID) {
    self.assetID = assetID
    self.recipeRevision = recipeRevision
    self.requestID = requestID
  }
}

public enum RetouchResultGate {
  public static func accepts(
    result: RetouchRequestIdentity,
    for current: RetouchRequestIdentity
  ) -> Bool {
    result == current
  }
}

/// Version-one deterministic local retouch rendering.
///
/// Clone copies a translated source patch through a pressure-aware brush mask.
/// Healing uses the same source patch with a bounded Gaussian softening before
/// blending. Neither operation writes to the original source image. Red-eye is
/// intentionally kept as a typed recipe operation but is rejected by the
/// compiler until a colour-aware implementation passes its quality gates.
enum RetouchRenderer {
  private static let brushComponentID = UUID(
    uuidString: "8F80A5D7-CCAC-4F56-A11C-7F19B6D9F0D5"
  )!

  static func applyClone(
    _ image: CIImage,
    adjustment: CloneAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    let patch = translatedPatch(
      image,
      sourceAnchor: adjustment.sourceAnchor,
      targetAnchor: adjustment.targetAnchor
    )
    let mask = try brushMask(image, brush: adjustment.brush, index: index)
    return try LocalMaskRenderer.blend(
      foreground: patch,
      background: image,
      mask: mask,
      index: index
    )
  }

  static func applyHealing(
    _ image: CIImage,
    adjustment: HealingAdjustmentV1,
    index: Int
  ) throws -> CIImage {
    let patch = translatedPatch(
      image,
      sourceAnchor: adjustment.sourceAnchor,
      targetAnchor: adjustment.targetAnchor
    )
    let extent = image.extent
    let longestEdge = max(extent.width, extent.height)
    let blurRadius = Float(max(0.1, min(24, longestEdge * adjustment.brush.radius * 0.08)))
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = patch
    blur.radius = blurRadius
    guard let softened = blur.outputImage?.cropped(to: extent) else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "healing")
    }

    // Keep a tunable portion of the sharp patch. This keeps healing bounded and
    // deterministic while avoiding a hard clone edge at the brush boundary.
    let blendMask = CIImage(
      color: CIColor(
        red: adjustment.blend,
        green: adjustment.blend,
        blue: adjustment.blend,
        alpha: adjustment.blend
      )
    ).cropped(to: extent)
    let softenedPatch = try LocalMaskRenderer.blend(
      foreground: softened,
      background: patch,
      mask: blendMask,
      index: index
    )
    let mask = try brushMask(image, brush: adjustment.brush, index: index)
    return try LocalMaskRenderer.blend(
      foreground: softenedPatch,
      background: image,
      mask: mask,
      index: index
    )
  }

  private static func translatedPatch(
    _ image: CIImage,
    sourceAnchor: RetouchPointV1,
    targetAnchor: RetouchPointV1
  ) -> CIImage {
    let extent = image.extent
    let deltaX = (targetAnchor.x - sourceAnchor.x) * extent.width
    // CIImage uses a bottom-left coordinate system while recipe points use a
    // top-left coordinate system.
    let deltaY = (sourceAnchor.y - targetAnchor.y) * extent.height
    return
      image
      .transformed(by: CGAffineTransform(translationX: deltaX, y: deltaY))
      .cropped(to: extent)
  }

  private static func brushMask(
    _ image: CIImage,
    brush: RetouchBrushV1,
    index: Int
  ) throws -> CIImage {
    var samples: [MaskBrushSampleV1] = []
    samples.reserveCapacity(brush.samples.count)
    for sample in brush.samples {
      guard
        let point = MaskPointV1(x: sample.point.x, y: sample.point.y),
        let converted = MaskBrushSampleV1(point: point, pressure: sample.pressure)
      else {
        throw RenderCoreError.invalidOperationValue(index: index, operation: "retouchBrush")
      }
      samples.append(converted)
    }
    guard
      let versionedBrush = BrushMaskV1(
        samples: samples,
        radius: brush.radius,
        feather: brush.feather,
        flow: brush.flow
      )
    else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "retouchBrush")
    }
    let graph = MaskGraphV1(
      components: [
        MaskGraphComponentV1(
          id: brushComponentID,
          operation: .add,
          primitive: .brush(versionedBrush)
        )
      ]
    )
    return try LocalMaskRenderer.apply(
      image,
      graph: graph,
      definitionIsInverted: false,
      index: index
    )
  }
}
