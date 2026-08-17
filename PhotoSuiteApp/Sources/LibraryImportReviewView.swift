// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoWorkflow
import SwiftUI

/// Stable identifiers for automation and VoiceOver-oriented UI tests.
public enum LibraryImportReviewAccessibility {
  public static let view = "library-import-review"
  public static let selectAll = "library-import-review-select-all"
  public static let importButton = "library-import-review-import"
  public static let cancelButton = "library-import-review-cancel"
  public static let summary = "library-import-review-summary"
  public static let modePicker = "library-import-review-mode"
  public static let destinationButton = "library-import-review-destination"

  public static func item(_ id: String) -> String {
    "library-import-review-item-\(id)"
  }
}

/// The file-handling choice shown in the import review sheet.
public enum LibraryImportModeChoice: String, CaseIterable, Identifiable, Sendable {
  case add
  case copy
  case move

  public var id: Self { self }

  public var title: String {
    switch self {
    case .add: "Add in place"
    case .copy: "Copy to folder"
    case .move: "Move to folder"
    }
  }

  fileprivate func photoImportMode(destinationURL: URL?) -> PhotoImportMode? {
    switch self {
    case .add: .add
    case .copy: destinationURL.map(PhotoImportMode.copy(to:))
    case .move: destinationURL.map(PhotoImportMode.move(to:))
    }
  }
}

/// A native, side-effect-free import review sheet for camera media.
///
/// The view owns only the selection state. The caller performs the actual catalog import through
/// `onImport`, which keeps security-scoped access and persistence outside the presentation layer.
@MainActor
public struct LibraryImportReviewView: View {
  public typealias ImportHandler = @MainActor ([CaptureMediaItem]) -> Void
  public typealias ImportModeHandler = @MainActor ([CaptureMediaItem], PhotoImportMode) -> Void
  public typealias CancelHandler = @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var review: LibraryImportReview
  @State private var isSubmitting = false
  @State private var mode: LibraryImportModeChoice = .add
  @State private var destinationURL: URL?
  @State private var isChoosingDestination = false

  private let onImport: ImportHandler
  private let onImportWithMode: ImportModeHandler?
  private let onCancel: CancelHandler

  public init(
    review: LibraryImportReview,
    onImport: @escaping ImportHandler,
    onImportWithMode: ImportModeHandler? = nil,
    onCancel: @escaping CancelHandler = {}
  ) {
    _review = State(initialValue: review)
    self.onImport = onImport
    self.onImportWithMode = onImportWithMode
    self.onCancel = onCancel
  }

