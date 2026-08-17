// SPDX-License-Identifier: MPL-2.0

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import PhotoDomain
import Vision

/// The semantic masks implemented by the built-in Vision provider.
///
/// `foreground` and `subject` use Apple's foreground-instance request. They
/// are separate recipe values so the UI can preserve the photographer's
/// choice, even though both currently use the same Vision revision.
public enum VisionAIMaskKind: String, Codable, CaseIterable, Hashable, Sendable {
  case foreground
  case subject
  case person

  var modelIdentifier: String {
    switch self {
    case .foreground, .subject:
      "com.apple.Vision.foreground-instance-mask.v1"
    case .person:
      "com.apple.Vision.person-segmentation.v1"
    }
  }

  var displayName: String {
    switch self {
    case .foreground: "Foreground"
    case .subject: "Subject"
    case .person: "Person"
    }
  }
}

/// A request that keeps the mask revision and request UUID next to the image.
/// The identity is required at the call boundary so a late Vision response
/// cannot overwrite a newer edit.
public struct VisionAIMaskRequest: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let image: ImageBuffer
  public let kind: VisionAIMaskKind
  public let modelIdentifier: String
  public let modelVersion: String

  public init(
    identity: MaskRequestIdentity,
    image: ImageBuffer,
    kind: VisionAIMaskKind,
    modelIdentifier: String? = nil,
    modelVersion: String = "1"
  ) {
    self.identity = identity
    self.image = image
    self.kind = kind
    self.modelIdentifier = modelIdentifier ?? kind.modelIdentifier
    self.modelVersion = modelVersion
  }
}

/// Durable payload embedded in `MaskDefinition.payload`.
///
/// Coverage is a tightly packed, one-component 8-bit mask. It is deliberately
/// independent from Vision's temporary `CVPixelBuffer`, which allows the
/// accepted result to be persisted and rendered again after a relaunch.
public struct VisionAIMaskPayloadV1: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let kind: VisionAIMaskKind
  public let providerIdentifier: String
  public let providerVersion: String
  public let dimensions: PixelDimensions
  public let bytesPerRow: Int
  public let coverage: Data

  public init?(
    kind: VisionAIMaskKind,
    dimensions: PixelDimensions,
    bytesPerRow: Int,
    coverage: Data,
    providerIdentifier: String = VisionAIModelService.providerIdentifier,
    providerVersion: String = VisionAIModelService.providerVersion
  ) {
    guard
      bytesPerRow == dimensions.width,
      coverage.count == bytesPerRow * dimensions.height,
      !providerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !providerVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return nil
    }

    schemaVersion = 1
    self.kind = kind
    self.providerIdentifier = providerIdentifier
    self.providerVersion = providerVersion
    self.dimensions = dimensions
    self.bytesPerRow = bytesPerRow
    self.coverage = coverage
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(UInt.self, forKey: .schemaVersion)
    let kind = try container.decode(VisionAIMaskKind.self, forKey: .kind)
    let providerIdentifier = try container.decode(String.self, forKey: .providerIdentifier)
    let providerVersion = try container.decode(String.self, forKey: .providerVersion)
    let dimensions = try container.decode(PixelDimensions.self, forKey: .dimensions)
    let bytesPerRow = try container.decode(Int.self, forKey: .bytesPerRow)
    let coverage = try container.decode(Data.self, forKey: .coverage)

    guard
      schemaVersion == 1,
      let value = Self(
        kind: kind,
        dimensions: dimensions,
        bytesPerRow: bytesPerRow,
        coverage: coverage,
        providerIdentifier: providerIdentifier,
        providerVersion: providerVersion
      )
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "Vision mask payload is not a valid version-one packed mask."
      )
    }

    self = value
  }
}

/// A Vision result that can be safely checked against the currently edited
/// mask before it is applied to a recipe.
public struct VisionAIMaskResult: Codable, Hashable, Sendable {
  public let identity: MaskRequestIdentity
  public let kind: VisionAIMaskKind
  public let mask: MaskDefinition
  public let modelIdentifier: String
  public let modelVersion: String

