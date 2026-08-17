// SPDX-License-Identifier: MPL-2.0

import CatalogCore
import Foundation
import PhotoDomain
import XCTest

@testable import PhotoWorkflow

final class CapturePipelineTests: XCTestCase {
  func testCaptureFixturesUseUniqueTemporaryRoots() throws {
    let first = try CaptureFixture()
    defer { first.remove() }
    let second = try CaptureFixture()
    defer { second.remove() }

    XCTAssertNotEqual(first.root, second.root)
  }

  func testWatchedFolderImportsStableFileAndPersistsRecipe() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("capture.jpg")
    try Data("capture-data".utf8).write(to: sourceURL)

    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let access = CaptureAccessFake()
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.folder,
        allowedExtensions: ["jpg"],
        settleInterval: 0
      ),
      catalog: catalog,
      sourceAccess: access.operations,
      fingerprint: { url in try SourceFingerprinter.fingerprint(url: url) },
      probe: { url in
        SourceProbe(
          dimensions: PixelDimensions(width: 32, height: 24)!,
          pins: EnginePins(
            decoderIdentifier: "test.decoder",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: url.pathExtension == "jpg" ? "public.jpeg" : nil
        )
      },
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let result = try await service.scanOnce()

    XCTAssertEqual(result.imported.map(\.filename), ["capture.jpg"])
    XCTAssertTrue(result.duplicates.isEmpty)
    XCTAssertTrue(result.failures.isEmpty)
    let activeCount = access.activeCount()
    let startedURLs = access.startedURLs()
    let stoppedURLs = access.stoppedURLs()
    XCTAssertEqual(activeCount, 0)
    XCTAssertEqual(startedURLs, [fixture.folder])
    XCTAssertEqual(stoppedURLs, [fixture.folder])

    let stored = try await catalog.listAssets(CatalogAssetListRequest()).assets
    XCTAssertEqual(stored.count, 1)
    XCTAssertEqual(stored[0].fingerprint.sha256, result.imported[0].fingerprint.sha256)
    XCTAssertEqual(stored[0].fingerprint.byteCount, result.imported[0].fingerprint.byteCount)
    let storedRecipe = try await catalog.latestRecipe(
      CatalogLatestRecipeRequest(assetID: stored[0].id)
    ).recipe
    XCTAssertEqual(storedRecipe?.pins.decoderIdentifier, "test.decoder")
  }

  func testWatchedFolderUsesFingerprintForDuplicateHandling() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("duplicate.CR2")
    try Data(repeating: 7, count: 128).write(to: sourceURL)
    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.folder,
        allowedExtensions: ["cr2"],
        settleInterval: 0
      ),
      catalog: catalog,
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 8, height: 8)!,
          pins: EnginePins(
            decoderIdentifier: "test.raw",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.camera-raw-image"
        )
      },
      now: { Date(timeIntervalSince1970: 1_700_000_001) }
    )

    let first = try await service.scanOnce()
    let second = try await service.scanOnce()

    XCTAssertEqual(first.imported.count, 1)
    XCTAssertEqual(second.imported.count, 0)
    XCTAssertEqual(second.duplicates.map(\.lastPathComponent), ["duplicate.CR2"])
    let assets = try await catalog.listAssets(CatalogAssetListRequest()).assets
    XCTAssertEqual(assets.count, 1)
  }

  func testWatchedFolderLeavesChangingFilePendingUntilItSettles() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("partial.jpg")
    try Data(repeating: 1, count: 4).write(to: sourceURL)
    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let clock = CaptureClock(Date(timeIntervalSince1970: 100))
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.folder,
        allowedExtensions: ["jpg"],
        settleInterval: 5
      ),
      catalog: catalog,
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 2, height: 2)!,
          pins: EnginePins(
            decoderIdentifier: "test.decoder",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.jpeg"
        )
      },
      now: { clock.value }
    )

    let first = try await service.scanOnce()
    XCTAssertEqual(first.imported.count, 0)
    XCTAssertEqual(first.pending.map(\.lastPathComponent), ["partial.jpg"])

    clock.value = Date(timeIntervalSince1970: 106)
    let second = try await service.scanOnce()
    XCTAssertEqual(second.imported.count, 1)
    XCTAssertTrue(second.pending.isEmpty)
  }

  func testWatchedFolderStopsSecurityScopeWhenCancelledDuringFingerprinting() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("cancel.jpg")
    try Data(repeating: 3, count: 16).write(to: sourceURL)
    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let access = CaptureAccessFake()
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.folder,
        allowedExtensions: ["jpg"],
        settleInterval: 0
      ),
      catalog: catalog,
      sourceAccess: access.operations,
      fingerprint: { _ in
        try await Task.sleep(for: .seconds(30))
        return SourceFingerprint(
          sha256: String(repeating: "a", count: 64), byteCount: 16, modificationDate: nil)!
      },
      probe: { _ in
        XCTFail("Probe must not run after cancellation")
        throw CancellationError()
      }
    )

    let task = Task { try await service.scanOnce() }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("The cancelled scan must throw CancellationError.")
    } catch is CancellationError {
      // Expected.
    }
    let activeCount = access.activeCount()
    let stoppedURLs = access.stoppedURLs()
    XCTAssertEqual(activeCount, 0)
    XCTAssertEqual(stoppedURLs, [fixture.folder])
  }

  func testWatchedFolderRenewsAStaleSecurityScopedBookmarkForTheCaller() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("renewed.jpg")
    try Data(repeating: 4, count: 16).write(to: sourceURL)
    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let resolvedFolder = fixture.folder
    let renewedData = Data([1, 2, 3])
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.root.appendingPathComponent("stale-placeholder"),
        bookmarkData: Data([9]),
        allowedExtensions: ["jpg"],
        settleInterval: 0
      ),
      catalog: catalog,
      bookmarkOperations: CaptureBookmarkOperations(
        resolve: { _ in
          return ResolvedSecurityScopedBookmark(
            url: resolvedFolder,
            isStale: true,
            renewedData: renewedData
          )
        }
      ),
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 2, height: 2)!,
          pins: EnginePins(
            decoderIdentifier: "test.decoder",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.jpeg"
        )
      }
    )

    let result = try await service.scanOnce()

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.renewedBookmarkData, renewedData)
    let storedBookmarkData = await service.renewedBookmarkData()
    XCTAssertEqual(storedBookmarkData, renewedData)
  }

  func testWatchedFolderWatchLoopRecoversAfterTransientDirectoryFailure() async throws {
    let fixture = try CaptureFixture()
    defer { fixture.remove() }
    let sourceURL = fixture.folder.appendingPathComponent("recovery.jpg")
    try Data(repeating: 9, count: 16).write(to: sourceURL)
    let catalog = try SQLiteCatalogStore(
      catalogURL: fixture.root.appendingPathComponent("PhotoSuite.sqlite"))
    let operations = RecoveringFolderOperations(folder: fixture.folder)
    let service = WatchedFolderCaptureService(
      configuration: CaptureFolderConfiguration(
        folderURL: fixture.folder,
        allowedExtensions: ["jpg"],
        settleInterval: 0,
        pollInterval: 0.01
      ),
      catalog: catalog,
      fileOperations: operations.operations,
      probe: { _ in
        SourceProbe(
          dimensions: PixelDimensions(width: 2, height: 2)!,
          pins: EnginePins(
            decoderIdentifier: "test.decoder",
            decoderVersion: "test-v1",
            renderSchemaVersion: 1,
            cameraProfileVersion: nil,
            modelVersions: [:]
          ),
          typeIdentifier: "public.jpeg"
        )
      }
    )

    await service.start()
    try await Task.sleep(for: .milliseconds(100))
    await service.stop()

    let lastError = await service.lastScanErrorMessage()
    let assets = try await catalog.listAssets(CatalogAssetListRequest()).assets
    let listCount = operations.listCount()
    XCTAssertNil(lastError)
    XCTAssertEqual(assets.count, 1)
    XCTAssertGreaterThanOrEqual(listCount, 2)
  }

  @MainActor
  func testCameraDiscoveryCanBeDrivenByAProtocolFakeWithoutPhysicalHardware() throws {
    let status = CaptureDeviceStatus(
      id: CaptureDeviceID(rawValue: "camera-1"),
      name: "Test Camera",
      productKind: "Camera",
      transportType: "USB",
      locationDescription: "USB",
      serialNumber: "TEST-1",
      state: .ready,
      hasOpenSession: true,
      supportsTetheredCapture: true,
      batteryLevel: 88,
      mediaFileCount: 3
    )
    let discovery = FakeCameraDiscovery(devices: [status])

    discovery.start()
    try discovery.requestCapture(deviceID: status.id)

    XCTAssertEqual(discovery.devices, [status])
    XCTAssertEqual(discovery.captureRequests, [status.id])
  }
}

