// SPDX-License-Identifier: MPL-2.0

import CoreGraphics
import CoreImage
import Foundation
import PhotoDomain
import Vision

/// A face rectangle reported by a local Vision detector.
///
/// The rectangle is geometry only. It carries no identity or biometric
/// information. The detector converts these observations into unlabeled
/// `PhotoFace` annotations for later user review.
public struct VisionFaceObservation: Codable, Hashable, Sendable {
  public let region: FaceRegion
  public let confidence: Double

  public init?(region: FaceRegion, confidence: Double) {
    guard confidence.isFinite, (0...1).contains(confidence) else {
      return nil
    }
    self.region = region
    self.confidence = confidence
  }
}

/// A version-pinned local face-detection request.
public struct VisionFaceDetectionRequest: Codable, Hashable, Sendable {
  public let requestID: UUID
  public let assetID: UUID
  public let image: ImageBuffer
  public let modelIdentifier: String
  public let modelVersion: String

  public init(
    requestID: UUID = UUID(),
    assetID: UUID,
    image: ImageBuffer,
    modelIdentifier: String = "com.apple.Vision.face-rectangles",
    modelVersion: String = "1"
  ) {
    self.requestID = requestID
    self.assetID = assetID
    self.image = image
    self.modelIdentifier = modelIdentifier
    self.modelVersion = modelVersion
  }
}

/// A face-detection result that can be checked before it is persisted.
public struct VisionFaceDetectionResult: Codable, Hashable, Sendable {
  public let requestID: UUID
  public let assetID: UUID
  public let faces: [PhotoFace]
  public let modelIdentifier: String
  public let modelVersion: String

  public init(
    requestID: UUID,
    assetID: UUID,
    faces: [PhotoFace],
    modelIdentifier: String,
    modelVersion: String
  ) {
    self.requestID = requestID
    self.assetID = assetID
    self.faces = faces
    self.modelIdentifier = modelIdentifier
    self.modelVersion = modelVersion
  }

  public func accepts(_ request: VisionFaceDetectionRequest) -> Bool {
    requestID == request.requestID
      && assetID == request.assetID
      && modelIdentifier == request.modelIdentifier
      && modelVersion == request.modelVersion
  }
}

public enum VisionFaceDetectionError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedImagePixelFormat(ImagePixelFormat)
  case invalidImageBuffer(String)
  case visionFailure(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedImagePixelFormat(let format):
      "Vision face detection does not accept the \(format) image pixel format."
    case .invalidImageBuffer(let reason):
      "The image buffer is invalid for Vision face detection: \(reason)."
    case .visionFailure(let reason):
      "Vision face detection failed: \(reason)."
    }
  }
}

/// Local face geometry detection backed by Apple's Vision framework.
///
/// The service performs no network access and never assigns a person name.
/// A detector closure is injectable so the request/result contract can be
/// tested without requiring a real face image or a specific Vision revision.
public actor VisionFaceDetectionService {
  public typealias Detector = @Sendable (ImageBuffer) async throws -> [VisionFaceObservation]

  private let detector: Detector

  public init() {
    self.detector = { image in
      try VisionFaceDetectionService.detectUsingVision(image)
    }
  }

  public init(detector: @escaping Detector) {
    self.detector = detector
  }

  public func detectFaces(
    _ request: VisionFaceDetectionRequest
  ) async throws -> VisionFaceDetectionResult {
    try Task.checkCancellation()
    let observations = try await detector(request.image)
    try Task.checkCancellation()

    let timestamp = Date()
    let faces = observations.compactMap { observation in
      PhotoFace(
        assetID: request.assetID,
        region: observation.region,
        confidence: observation.confidence,
        source: .vision,
        createdAt: timestamp,
        updatedAt: timestamp
      )
    }

    return VisionFaceDetectionResult(
      requestID: request.requestID,
      assetID: request.assetID,
      faces: faces,
      modelIdentifier: request.modelIdentifier,
      modelVersion: request.modelVersion
    )
  }

  private static func detectUsingVision(
    _ buffer: ImageBuffer
  ) throws -> [VisionFaceObservation] {
    let ciImage = try makeCIImage(from: buffer)
    let context = CIContext(options: [CIContextOption.priorityRequestLow: true])
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      throw VisionFaceDetectionError.visionFailure("The image could not be converted to CGImage.")
    }

    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw VisionFaceDetectionError.visionFailure(String(describing: error))
    }

    return (request.results ?? []).compactMap { observation in
      let box = observation.boundingBox
      let y = 1 - box.maxY
      guard
        let region = FaceRegion(
          x: box.minX,
          y: y,
          width: box.width,
          height: box.height
        )
      else {
        return nil
      }
      return VisionFaceObservation(region: region, confidence: Double(observation.confidence))
    }
  }

  private static func makeCIImage(from buffer: ImageBuffer) throws -> CIImage {
    let width = buffer.dimensions.width
    let height = buffer.dimensions.height
    let format: CIFormat
    let bytesPerPixel: Int

    switch buffer.pixelFormat {
    case .rgba8:
      format = .RGBA8
      bytesPerPixel = 4
    case .bgra8:
      format = .BGRA8
      bytesPerPixel = 4
    case .rgba16Float:
      format = .RGBAh
      bytesPerPixel = 8
    case .unknown:
      throw VisionFaceDetectionError.unsupportedImagePixelFormat(buffer.pixelFormat)
    }

    guard width > 0, height > 0 else {
      throw VisionFaceDetectionError.invalidImageBuffer("dimensions must be positive")
    }
    guard buffer.bytesPerRow <= UInt(Int.max) else {
      throw VisionFaceDetectionError.invalidImageBuffer("bytesPerRow is too large")
    }

    let bytesPerRow = Int(buffer.bytesPerRow)
    let (minimumBytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
    guard !rowOverflow, bytesPerRow >= minimumBytesPerRow else {
      throw VisionFaceDetectionError.invalidImageBuffer("bytesPerRow is too small")
    }
    let (requiredBytes, dataOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
    guard !dataOverflow, buffer.data.count >= requiredBytes else {
      throw VisionFaceDetectionError.invalidImageBuffer("pixel data is truncated")
    }

    let colorSpace = colorSpace(for: buffer.colorSpaceName)
    return CIImage(
      bitmapData: buffer.data,
      bytesPerRow: bytesPerRow,
      size: CGSize(width: width, height: height),
      format: format,
      colorSpace: colorSpace
    )
  }

  private static func colorSpace(for name: String?) -> CGColorSpace {
    switch name?.lowercased() {
    case "srgb", "public.srgb":
      CGColorSpace(name: CGColorSpace.sRGB)!
    case "display-p3", "displayp3":
      CGColorSpace(name: CGColorSpace.displayP3)!
    case "extended-linear-display-p3":
      CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    case "extended-linear-acescg":
      CGColorSpace(name: CGColorSpace.acescgLinear)!
    default:
      CGColorSpace(name: CGColorSpace.sRGB)!
    }
  }
}
