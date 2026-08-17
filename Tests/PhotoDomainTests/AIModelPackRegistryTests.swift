// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation
import XCTest

@testable import PhotoDomain

final class AIModelPackRegistryTests: XCTestCase {
  func testValidLocalPackManifestLoadsAfterChecksumAndRuntimeGatesPass() throws {
    let payload = Data("photosuite-test-model".utf8)
    let resourceURL = try temporaryResource(payload)
    defer { try? FileManager.default.removeItem(at: resourceURL) }

    let manifest = try makeManifest(
      resourceURL: resourceURL,
      sha256: digest(payload),
      minimumMemoryMB: 1024,
      expectedInferenceMilliseconds: 80
    )
    let registry = try LocalAIModelPackRegistry(manifests: [manifest])
    let runtime = try AIModelPackRuntimeProfile(
      availableMemoryMB: 4096,
      maximumInferenceMilliseconds: 200
    )

    let report = registry.availability(for: manifest.modelID, runtime: runtime)
    let artifact = try registry.load(modelID: manifest.modelID, runtime: runtime)

    XCTAssertEqual(report.availability, .available)
    XCTAssertEqual(artifact.manifest, manifest)
    XCTAssertEqual(artifact.resourceURL, resourceURL)
    XCTAssertEqual(artifact.verifiedSHA256, digest(payload))
  }

  func testManifestRejectsInvalidChecksumAndNetworkResource() throws {
    let resourceURL = URL(fileURLWithPath: "/tmp/photosuite-model.mlmodelc")

    XCTAssertThrowsError(
      try AIModelPackManifest(
        modelID: "photosuite.test.invalid-checksum",
        version: "1.0.0",
        kind: .subject,
        license: .apache2,
        provenanceURL: URL(string: "https://example.com/model-card")!,
        resourceURL: resourceURL,
        sha256: "not-a-sha256",
        requirements: try AIModelPackRequirements(
          minimumMemoryMB: 1024,
          expectedInferenceMilliseconds: 80
        )
      )
    ) { error in
      XCTAssertEqual(error as? AIModelPackManifestError, .invalidChecksum)
    }

    XCTAssertThrowsError(
      try AIModelPackManifest(
        modelID: "photosuite.test.network-resource",
        version: "1.0.0",
        kind: .sky,
        license: .apache2,
        provenanceURL: URL(string: "https://example.com/model-card")!,
        resourceURL: URL(string: "https://example.com/model.mlmodelc")!,
        sha256: String(repeating: "a", count: 64),
        requirements: try AIModelPackRequirements(
          minimumMemoryMB: 1024,
          expectedInferenceMilliseconds: 80
        )
      )
    ) { error in
      XCTAssertEqual(error as? AIModelPackManifestError, .resourceMustBeLocal)
    }
  }

  func testRegistryReportsUnavailableMissingPackAndRuntimeGateFailures() throws {
    let missingURL = URL(fileURLWithPath: "/tmp/photosuite-missing-model.mlmodelc")
    let manifest = try makeManifest(
      resourceURL: missingURL,
      sha256: String(repeating: "b", count: 64),
      minimumMemoryMB: 4096,
      expectedInferenceMilliseconds: 240
    )
    let registry = try LocalAIModelPackRegistry(manifests: [manifest])

    let missingReport = registry.availability(
      for: manifest.modelID,
      runtime: try AIModelPackRuntimeProfile(
        availableMemoryMB: 8192,
        maximumInferenceMilliseconds: 500
      )
    )
    XCTAssertEqual(missingReport.availability, .unavailable(.resourceMissing))

    let payload = Data("photosuite-runtime-gate-model".utf8)
    let resourceURL = try temporaryResource(payload)
    defer { try? FileManager.default.removeItem(at: resourceURL) }
    let gatedManifest = try makeManifest(
      resourceURL: resourceURL,
      sha256: digest(payload),
      minimumMemoryMB: 4096,
      expectedInferenceMilliseconds: 240
    )
    let gatedRegistry = try LocalAIModelPackRegistry(manifests: [gatedManifest])

    let memoryReport = gatedRegistry.availability(
      for: gatedManifest.modelID,
      runtime: try AIModelPackRuntimeProfile(
        availableMemoryMB: 2048,
        maximumInferenceMilliseconds: 500
      )
    )
    XCTAssertEqual(
      memoryReport.availability,
      .unavailable(.insufficientMemory(requiredMB: 4096, availableMB: 2048))
    )

    let speedReport = gatedRegistry.availability(
      for: gatedManifest.modelID,
      runtime: try AIModelPackRuntimeProfile(
        availableMemoryMB: 8192,
        maximumInferenceMilliseconds: 100
      )
    )
    XCTAssertEqual(
      speedReport.availability,
      .unavailable(.speedBudgetExceeded(expectedMilliseconds: 240, maximumMilliseconds: 100))
    )
  }

