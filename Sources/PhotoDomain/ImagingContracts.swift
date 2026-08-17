// SPDX-License-Identifier: MPL-2.0

import Foundation

public enum ImagePixelFormat: Codable, Hashable, Sendable {
  case rgba8
  case bgra8
  case rgba16Float
  case unknown(String)

  public init(from decoder: any Decoder) throws {
    let decoded = try UnknownStringCodeCoding.decode(from: decoder)
    guard !decoded.isExplicitlyUnknown else {
      self = .unknown(decoded.value)
      return
    }
    self = Self(code: decoded.value)
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .unknown(let value):
      try UnknownStringCodeCoding.encodeUnknown(
        value,
        reservedValues: ["rgba8", "bgra8", "rgba16Float"],
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private init(code: String) {
    switch code {
    case "rgba8": self = .rgba8
    case "bgra8": self = .bgra8
    case "rgba16Float": self = .rgba16Float
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .rgba8: "rgba8"
    case .bgra8: "bgra8"
    case .rgba16Float: "rgba16Float"
    case .unknown(let code): code
    }
  }
}

public struct ImageBuffer: Codable, Hashable, Sendable {
  public let data: Data
  public let dimensions: PixelDimensions
  public let bytesPerRow: UInt
  public let pixelFormat: ImagePixelFormat
  public let colorSpaceName: String?

  public init(
    data: Data,
    dimensions: PixelDimensions,
    bytesPerRow: UInt,
    pixelFormat: ImagePixelFormat,
    colorSpaceName: String?
  ) {
    self.data = data
    self.dimensions = dimensions
    self.bytesPerRow = bytesPerRow
    self.pixelFormat = pixelFormat
    self.colorSpaceName = colorSpaceName
  }
}

public struct RawDecodeRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL
  public let decoderVersion: String?

  public init(sourceURL: URL, decoderVersion: String? = nil) {
    self.sourceURL = sourceURL
    self.decoderVersion = decoderVersion
  }
}

public struct RawDecodeResult: Codable, Hashable, Sendable {
  public let image: ImageBuffer
  public let metadata: [String: String]
  public let decoderIdentifier: String
  public let decoderVersion: String

  public init(
    image: ImageBuffer,
    metadata: [String: String],
    decoderIdentifier: String,
    decoderVersion: String
  ) {
    self.image = image
    self.metadata = metadata
    self.decoderIdentifier = decoderIdentifier
    self.decoderVersion = decoderVersion
  }
}

public struct RawCapabilityRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL?

  public init(sourceURL: URL? = nil) {
    self.sourceURL = sourceURL
  }
}

public struct RawCapabilityResult: Codable, Hashable, Sendable {
  public let supportedCameraModels: [String]
  public let supportedDecoderVersions: [String]

  public init(supportedCameraModels: [String], supportedDecoderVersions: [String]) {
    self.supportedCameraModels = supportedCameraModels
    self.supportedDecoderVersions = supportedDecoderVersions
  }
}

public protocol RawDecoder: Sendable {
  func decode(_ request: RawDecodeRequest) async throws -> RawDecodeResult
  func capabilities(_ request: RawCapabilityRequest) async throws -> RawCapabilityResult
}

public struct RenderRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL
  public let recipe: EditRecipe
  public let maximumPixelDimension: Int?
  public let outputColorSpaceName: String

  public init(
    sourceURL: URL,
    recipe: EditRecipe,
    maximumPixelDimension: Int?,
    outputColorSpaceName: String
  ) {
    self.sourceURL = sourceURL
    self.recipe = recipe
    self.maximumPixelDimension = maximumPixelDimension
    self.outputColorSpaceName = outputColorSpaceName
  }
}

public struct RenderHistogram: Codable, Hashable, Sendable {
  public static let binCount = 256

  public let red: [UInt64]
  public let green: [UInt64]
  public let blue: [UInt64]
  public let luminance: [UInt64]

  public init?(red: [UInt64], green: [UInt64], blue: [UInt64], luminance: [UInt64]) {
    guard
      red.count == Self.binCount,
      green.count == Self.binCount,
      blue.count == Self.binCount,
      luminance.count == Self.binCount
    else {
      return nil
    }
    self.red = red
    self.green = green
    self.blue = blue
    self.luminance = luminance
  }
}

public struct RenderResult: Codable, Hashable, Sendable {
  public let imageData: Data
  public let typeIdentifier: String
  public let pixelDimensions: PixelDimensions
  public let histogram: RenderHistogram?

  public init(
    imageData: Data,
    typeIdentifier: String,
    pixelDimensions: PixelDimensions,
    histogram: RenderHistogram? = nil
  ) {
    self.imageData = imageData
    self.typeIdentifier = typeIdentifier
    self.pixelDimensions = pixelDimensions
    self.histogram = histogram
  }
}

public protocol RenderEngine: Sendable {
  func render(_ request: RenderRequest) async throws -> RenderResult
}

public struct AIModelRequest: Codable, Hashable, Sendable {
  public let assetID: UUID
  public let image: ImageBuffer
  public let maskKind: MaskKind
  public let modelIdentifier: String

  public init(
    assetID: UUID,
    image: ImageBuffer,
    maskKind: MaskKind,
    modelIdentifier: String
  ) {
    self.assetID = assetID
    self.image = image
    self.maskKind = maskKind
    self.modelIdentifier = modelIdentifier
  }
}

public struct AIModelResult: Codable, Hashable, Sendable {
  public let mask: MaskDefinition
  public let modelVersion: String