  public init(
    identity: MaskRequestIdentity,
    kind: VisionAIMaskKind,
    mask: MaskDefinition,
    modelIdentifier: String,
    modelVersion: String
  ) {
    self.identity = identity
    self.kind = kind
    self.mask = mask
    self.modelIdentifier = modelIdentifier
    self.modelVersion = modelVersion
  }

  public func decodePayload() throws -> VisionAIMaskPayloadV1 {
    try JSONDecoder().decode(VisionAIMaskPayloadV1.self, from: mask.payload)
  }
}

public enum VisionAIMaskError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedMaskKind(String)
  case unsupportedImagePixelFormat(ImagePixelFormat)
  case invalidImageBuffer(String)
  case noMaskProduced(VisionAIMaskKind)
  case visionFailure(String)
  case unsupportedVisionMaskPixelFormat(UInt32)
  case maskConversionFailed

  /// A deterministic synthetic image is not guaranteed to contain a semantic
  /// subject. Tests may skip that case while still failing real conversion and
  /// contract errors.
  public var shouldSkipDeterministicFixture: Bool {
    if case .noMaskProduced = self { return true }
    return false
  }

  public var errorDescription: String? {
    switch self {
    case .unsupportedMaskKind(let kind):
      "Vision AI does not implement the \(kind) mask kind."
    case .unsupportedImagePixelFormat(let format):
      "Vision AI does not accept the \(format) image pixel format."
    case .invalidImageBuffer(let reason):
      "The image buffer is invalid for Vision AI: \(reason)."
    case .noMaskProduced(let kind):
      "Vision did not produce a \(kind.displayName.lowercased()) mask for this image."
    case .visionFailure(let reason):
      "Vision failed to generate a mask: \(reason)."
    case .unsupportedVisionMaskPixelFormat(let format):
      "Vision returned an unsupported mask pixel format: \(format)."
    case .maskConversionFailed:
      "The Vision mask could not be converted to durable grayscale coverage."
    }
  }
}

public protocol VisionAIMaskProvider: Sendable {
  func generateMask(_ request: VisionAIMaskRequest) async throws -> VisionAIMaskResult
}

