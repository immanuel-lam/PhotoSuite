// SPDX-License-Identifier: MPL-2.0

import Foundation
import PhotoDomain
import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

extension ModernUIAccessibility {
  static let missingSourceRelink = "missing-source-relink"
  static let missingSourceRelinkChoose = "missing-source-relink-choose"
  static let missingSourceRelinkCancel = "missing-source-relink-cancel"
  static let missingSourceRelinkError = "missing-source-relink-error"
}

/// Native single-file recovery for a Library asset whose original source is unavailable.
///
/// The view does not change catalog state directly. The handler performs fingerprint
/// validation and durable relinking in `PhotoWorkspace`.
@MainActor
struct MissingSourceRelinkView: View {
  typealias RelinkHandler = @MainActor (URL) async throws -> Void
  typealias CancelHandler = @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  let asset: PhotoAsset
  let onRelink: RelinkHandler
  let onCancel: CancelHandler

  @State private var isChoosingReplacement = false
  @State private var isRelinking = false
  @State private var errorMessage: String?

  init(
    asset: PhotoAsset,
    onRelink: @escaping RelinkHandler,
    onCancel: @escaping CancelHandler = {}
  ) {
    self.asset = asset
    self.onRelink = onRelink
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      details
      if let errorMessage {
        errorBanner(errorMessage)
      }
      Divider()
      footer
    }
    .frame(minWidth: 500, idealWidth: 560, minHeight: 360, idealHeight: 420)
    .background(Color(nsColor: .windowBackgroundColor))
    .fileImporter(
      isPresented: $isChoosingReplacement,
      allowedContentTypes: [.item],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      relink(url)
    }
    .accessibilityIdentifier(ModernUIAccessibility.missingSourceRelink)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 3) {
        Text("Relink Missing Source")
          .font(.title2.weight(.semibold))
        Text(asset.filename)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 12)
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .accessibilityLabel("Source file missing")
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 18)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(
        "Choose an unchanged copy of this photograph.",
        systemImage: "checkmark.shield"
      )
      .font(.headline)

      Text(
        "PhotoSuite compares the file fingerprint before it updates the catalog. Your edit recipe and original file are not changed."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 5) {
        Text("Last known location")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(asset.sourceURL.path)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "xmark.octagon.fill")
        .foregroundStyle(.red)
      Text(message)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.red.opacity(0.22), lineWidth: 0.5)
    }
    .padding(.horizontal, 22)
    .padding(.bottom, 12)
    .accessibilityIdentifier(ModernUIAccessibility.missingSourceRelinkError)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      if isRelinking {
        ProgressView()
          .controlSize(.small)
        Text("Checking source…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      Button("Cancel") {
        onCancel()
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
      .disabled(isRelinking)
      .accessibilityIdentifier(ModernUIAccessibility.missingSourceRelinkCancel)

      Button {
        isChoosingReplacement = true
      } label: {
        Label("Choose Replacement…", systemImage: "folder")
      }
      .modifier(GlassButtonWhenAvailable(prominent: true))
      .keyboardShortcut(.defaultAction)
      .disabled(isRelinking)
      .accessibilityIdentifier(ModernUIAccessibility.missingSourceRelinkChoose)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .modifier(NavigationGlassSurface(cornerRadius: 16))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private func relink(_ url: URL) {
    isRelinking = true
    errorMessage = nil
    Task { @MainActor in
      do {
        try await onRelink(url)
        dismiss()
      } catch {
        isRelinking = false
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }
}
