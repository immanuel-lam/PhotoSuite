// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Foundation
import ImageIO
@preconcurrency import PDFKit
import PhotoDomain
import UniformTypeIdentifiers

/// Errors raised by the bounded, offline professional output exporters.
public enum ProfessionalOutputError: Error, LocalizedError, Equatable, Sendable {
  case noPages
  case noSlides
  case noGalleryItems
  case invalidDestination(URL)
  case destinationParentMissing(URL)
  case invalidCanvasSize
  case invalidDuration
  case invalidFrameRate
  case unsupportedImageType(String)
  case invalidImageData(String)
  case renderFailed(String)
  case pdfCreationFailed
  case movieCreationFailed(String)
  case publicationFailed(String)
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .noPages: "The book has no pages."
    case .noSlides: "The slideshow has no slides."
    case .noGalleryItems: "The gallery has no photographs."
    case .invalidDestination(let url): "The destination is invalid: \(url.path)."
    case .destinationParentMissing(let url):
      "The destination folder does not exist: \(url.path)."
    case .invalidCanvasSize: "The canvas size must contain positive dimensions."
    case .invalidDuration: "The slide duration must be greater than zero."
    case .invalidFrameRate: "The frame rate must be between 1 and 60 frames per second."
    case .unsupportedImageType(let type): "The rendered image type is not supported: \(type)."
    case .invalidImageData(let name): "The rendered image is invalid: \(name)."
    case .renderFailed(let message): "The photograph could not be rendered: \(message)."
    case .pdfCreationFailed: "The PDF document could not be created."
    case .movieCreationFailed(let message): "The slideshow movie could not be created: \(message)."
    case .publicationFailed(let message): "The output could not be published: \(message)."
    case .cancelled: "The output was cancelled before publication."
    }
  }
}

/// A rendered-output input. The source remains immutable; each exporter uses the recipe with the
/// supplied render engine and never writes to `asset.sourceURL`.
public struct ProfessionalOutputPhoto: Codable, Hashable, Sendable {
  public let asset: PhotoAsset
  public let recipe: EditRecipe
  public let caption: String?

  public init(asset: PhotoAsset, recipe: EditRecipe, caption: String? = nil) {
    self.asset = asset
    self.recipe = recipe
    self.caption = Self.normalise(caption)
  }

  private static func normalise(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalised = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return normalised.isEmpty ? nil : normalised
  }
}

public enum PhotoBookPageSize: String, Codable, CaseIterable, Hashable, Sendable {
  case a4
  case letter
  case square

  var mediaBox: CGRect {
    switch self {
    case .a4: CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
    case .letter: CGRect(x: 0, y: 0, width: 612, height: 792)
    case .square: CGRect(x: 0, y: 0, width: 720, height: 720)
    }
  }
}

public struct PhotoBookExportRequest: Codable, Hashable, Sendable {
  public let title: String
  public let author: String?
  public let pages: [ProfessionalOutputPhoto]
  public let destinationURL: URL
  public let pageSize: PhotoBookPageSize

  public init(
    title: String,
    author: String? = nil,
    pages: [ProfessionalOutputPhoto],
    destinationURL: URL,
    pageSize: PhotoBookPageSize = .a4
  ) {
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.author = Self.normalise(author)
    self.pages = pages
    self.destinationURL = destinationURL
    self.pageSize = pageSize
  }

  private static func normalise(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalised = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return normalised.isEmpty ? nil : normalised
  }
}

public struct PhotoSlideshowCanvas: Codable, Hashable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int = 1_920, height: Int = 1_080) {
    self.width = width
    self.height = height
  }
}

public struct PhotoSlideshowExportRequest: Codable, Hashable, Sendable {
  public let title: String
  public let slides: [ProfessionalOutputPhoto]
  public let destinationURL: URL
  public let secondsPerSlide: Double
  public let framesPerSecond: Int
  public let canvas: PhotoSlideshowCanvas

