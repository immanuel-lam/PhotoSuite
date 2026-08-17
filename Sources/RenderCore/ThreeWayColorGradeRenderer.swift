// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreImage
import Foundation
import PhotoDomain

enum ThreeWayColorGradeRenderer {
  private static let kernel = CIColorKernel(
    source: """
      kernel vec4 applyThreeWayColorGrade(
        sampler image,
        vec3 shadowAdjustment,
        vec3 midtoneAdjustment,
        vec3 highlightAdjustment
      ) {
        vec4 pixel = sample(image, samplerCoord(image));
        float luminance = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
        float shadows = 1.0 - smoothstep(0.18, 0.50, luminance);
        float highlights = smoothstep(0.50, 0.82, luminance);
        float midtones = max(0.0, 1.0 - shadows - highlights);
        pixel.rgb += shadowAdjustment * shadows;
        pixel.rgb += midtoneAdjustment * midtones;
        pixel.rgb += highlightAdjustment * highlights;
        return pixel;
      }
      """)

  static func apply(
    _ image: CIImage,
    grade: ThreeWayColorGrade,
    index: Int
  ) throws -> CIImage {
    guard !grade.isNeutral else { return image }
    guard let kernel else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "threeWayColorGrade")
    }
    guard
      let output = kernel.apply(
        extent: image.extent,
        arguments: [
          image,
          adjustment(for: grade.shadows),
          adjustment(for: grade.midtones),
          adjustment(for: grade.highlights),
        ]
      )
    else {
      throw RenderCoreError.invalidOperationValue(index: index, operation: "threeWayColorGrade")
    }
    return output
  }

  private static func adjustment(for tone: ThreeWayColorGrade.Tone) -> CIVector {
    let hue = tone.hueDegrees.truncatingRemainder(dividingBy: 360) / 60
    let sector = Int(floor(hue))
    let fraction = hue - floor(hue)
    let primary: (Double, Double, Double)

    switch sector {
    case 0: primary = (1, fraction, 0)
    case 1: primary = (1 - fraction, 1, 0)
    case 2: primary = (0, 1, fraction)
    case 3: primary = (0, 1 - fraction, 1)
    case 4: primary = (fraction, 0, 1)
    default: primary = (1, 0, 1 - fraction)
    }

    let primaryLuminance = 0.2126 * primary.0 + 0.7152 * primary.1 + 0.0722 * primary.2
    return CIVector(
      x: CGFloat((primary.0 - primaryLuminance) * tone.chroma + tone.luminance),
      y: CGFloat((primary.1 - primaryLuminance) * tone.chroma + tone.luminance),
      z: CGFloat((primary.2 - primaryLuminance) * tone.chroma + tone.luminance)
    )
  }
}
