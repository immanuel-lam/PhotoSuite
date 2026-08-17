// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PhotoDomain

/// A value-only review of media discovered on a camera or in an import source.
///
/// The review does not copy files, update the catalog, or start a security scope. It is a
/// deliberately small boundary between capture discovery and the import operation. The caller
/// owns the side effect and receives the selected `CaptureMediaItem` values from
/// `selectedMediaItems`.
public struct LibraryImportReview: Codable, Hashable, Sendable, Identifiable {
  public enum ItemState: String, Codable, Hashable, Sendable {
    case ready
    case duplicate
    case unavailable
  }

  public struct Item: Codable, Hashable, Sendable, Identifiable {
    public let media: CaptureMediaItem
    public let existingAsset: PhotoAsset?
    public let state: ItemState
    public var isSelected: Bool

    public var id: String { media.id }

    public var canImport: Bool {
      state == .ready
    }

    public init(
      media: CaptureMediaItem,
      state: ItemState = .ready,
      existingAsset: PhotoAsset? = nil,
      isSelected: Bool = true
    ) {
      self.media = media
      self.existingAsset = existingAsset
      self.state = state
      self.isSelected = state == .ready && isSelected
    }
  }

  public let id: UUID
  public let deviceID: CaptureDeviceID
  public private(set) var items: [Item]

  public init(
    id: UUID = UUID(),
    deviceID: CaptureDeviceID,
    items: [Item]
  ) {
    self.id = id
    self.deviceID = deviceID

    var seenIDs = Set<String>()
    self.items = items.filter { item in
      seenIDs.insert(item.id).inserted
    }
  }

  /// Creates a review from discovered camera media and marks source URLs already present in the
  /// catalog as duplicates. A duplicate stays visible for user confidence, but it cannot be
  /// selected for import.
  public init(
    id: UUID = UUID(),
    deviceID: CaptureDeviceID,
    mediaItems: [CaptureMediaItem],
    existingAssets: [PhotoAsset] = []
  ) {
    let assetsByURL = Dictionary(
      existingAssets.compactMap { asset -> (URL, PhotoAsset)? in
        guard asset.sourceURL.isFileURL else { return nil }
        return (asset.sourceURL.standardizedFileURL, asset)
      },
      uniquingKeysWith: { first, _ in first }
    )
    let items = mediaItems.map { media in
      guard let fileURL = media.fileURL?.standardizedFileURL,
        let existingAsset = assetsByURL[fileURL]
      else {
        return Item(media: media)
      }
      return Item(
        media: media,
        state: .duplicate,
        existingAsset: existingAsset,
        isSelected: false
      )
    }
    self.init(id: id, deviceID: deviceID, items: items)
  }

  /// Creates a review from catalog assets. This is useful for a camera UI that receives a
  /// completed import result and needs to show which items are now represented in the Library.
  public init(
    id: UUID = UUID(),
    deviceID: CaptureDeviceID,
    assets: [PhotoAsset]
  ) {
    let mediaItems = assets.map { asset in
      CaptureMediaItem(
        id: "asset:\(asset.id.uuidString)",
        deviceID: deviceID,
        filename: asset.filename,
        typeIdentifier: asset.typeIdentifier,
        fileURL: asset.sourceURL,
        isRaw: Self.isRaw(asset.filename),
        creationDate: asset.captureDate
      )
    }
    let items = zip(mediaItems, assets).map { media, asset in
      Item(media: media, state: .duplicate, existingAsset: asset, isSelected: false)
    }
    self.init(id: id, deviceID: deviceID, items: items)
  }

  public var selectionCount: Int {
    items.reduce(into: 0) { count, item in
      if item.isSelected && item.canImport { count += 1 }
    }
  }

  public var selectableItemCount: Int {
    items.reduce(into: 0) { count, item in
      if item.canImport { count += 1 }
    }
  }

  public var allSelectableItemsSelected: Bool {
    selectableItemCount > 0 && selectionCount == selectableItemCount
  }

  public var selectedItems: [Item] {
    items.filter { $0.isSelected && $0.canImport }
  }

  public var selectedMediaItems: [CaptureMediaItem] {
    selectedItems.map(\.media)
  }

  public var isEmpty: Bool {
    items.isEmpty
  }

  public func item(withID id: String) -> Item? {
    items.first { $0.id == id }
  }

  public mutating func toggleSelection(for id: String) {
    guard let index = items.firstIndex(where: { $0.id == id }), items[index].canImport else {
      return
    }
    items[index].isSelected.toggle()
  }

  public mutating func setSelection(_ selected: Bool, for id: String) {
    guard let index = items.firstIndex(where: { $0.id == id }), items[index].canImport else {
      return
    }
    items[index].isSelected = selected
  }

  public mutating func selectAll() {
    items = items.map { item in
      guard item.canImport else { return item }
      var selected = item
      selected.isSelected = true
      return selected
    }
  }

  public mutating func deselectAll() {
    items = items.map { item in
      guard item.isSelected else { return item }
      var deselected = item
      deselected.isSelected = false
      return deselected
    }
  }

  public mutating func removeItem(withID id: String) {
    items.removeAll { $0.id == id }
  }

  private static func isRaw(_ filename: String) -> Bool {
    ["arw", "cr2", "cr3", "dng", "raf", "rw2", "nef", "orf", "raw"]
      .contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case deviceID
    case items
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      deviceID: container.decode(CaptureDeviceID.self, forKey: .deviceID),
      items: container.decode([Item].self, forKey: .items)
    )
  }
}
