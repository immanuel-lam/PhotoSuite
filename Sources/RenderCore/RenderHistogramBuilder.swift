// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import ImageIO
import PhotoDomain

enum RenderHistogramBuilder {
  static func make(from imageData: Data) throws -> RenderHistogram {
    guard
      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw RenderCoreError.renderFailed
    }

    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { throw RenderCoreError.renderFailed }
    let bytesPerRow = width * 4
    var pixels = Data(count: bytesPerRow * height)
    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let address = buffer.baseAddress,
        let context = CGContext(
          data: address,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return false
      }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else { throw RenderCoreError.renderFailed }

    var red = Array(repeating: UInt64.zero, count: RenderHistogram.binCount)
    var green = Array(repeating: UInt64.zero, count: RenderHistogram.binCount)
    var blue = Array(repeating: UInt64.zero, count: RenderHistogram.binCount)
    var luminance = Array(repeating: UInt64.zero, count: RenderHistogram.binCount)
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let redValue = pixels[offset]
      let greenValue = pixels[offset + 1]
      let blueValue = pixels[offset + 2]
      red[Int(redValue)] += 1
      green[Int(greenValue)] += 1
      blue[Int(blueValue)] += 1
      let redLuminance = 0.2126 * Double(redValue)
      let greenLuminance = 0.7152 * Double(greenValue)
      let blueLuminance = 0.0722 * Double(blueValue)
      let luma = Int((redLuminance + greenLuminance + blueLuminance).rounded())
      luminance[luma] += 1
    }
    guard
      let histogram = RenderHistogram(
        red: red,
        green: green,
        blue: blue,
        luminance: luminance
      )
    else {
      throw RenderCoreError.renderFailed
    }
    return histogram
  }
}
