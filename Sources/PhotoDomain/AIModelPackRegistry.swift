// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation

/// Resource and performance requirements declared by an offline model pack.
///
/// `expectedInferenceMilliseconds` is a pack-card value. It is a gate, not a
/// benchmark result. The host must measure the installed pack separately
/// before publishing a production quality claim.
public struct AIModelPackRequirements: Codable, Hashable, Sendable {
  public let minimumMemoryMB: Int
  public let expectedInferenceMilliseconds: Int

  public init(
    minimumMemoryMB: Int,
    expectedInferenceMilliseconds: Int
  ) throws {
    guard minimumMemoryMB > 0 else {
      throw AIModelPackManifestError.invalidMemoryRequirement(minimumMemoryMB)
    }
    guard expectedInferenceMilliseconds > 0 else {
      throw AIModelPackManifestError.invalidSpeedRequirement(
        expectedInferenceMilliseconds
      )
    }
    self.minimumMemoryMB = minimumMemoryMB
    self.expectedInferenceMilliseconds = expectedInferenceMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case minimumMemoryMB
    case expectedInferenceMilliseconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      minimumMemoryMB: container.decode(Int.self, forKey: .minimumMemoryMB),
      expectedInferenceMilliseconds: container.decode(
        Int.self,
        forKey: .expectedInferenceMilliseconds
      )
    )
  }
}

/// An offline model pack manifest. The manifest identifies the model,
/// its licence and provenance, and the exact local resource to load.
public struct AIModelPackManifest: Codable, Hashable, Sendable, Identifiable {
  public static let currentSchemaVersion: UInt = 1

  public let schemaVersion: UInt
  public let modelID: String
  public let version: String
  public let kind: AIModelKind
  public let license: AIModelLicense
  public let provenanceURL: URL
  public let resourceURL: URL
  public let sha256: String
  public let requirements: AIModelPackRequirements

  public var id: String { modelID }

  public init(
    schemaVersion: UInt = AIModelPackManifest.currentSchemaVersion,
    modelID: String,
    version: String,
    kind: AIModelKind,
    license: AIModelLicense,
    provenanceURL: URL,
    resourceURL: URL,
    sha256: String,
    requirements: AIModelPackRequirements
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw AIModelPackManifestError.unsupportedSchemaVersion(schemaVersion)
    }
    let normalizedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedModelID.isEmpty else {
      throw AIModelPackManifestError.invalidModelID
    }
    let normalizedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedVersion.isEmpty else {
      throw AIModelPackManifestError.invalidVersion
    }
    guard provenanceURL.scheme != nil, !provenanceURL.absoluteString.isEmpty else {
      throw AIModelPackManifestError.invalidProvenanceURL
    }
    guard resourceURL.isFileURL else {
      throw AIModelPackManifestError.resourceMustBeLocal
    }
    let normalizedDigest = sha256.lowercased()
    guard
      normalizedDigest.count == 64,
      normalizedDigest.allSatisfy(\.isHexDigit)
    else {
      throw AIModelPackManifestError.invalidChecksum
    }

    self.schemaVersion = schemaVersion
    self.modelID = normalizedModelID
    self.version = normalizedVersion
    self.kind = kind
    self.license = license
    self.provenanceURL = provenanceURL
    self.resourceURL = resourceURL
    self.sha256 = normalizedDigest
    self.requirements = requirements
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case modelID
    case version
    case kind
    case license
    case provenanceURL
    case resourceURL
    case sha256
    case requirements
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      schemaVersion: container.decode(UInt.self, forKey: .schemaVersion),
      modelID: container.decode(String.self, forKey: .modelID),
      version: container.decode(String.self, forKey: .version),
      kind: container.decode(AIModelKind.self, forKey: .kind),
      license: container.decode(AIModelLicense.self, forKey: .license),
      provenanceURL: container.decode(URL.self, forKey: .provenanceURL),
      resourceURL: container.decode(URL.self, forKey: .resourceURL),
      sha256: container.decode(String.self, forKey: .sha256),
      requirements: container.decode(
        AIModelPackRequirements.self,
        forKey: .requirements
      )
    )
  }
}

public enum AIModelPackManifestError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchemaVersion(UInt)
  case invalidModelID
  case invalidVersion
  case invalidProvenanceURL
  case resourceMustBeLocal
  case invalidChecksum
  case invalidMemoryRequirement(Int)
  case invalidSpeedRequirement(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      "The model-pack manifest schema is not supported: \(version)."
    case .invalidModelID:
      "The model-pack identifier is required."
    case .invalidVersion:
      "The model-pack version is required."
    case .invalidProvenanceURL:
      "The model-pack provenance URL is invalid."
    case .resourceMustBeLocal:
      "Model-pack resources must use a local file URL."
    case .invalidChecksum:
      "The model-pack SHA-256 must contain 64 hexadecimal characters."
    case .invalidMemoryRequirement(let value):
      "The model-pack memory requirement is invalid: \(value) MB."
    case .invalidSpeedRequirement(let value):
      "The model-pack speed requirement is invalid: \(value) ms."
    }
  }
}