  public var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      reviewContent
      Divider()
      footer
    }
    .frame(minWidth: 640, idealWidth: 760, minHeight: 440, idealHeight: 560)
    .background(Color(nsColor: .windowBackgroundColor))
    .fileImporter(
      isPresented: $isChoosingDestination,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result else { return }
      destinationURL = urls.first?.standardizedFileURL
    }
    .accessibilityIdentifier(LibraryImportReviewAccessibility.view)
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "square.and.arrow.down")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 3) {
        Text("Review Import")
          .font(.title2.weight(.semibold))
        Text("\(review.items.count) items from \(review.deviceID.rawValue)")
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 12)

      if review.selectableItemCount > 0 {
        GlassControlGroup {
          Button {
            if review.allSelectableItemsSelected {
              review.deselectAll()
            } else {
              review.selectAll()
            }
          } label: {
            Label(
              review.allSelectableItemsSelected ? "Deselect All" : "Select All",
              systemImage: review.allSelectableItemsSelected
                ? "minus.circle" : "checkmark.circle"
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(LibraryImportReviewAccessibility.selectAll)
        }
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 18)
  }

  @ViewBuilder
  private var reviewContent: some View {
    if review.isEmpty {
      VStack(spacing: 10) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 34, weight: .light))
          .foregroundStyle(.secondary)
        Text("Nothing to Import")
          .font(.headline)
        Text("New photographs from the camera will appear here.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(34)
    } else {
      VStack(spacing: 0) {
        if onImportWithMode != nil {
          transferOptions
        }
        List {
          Section {
            ForEach(review.items) { item in
              LibraryImportReviewRow(item: item) {
                review.toggleSelection(for: item.id)
              }
            }
          } header: {
            Text("Photographs")
              .font(.caption.weight(.semibold))
              .textCase(nil)
          }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
      }
    }
  }

  private var transferOptions: some View {
    HStack(spacing: 12) {
      Label("Source handling", systemImage: "externaldrive")
        .font(.callout.weight(.medium))
      Picker("Source handling", selection: $mode) {
        ForEach(LibraryImportModeChoice.allCases) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier(LibraryImportReviewAccessibility.modePicker)

      if mode != .add {
        Button {
          isChoosingDestination = true
        } label: {
          Label(
            destinationURL?.lastPathComponent ?? "Choose destination…",
            systemImage: "folder"
          )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier(LibraryImportReviewAccessibility.destinationButton)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
  }

  private var footer: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(selectionSummary)
          .font(.callout.weight(.medium))
          .accessibilityIdentifier(LibraryImportReviewAccessibility.summary)
        if review.items.contains(where: { $0.state == .duplicate }) {
          Text("Existing photographs remain in the Library and are not selected.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 12)

      Button("Cancel") {
        onCancel()
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
      .accessibilityIdentifier(LibraryImportReviewAccessibility.cancelButton)

      Button {
        isSubmitting = true
        if let onImportWithMode,
          let photoImportMode = mode.photoImportMode(destinationURL: destinationURL)
        {
          onImportWithMode(review.selectedMediaItems, photoImportMode)
        } else {
          onImport(review.selectedMediaItems)
        }
        dismiss()
      } label: {
        Label("Import \(review.selectionCount)", systemImage: "square.and.arrow.down")
      }
      .modifier(GlassButtonWhenAvailable(prominent: true))
      .keyboardShortcut(.defaultAction)
      .disabled(
        review.selectionCount == 0
          || isSubmitting
          || (onImportWithMode != nil && mode != .add && destinationURL == nil)
      )
      .accessibilityIdentifier(LibraryImportReviewAccessibility.importButton)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .modifier(NavigationGlassSurface(cornerRadius: 16))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var selectionSummary: String {
    switch review.selectionCount {
    case 0: "No photographs selected"
    case 1: "1 photograph selected"
    default: "\(review.selectionCount) photographs selected"
    }
  }
}

@MainActor
private struct LibraryImportReviewRow: View {
  let item: LibraryImportReview.Item
  let onToggle: () -> Void

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: 12) {
        Image(systemName: selectionSymbol)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(selectionColor)
          .frame(width: 24)

        Image(systemName: item.media.isRaw ? "camera.aperture" : "photo")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 34, height: 34)
          .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 3) {
          Text(item.media.filename.isEmpty ? "Unnamed photograph" : item.media.filename)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)

          HStack(spacing: 8) {
            Text(item.media.isRaw ? "RAW" : "Image")
            if let creationDate = item.media.creationDate {
              Text(creationDate, style: .date)
            }
            if let typeIdentifier = item.media.typeIdentifier {
              Text(typeIdentifier)
                .lineLimit(1)
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }

        Spacer(minLength: 10)

        stateLabel
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(item.canImport ? 1 : 0.68)
    .disabled(!item.canImport)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(LibraryImportReviewAccessibility.item(item.id))
    .accessibilityLabel(item.media.filename.isEmpty ? "Unnamed photograph" : item.media.filename)
    .accessibilityValue(accessibilityValue)
  }

  @ViewBuilder
  private var stateLabel: some View {
    switch item.state {
    case .ready:
      EmptyView()
    case .duplicate:
      Text("Already in Library")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    case .unavailable:
      Text("Unavailable")
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.12), in: Capsule())
    }
  }

  private var selectionSymbol: String {
    if !item.canImport { return "minus.circle" }
    return item.isSelected ? "checkmark.circle.fill" : "circle"
  }

  private var selectionColor: Color {
    if !item.canImport { return .secondary }
    return item.isSelected ? .accentColor : .secondary
  }

  private var accessibilityValue: String {
    switch item.state {
    case .ready: item.isSelected ? "Selected for import" : "Not selected"
    case .duplicate: "Already in Library"
    case .unavailable: "Unavailable"
    }
  }
}
