// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ImageIO
import PhotoDomain
import UniformTypeIdentifiers

public struct CoreImageRenderEngine: RenderEngine, Sendable {
  private let decoder: AppleRawDecoder

  public init(decoder: AppleRawDecoder) {
    self.decoder = decoder
  }

  public func render(_ request: RenderRequest) async throws -> RenderResult {
    guard request.outputColorSpaceName == "extended-linear-display-p3" else {
      throw RenderCoreError.unsupportedOutputColorSpace(request.outputColorSpaceName)
    }
    let image = try await decoder.preview(
      sourceURL: request.sourceURL,
      recipe: request.recipe,
      maximumPixelDimension: request.maximumPixelDimension
    )
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw RenderCoreError.renderFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw RenderCoreError.renderFailed
    }
    guard let dimensions = PixelDimensions(width: image.width, height: image.height) else {
      throw RenderCoreError.renderFailed
    }
    return RenderResult(
      imageData: data as Data,
      typeIdentifier: UTType.png.identifier,
      pixelDimensions: dimensions
    )
  }
}
