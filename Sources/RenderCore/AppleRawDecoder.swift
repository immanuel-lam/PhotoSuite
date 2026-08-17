// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import CryptoKit
import Foundation
import ImageIO
import Metal
import PhotoDomain
import UniformTypeIdentifiers

protocol AppleRAWFilterAccess: AnyObject {
  var supportedDecoderVersions: [String] { get }
  var decoderVersion: String { get }
  var outputImage: CIImage? { get }
  var properties: [AnyHashable: Any] { get }

  func selectDecoderVersion(_ version: String) -> Bool
}

protocol AppleRAWFilterProviding {
  func makeFilter(imageURL: URL) -> (any AppleRAWFilterAccess)?
}

private final class SystemAppleRAWFilter: AppleRAWFilterAccess {
  private let filter: CIRAWFilter

  init(filter: CIRAWFilter) {
    self.filter = filter
  }

  var supportedDecoderVersions: [String] {
    filter.supportedDecoderVersions.map(\.rawValue)
  }

  var decoderVersion: String { filter.decoderVersion.rawValue }
  var outputImage: CIImage? { filter.outputImage }
  var properties: [AnyHashable: Any] { filter.properties }

  func selectDecoderVersion(_ version: String) -> Bool {
    guard
      let selected = filter.supportedDecoderVersions.first(where: {
        $0.rawValue == version
      })
    else {
      return false
    }
    filter.decoderVersion = selected
    return true
  }
}

