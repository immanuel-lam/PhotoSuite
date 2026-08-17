// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

#if canImport(ImageCaptureCore)
  @preconcurrency import ImageCaptureCore

  /// FOSS camera discovery through Apple's ImageCaptureCore framework.
  ///
  /// This adapter exposes device discovery, status, media-added notifications, and the standard
  /// tethered `requestTakePicture` command. Vendor-specific Canon, Nikon, Sony, Fujifilm, and Leica
  /// SDKs are intentionally not linked into PhotoSuite; those adapters can implement the same
  /// `CameraDeviceDiscovery` contract in a separately signed XPC process.
  @MainActor
  public final class ImageCaptureCoreCameraDiscovery: NSObject, CameraDeviceDiscovery,
    @preconcurrency ICDeviceBrowserDelegate, @preconcurrency ICDeviceDelegate
  {
    private let browser: ICDeviceBrowser
    private var cameras: [CaptureDeviceID: ICCameraDevice] = [:]
    private var statuses: [CaptureDeviceID: CaptureDeviceStatus] = [:]
    private var continuations: [UUID: AsyncStream<CaptureDeviceChange>.Continuation] = [:]

    public init(browser: ICDeviceBrowser = ICDeviceBrowser()) {
      self.browser = browser
      super.init()
      self.browser.delegate = self
      // Camera devices plus local and remote locations. ImageCaptureCore uses a bit mask despite
      // the historical NS_ENUM declaration.
      self.browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: 0x0000_FF01)!
    }

    public var devices: [CaptureDeviceStatus] {
      statuses.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func start() {
      browser.delegate = self
      browser.start()
    }

    public func stop() {
      browser.stop()
      cameras.removeAll()
      statuses.removeAll()
      finishStreams()
    }

    public func requestCapture(deviceID: CaptureDeviceID) throws {
      guard let camera = cameras[deviceID], let current = statuses[deviceID] else {
        throw CaptureDeviceError.deviceNotFound(deviceID)
      }
      guard current.supportsTetheredCapture else {
        throw CaptureDeviceError.captureUnavailable(deviceID)
      }

      let capturing = status(for: camera, state: .capturing)
      statuses[deviceID] = capturing
      emit(.updated(capturing))
      camera.requestTakePicture()
    }

    public func makeEventStream() -> AsyncStream<CaptureDeviceChange> {
      let streamID = UUID()
      return AsyncStream { continuation in
        continuations[streamID] = continuation
        continuation.onTermination = { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.continuations.removeValue(forKey: streamID)
          }
        }
      }
    }

    // MARK: ICDeviceBrowserDelegate

    public func deviceBrowser(
      _ browser: ICDeviceBrowser,
      didAdd device: ICDevice,
      moreComing: Bool
    ) {
      guard let camera = device as? ICCameraDevice else { return }
      let id = identifier(for: device)
      cameras[id] = camera
      camera.delegate = self
      let current = status(for: camera, state: .discovered)
      statuses[id] = current
      emit(.added(current))
    }

    public func deviceBrowser(
      _ browser: ICDeviceBrowser,
      didRemove device: ICDevice,
      moreGoing: Bool
    ) {
      let id = identifier(for: device)
      cameras.removeValue(forKey: id)
      statuses.removeValue(forKey: id)
      emit(.removed(id))
    }

    public func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {}

    // MARK: ICDeviceDelegate

    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
      update(device: device, state: error.map { .failed($0.localizedDescription) } ?? .ready)
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
      update(device: device, state: error.map { .failed($0.localizedDescription) } ?? .discovered)
    }

    public func didRemove(_ device: ICDevice) {
      deviceBrowser(browser, didRemove: device, moreGoing: false)
    }

    public func deviceDidBecomeReady(_ device: ICDevice) {
      update(device: device, state: .ready)
    }

    public func device(
      _ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]
    ) {
      _ = status
      update(device: device, state: .ready)
    }

    public func device(_ device: ICDevice, didEncounterError error: Error?) {
      update(device: device, state: .failed(error?.localizedDescription ?? "Unknown camera error."))
    }

    public func device(_ device: ICDevice, didEjectWithError error: Error?) {
      update(device: device, state: error.map { .failed($0.localizedDescription) } ?? .discovered)
    }

    // MARK: ICCameraDevice delegate selectors

    /// The object is intentionally declared as `ICDeviceDelegate` above. ImageCaptureCore also
    /// sends these optional camera selectors when the delegate implements them, without requiring
    /// a vendor SDK or a hard dependency on the full `ICCameraDeviceDelegate` protocol.
    @objc(cameraDevice:didAddItems:)
    public func cameraDevice(_ camera: ICCameraDevice, didAddItems items: [ICCameraItem]) {
      let id = identifier(for: camera)
      let mediaItems = items.compactMap { item -> CaptureMediaItem? in
        guard let name = item.name else { return nil }
        let itemID = "\(id.rawValue):\(item.ptpObjectHandle):\(name)"
        let fileURL = item.fileSystemPath.map { URL(fileURLWithPath: $0) }
        return CaptureMediaItem(
          id: itemID,
          deviceID: id,
          filename: name,
          typeIdentifier: item.uti,
          fileURL: fileURL,
          isRaw: item.isRaw,
          creationDate: item.creationDate as Date?
        )
      }
      guard !mediaItems.isEmpty else { return }
      emit(.mediaAdded(deviceID: id, items: mediaItems))
      update(device: camera, state: .ready)
    }

    @objc(cameraDevice:didRemoveItems:)
    public func cameraDevice(_ camera: ICCameraDevice, didRemoveItems items: [ICCameraItem]) {
      _ = items
      update(device: camera, state: .ready)
    }

    @objc(cameraDeviceDidChangeCapability:)
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
      update(device: camera, state: camera.hasOpenSession ? .ready : .discovered)
    }

    @objc(deviceDidBecomeReadyWithCompleteContentCatalog:)
    public func deviceDidBecomeReadyWithCompleteContentCatalog(_ device: ICCameraDevice) {
      update(device: device, state: .ready)
    }

    // MARK: Private

    private func identifier(for device: ICDevice) -> CaptureDeviceID {
      if let uuid = device.uuidString, !uuid.isEmpty {
        return CaptureDeviceID(rawValue: uuid)
      }
      if let serial = device.serialNumberString, !serial.isEmpty {
        return CaptureDeviceID(rawValue: serial)
      }
      return CaptureDeviceID(
        rawValue: "\(device.productKind ?? "camera"):\(device.name ?? "unknown")")
    }

    private func status(
      for camera: ICCameraDevice,
      state: CaptureDeviceState
    ) -> CaptureDeviceStatus {
      let deviceID = identifier(for: camera)
      let supportsTetheredCapture = camera.tetheredCaptureEnabled
      let battery = camera.batteryLevelAvailable ? Int(camera.batteryLevel) : nil
      return CaptureDeviceStatus(
        id: deviceID,
        name: camera.name ?? "Camera",
        productKind: camera.productKind,
        transportType: camera.transportType,
        locationDescription: camera.locationDescription,
        serialNumber: camera.serialNumberString,
        state: state,
        hasOpenSession: camera.hasOpenSession,
        supportsTetheredCapture: supportsTetheredCapture,
        batteryLevel: battery,
        mediaFileCount: camera.mediaFiles?.count
      )
    }

    private func update(device: ICDevice, state: CaptureDeviceState) {
      guard let camera = device as? ICCameraDevice else { return }
      let id = identifier(for: camera)
      guard cameras[id] != nil else { return }
      let updated = status(for: camera, state: state)
      statuses[id] = updated
      emit(.updated(updated))
    }

    private func emit(_ change: CaptureDeviceChange) {
      for continuation in continuations.values {
        continuation.yield(change)
      }
    }

    private func finishStreams() {
      for continuation in continuations.values {
        continuation.finish()
      }
      continuations.removeAll()
    }
  }
#endif
