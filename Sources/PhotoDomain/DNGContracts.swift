// SPDX-License-Identifier: MPL-2.0

import Foundation

/// The four bytes stored by the DNGVersion tag.
///
/// PhotoSuite keeps the complete four-byte value so recipes and diagnostics do
/// not lose a future DNG build component. The metadata reader currently
/// supports DNG 1.x through 1.7.x. Pixel encoding remains a separate contract.
public struct DNGVersion: Codable, Comparable, Hashable, Sendable {
  public let major: UInt8
  public let minor: UInt8
  public let patch: UInt8
  public let build: UInt8

  public init(major: UInt8, minor: UInt8, patch: UInt8 = 0, build: UInt8 = 0) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.build = build
  }

  public init?(bytes: [UInt8]) {
    guard bytes.count == 4 else { return nil }
    self.init(major: bytes[0], minor: bytes[1], patch: bytes[2], build: bytes[3])
  }

  public static let dng171 = DNGVersion(major: 1, minor: 7, patch: 1)

  public var bytes: [UInt8] { [major, minor, patch, build] }

  public var stringValue: String {
    if build == 0 {
      return "\(major).\(minor).\(patch)"
    }
    return "\(major).\(minor).\(patch).\(build)"
  }

  public var isSupportedMetadataVersion: Bool {
    major == 1 && minor <= 7
  }

  public static func < (lhs: DNGVersion, rhs: DNGVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    return lhs.build < rhs.build
  }
}

public enum DNGByteOrder: String, Codable, Hashable, Sendable {
  case littleEndian
  case bigEndian
}

public enum DNGContainerState: String, Codable, Hashable, Sendable {
  case notDNG
  case valid
  case unsupportedVersion
  case unsupportedContainer
  case malformed
}

public enum DNGContainerIssue: String, Codable, Error, Hashable, Sendable {
  case truncatedHeader
  case invalidByteOrder
  case invalidTIFFMagic
  case bigTIFFUnsupported
  case missingFirstIFD
  case truncatedIFD
  case invalidIFDOffset
  case invalidTagValue
  case missingDNGVersion
  case unsupportedDNGVersion
}

public struct DNGActiveArea: Codable, Hashable, Sendable {
  public let top: UInt32
  public let left: UInt32
  public let bottom: UInt32
  public let right: UInt32

  public init(top: UInt32, left: UInt32, bottom: UInt32, right: UInt32) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }
}

public struct DNGContainerMetadata: Codable, Hashable, Sendable {
  public let imageWidth: UInt32?
  public let imageHeight: UInt32?
  public let bitsPerSample: [UInt16]
  public let compression: UInt16?
  public let photometricInterpretation: UInt16?
  public let samplesPerPixel: UInt16?
  public let make: String?
  public let model: String?
  public let uniqueCameraModel: String?
  public let cfaRepeatPatternWidth: UInt16?
  public let cfaRepeatPatternHeight: UInt16?
  public let cfaPattern: [UInt8]
  public let activeArea: DNGActiveArea?
  public let whiteLevel: [UInt32]
  public let blackLevel: [Double]
  public let defaultCropOrigin: [Double]
  public let defaultCropSize: [Double]
  public let colorMatrix1: [Double]
  public let colorMatrix2: [Double]
  public let stripCount: UInt32
  public let tileCount: UInt32
  public let hasRawImageData: Bool
  public let recognizedTagIDs: [UInt16]

  public init(
    imageWidth: UInt32?,
    imageHeight: UInt32?,
    bitsPerSample: [UInt16],
    compression: UInt16?,
    photometricInterpretation: UInt16?,
    samplesPerPixel: UInt16?,
    make: String?,
    model: String?,
    uniqueCameraModel: String?,
    cfaRepeatPatternWidth: UInt16?,
    cfaRepeatPatternHeight: UInt16?,
    cfaPattern: [UInt8],
    activeArea: DNGActiveArea?,
    whiteLevel: [UInt32],
    blackLevel: [Double],
    defaultCropOrigin: [Double],
    defaultCropSize: [Double],
    colorMatrix1: [Double],
    colorMatrix2: [Double],
    stripCount: UInt32,
    tileCount: UInt32,
    hasRawImageData: Bool,
    recognizedTagIDs: [UInt16]
  ) {
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    self.bitsPerSample = bitsPerSample
    self.compression = compression
    self.photometricInterpretation = photometricInterpretation
    self.samplesPerPixel = samplesPerPixel
    self.make = make
    self.model = model
    self.uniqueCameraModel = uniqueCameraModel
    self.cfaRepeatPatternWidth = cfaRepeatPatternWidth
    self.cfaRepeatPatternHeight = cfaRepeatPatternHeight
    self.cfaPattern = cfaPattern
    self.activeArea = activeArea
    self.whiteLevel = whiteLevel
    self.blackLevel = blackLevel
    self.defaultCropOrigin = defaultCropOrigin
    self.defaultCropSize = defaultCropSize
    self.colorMatrix1 = colorMatrix1
    self.colorMatrix2 = colorMatrix2
    self.stripCount = stripCount
    self.tileCount = tileCount
    self.hasRawImageData = hasRawImageData
    self.recognizedTagIDs = recognizedTagIDs
  }
}