  public init(
    title: String,
    slides: [ProfessionalOutputPhoto],
    destinationURL: URL,
    secondsPerSlide: Double = 4,
    framesPerSecond: Int = 30,
    canvas: PhotoSlideshowCanvas = PhotoSlideshowCanvas()
  ) {
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.slides = slides
    self.destinationURL = destinationURL
    self.secondsPerSlide = secondsPerSlide
    self.framesPerSecond = framesPerSecond
    self.canvas = canvas
  }
}

public struct PhotoGalleryExportRequest: Codable, Hashable, Sendable {
  public let title: String
  public let subtitle: String?
  public let items: [ProfessionalOutputPhoto]
  public let destinationURL: URL
  public let maximumPixelDimension: Int?

  public init(
    title: String,
    subtitle: String? = nil,
    items: [ProfessionalOutputPhoto],
    destinationURL: URL,
    maximumPixelDimension: Int? = 2_400
  ) {
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.subtitle = Self.normalise(subtitle)
    self.items = items
    self.destinationURL = destinationURL
    self.maximumPixelDimension = maximumPixelDimension
  }

  private static func normalise(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalised = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return normalised.isEmpty ? nil : normalised
  }
}

/// A PDF book exporter with one rendered photograph per page and a small caption block. The
/// result is a portable PDF; page templates, spreads, bleeds and printer profiles remain future
/// work outside this bounded implementation.
public struct PDFBookExporter: Sendable {
  private let renderer: any RenderEngine

  public init(renderer: any RenderEngine) {
    self.renderer = renderer
  }

  public func export(_ request: PhotoBookExportRequest) async throws -> URL {
    guard !request.pages.isEmpty else { throw ProfessionalOutputError.noPages }
    try ProfessionalOutputFileSupport.validateDestination(
      request.destinationURL, isDirectory: false)
    let temporaryURL = try ProfessionalOutputFileSupport.makeTemporaryFile(
      beside: request.destinationURL,
      suffix: "pdf"
    )
    defer { ProfessionalOutputFileSupport.removeIfPresent(temporaryURL) }

    do {
      let mediaBox = request.pageSize.mediaBox
      guard let context = CGContext(temporaryURL as CFURL, mediaBox: nil, nil) else {
        throw ProfessionalOutputError.pdfCreationFailed
      }

      for page in request.pages {
        try Self.checkCancellation()
        let result = try await render(page, maximumPixelDimension: Self.maximumDimension(mediaBox))
        guard let image = Self.image(from: result.imageData) else {
          throw ProfessionalOutputError.invalidImageData(page.asset.filename)
        }
        context.beginPDFPage(
          [
            kCGPDFContextMediaBox as String: mediaBox
          ] as CFDictionary)
        Self.drawBookPage(
          image: image,
          mediaBox: mediaBox,
          title: request.title,
          caption: page.caption ?? page.asset.filename,
          context: context
        )
        context.endPDFPage()
      }
      context.closePDF()

      try Self.checkCancellation()
      guard let document = PDFDocument(url: temporaryURL) else {
        throw ProfessionalOutputError.pdfCreationFailed
      }
      var attributes: [PDFDocumentAttribute: Any] = [
        .titleAttribute: request.title,
        .creatorAttribute: "PhotoSuite",
      ]
      if let author = request.author { attributes[.authorAttribute] = author }
      document.documentAttributes = attributes
      guard document.write(to: temporaryURL) else {
        throw ProfessionalOutputError.pdfCreationFailed
      }
      try Self.checkCancellation()
      try ProfessionalOutputFileSupport.publish(
        temporaryURL: temporaryURL,
        destinationURL: request.destinationURL
      )
      return request.destinationURL
    } catch is CancellationError {
      throw ProfessionalOutputError.cancelled
    } catch let error as ProfessionalOutputError {
      throw error
    } catch {
      throw ProfessionalOutputError.publicationFailed(error.localizedDescription)
    }
  }