/// Runtime limits used before an optional model pack is loaded.
public struct AIModelPackRuntimeProfile: Hashable, Sendable {
  public let availableMemoryMB: Int
  public let maximumInferenceMilliseconds: Int

  public init(
    availableMemoryMB: Int,
    maximumInferenceMilliseconds: Int
  ) throws {
    guard availableMemoryMB > 0 else {
      throw AIModelPackManifestError.invalidMemoryRequirement(availableMemoryMB)
    }
    guard maximumInferenceMilliseconds > 0 else {
      throw AIModelPackManifestError.invalidSpeedRequirement(
        maximumInferenceMilliseconds
      )
    }
    self.availableMemoryMB = availableMemoryMB
    self.maximumInferenceMilliseconds = maximumInferenceMilliseconds
  }
}

public enum AIModelPackUnavailableReason: Equatable, Hashable, Sendable {
  case notRegistered
  case resourceMissing
  case resourceMustBeLocal
  case resourceUnreadable
  case checksumMismatch
  case insufficientMemory(requiredMB: Int, availableMB: Int)
  case speedBudgetExceeded(expectedMilliseconds: Int, maximumMilliseconds: Int)
}

public enum AIModelPackAvailability: Equatable, Hashable, Sendable {
  case available
  case unavailable(AIModelPackUnavailableReason)
}

public struct AIModelPackAvailabilityReport: Equatable, Hashable, Sendable {
  public let modelID: String
  public let availability: AIModelPackAvailability

  public init(modelID: String, availability: AIModelPackAvailability) {
    self.modelID = modelID
    self.availability = availability
  }

  public var isAvailable: Bool {
    if case .available = availability { return true }
    return false
  }
}

public enum AIModelPackLoaderError: Error, Equatable, LocalizedError, Sendable {
  case notRegistered
  case resourceMissing
  case resourceMustBeLocal
  case resourceUnreadable
  case checksumMismatch(expected: String, actual: String)
  case insufficientMemory(requiredMB: Int, availableMB: Int)
  case speedBudgetExceeded(expectedMilliseconds: Int, maximumMilliseconds: Int)

  public var errorDescription: String? {
    switch self {
    case .notRegistered:
      "The model pack is not registered."
    case .resourceMissing:
      "The local model-pack resource is not installed."
    case .resourceMustBeLocal:
      "Model-pack resources must use a local file URL."
    case .resourceUnreadable:
      "The local model-pack resource cannot be read."
    case .checksumMismatch(let expected, let actual):
      "The model-pack checksum does not match. Expected \(expected), got \(actual)."
    case .insufficientMemory(let requiredMB, let availableMB):
      "The model pack requires \(requiredMB) MB, but only \(availableMB) MB is available."
    case .speedBudgetExceeded(let expectedMilliseconds, let maximumMilliseconds):
      "The model pack expects \(expectedMilliseconds) ms, above the \(maximumMilliseconds) ms budget."
    }
  }
}

/// A verified local resource. This contract does not instantiate `MLModel`.
/// The macOS application can pass `resourceURL` to Core ML after this local
/// verification succeeds.
public struct VerifiedAIModelPack: Hashable, Sendable {
  public let manifest: AIModelPackManifest
  public let resourceURL: URL
  public let verifiedSHA256: String

  public init(
    manifest: AIModelPackManifest,
    resourceURL: URL,
    verifiedSHA256: String
  ) {
    self.manifest = manifest
    self.resourceURL = resourceURL
    self.verifiedSHA256 = verifiedSHA256
  }
}

public protocol AIModelPackLoader: Sendable {
  func load(
    manifest: AIModelPackManifest,
    runtime: AIModelPackRuntimeProfile
  ) throws -> VerifiedAIModelPack
}

/// Loads only already-installed local Core ML resources. It never downloads,
/// resolves, or accesses a network URL.
public struct LocalCoreMLModelPackLoader: AIModelPackLoader, Sendable {
  public init() {}

  public func load(
    manifest: AIModelPackManifest,
    runtime: AIModelPackRuntimeProfile
  ) throws -> VerifiedAIModelPack {
    guard manifest.resourceURL.isFileURL else {
      throw AIModelPackLoaderError.resourceMustBeLocal
    }

    var isDirectory = ObjCBool(false)
    guard
      FileManager.default.fileExists(
        atPath: manifest.resourceURL.path,
        isDirectory: &isDirectory
      )
    else {
      throw AIModelPackLoaderError.resourceMissing
    }

    guard runtime.availableMemoryMB >= manifest.requirements.minimumMemoryMB else {
      throw AIModelPackLoaderError.insufficientMemory(
        requiredMB: manifest.requirements.minimumMemoryMB,
        availableMB: runtime.availableMemoryMB
      )
    }
    guard
      manifest.requirements.expectedInferenceMilliseconds
        <= runtime.maximumInferenceMilliseconds
    else {
      throw AIModelPackLoaderError.speedBudgetExceeded(
        expectedMilliseconds: manifest.requirements.expectedInferenceMilliseconds,
        maximumMilliseconds: runtime.maximumInferenceMilliseconds
      )
    }

    let actualSHA256: String
    do {
      actualSHA256 = try LocalAIModelPackResourceDigest.sha256(
        at: manifest.resourceURL,
        isDirectory: isDirectory.boolValue
      )
    } catch {
      throw AIModelPackLoaderError.resourceUnreadable
    }
    guard actualSHA256 == manifest.sha256 else {
      throw AIModelPackLoaderError.checksumMismatch(
        expected: manifest.sha256,
        actual: actualSHA256
      )
    }

    return VerifiedAIModelPack(
      manifest: manifest,
      resourceURL: manifest.resourceURL,
      verifiedSHA256: actualSHA256
    )
  }
}