  public init(mask: MaskDefinition, modelVersion: String) {
    self.mask = mask
    self.modelVersion = modelVersion
  }
}

public protocol AIModelService: Sendable {
  func generateMask(_ request: AIModelRequest) async throws -> AIModelResult
}

public struct CodecDecodeRequest: Codable, Hashable, Sendable {
  public let data: Data
  public let typeIdentifier: String?

  public init(data: Data, typeIdentifier: String?) {
    self.data = data
    self.typeIdentifier = typeIdentifier
  }
}

public struct CodecDecodeResult: Codable, Hashable, Sendable {
  public let image: ImageBuffer
  public let properties: [String: String]

  public init(image: ImageBuffer, properties: [String: String]) {
    self.image = image
    self.properties = properties
  }
}

public struct CodecEncodeRequest: Codable, Hashable, Sendable {
  public let image: ImageBuffer
  public let typeIdentifier: String
  public let quality: Double?

  public init(image: ImageBuffer, typeIdentifier: String, quality: Double?) {
    self.image = image
    self.typeIdentifier = typeIdentifier
    self.quality = quality
  }
}

public struct CodecEncodeResult: Codable, Hashable, Sendable {
  public let data: Data
  public let typeIdentifier: String

  public init(data: Data, typeIdentifier: String) {
    self.data = data
    self.typeIdentifier = typeIdentifier
  }
}

public protocol Codec: Sendable {
  func decode(_ request: CodecDecodeRequest) async throws -> CodecDecodeResult
  func encode(_ request: CodecEncodeRequest) async throws -> CodecEncodeResult
}

public enum ExportFormat: Codable, Hashable, Sendable {
  case jpeg
  case heif
  case tiff
  case unknown(String)

  public init(from decoder: any Decoder) throws {
    let decoded = try UnknownStringCodeCoding.decode(from: decoder)
    guard !decoded.isExplicitlyUnknown else {
      self = .unknown(decoded.value)
      return
    }
    self = Self(code: decoded.value)
  }

  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .unknown(let value):
      try UnknownStringCodeCoding.encodeUnknown(
        value,
        reservedValues: ["jpeg", "heif", "tiff"],
        to: encoder
      )
    default:
      try UnknownStringCodeCoding.encodeKnown(code, to: encoder)
    }
  }

  private init(code: String) {
    switch code {
    case "jpeg": self = .jpeg
    case "heif": self = .heif
    case "tiff": self = .tiff
    default: self = .unknown(code)
    }
  }

  private var code: String {
    switch self {
    case .jpeg: "jpeg"
    case .heif: "heif"
    case .tiff: "tiff"
    case .unknown(let code): code
    }
  }
}

public enum ExportResize: Codable, Hashable, Sendable {
  case original
  case longEdge(Int)
  case dimensions(width: Int, height: Int)
}

public enum ExportMetadataPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  case basic
  case copyrightOnly
  case all
  case none
}

public enum ExportWatermark: Codable, Hashable, Sendable {
  case none
  case text(String)
}

public enum ExportOutputSharpening: String, Codable, CaseIterable, Hashable, Sendable {
  case none
  case screenStandard
  case screenHigh
  case printStandard
}

public struct ExportOptions: Codable, Hashable, Sendable {
  public let resize: ExportResize
  public let metadata: ExportMetadataPolicy
  public let watermark: ExportWatermark
  public let outputSharpening: ExportOutputSharpening

  public init(
    resize: ExportResize = .original,
    metadata: ExportMetadataPolicy = .basic,
    watermark: ExportWatermark = .none,
    outputSharpening: ExportOutputSharpening = .none
  ) {
    self.resize = resize
    self.metadata = metadata
    self.watermark = watermark
    self.outputSharpening = outputSharpening
  }
}

public struct ExportRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL
  public let recipe: EditRecipe
  public let destinationURL: URL
  public let format: ExportFormat
  public let quality: Double?
  public let options: ExportOptions

  public init(
    sourceURL: URL,
    recipe: EditRecipe,
    destinationURL: URL,
    format: ExportFormat,
    quality: Double?,
    options: ExportOptions = ExportOptions()
  ) {
    self.sourceURL = sourceURL
    self.recipe = recipe
    self.destinationURL = destinationURL
    self.format = format
    self.quality = quality
    self.options = options
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sourceURL = try container.decode(URL.self, forKey: .sourceURL)
    recipe = try container.decode(EditRecipe.self, forKey: .recipe)
    destinationURL = try container.decode(URL.self, forKey: .destinationURL)
    format = try container.decode(ExportFormat.self, forKey: .format)
    quality = try container.decodeIfPresent(Double.self, forKey: .quality)
    options = try container.decodeIfPresent(ExportOptions.self, forKey: .options) ?? ExportOptions()
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sourceURL, forKey: .sourceURL)
    try container.encode(recipe, forKey: .recipe)
    try container.encode(destinationURL, forKey: .destinationURL)
    try container.encode(format, forKey: .format)
    try container.encodeIfPresent(quality, forKey: .quality)
    try container.encode(options, forKey: .options)
  }

  private enum CodingKeys: String, CodingKey {
    case sourceURL
    case recipe
    case destinationURL
    case format
    case quality
    case options
  }
}

public struct ExportResult: Codable, Hashable, Sendable {
  public let derivative: DurableDerivative

  public init(derivative: DurableDerivative) {
    self.derivative = derivative
  }
}

public protocol Exporter: Sendable {
  func export(_ request: ExportRequest) async throws -> ExportResult
}