  private func render(
    _ photo: ProfessionalOutputPhoto,
    maximumPixelDimension: Int
  ) async throws -> RenderResult {
    do {
      return try await renderer.render(
        RenderRequest(
          sourceURL: photo.asset.sourceURL,
          recipe: photo.recipe,
          maximumPixelDimension: maximumPixelDimension,
          outputColorSpaceName: "sRGB"
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProfessionalOutputError.renderFailed(photo.asset.filename)
    }
  }

  private static func drawBookPage(
    image: CGImage,
    mediaBox: CGRect,
    title: String,
    caption: String,
    context: CGContext
  ) {
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(mediaBox)
    let inset: CGFloat = 36
    let textHeight: CGFloat = 56
    let imageRect = CGRect(
      x: inset,
      y: inset + textHeight,
      width: mediaBox.width - (inset * 2),
      height: mediaBox.height - (inset * 2) - textHeight
    )
    context.interpolationQuality = .high
    context.draw(image, in: Self.aspectFit(image, in: imageRect))

    let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
    let captionFont = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
    Self.drawText(
      title, font: titleFont, color: CGColor(gray: 0.15, alpha: 1),
      at: CGPoint(x: inset, y: inset + 30), context: context)
    Self.drawText(
      caption, font: captionFont, color: CGColor(gray: 0.35, alpha: 1),
      at: CGPoint(x: inset, y: inset + 14), context: context)
  }

  private static func drawText(
    _ text: String,
    font: CTFont,
    color: CGColor,
    at point: CGPoint,
    context: CGContext
  ) {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    context.saveGState()
    context.textPosition = point
    CTLineDraw(line, context)
    context.restoreGState()
  }

  private static func maximumDimension(_ rect: CGRect) -> Int {
    Int(ceil(max(rect.width, rect.height)))
  }

  private static func aspectFit(_ image: CGImage, in rect: CGRect) -> CGRect {
    let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    return CGRect(
      x: rect.midX - size.width / 2,
      y: rect.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}

/// A silent H.264 slideshow exporter. It writes a `.mov` movie with one still frame sequence per
/// slide. Audio, transitions and publishing services are intentionally outside this bounded API.
public struct AVFoundationSlideshowExporter: Sendable {
  private let renderer: any RenderEngine

  public init(renderer: any RenderEngine) {
    self.renderer = renderer
  }

  public func export(_ request: PhotoSlideshowExportRequest) async throws -> URL {
    guard !request.slides.isEmpty else { throw ProfessionalOutputError.noSlides }
    guard request.secondsPerSlide.isFinite, request.secondsPerSlide > 0 else {
      throw ProfessionalOutputError.invalidDuration
    }
    guard (1...60).contains(request.framesPerSecond) else {
      throw ProfessionalOutputError.invalidFrameRate
    }
    guard request.canvas.width > 0, request.canvas.height > 0 else {
      throw ProfessionalOutputError.invalidCanvasSize
    }
    try ProfessionalOutputFileSupport.validateDestination(
      request.destinationURL, isDirectory: false)
    let temporaryURL = try ProfessionalOutputFileSupport.makeTemporaryFile(
      beside: request.destinationURL,
      suffix: "mov"
    )
    defer { ProfessionalOutputFileSupport.removeIfPresent(temporaryURL) }

    do {
      // AVAssetWriter requires an unused output URL. The shared temporary-file helper creates a
      // placeholder so that other exporters can open it directly; remove that placeholder before
      // constructing the writer.
      ProfessionalOutputFileSupport.removeIfPresent(temporaryURL)
      let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mov)
      let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: request.canvas.width,
        AVVideoHeightKey: request.canvas.height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: request.canvas.width * request.canvas.height * 4,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
      ]
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
      input.expectsMediaDataInRealTime = false
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
          kCVPixelBufferWidthKey as String: request.canvas.width,
          kCVPixelBufferHeightKey as String: request.canvas.height,
          kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
      )
      guard writer.canAdd(input) else {
        throw ProfessionalOutputError.movieCreationFailed("The video input could not be added.")
      }
      writer.add(input)
      guard writer.startWriting() else {
        throw ProfessionalOutputError.movieCreationFailed(
          writer.error?.localizedDescription ?? "The writer could not start.")
      }
      writer.startSession(atSourceTime: .zero)

      let frameCount = max(
        1, Int((request.secondsPerSlide * Double(request.framesPerSecond)).rounded()))
      var frameIndex: Int64 = 0
      for slide in request.slides {
        try Self.checkCancellation()
        let result = try await render(
          slide, maximumPixelDimension: max(request.canvas.width, request.canvas.height))
        guard let image = Self.image(from: result.imageData) else {
          throw ProfessionalOutputError.invalidImageData(slide.asset.filename)
        }
        guard let buffer = Self.pixelBuffer(from: image, size: request.canvas) else {
          throw ProfessionalOutputError.movieCreationFailed("A pixel buffer could not be created.")
        }
        for _ in 0..<frameCount {
          try Self.checkCancellation()
          while !input.isReadyForMoreMediaData {
            try Self.checkCancellation()
            if writer.status == .failed {
              throw ProfessionalOutputError.movieCreationFailed(
                writer.error?.localizedDescription ?? "The writer failed while waiting for input."
              )
            }
            await Task.yield()
          }
          let time = CMTime(value: frameIndex, timescale: CMTimeScale(request.framesPerSecond))
          guard adaptor.append(buffer, withPresentationTime: time) else {
            throw ProfessionalOutputError.movieCreationFailed(
              writer.error?.localizedDescription ?? "A video frame could not be appended.")
          }
          frameIndex += 1
        }
      }

      input.markAsFinished()
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        writer.finishWriting { continuation.resume() }
      }
      guard writer.status == .completed else {
        throw ProfessionalOutputError.movieCreationFailed(
          writer.error?.localizedDescription ?? "The writer did not complete.")
      }
      try Self.checkCancellation()
      try ProfessionalOutputFileSupport.publish(
        temporaryURL: temporaryURL,
        destinationURL: request.destinationURL
      )
      return request.destinationURL
    } catch is CancellationError {
      throw ProfessionalOutputError.cancelled
    } catch let error as ProfessionalOutputError {
      throw error
    } catch {
      throw ProfessionalOutputError.movieCreationFailed(error.localizedDescription)
    }
  }