public struct DNGContainerInspection: Codable, Hashable, Sendable {
  public let state: DNGContainerState
  public let dngVersion: DNGVersion?
  public let backwardVersion: DNGVersion?
  public let byteOrder: DNGByteOrder?
  public let isBigTIFF: Bool
  public let metadata: DNGContainerMetadata?
  public let issue: DNGContainerIssue?
  public let sourceByteCount: UInt64

  public init(
    state: DNGContainerState,
    dngVersion: DNGVersion?,
    backwardVersion: DNGVersion?,
    byteOrder: DNGByteOrder?,
    isBigTIFF: Bool,
    metadata: DNGContainerMetadata?,
    issue: DNGContainerIssue?,
    sourceByteCount: UInt64
  ) {
    self.state = state
    self.dngVersion = dngVersion
    self.backwardVersion = backwardVersion
    self.byteOrder = byteOrder
    self.isBigTIFF = isBigTIFF
    self.metadata = metadata
    self.issue = issue
    self.sourceByteCount = sourceByteCount
  }
}

public struct DNGInspectionRequest: Codable, Hashable, Sendable {
  public static let defaultMaximumFileSize: UInt64 = 512 * 1024 * 1024

  public let sourceURL: URL
  public let maximumFileSize: UInt64

  public init(
    sourceURL: URL,
    maximumFileSize: UInt64 = DNGInspectionRequest.defaultMaximumFileSize
  ) {
    self.sourceURL = sourceURL
    self.maximumFileSize = maximumFileSize
  }
}

public enum DNGReaderError: Error, Equatable, LocalizedError, Sendable {
  case sourceUnavailable(URL?)
  case fileTooLarge(actual: UInt64, limit: UInt64)

  public var errorDescription: String? {
    switch self {
    case .sourceUnavailable(let sourceURL):
      if let sourceURL {
        return "The DNG source cannot be read: \(sourceURL.lastPathComponent)."
      }
      return "The DNG source cannot be read."
    case .fileTooLarge(let actual, let limit):
      return "The DNG source is too large to inspect safely (\(actual) bytes; limit \(limit))."
    }
  }
}

public enum DNGWriterFeature: String, Codable, Hashable, Sendable {
  case metadataPatch
  case rawPixelEncoding
  case privateDataPreservation
}

/// A stable contract for a future DNG writer.
///
/// The current implementation exposes only a metadata-inspection reader. No
/// writer claims to emit DNG pixels or rewrite a source file until a complete
/// encoder passes the parser, corpus, and recovery gates.
public struct DNGWriterContract: Codable, Hashable, Sendable {
  public let schemaVersion: UInt
  public let targetVersion: DNGVersion
  public let supportedFeatures: Set<DNGWriterFeature>

  public init(
    schemaVersion: UInt,
    targetVersion: DNGVersion,
    supportedFeatures: Set<DNGWriterFeature>
  ) {
    self.schemaVersion = schemaVersion
    self.targetVersion = targetVersion
    self.supportedFeatures = supportedFeatures
  }

  public static let metadataOnly = DNGWriterContract(
    schemaVersion: 1,
    targetVersion: .dng171,
    supportedFeatures: [.metadataPatch]
  )

  public var supportsMetadataPatch: Bool {
    supportedFeatures.contains(.metadataPatch)
  }

  public var supportsRawPixelEncoding: Bool {
    supportedFeatures.contains(.rawPixelEncoding)
  }
}

public struct DNGMetadataPatch: Codable, Hashable, Sendable {
  public let make: String?
  public let model: String?
  public let uniqueCameraModel: String?
  public let software: String?

  public init(
    make: String? = nil,
    model: String? = nil,
    uniqueCameraModel: String? = nil,
    software: String? = nil
  ) {
    self.make = make
    self.model = model
    self.uniqueCameraModel = uniqueCameraModel
    self.software = software
  }
}

public struct DNGWriteRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL
  public let destinationURL: URL
  public let metadataPatch: DNGMetadataPatch

  public init(sourceURL: URL, destinationURL: URL, metadataPatch: DNGMetadataPatch) {
    self.sourceURL = sourceURL
    self.destinationURL = destinationURL
    self.metadataPatch = metadataPatch
  }
}

public struct DNGWriteResult: Codable, Hashable, Sendable {
  public let destinationURL: URL
  public let contract: DNGWriterContract

  public init(destinationURL: URL, contract: DNGWriterContract) {
    self.destinationURL = destinationURL
    self.contract = contract
  }
}

public protocol DNGContainerReader: Sendable {
  func inspect(_ request: DNGInspectionRequest) throws -> DNGContainerInspection
}

public protocol DNGContainerWriter: Sendable {
  var contract: DNGWriterContract { get }
  func write(_ request: DNGWriteRequest) throws -> DNGWriteResult
}
