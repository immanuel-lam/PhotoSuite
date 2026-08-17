// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import ImageIO
import Metal
import PhotoDomain
import UniformTypeIdentifiers

public actor AppleRawDecoder: RawDecoder {
  struct DecodedImage {
    let image: CIImage
    let metadata: [String: String]
    let decoderIdentifier: String
    let decoderVersion: String
  }

  let device: any MTLDevice
  let context: CIContext
  let workingColorSpace: CGColorSpace
  let previewColorSpace: CGColorSpace
  let sRGBColorSpace: CGColorSpace

  public init() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw RenderCoreError.metalUnavailable
    }
    guard
      let acescg = CGColorSpace(name: CGColorSpace.acescgLinear),
      let extendedACEScg = CGColorSpaceCreateExtended(acescg),
      CGColorSpaceUsesExtendedRange(extendedACEScg)
    else {
      throw RenderCoreError.colorSpaceUnavailable("extended ACEScg")
    }
    guard
      let previewColorSpace = CGColorSpace(
        name: CGColorSpace.extendedLinearDisplayP3
      )
    else {
      throw RenderCoreError.colorSpaceUnavailable("extended-linear Display P3")
    }
    guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw RenderCoreError.colorSpaceUnavailable("sRGB")
    }

    self.device = device
    self.workingColorSpace = extendedACEScg
    self.previewColorSpace = previewColorSpace
    self.sRGBColorSpace = sRGBColorSpace
    self.context = CIContext(
      mtlDevice: device,
      options: [
        .workingColorSpace: extendedACEScg,
        .workingFormat: CIFormat.RGBAh,
        .outputColorSpace: previewColorSpace,
      ]
    )
  }

  public func decode(_ request: RawDecodeRequest) async throws -> RawDecodeResult {
    try Task.checkCancellation()
    let decoded = try decodeImage(
      at: request.sourceURL,
      decoderVersion: request.decoderVersion
    )
    try Task.checkCancellation()
    let extent = decoded.image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard
      let dimensions = PixelDimensions(width: width, height: height),
      width <= Int.max / 4,
      height <= Int.max / (width * 4)
    else {
      throw RenderCoreError.renderFailed
    }
    let bytesPerRow = width * 4
    var data = Data(count: bytesPerRow * height)
    try Task.checkCancellation()
    data.withUnsafeMutableBytes { buffer in
      guard let address = buffer.baseAddress else { return }
      context.render(
        decoded.image,
        toBitmap: address,
        rowBytes: bytesPerRow,
        bounds: extent,
        format: .RGBA8,
        colorSpace: sRGBColorSpace
      )
    }
    try Task.checkCancellation()

    return RawDecodeResult(
      image: ImageBuffer(
        data: data,
        dimensions: dimensions,
        bytesPerRow: UInt(bytesPerRow),
        pixelFormat: .rgba8,
        colorSpaceName: "sRGB"
      ),
      metadata: decoded.metadata,
      decoderIdentifier: decoded.decoderIdentifier,
      decoderVersion: decoded.decoderVersion
    )
  }

  public func capabilities(_ request: RawCapabilityRequest) async throws -> RawCapabilityResult {
    try Task.checkCancellation()
    let versions: [String]
    if let sourceURL = request.sourceURL,
      isRAWSource(at: sourceURL),
      let raw = CIRAWFilter(imageURL: sourceURL)
    {
      versions = raw.supportedDecoderVersions.map(\.rawValue)
    } else {
      versions = []
    }
    try Task.checkCancellation()

    return RawCapabilityResult(
      supportedCameraModels: CIRAWFilter.supportedCameraModels,
      supportedDecoderVersions: versions
    )
  }

  public func preview(
    sourceURL: URL,
    recipe: EditRecipe,
    maximumPixelDimension: Int?
  ) throws -> CGImage {
    try Task.checkCancellation()
    var image = try compiledImage(sourceURL: sourceURL, recipe: recipe)
    try Task.checkCancellation()
    var renderBounds = image.extent

    if let maximumPixelDimension {
      guard maximumPixelDimension > 0 else {
        throw RenderCoreError.invalidMaximumPixelDimension(maximumPixelDimension)
      }
      let longestEdge = max(renderBounds.width, renderBounds.height)
      if longestEdge > CGFloat(maximumPixelDimension) {
        let scale = CGFloat(maximumPixelDimension) / longestEdge
        let targetWidth = max(1, Int(floor(renderBounds.width * scale)))
        let targetHeight = max(1, Int(floor(renderBounds.height * scale)))
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        guard let scaled = filter.outputImage else {
          throw RenderCoreError.renderFailed
        }
        renderBounds = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        image = scaled.cropped(to: renderBounds)
      }
    }
    try Task.checkCancellation()
    guard
      let output = context.createCGImage(
        image,
        from: renderBounds,
        format: .RGBAh,
        colorSpace: previewColorSpace
      )
    else {
      throw RenderCoreError.renderFailed
    }
    try Task.checkCancellation()
    return output
  }

  func exportJPEG(
    _ request: ExportRequest,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating
  ) async throws -> ExportResult {
    try Task.checkCancellation()
    guard case .jpeg = request.format else {
      throw RenderCoreError.unsupportedExportFormat(exportFormatName(request.format))
    }
    let quality = request.quality ?? 0.9
    guard quality.isFinite, (0...1).contains(quality) else {
      throw RenderCoreError.invalidJPEGQuality(quality)
    }
    guard request.destinationURL.isFileURL else {
      throw RenderCoreError.invalidDestination(request.destinationURL)
    }

    let resolvedSource = request.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedDestination = request.destinationURL.standardizedFileURL.resolvingSymlinksInPath()
    guard resolvedSource != resolvedDestination else {
      throw RenderCoreError.sourceDestinationConflict(request.sourceURL)
    }

    let image = try compiledImage(sourceURL: request.sourceURL, recipe: request.recipe)
    try Task.checkCancellation()
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
      .cropped(to: image.extent)
    let opaqueImage = image.composited(over: black).cropped(to: image.extent)
    let destinationDirectory = request.destinationURL.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: destinationDirectory.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue
    else {
      throw RenderCoreError.invalidDestination(request.destinationURL)
    }
    let temporaryURL = destinationDirectory.appendingPathComponent(
      ".\(request.destinationURL.lastPathComponent).photosuite-tmp-\(UUID().uuidString)"
    )
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    try Task.checkCancellation()
    do {
      try context.writeJPEGRepresentation(
        of: opaqueImage,
        to: temporaryURL,
        colorSpace: sRGBColorSpace,
        options: [
          kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality
        ]
      )
    } catch {
      throw RenderCoreError.jpegEncodingFailed(request.destinationURL)
    }
    try Task.checkCancellation()

    guard
      let temporaryData = try? Data(contentsOf: temporaryURL),
      !temporaryData.isEmpty,
      let imageSource = CGImageSourceCreateWithData(temporaryData as CFData, nil),
      CGImageSourceGetType(imageSource) as String? == UTType.jpeg.identifier
    else {
      throw RenderCoreError.jpegEncodingFailed(request.destinationURL)
    }
    try Task.checkCancellation()
    let digest = SHA256.hash(data: temporaryData)
      .map { String(format: "%02x", $0) }
      .joined()
    guard
      let fingerprint = SourceFingerprint(
        sha256: digest,
        byteCount: UInt64(temporaryData.count),
        modificationDate: nil
      )
    else {
      throw RenderCoreError.jpegEncodingFailed(request.destinationURL)
    }

    await publicationGate.waitBeforePublication()
    try Task.checkCancellation()
    do {
      try publisher.publish(
        temporaryURL: temporaryURL,
        destinationURL: request.destinationURL
      )
    } catch {
      throw RenderCoreError.atomicWriteFailed(request.destinationURL)
    }

    return ExportResult(
      derivative: DurableDerivative(
        schemaVersion: 1,
        assetID: request.recipe.assetID,
        recipeRevision: request.recipe.revision,
        kind: .export,
        outputURL: request.destinationURL,
        typeIdentifier: UTType.jpeg.identifier,
        fingerprint: fingerprint,
        createdAt: Date()
      )
    )
  }

  private func compiledImage(sourceURL: URL, recipe: EditRecipe) throws -> CIImage {
    try Task.checkCancellation()
    let decoderVersion =
      recipe.pins.decoderIdentifier == "com.apple.ciraw"
      ? recipe.pins.decoderVersion
      : nil
    let decoded = try decodeImage(at: sourceURL, decoderVersion: decoderVersion)
    try Task.checkCancellation()
    guard decoded.decoderIdentifier == recipe.pins.decoderIdentifier else {
      throw RenderCoreError.decoderIdentifierMismatch(
        expected: recipe.pins.decoderIdentifier,
        actual: decoded.decoderIdentifier
      )
    }
    guard decoded.decoderVersion == recipe.pins.decoderVersion else {
      throw RenderCoreError.decoderVersionMismatch(
        expected: recipe.pins.decoderVersion,
        actual: decoded.decoderVersion
      )
    }
    let image = try EditGraphCompiler.compile(decoded.image, recipe: recipe)
    try Task.checkCancellation()
    return image
  }

  private func exportFormatName(_ format: ExportFormat) -> String {
    switch format {
    case .jpeg: "jpeg"
    case .heif: "heif"
    case .tiff: "tiff"
    case .unknown(let value): value
    }
  }

  func decodeImage(at sourceURL: URL, decoderVersion: String?) throws -> DecodedImage {
    let values = try? sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
    guard values?.isRegularFile == true, values?.isReadable != false else {
      throw RenderCoreError.unreadableSource(sourceURL)
    }

    if isRAWSource(at: sourceURL) {
      guard let raw = CIRAWFilter(imageURL: sourceURL) else {
        throw RenderCoreError.unsupportedSource(sourceURL)
      }
      if let decoderVersion {
        guard
          let supportedVersion = raw.supportedDecoderVersions.first(where: {
            $0.rawValue == decoderVersion
          })
        else {
          throw RenderCoreError.unsupportedDecoderVersion(decoderVersion)
        }
        raw.decoderVersion = supportedVersion
      }
      guard let image = raw.outputImage else {
        throw RenderCoreError.corruptSource(sourceURL)
      }
      return DecodedImage(
        image: try normalized(image, sourceURL: sourceURL),
        metadata: stringMetadata(from: raw.properties),
        decoderIdentifier: "com.apple.ciraw",
        decoderVersion: raw.decoderVersion.rawValue
      )
    }

    if let image = CIImage(
      contentsOf: sourceURL,
      options: [.applyOrientationProperty: true]
    ) {
      return DecodedImage(
        image: try normalized(image, sourceURL: sourceURL),
        metadata: stringMetadata(from: image.properties),
        decoderIdentifier: "com.apple.coreimage.common-image",
        decoderVersion: "system-default"
      )
    }

    if isRecognizedImageContainer(at: sourceURL) {
      throw RenderCoreError.corruptSource(sourceURL)
    }
    throw RenderCoreError.unsupportedSource(sourceURL)
  }

  private func normalized(_ image: CIImage, sourceURL: URL) throws -> CIImage {
    let extent = image.extent
    guard
      extent.origin.x.isFinite,
      extent.origin.y.isFinite,
      extent.width.isFinite,
      extent.height.isFinite,
      !extent.isEmpty,
      extent.width > 0,
      extent.height > 0
    else {
      throw RenderCoreError.corruptSource(sourceURL)
    }
    return image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
  }

  private func stringMetadata(from properties: [AnyHashable: Any]) -> [String: String] {
    properties.reduce(into: [:]) { result, entry in
      guard let key = entry.key as? String else { return }
      switch entry.value {
      case let value as String:
        result[key] = value
      case let value as NSNumber:
        result[key] = value.stringValue
      default:
        break
      }
    }
  }

  private func isRAWSource(at sourceURL: URL) -> Bool {
    if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let detectedType = CGImageSourceGetType(source),
      UTType(detectedType as String)?.conforms(to: .rawImage) == true
    {
      return true
    }
    return (try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType)?
      .conforms(to: .rawImage) == true
  }

  private func isRecognizedImageContainer(at sourceURL: URL) -> Bool {
    if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let detectedType = CGImageSourceGetType(source),
      UTType(detectedType as String)?.conforms(to: .image) == true
    {
      return true
    }
    guard let prefix = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe]).prefix(12) else {
      return false
    }
    let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    return prefix.starts(with: pngSignature)
      || prefix.starts(with: [0xFF, 0xD8, 0xFF])
      || prefix.starts(with: [0x49, 0x49, 0x2A, 0x00])
      || prefix.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
  }
}