private final class CaptureFixture {
  let root: URL
  let folder: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("PhotoSuite-Capture-\(UUID().uuidString)", isDirectory: true)
    folder = root.appendingPathComponent("Watched", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}

private final class CaptureAccessFake: @unchecked Sendable {
  private let lock = NSLock()
  private var active = 0
  private var started: [URL] = []
  private var stopped: [URL] = []

  var operations: CaptureSourceAccess {
    CaptureSourceAccess(
      persist: { _, _ in },
      start: { [self] url in
        lock.lock()
        active += 1
        started.append(url)
        lock.unlock()
        return true
      },
      stop: { [self] url in
        lock.lock()
        active -= 1
        stopped.append(url)
        lock.unlock()
      }
    )
  }

  func activeCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return active
  }

  func startedURLs() -> [URL] {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  func stoppedURLs() -> [URL] {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
}

private final class CaptureClock: @unchecked Sendable {
  var value: Date

  init(_ value: Date) {
    self.value = value
  }
}

private final class RecoveringFolderOperations: @unchecked Sendable {
  private let folder: URL
  private let lock = NSLock()
  private var calls = 0

  init(folder: URL) {
    self.folder = folder
  }

  var operations: CaptureFolderFileOperations {
    CaptureFolderFileOperations(
      listFiles: { [self] _ in
        lock.lock()
        calls += 1
        let currentCall = calls
        lock.unlock()
        if currentCall == 1 {
          throw TestCaptureError.transientDirectoryFailure
        }
        return try FileManager.default.contentsOfDirectory(
          at: folder,
          includingPropertiesForKeys: [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey,
            .contentModificationDateKey,
          ],
          options: []
        )
      }
    )
  }

  func listCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }
}

@MainActor
private final class FakeCameraDiscovery: CameraDeviceDiscovery {
  private(set) var devices: [CaptureDeviceStatus]
  private(set) var captureRequests: [CaptureDeviceID] = []

  init(devices: [CaptureDeviceStatus]) {
    self.devices = devices
  }

  func start() {}
  func stop() {}
  func requestCapture(deviceID: CaptureDeviceID) throws {
    guard devices.contains(where: { $0.id == deviceID }) else {
      throw CaptureDeviceError.deviceNotFound(deviceID)
    }
    captureRequests.append(deviceID)
  }

  func makeEventStream() -> AsyncStream<CaptureDeviceChange> {
    AsyncStream { continuation in continuation.finish() }
  }
}

private enum TestCaptureError: Error {
  case transientDirectoryFailure
}