/// An offline, system-framework-only mask provider.
///
/// This service uses `VNGenerateForegroundInstanceMaskRequest` for foreground
/// and subject masks, and `VNGeneratePersonSegmentationRequest` for person
/// masks. It does not download, install, or execute proprietary model packs.
public actor VisionAIModelService: VisionAIMaskProvider, AIModelService {
  public static let providerIdentifier = "com.apple.Vision"
  public static let providerVersion = "1"
  public static let supportedMaskKinds: [VisionAIMaskKind] = [.foreground, .subject, .person]

  public init() {}

  public static func supports(_ kind: VisionAIMaskKind) -> Bool {
    supportedMaskKinds.contains(kind)
  }

  /// Compatibility query for the existing domain contract. The domain has a
  /// single `.subject` case for semantic masks; `.sky`, `.object`, `.depth`,
  /// and all other kinds remain unsupported by this provider.
  public static func supports(_ kind: MaskKind) -> Bool {
    if case .subject = kind { return true }
    return false
  }

  public func generateMask(_ request: VisionAIMaskRequest) async throws -> VisionAIMaskResult {
    try Task.checkCancellation()

    let image = try makeCIImage(from: request.image)
    let maskPixelBuffer = try performVisionRequest(kind: request.kind, image: image)
    try Task.checkCancellation()

    let maskData = try packedCoverage(from: maskPixelBuffer)
      .resized(to: request.image.dimensions)
    guard
      let dimensions = PixelDimensions(width: maskData.width, height: maskData.height),
      let payload = VisionAIMaskPayloadV1(
        kind: request.kind,
        dimensions: dimensions,
        bytesPerRow: maskData.width,
        coverage: maskData.coverage
      )
    else {
      throw VisionAIMaskError.maskConversionFailed
    }

    let maskPayload = try JSONEncoder().encode(payload)
    let mask = MaskDefinition(
      id: request.identity.revision.maskID,
      schemaVersion: 1,
      kind: .subject,
      name: "Vision \(request.kind.displayName)",
      isInverted: false,
      payload: maskPayload
    )

    return VisionAIMaskResult(
      identity: request.identity,
      kind: request.kind,
      mask: mask,
      modelIdentifier: request.modelIdentifier,
      modelVersion: request.modelVersion
    )
  }

  /// Adapter for the pre-identity `AIModelService` contract. New callers must
  /// use `VisionAIMaskRequest` so mask ID, revision, and request UUID are kept.
  public func generateMask(_ request: AIModelRequest) async throws -> AIModelResult {
    let kind = try legacyKind(for: request)
    let identity = MaskRequestIdentity(
      revision: MaskRevisionIdentity(
        assetID: request.assetID,
        maskID: UUID(),
        revision: 0
      ),
      requestID: UUID()
    )
    let typedRequest = VisionAIMaskRequest(
      identity: identity,
      image: request.image,
      kind: kind,
      modelIdentifier: request.modelIdentifier
    )
    let result = try await generateMask(typedRequest)
    return AIModelResult(mask: result.mask, modelVersion: result.modelVersion)
  }

  private func legacyKind(for request: AIModelRequest) throws -> VisionAIMaskKind {
    switch request.maskKind {
    case .subject:
      let identifier = request.modelIdentifier.lowercased()
      if identifier.contains("person") {
        return .person
      }
      if identifier.contains("foreground") {
        return .foreground
      }
      return .subject
    case .brush: throw VisionAIMaskError.unsupportedMaskKind("brush")
    case .linearGradient: throw VisionAIMaskError.unsupportedMaskKind("linearGradient")
    case .radialGradient: throw VisionAIMaskError.unsupportedMaskKind("radialGradient")
    case .luminanceRange: throw VisionAIMaskError.unsupportedMaskKind("luminanceRange")
    case .colorRange: throw VisionAIMaskError.unsupportedMaskKind("colorRange")
    case .depthRange: throw VisionAIMaskError.unsupportedMaskKind("depth")
    case .sky: throw VisionAIMaskError.unsupportedMaskKind("sky")
    case .background: throw VisionAIMaskError.unsupportedMaskKind("background")
    case .object: throw VisionAIMaskError.unsupportedMaskKind("object")
    case .unknown(let value): throw VisionAIMaskError.unsupportedMaskKind(value)
    }
  }

  private func makeCIImage(from buffer: ImageBuffer) throws -> CIImage {
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
      throw VisionAIMaskError.unsupportedImagePixelFormat(buffer.pixelFormat)
    }

    let bytesPerRow = Int(buffer.bytesPerRow)
    guard width > 0, height > 0 else {
      throw VisionAIMaskError.invalidImageBuffer("dimensions must be positive")
    }
    guard bytesPerRow >= width * bytesPerPixel else {
      throw VisionAIMaskError.invalidImageBuffer("bytesPerRow is too small")
    }
    guard buffer.data.count >= bytesPerRow * height else {
      throw VisionAIMaskError.invalidImageBuffer("pixel data is truncated")
    }

    let colorSpace =
      CGColorSpace(name: colorSpaceName(for: buffer.colorSpaceName))
      ?? CGColorSpace(name: CGColorSpace.sRGB)!
    return CIImage(
      bitmapData: buffer.data,
      bytesPerRow: bytesPerRow,
      size: CGSize(width: width, height: height),
      format: format,
      colorSpace: colorSpace
    )
  }

  private func colorSpaceName(for name: String?) -> CFString {
    switch name?.lowercased() {
    case "srgb", "public.srgb": CGColorSpace.sRGB
    case "display-p3", "displayp3": CGColorSpace.displayP3
    case "extended-linear-display-p3": CGColorSpace.extendedLinearDisplayP3
    case "extended-linear-acescg": CGColorSpace.acescgLinear
    default: CGColorSpace.sRGB
    }
  }

  private func performVisionRequest(
    kind: VisionAIMaskKind,
    image: CIImage
  ) throws -> CVPixelBuffer {
    let handler = VNImageRequestHandler(ciImage: image, options: [:])

    switch kind {
    case .foreground, .subject:
      let request = VNGenerateForegroundInstanceMaskRequest()
      do {
        try handler.perform([request])
      } catch {
        throw VisionAIMaskError.visionFailure(String(describing: error))
      }
      guard let observation = request.results?.first else {
        throw VisionAIMaskError.noMaskProduced(kind)
      }
      do {
        let mask = try observation.generateScaledMaskForImage(
          forInstances: observation.allInstances,
          from: handler
        )
        return mask
      } catch let error as VisionAIMaskError {
        throw error
      } catch {
        throw VisionAIMaskError.visionFailure(String(describing: error))
      }

    case .person:
      let request = VNGeneratePersonSegmentationRequest()
      request.qualityLevel = .accurate
      request.outputPixelFormat = kCVPixelFormatType_OneComponent8
      do {
        try handler.perform([request])
      } catch {
        throw VisionAIMaskError.visionFailure(String(describing: error))
      }
      guard let observation = request.results?.first else {
        throw VisionAIMaskError.noMaskProduced(kind)
      }
      return observation.pixelBuffer
    }
  }

  private struct PackedCoverage {
    let width: Int
    let height: Int
    let coverage: Data

    func resized(to dimensions: PixelDimensions) -> Self {
      guard width != dimensions.width || height != dimensions.height else {
        return self
      }

      var resized = Data(repeating: 0, count: dimensions.width * dimensions.height)
      resized.withUnsafeMutableBytes { destination in
        guard let destinationBase = destination.baseAddress else { return }
        coverage.withUnsafeBytes { source in
          guard let sourceBase = source.baseAddress else { return }
          for y in 0..<dimensions.height {
            let sourceY = min(height - 1, y * height / dimensions.height)
            for x in 0..<dimensions.width {
              let sourceX = min(width - 1, x * width / dimensions.width)
              let value = sourceBase.load(
                fromByteOffset: sourceY * width + sourceX,
                as: UInt8.self
              )
              destinationBase.storeBytes(
                of: value,
                toByteOffset: y * dimensions.width + x,
                as: UInt8.self
              )
            }
          }
        }
      }
      return Self(width: dimensions.width, height: dimensions.height, coverage: resized)
    }
  }

  private func packedCoverage(from pixelBuffer: CVPixelBuffer) throws -> PackedCoverage {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0 else {
      throw VisionAIMaskError.maskConversionFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw VisionAIMaskError.maskConversionFailed
    }
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    var coverage = Data(repeating: 0, count: width * height)

    coverage.withUnsafeMutableBytes { destination in
      guard let destinationBase = destination.baseAddress else { return }
      for row in 0..<height {
        let sourceRow = baseAddress.advanced(by: row * sourceBytesPerRow)
        let destinationRow = destinationBase.advanced(by: row * width)
        switch pixelFormat {
        case kCVPixelFormatType_OneComponent8:
          destinationRow.copyMemory(from: sourceRow, byteCount: width)
        case kCVPixelFormatType_OneComponent32Float:
          for column in 0..<width {
            let value = sourceRow.load(
              fromByteOffset: column * MemoryLayout<Float>.size,
              as: Float.self
            )
            let clamped = value.isFinite ? min(max(value, 0), 1) : 0
            destinationRow.storeBytes(
              of: UInt8((clamped * 255).rounded()),
              toByteOffset: column,
              as: UInt8.self
            )
          }
        case kCVPixelFormatType_OneComponent16Half:
          for column in 0..<width {
            let bits = sourceRow.load(
              fromByteOffset: column * MemoryLayout<UInt16>.size,
              as: UInt16.self
            )
            let value = Float(Float16(bitPattern: bits))
            let clamped = value.isFinite ? min(max(value, 0), 1) : 0
            destinationRow.storeBytes(
              of: UInt8((clamped * 255).rounded()),
              toByteOffset: column,
              as: UInt8.self
            )
          }
        default:
          return
        }
      }
    }

    guard
      pixelFormat == kCVPixelFormatType_OneComponent8
        || pixelFormat == kCVPixelFormatType_OneComponent32Float
        || pixelFormat == kCVPixelFormatType_OneComponent16Half
    else {
      throw VisionAIMaskError.unsupportedVisionMaskPixelFormat(pixelFormat)
    }
    return PackedCoverage(width: width, height: height, coverage: coverage)
  }
}

extension MaskResultGate {
  /// Identity gate for the Vision result type. It mirrors the existing
  /// `MaskOperationResult` gate without converting a raster mask into a graph.
  public static func accepts(
    _ result: VisionAIMaskResult,
    for currentIdentity: MaskRequestIdentity
  ) -> Bool {
    result.identity == currentIdentity
  }
}
