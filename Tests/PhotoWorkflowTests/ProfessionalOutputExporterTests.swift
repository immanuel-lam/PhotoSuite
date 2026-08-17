// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import PhotoDomain
import UniformTypeIdentifiers
import XCTest

@testable import PhotoWorkflow

final class ProfessionalOutputExporterTests: XCTestCase {
  private var testDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "PhotoSuiteProfessionalOutput-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: false)
  }

  override func tearDownWithError() throws {
    if let testDirectory { try? FileManager.default.removeItem(at: testDirectory) }
    try super.tearDownWithError()
  }

  func testPDFBookExportPublishesValidAttributedDocument() async throws {
    let renderer = FixtureRenderer(imageData: makePNGData(red: 0.82, green: 0.2, blue: 0.15))
    let pages = [
      makePhoto(index: 1, caption: "First frame"), makePhoto(index: 2, caption: "Second frame"),
    ]
    let destination = testDirectory.appendingPathComponent("book.pdf")

    let output = try await PDFBookExporter(renderer: renderer).export(
      PhotoBookExportRequest(
        title: "Field Notes",
        author: "PhotoSuite Test",
        pages: pages,
        destinationURL: destination,
        pageSize: .letter
      )
    )

    XCTAssertEqual(output, destination)
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    let document = try XCTUnwrap(PDFDocument(url: destination))
    XCTAssertEqual(document.pageCount, 2)
    XCTAssertEqual(
      document.documentAttributes?[PDFDocumentAttribute.titleAttribute as AnyHashable] as? String,
      "Field Notes"
    )
    XCTAssertEqual(
      document.documentAttributes?[PDFDocumentAttribute.authorAttribute as AnyHashable] as? String,
      "PhotoSuite Test"
    )
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(
        at: testDirectory, includingPropertiesForKeys: nil
      ).contains {
        $0.lastPathComponent.hasPrefix(".photosuite-output-")
      })
  }

  func testSlideshowExportPublishesSilentH264Movie() async throws {
    let renderer = FixtureRenderer(imageData: makePNGData(red: 0.1, green: 0.54, blue: 0.86))
    let destination = testDirectory.appendingPathComponent("slideshow.mov")
    let request = PhotoSlideshowExportRequest(
      title: "A Short Walk",
      slides: [makePhoto(index: 1), makePhoto(index: 2)],
      destinationURL: destination,
      secondsPerSlide: 0.5,
      framesPerSecond: 2,
      canvas: PhotoSlideshowCanvas(width: 64, height: 36)
    )

    let output = try await AVFoundationSlideshowExporter(renderer: renderer).export(request)

    XCTAssertEqual(output, destination)
    let asset = AVURLAsset(url: destination)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(tracks.count, 1)
    XCTAssertGreaterThanOrEqual(duration.seconds, 0.9)
    XCTAssertGreaterThan(FileManager.default.fileSize(atPath: destination.path) ?? 0, 0)
  }

  func testGalleryExportPublishesEscapedWebKitCompatibleStaticSite() async throws {
    let renderer = FixtureRenderer(imageData: makePNGData(red: 0.2, green: 0.76, blue: 0.3))
    let destination = testDirectory.appendingPathComponent("gallery", isDirectory: true)
    let item = makePhoto(index: 1, caption: "A <sunny> day & night")

    let output = try await StaticHTMLGalleryExporter(renderer: renderer).export(
      PhotoGalleryExportRequest(
        title: "Summer <2026>",
        subtitle: "Offline proof gallery",
        items: [item],
        destinationURL: destination,
        maximumPixelDimension: 1_200
      )
    )

    XCTAssertEqual(output, destination)
    let html = try String(
      contentsOf: destination.appendingPathComponent("index.html"), encoding: .utf8)
    XCTAssertTrue(html.contains("Summer &lt;2026&gt;"))
    XCTAssertTrue(html.contains("A &lt;sunny&gt; day &amp; night"))
    XCTAssertTrue(html.contains("<meta name=\"viewport\""))
    XCTAssertTrue(html.contains("aria-label=\"Photo gallery\""))
    let manifest = try JSONDecoder().decode(
      [GalleryManifestFixture].self,
      from: Data(contentsOf: destination.appendingPathComponent("gallery.json"))
    )
    XCTAssertEqual(manifest.count, 1)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destination.appendingPathComponent(manifest[0].filename).path))
  }

  func testCancellationDoesNotPublishBookOrLeaveTemporaryOutput() async throws {
    let renderer = FixtureRenderer(imageData: makePNGData(red: 0.3, green: 0.3, blue: 0.3))
    let destination = testDirectory.appendingPathComponent("cancelled.pdf")
    let request = PhotoBookExportRequest(
      title: "Cancelled",
      pages: [makePhoto(index: 1)],
      destinationURL: destination
    )
    let task = Task {
      try await PDFBookExporter(renderer: renderer).export(request)
    }
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("A cancelled export must not publish.")
    } catch let error as ProfessionalOutputError {
      XCTAssertEqual(error, .cancelled)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(
        at: testDirectory, includingPropertiesForKeys: nil
      ).contains {
        $0.lastPathComponent.hasPrefix(".photosuite-output-")
      })
  }

  func testInvalidProfessionalOutputRequestsFailBeforeCreatingFiles() async throws {
    let renderer = FixtureRenderer(imageData: makePNGData(red: 0.1, green: 0.1, blue: 0.1))
    let destination = testDirectory.appendingPathComponent("invalid.mov")
    let noSlides = PhotoSlideshowExportRequest(
      title: "Empty",
      slides: [],
      destinationURL: destination
    )

    do {
      _ = try await AVFoundationSlideshowExporter(renderer: renderer).export(noSlides)
      XCTFail("An empty slideshow must fail.")
    } catch let error as ProfessionalOutputError {
      XCTAssertEqual(error, .noSlides)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }

  private func makePhoto(index: Int, caption: String? = nil) -> ProfessionalOutputPhoto {
    let url = URL(fileURLWithPath: "/tmp/photo-\(index).png")
    let asset = PhotoAsset(
      sourceURL: url,
      filename: "photo-\(index).png",
      typeIdentifier: "public.png",
      fingerprint: SourceFingerprint(
        sha256: String(repeating: "a", count: 64),
        byteCount: 42,
        modificationDate: nil
      )!,
      importDate: Date(timeIntervalSince1970: 100),
      captureDate: Date(timeIntervalSince1970: 90),
      pixelDimensions: PixelDimensions(width: 16, height: 12)!,
      rating: index,
      metadata: PhotoMetadata(keywords: ["test", "photo-\(index)"])!
    )!
    let recipe = EditRecipe(
      assetID: asset.id,
      pins: EnginePins(
        decoderIdentifier: "test.decoder",
        decoderVersion: "1",
        renderSchemaVersion: 1,
        cameraProfileVersion: nil,
        modelVersions: [:]
      )
    )
    return ProfessionalOutputPhoto(asset: asset, recipe: recipe, caption: caption)
  }

  private func makePNGData(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data {
    let width = 16
    let height = 12
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let output = CGImageDestinationCreateWithData(
      data,
      UTType.png.identifier as CFString,
      1,
      nil
    )!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    XCTAssertTrue(CGImageDestinationFinalize(output))
    return data as Data
  }
}

private struct FixtureRenderer: RenderEngine, Sendable {
  let imageData: Data

  func render(_ request: RenderRequest) async throws -> RenderResult {
    RenderResult(
      imageData: imageData,
      typeIdentifier: "public.png",
      pixelDimensions: PixelDimensions(width: 16, height: 12)!
    )
  }
}

private struct GalleryManifestFixture: Codable {
  let filename: String
  let title: String
  let sourceFilename: String
  let rating: Int
  let keywords: [String]
}

extension FileManager {
  fileprivate func fileSize(atPath path: String) -> UInt64? {
    (try? attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
  }
}