  func testRegistryReportsUnregisteredPackWithoutAttemptingAResourceAccess() throws {
    let registry = try LocalAIModelPackRegistry(manifests: [])
    let report = registry.availability(
      for: "photosuite.not-registered",
      runtime: try AIModelPackRuntimeProfile(
        availableMemoryMB: 4096,
        maximumInferenceMilliseconds: 200
      )
    )

    XCTAssertEqual(report.modelID, "photosuite.not-registered")
    XCTAssertEqual(report.availability, .unavailable(.notRegistered))
    XCTAssertThrowsError(
      try registry.load(
        modelID: "photosuite.not-registered",
        runtime: try AIModelPackRuntimeProfile(
          availableMemoryMB: 4096,
          maximumInferenceMilliseconds: 200
        )
      )
    ) { error in
      XCTAssertEqual(error as? AIModelPackLoaderError, .notRegistered)
    }
  }

  func testLoaderRejectsChecksumMismatchForLocalPack() throws {
    let payload = Data("photosuite-corrupt-model".utf8)
    let resourceURL = try temporaryResource(payload)
    defer { try? FileManager.default.removeItem(at: resourceURL) }
    let manifest = try makeManifest(
      resourceURL: resourceURL,
      sha256: String(repeating: "c", count: 64),
      minimumMemoryMB: 1024,
      expectedInferenceMilliseconds: 80
    )
    let registry = try LocalAIModelPackRegistry(manifests: [manifest])

    XCTAssertThrowsError(
      try registry.load(
        modelID: manifest.modelID,
        runtime: try AIModelPackRuntimeProfile(
          availableMemoryMB: 4096,
          maximumInferenceMilliseconds: 200
        )
      )
    ) { error in
      guard case .checksumMismatch(let expected, let actual) = error as? AIModelPackLoaderError
      else {
        return XCTFail("Expected checksum mismatch, got \(error)")
      }
      XCTAssertEqual(expected, manifest.sha256)
      XCTAssertEqual(actual, digest(payload))
    }
  }

  private func makeManifest(
    resourceURL: URL,
    sha256: String,
    minimumMemoryMB: Int,
    expectedInferenceMilliseconds: Int
  ) throws -> AIModelPackManifest {
    try AIModelPackManifest(
      modelID: "photosuite.test.subject",
      version: "1.0.0",
      kind: .subject,
      license: .apache2,
      provenanceURL: URL(string: "https://example.com/photosuite/model-card")!,
      resourceURL: resourceURL,
      sha256: sha256,
      requirements: try AIModelPackRequirements(
        minimumMemoryMB: minimumMemoryMB,
        expectedInferenceMilliseconds: expectedInferenceMilliseconds
      )
    )
  }

  private func temporaryResource(_ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuiteAIModelPackTests", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let resourceURL = directory.appendingPathComponent(UUID().uuidString + ".mlmodelc")
    try data.write(to: resourceURL, options: .atomic)
    return resourceURL
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