public enum AIModelPackRegistryError: Error, Equatable, LocalizedError, Sendable {
  case duplicateModelID(String)

  public var errorDescription: String? {
    switch self {
    case .duplicateModelID(let modelID):
      "The model-pack identifier is registered more than once: \(modelID)."
    }
  }
}

/// An offline registry for optional Core ML packs.
public struct LocalAIModelPackRegistry: Sendable {
  private let manifestsByID: [String: AIModelPackManifest]
  private let loader: LocalCoreMLModelPackLoader

  public init(manifests: [AIModelPackManifest]) throws {
    var records: [String: AIModelPackManifest] = [:]
    records.reserveCapacity(manifests.count)
    for manifest in manifests {
      guard records[manifest.modelID] == nil else {
        throw AIModelPackRegistryError.duplicateModelID(manifest.modelID)
      }
      records[manifest.modelID] = manifest
    }
    self.manifestsByID = records
    self.loader = LocalCoreMLModelPackLoader()
  }

  public func manifest(for modelID: String) -> AIModelPackManifest? {
    manifestsByID[modelID]
  }

  public func availability(
    for modelID: String,
    runtime: AIModelPackRuntimeProfile
  ) -> AIModelPackAvailabilityReport {
    guard let manifest = manifestsByID[modelID] else {
      return AIModelPackAvailabilityReport(
        modelID: modelID,
        availability: .unavailable(.notRegistered)
      )
    }

    do {
      _ = try loader.load(manifest: manifest, runtime: runtime)
      return AIModelPackAvailabilityReport(
        modelID: modelID,
        availability: .available
      )
    } catch let error as AIModelPackLoaderError {
      return AIModelPackAvailabilityReport(
        modelID: modelID,
        availability: .unavailable(Self.reason(for: error))
      )
    } catch {
      return AIModelPackAvailabilityReport(
        modelID: modelID,
        availability: .unavailable(.resourceUnreadable)
      )
    }
  }

  public func load(
    modelID: String,
    runtime: AIModelPackRuntimeProfile
  ) throws -> VerifiedAIModelPack {
    guard let manifest = manifestsByID[modelID] else {
      throw AIModelPackLoaderError.notRegistered
    }
    return try loader.load(manifest: manifest, runtime: runtime)
  }

  private static func reason(
    for error: AIModelPackLoaderError
  ) -> AIModelPackUnavailableReason {
    switch error {
    case .notRegistered:
      .notRegistered
    case .resourceMissing:
      .resourceMissing
    case .resourceMustBeLocal:
      .resourceMustBeLocal
    case .resourceUnreadable:
      .resourceUnreadable
    case .checksumMismatch:
      .checksumMismatch
    case .insufficientMemory(let requiredMB, let availableMB):
      .insufficientMemory(requiredMB: requiredMB, availableMB: availableMB)
    case .speedBudgetExceeded(let expectedMilliseconds, let maximumMilliseconds):
      .speedBudgetExceeded(
        expectedMilliseconds: expectedMilliseconds,
        maximumMilliseconds: maximumMilliseconds
      )
    }
  }
}

private enum LocalAIModelPackResourceDigest {
  static func sha256(at url: URL, isDirectory: Bool) throws -> String {
    if isDirectory {
      return try sha256Directory(at: url)
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    return hex(SHA256.hash(data: data))
  }

  private static func sha256Directory(at url: URL) throws -> String {
    let rootURL = url.standardizedFileURL
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ]
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: Array(keys),
        options: []
      )
    else {
      throw AIModelPackLoaderError.resourceUnreadable
    }

    var files: [(path: String, data: Data)] = []
    while let childURL = enumerator.nextObject() as? URL {
      let values = try childURL.resourceValues(forKeys: keys)
      if values.isSymbolicLink == true {
        throw AIModelPackLoaderError.resourceUnreadable
      }
      if values.isDirectory == true {
        continue
      }
      guard values.isRegularFile == true else {
        throw AIModelPackLoaderError.resourceUnreadable
      }
      let relativePath = String(
        childURL.path.dropFirst(rootURL.path.count)
      ).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      files.append(
        (
          path: relativePath,
          data: try Data(contentsOf: childURL, options: .mappedIfSafe)
        )
      )
    }

    files.sort { $0.path < $1.path }
    var hasher = SHA256()
    for file in files {
      hasher.update(data: Data(file.path.utf8))
      hasher.update(data: Data([0]))
      hasher.update(data: file.data)
      hasher.update(data: Data([0]))
    }
    return hex(hasher.finalize())
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