private struct SystemAppleRAWFilterProvider: AppleRAWFilterProviding {
  func makeFilter(imageURL: URL) -> (any AppleRAWFilterAccess)? {
    CIRAWFilter(imageURL: imageURL).map(SystemAppleRAWFilter.init)
  }
}

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
  private let rawFilterProvider: any AppleRAWFilterProviding

  public init() throws {
    try self.init(rawFilterProvider: SystemAppleRAWFilterProvider())
  }

  init(rawFilterProvider: any AppleRAWFilterProviding) throws {
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
    self.rawFilterProvider = rawFilterProvider
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
    let detectedSourceKind: RawSourceKind
    if let sourceURL = request.sourceURL,
      let raw = rawFilterProvider.makeFilter(imageURL: sourceURL),
      isRealRAWFilter(raw)
    {
      versions = raw.supportedDecoderVersions
      detectedSourceKind = .cirawRaw
    } else {
      versions = []
      detectedSourceKind = request.sourceURL.map { self.sourceKind(for: $0) } ?? .unknown
    }
    try Task.checkCancellation()

    return RawCapabilityResult(
      supportedCameraModels: CIRAWFilter.supportedCameraModels,
      supportedDecoderVersions: versions,
      sourceKind: detectedSourceKind
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
    publicationGate: any ExportPublicationGating,
    temporaryFileRemover: any TemporaryFileRemoving
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

    var image = try compiledImage(sourceURL: request.sourceURL, recipe: request.recipe)
    image = try applyingExportResize(request.options.resize, to: image)
    image = try applyingOutputSharpening(request.options.outputSharpening, to: image)
    image = try applyingWatermark(request.options.watermark, to: image)
    try Task.checkCancellation()
    let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
      .cropped(to: image.extent)
    let opaqueImage = image.composited(over: black).cropped(to: image.extent)
      .settingProperties(
        exportMetadataProperties(
          policy: request.options.metadata,
          sourceURL: request.sourceURL,
          outputExtent: image.extent
        )
      )
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
    let result: ExportResult
    do {
      result = try await encodeAndPublishJPEG(
        opaqueImage,
        request: request,
        quality: quality,
        temporaryURL: temporaryURL,
        publisher: publisher,
        publicationGate: publicationGate
      )
    } catch let primaryError {
      try removeTemporaryFileIfPresent(
        at: temporaryURL,
        remover: temporaryFileRemover,
        primaryError: primaryError
      )
      throw primaryError
    }
    try removeTemporaryFileIfPresent(
      at: temporaryURL,
      remover: temporaryFileRemover,
      primaryError: nil
    )
    return result
  }

  /// Exports the same compiled edit graph to the lossless and native image
  /// containers supported by ImageIO. JPEG remains on its existing Core Image
  /// writer so its established metadata and cancellation behaviour stay
  /// unchanged.
  func exportImage(
    _ request: ExportRequest,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating,
    temporaryFileRemover: any TemporaryFileRemoving
  ) async throws -> ExportResult {
    switch request.format {
    case .jpeg:
      return try await exportJPEG(
        request,
        publisher: publisher,
        publicationGate: publicationGate,
        temporaryFileRemover: temporaryFileRemover
      )
    case .png, .heif, .tiff:
      break
    case .unknown:
      throw RenderCoreError.unsupportedExportFormat(exportFormatName(request.format))
    }

    try Task.checkCancellation()
    guard request.destinationURL.isFileURL else {
      throw RenderCoreError.invalidDestination(request.destinationURL)
    }
    if case .heif = request.format, let quality = request.quality {
      guard quality.isFinite, (0...1).contains(quality) else {
        throw RenderCoreError.invalidImageQuality(format: "HEIF", value: quality)
      }
    }

    let resolvedSource = request.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedDestination = request.destinationURL.standardizedFileURL.resolvingSymlinksInPath()
    guard resolvedSource != resolvedDestination else {
      throw RenderCoreError.sourceDestinationConflict(request.sourceURL)
    }

    var isDirectory: ObjCBool = false
    let destinationDirectory = request.destinationURL.deletingLastPathComponent()
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
    let encodedData: Data
    do {
      encodedData = try await encodeImage(
        request,
        temporaryURL: temporaryURL,
        publisher: publisher,
        publicationGate: publicationGate
      )
    } catch let primaryError {
      try removeTemporaryFileIfPresent(
        at: temporaryURL,
        remover: temporaryFileRemover,
        primaryError: primaryError
      )
      throw primaryError
    }
    try removeTemporaryFileIfPresent(
      at: temporaryURL,
      remover: temporaryFileRemover,
      primaryError: nil
    )

    return ExportResult(
      derivative: DurableDerivative(
        schemaVersion: 1,
        assetID: request.recipe.assetID,
        recipeRevision: request.recipe.revision,
        kind: .export,
        outputURL: request.destinationURL,
        typeIdentifier: exportTypeIdentifier(request.format),
        fingerprint: fingerprint(for: encodedData),
        createdAt: Date()
      )
    )
  }

  private func encodeImage(
    _ request: ExportRequest,
    temporaryURL: URL,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating
  ) async throws -> Data {
    var image = try compiledImage(sourceURL: request.sourceURL, recipe: request.recipe)
    image = try applyingExportResize(request.options.resize, to: image)
    image = try applyingOutputSharpening(request.options.outputSharpening, to: image)
    image = try applyingWatermark(request.options.watermark, to: image)
    try Task.checkCancellation()

    let outputExtent = image.extent.integral
    let outputImage: CIImage
    if case .heif = request.format {
      let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
        .cropped(to: outputExtent)
      outputImage = image.composited(over: black).cropped(to: outputExtent)
    } else {
      outputImage = image.cropped(to: outputExtent)
    }
    guard
      let cgImage = context.createCGImage(
        outputImage,
        from: outputExtent,
        format: .RGBA8,
        colorSpace: sRGBColorSpace
      ),
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        exportTypeIdentifier(request.format) as CFString,
        1,
        nil
      )
    else {
      throw RenderCoreError.imageEncodingFailed(
        format: exportFormatName(request.format),
        request.destinationURL
      )
    }

    var properties = exportMetadataProperties(
      policy: request.options.metadata,
      sourceURL: request.sourceURL,
      outputExtent: outputExtent
    )
    if case .heif = request.format, let quality = request.quality {
      properties[kCGImageDestinationLossyCompressionQuality as String] = quality
    }
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw RenderCoreError.imageEncodingFailed(
        format: exportFormatName(request.format),
        request.destinationURL
      )
    }
    try Task.checkCancellation()

    guard
      let temporaryData = try? Data(contentsOf: temporaryURL),
      !temporaryData.isEmpty,
      let imageSource = CGImageSourceCreateWithData(temporaryData as CFData, nil),
      CGImageSourceGetType(imageSource) as String? == exportTypeIdentifier(request.format)
    else {
      throw RenderCoreError.imageEncodingFailed(
        format: exportFormatName(request.format),
        request.destinationURL
      )
    }
    try Task.checkCancellation()
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
    return temporaryData
  }

  private func exportTypeIdentifier(_ format: ExportFormat) -> String {
    switch format {
    case .jpeg: UTType.jpeg.identifier
    case .png: UTType.png.identifier
    case .heif: UTType.heic.identifier
    case .tiff: UTType.tiff.identifier
    case .unknown: "public.data"
    }
  }

  private func fingerprint(for data: Data) -> SourceFingerprint? {
    let digest = SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
    return SourceFingerprint(
      sha256: digest,
      byteCount: UInt64(data.count),
      modificationDate: nil
    )
  }

  private func encodeAndPublishJPEG(
    _ opaqueImage: CIImage,
    request: ExportRequest,
    quality: Double,
    temporaryURL: URL,
    publisher: any AtomicFilePublishing,
    publicationGate: any ExportPublicationGating
  ) async throws -> ExportResult {
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

  private func removeTemporaryFileIfPresent(
    at temporaryURL: URL,
    remover: any TemporaryFileRemoving,
    primaryError: (any Error)?
  ) throws {
    guard FileManager.default.fileExists(atPath: temporaryURL.path) else { return }
    do {
      try remover.removeItem(at: temporaryURL)
    } catch let cleanupError {
      throw RenderCoreError.cleanupFailed(
        operation: "export.temporary.remove",
        primaryError: primaryError.map { String(describing: $0) } ?? "No primary export error.",
        cleanupError: String(describing: cleanupError)
      )
    }
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

  private func applyingExportResize(_ resize: ExportResize, to image: CIImage) throws -> CIImage {
    let extent = image.extent.integral
    let target: (width: Int, height: Int)
    switch resize {
    case .original:
      return image
    case .longEdge(let pixels):
      guard pixels > 0 else {
        throw RenderCoreError.invalidExportResize("Long edge must be greater than zero.")
      }
      let scale = min(1, CGFloat(pixels) / max(extent.width, extent.height))
      target = (
        max(1, Int(floor(extent.width * scale))),
        max(1, Int(floor(extent.height * scale)))
      )
    case .dimensions(let width, let height):
      guard width > 0, height > 0 else {
        throw RenderCoreError.invalidExportResize("Width and height must be greater than zero.")
      }
      let scale = min(
        1,
        CGFloat(width) / extent.width,
        CGFloat(height) / extent.height
      )
      target = (
        max(1, Int(floor(extent.width * scale))),
        max(1, Int(floor(extent.height * scale)))
      )
    }

    guard target.width != Int(extent.width) || target.height != Int(extent.height) else {
      return image
    }
    let scale = CGFloat(target.width) / extent.width
    let filter = CIFilter.lanczosScaleTransform()
    filter.inputImage = image
    filter.scale = Float(scale)
    filter.aspectRatio = Float(
      (CGFloat(target.height) / extent.height) / scale
    )
    guard let output = filter.outputImage else { throw RenderCoreError.renderFailed }
    return output.cropped(
      to: CGRect(x: 0, y: 0, width: target.width, height: target.height)
    )
  }

  private func exportMetadataProperties(
    policy: ExportMetadataPolicy,
    sourceURL: URL,
    outputExtent: CGRect
  ) -> [String: Any] {
    guard policy != .none,
      let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      var sourceProperties =
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else {
      return [:]
    }

    switch policy {
    case .all:
      break
    case .basic:
      sourceProperties = sourceProperties.filter { key, _ in
        key == kCGImagePropertyExifDictionary as String
          || key == kCGImagePropertyTIFFDictionary as String
      }
    case .copyrightOnly:
      sourceProperties = copyrightMetadata(from: sourceProperties)
    case .none:
      return [:]
    }

    sourceProperties[kCGImagePropertyOrientation as String] = 1
    sourceProperties[kCGImagePropertyPixelWidth as String] = Int(outputExtent.width)
    sourceProperties[kCGImagePropertyPixelHeight as String] = Int(outputExtent.height)
    if var exif = sourceProperties[kCGImagePropertyExifDictionary as String]
      as? [String: Any]
    {
      exif[kCGImagePropertyExifPixelXDimension as String] = Int(outputExtent.width)
      exif[kCGImagePropertyExifPixelYDimension as String] = Int(outputExtent.height)
      sourceProperties[kCGImagePropertyExifDictionary as String] = exif
    }
    return sourceProperties
  }

  private func copyrightMetadata(from sourceProperties: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    if let sourceTIFF = sourceProperties[kCGImagePropertyTIFFDictionary as String]
      as? [String: Any]
    {
      let tiff = sourceTIFF.filter { key, _ in
        key == kCGImagePropertyTIFFArtist as String
          || key == kCGImagePropertyTIFFCopyright as String
      }
      if !tiff.isEmpty { result[kCGImagePropertyTIFFDictionary as String] = tiff }
    }
    if let sourceIPTC = sourceProperties[kCGImagePropertyIPTCDictionary as String]
      as? [String: Any]
    {
      let iptc = sourceIPTC.filter { key, _ in
        key == kCGImagePropertyIPTCByline as String
          || key == kCGImagePropertyIPTCCopyrightNotice as String
      }
      if !iptc.isEmpty { result[kCGImagePropertyIPTCDictionary as String] = iptc }
    }
    return result
  }

  private func applyingWatermark(_ watermark: ExportWatermark, to image: CIImage) throws -> CIImage
  {
    guard case .text(let value) = watermark else { return image }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return image }
    guard text.count <= 256 else {
      throw RenderCoreError.invalidWatermark(
        "Text watermarks must contain at most 256 characters."
      )
    }
    let extent = image.extent.integral
    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width > 0, height > 0,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let bitmap = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw RenderCoreError.renderFailed
    }

    let fontSize = min(64, max(12, CGFloat(min(width, height)) * 0.08))
    let font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize, nil)
    let attributedText = NSAttributedString(
      string: text,
      attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 1, alpha: 0.92),
      ]
    )
    let line = CTLineCreateWithAttributedString(attributedText)
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    let padding = max(10, fontSize * 0.75)
    bitmap.setShadow(
      offset: CGSize(width: 0, height: -1),
      blur: max(1, fontSize * 0.12),
      color: CGColor(gray: 0, alpha: 0.9)
    )
    bitmap.textPosition = CGPoint(
      x: max(padding, CGFloat(width) - bounds.width - padding - bounds.minX),
      y: padding - bounds.minY
    )
    CTLineDraw(line, bitmap)
    guard let watermarkImage = bitmap.makeImage() else {
      throw RenderCoreError.renderFailed
    }
    return CIImage(cgImage: watermarkImage)
      .composited(over: image)
      .cropped(to: extent)
  }

  private func applyingOutputSharpening(
    _ sharpening: ExportOutputSharpening,
    to image: CIImage
  ) throws -> CIImage {
    let sharpness: Float
    switch sharpening {
    case .none:
      return image
    case .screenStandard:
      sharpness = 0.4
    case .screenHigh:
      sharpness = 0.75
    case .printStandard:
      sharpness = 0.55
    }
    let filter = CIFilter.sharpenLuminance()
    filter.inputImage = image
    filter.sharpness = sharpness
    guard let output = filter.outputImage else { throw RenderCoreError.renderFailed }
    return output.cropped(to: image.extent)
  }

  private func exportFormatName(_ format: ExportFormat) -> String {
    switch format {
    case .jpeg: "jpeg"
    case .png: "png"
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

    if let raw = rawFilterProvider.makeFilter(imageURL: sourceURL), isRealRAWFilter(raw) {
      if let decoderVersion {
        guard raw.selectDecoderVersion(decoderVersion) else {
          throw RenderCoreError.unsupportedDecoderVersion(decoderVersion)
        }
      }
      guard let image = raw.outputImage else {
        throw RenderCoreError.corruptSource(sourceURL)
      }
      return DecodedImage(
        image: try normalized(image, sourceURL: sourceURL),
        metadata: stringMetadata(from: raw.properties),
        decoderIdentifier: "com.apple.ciraw",
        decoderVersion: raw.decoderVersion
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

  private func isRealRAWFilter(_ raw: any AppleRAWFilterAccess) -> Bool {
    let decoderVersion = raw.decoderVersion
    let supportedDecoderVersions = raw.supportedDecoderVersions
    return !decoderVersion.isEmpty
      && !Self.isNoRAWDecoderVersion(decoderVersion)
      && supportedDecoderVersions.contains { version in
        !version.isEmpty && !Self.isNoRAWDecoderVersion(version)
      }
  }

  private nonisolated static func isNoRAWDecoderVersion(_ version: String) -> Bool {
    version.caseInsensitiveCompare("None") == .orderedSame
  }

  private func sourceKind(for sourceURL: URL) -> RawSourceKind {
    if let inspection = try? DNGMetadataReader().inspect(
      DNGInspectionRequest(sourceURL: sourceURL)
    ) {
      switch inspection.state {
      case .valid, .unsupportedVersion, .unsupportedContainer, .malformed:
        if inspection.byteOrder != nil {
          return .dngContainer
        }
      case .notDNG:
        break
      }
    }

    if let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let typeIdentifier = CGImageSourceGetType(source) as String?,
      UTType(typeIdentifier)?.conforms(to: .image) == true
    {
      return .imageIOImage
    }
    return .unsupported
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