  private func render(
    _ photo: ProfessionalOutputPhoto,
    maximumPixelDimension: Int
  ) async throws -> RenderResult {
    do {
      return try await renderer.render(
        RenderRequest(
          sourceURL: photo.asset.sourceURL,
          recipe: photo.recipe,
          maximumPixelDimension: maximumPixelDimension,
          outputColorSpaceName: "sRGB"
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProfessionalOutputError.renderFailed(photo.asset.filename)
    }
  }

  private static func pixelBuffer(from image: CGImage, size: PhotoSlideshowCanvas) -> CVPixelBuffer?
  {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        size.width,
        size.height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
      ) == kCVReturnSuccess,
      let pixelBuffer
    else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard
      let context = CGContext(
        data: baseAddress,
        width: size.width,
        height: size.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }

    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    context.interpolationQuality = .high
    context.draw(
      image, in: aspectFit(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height)))
    return pixelBuffer
  }

  private static func aspectFit(_ image: CGImage, in rect: CGRect) -> CGRect {
    let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    return CGRect(
      x: rect.midX - size.width / 2,
      y: rect.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}

/// Generates a self-contained static gallery. The output contains only `index.html`, a stylesheet
/// embedded in that file, an accessible image grid and a JSON manifest. It can be opened in WebKit
/// or any standards-compliant browser; this type does not host or publish the gallery.
public struct StaticHTMLGalleryExporter: Sendable {
  private let renderer: any RenderEngine

  public init(renderer: any RenderEngine) {
    self.renderer = renderer
  }

  public func export(_ request: PhotoGalleryExportRequest) async throws -> URL {
    guard !request.items.isEmpty else { throw ProfessionalOutputError.noGalleryItems }
    if let maximumPixelDimension = request.maximumPixelDimension, maximumPixelDimension <= 0 {
      throw ProfessionalOutputError.invalidCanvasSize
    }
    try ProfessionalOutputFileSupport.validateDestination(request.destinationURL, isDirectory: true)
    let stagingURL = try ProfessionalOutputFileSupport.makeTemporaryDirectory(
      beside: request.destinationURL)
    defer { ProfessionalOutputFileSupport.removeIfPresent(stagingURL) }
    let assetsURL = stagingURL.appendingPathComponent("assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: false)

    do {
      var manifest: [GalleryManifestItem] = []
      for (index, item) in request.items.enumerated() {
        try Self.checkCancellation()
        let result = try await render(item, maximumPixelDimension: request.maximumPixelDimension)
        let ext = try Self.fileExtension(for: result.typeIdentifier)
        let filename = String(
          format: "%04d-%@.%@", index + 1, Self.safeFilename(item.asset.filename), ext)
        let imageURL = assetsURL.appendingPathComponent(filename)
        try result.imageData.write(to: imageURL, options: [.atomic])
        manifest.append(
          GalleryManifestItem(
            filename: "assets/\(filename)",
            title: item.caption ?? item.asset.filename,
            sourceFilename: item.asset.filename,
            rating: item.asset.rating,
            keywords: item.asset.metadata.keywords
          )
        )
      }

      try Self.checkCancellation()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let manifestData = try encoder.encode(manifest)
      try manifestData.write(
        to: stagingURL.appendingPathComponent("gallery.json"), options: [.atomic])
      let html = Self.html(
        title: request.title,
        subtitle: request.subtitle,
        items: manifest
      )
      guard let htmlData = html.data(using: .utf8) else {
        throw ProfessionalOutputError.publicationFailed("The HTML document is not UTF-8.")
      }
      try htmlData.write(to: stagingURL.appendingPathComponent("index.html"), options: [.atomic])
      try Self.checkCancellation()
      try ProfessionalOutputFileSupport.publish(
        temporaryURL: stagingURL,
        destinationURL: request.destinationURL
      )
      return request.destinationURL
    } catch is CancellationError {
      throw ProfessionalOutputError.cancelled
    } catch let error as ProfessionalOutputError {
      throw error
    } catch {
      throw ProfessionalOutputError.publicationFailed(error.localizedDescription)
    }
  }

  private func render(
    _ photo: ProfessionalOutputPhoto,
    maximumPixelDimension: Int?
  ) async throws -> RenderResult {
    do {
      return try await renderer.render(
        RenderRequest(
          sourceURL: photo.asset.sourceURL,
          recipe: photo.recipe,
          maximumPixelDimension: maximumPixelDimension,
          outputColorSpaceName: "sRGB"
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ProfessionalOutputError.renderFailed(photo.asset.filename)
    }
  }

  private struct GalleryManifestItem: Codable, Sendable {
    let filename: String
    let title: String
    let sourceFilename: String
    let rating: Int
    let keywords: [String]
  }

  private static func html(
    title: String,
    subtitle: String?,
    items: [GalleryManifestItem]
  ) -> String {
    let cards = items.map { item in
      """
      <figure class="card"><a href="\(escape(item.filename))"><img loading="lazy" src="\(escape(item.filename))" alt="\(escape(item.title))"></a><figcaption><strong>\(escape(item.title))</strong><span>\(escape(item.sourceFilename))</span></figcaption></figure>
      """
    }.joined(separator: "\n")
    let subtitleMarkup = subtitle.map { "<p class=\"subtitle\">\(escape($0))</p>" } ?? ""
    return """
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(escape(title))</title><style>
      :root{color-scheme:light dark;--background:#f4f4f5;--surface:#fff;--text:#191919;--muted:#6c6c70;--line:#dedee3}*{box-sizing:border-box}body{margin:0;background:var(--background);color:var(--text);font:15px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}main{max-width:1440px;margin:0 auto;padding:48px 32px 72px}header{margin-bottom:32px;border-bottom:1px solid var(--line);padding-bottom:24px}h1{font-size:32px;letter-spacing:-.03em;margin:0 0 8px}.subtitle{color:var(--muted);margin:0}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:20px}.card{background:var(--surface);border:1px solid var(--line);border-radius:14px;overflow:hidden;margin:0}.card a{display:block;background:#151515;aspect-ratio:4/3}.card img{width:100%;height:100%;object-fit:contain;display:block}.card figcaption{display:grid;gap:4px;padding:12px 14px}.card span{font-size:12px;color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}@media(prefers-color-scheme:dark){:root{--background:#171719;--surface:#252527;--text:#f4f4f5;--muted:#a5a5ad;--line:#3a3a3e}}
      </style></head><body><main><header><h1>\(escape(title))</h1>\(subtitleMarkup)</header><section class="grid" aria-label="Photo gallery">\(cards)</section></main></body></html>
      """
  }

  private static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }

  private static func safeFilename(_ value: String) -> String {
    let base = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
    let result = base.unicodeScalars.map { scalar in
      CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
    }.joined()
    return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      .ifEmpty("photo")
  }

  private static func fileExtension(for typeIdentifier: String) throws -> String {
    guard let type = UTType(typeIdentifier) else {
      throw ProfessionalOutputError.unsupportedImageType(typeIdentifier)
    }
    if type.conforms(to: .jpeg) { return "jpg" }
    if type.conforms(to: .png) { return "png" }
    if type.conforms(to: .heic) { return "heic" }
    if type.conforms(to: .tiff) { return "tiff" }
    throw ProfessionalOutputError.unsupportedImageType(typeIdentifier)
  }
}

private enum ProfessionalOutputFileSupport {
  static func validateDestination(_ url: URL, isDirectory: Bool) throws {
    guard url.isFileURL, !url.path.isEmpty else {
      throw ProfessionalOutputError.invalidDestination(url)
    }
    let parent = url.deletingLastPathComponent()
    var parentIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
      parentIsDirectory.boolValue
    else {
      throw ProfessionalOutputError.destinationParentMissing(parent)
    }
    if FileManager.default.fileExists(atPath: url.path) {
      var existingIsDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &existingIsDirectory)
      guard existingIsDirectory.boolValue == isDirectory else {
        throw ProfessionalOutputError.invalidDestination(url)
      }
    }
  }

  static func makeTemporaryFile(beside destination: URL, suffix: String) throws -> URL {
    let url = destination.deletingLastPathComponent()
      .appendingPathComponent(".photosuite-output-\(UUID().uuidString).\(suffix)")
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
      throw ProfessionalOutputError.publicationFailed("The temporary output could not be created.")
    }
    return url
  }

  static func makeTemporaryDirectory(beside destination: URL) throws -> URL {
    let url = destination.deletingLastPathComponent()
      .appendingPathComponent(".photosuite-gallery-\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
      return url
    } catch {
      throw ProfessionalOutputError.publicationFailed("The temporary gallery could not be created.")
    }
  }

  static func publish(temporaryURL: URL, destinationURL: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        _ = try FileManager.default.replaceItemAt(
          destinationURL,
          withItemAt: temporaryURL,
          backupItemName: nil,
          options: []
        )
      } else {
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
      }
    } catch {
      throw ProfessionalOutputError.publicationFailed(error.localizedDescription)
    }
  }

  static func removeIfPresent(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try? FileManager.default.removeItem(at: url)
  }
}

extension String {
  fileprivate func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}

extension PDFBookExporter {
  fileprivate static func checkCancellation() throws {
    if Task.isCancelled { throw CancellationError() }
  }

  fileprivate static func image(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

extension AVFoundationSlideshowExporter {
  fileprivate static func checkCancellation() throws {
    if Task.isCancelled { throw CancellationError() }
  }

  fileprivate static func image(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

extension StaticHTMLGalleryExporter {
  fileprivate static func checkCancellation() throws {
    if Task.isCancelled { throw CancellationError() }
  }
}
