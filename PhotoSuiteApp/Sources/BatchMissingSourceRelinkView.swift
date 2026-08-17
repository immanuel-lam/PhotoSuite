// SPDX-License-Identifier: MPL-2.0

import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

extension ModernUIAccessibility {
  static let batchMissingSourceRelinkToolbar = "batch-missing-source-relink-toolbar"
  static let batchMissingSourceRelink = "batch-missing-source-relink"
  static let batchMissingSourceRelinkChoose = "batch-missing-source-relink-choose"
  static let batchMissingSourceRelinkCancel = "batch-missing-source-relink-cancel"
  static let batchMissingSourceRelinkSummary = "batch-missing-source-relink-summary"
  static let batchMissingSourceRelinkError = "batch-missing-source-relink-error"
}

/// Native folder recovery for multiple missing Library sources.
///
/// The view owns presentation state only. The supplied handler performs the security
/// scoped scan and catalog transactions in `PhotoWorkspace`.
@MainActor
struct BatchMissingSourceRelinkView: View {
  typealias RelinkHandler = @MainActor (URL) async throws -> BatchRelinkResult
  typealias CancelHandler = @MainActor () -> Void

  @Environment(\.dismiss) private var dismiss
  let missingAssetCount: Int
  let onRelink: RelinkHandler
  let onCancel: CancelHandler

  @State private var isChoosingFolder = false
  @State private var isRelinking = false
  @State private var result: BatchRelinkResult?
  @State private var errorMessage: String?

  init(
    missingAssetCount: Int,
    onRelink: @escaping RelinkHandler,
    onCancel: @escaping CancelHandler = {}
  ) {
    self.missingAssetCount = missingAssetCount
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
    .frame(minWidth: 520, idealWidth: 580, minHeight: 390, idealHeight: 460)
    .background(Color(nsColor: .windowBackgroundColor))
    .fileImporter(
      isPresented: $isChoosingFolder,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { importResult in
      guard case .success(let urls) = importResult, let folderURL = urls.first else { return }
      relink(folderURL)
    }
    .accessibilityIdentifier(ModernUIAccessibility.batchMissingSourceRelink)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 3) {
        Text("Relink Missing Sources")
          .font(.title2.weight(.semibold))
        Text("Restore paths for \(missingAssetCount) missing \(missingAssetNoun)")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      Image(systemName: "folder.badge.questionmark")
        .foregroundStyle(.orange)
        .accessibilityLabel("Missing source recovery")
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 18)
  }

  @ViewBuilder
  private var details: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(
        "Choose the folder that contains your original files.",
        systemImage: "checkmark.shield"
      )
      .font(.headline)

      Text(
        "PhotoSuite scans nested folders and compares SHA-256 fingerprints before it changes the catalog. A filename is used only to choose between files with the same fingerprint."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let result {
        resultSummary(result)
      } else {
        ContentUnavailableView(
          "No Folder Selected",
          systemImage: "folder",
          description: Text("Your original files are never moved or overwritten.")
        )
        .frame(maxWidth: .infinity, minHeight: 150)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func resultSummary(_ result: BatchRelinkResult) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Scan complete")
        .font(.headline)
      HStack(spacing: 8) {
        summaryPill("Relinked", value: result.matched.count, tint: .green)
        summaryPill("Not found", value: result.unmatched.count, tint: .orange)
        summaryPill("Failed", value: result.failures.count, tint: .red)
      }
      Text("Scanned \(result.scannedFileCount) files in \(result.folderURL.lastPathComponent).")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
    }
    .accessibilityIdentifier(ModernUIAccessibility.batchMissingSourceRelinkSummary)
  }

  private func summaryPill(_ title: String, value: Int, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value, format: .number)
        .font(.headline.monospacedDigit())
        .foregroundStyle(tint)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var missingAssetNoun: String {
    missingAssetCount == 1 ? "photograph" : "photographs"
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
    .accessibilityIdentifier(ModernUIAccessibility.batchMissingSourceRelinkError)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      if isRelinking {
        ProgressView()
          .controlSize(.small)
        Text("Checking sources…")
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
      .accessibilityIdentifier(ModernUIAccessibility.batchMissingSourceRelinkCancel)

      Button {
        isChoosingFolder = true
      } label: {
        Label(result == nil ? "Choose Folder…" : "Scan Another Folder…", systemImage: "folder")
      }
      .modifier(GlassButtonWhenAvailable(prominent: true))
      .keyboardShortcut(.defaultAction)
      .disabled(isRelinking || missingAssetCount == 0)
      .accessibilityIdentifier(ModernUIAccessibility.batchMissingSourceRelinkChoose)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .modifier(NavigationGlassSurface(cornerRadius: 16))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private func relink(_ folderURL: URL) {
    isRelinking = true
    errorMessage = nil
    Task { @MainActor in
      do {
        result = try await onRelink(folderURL)
        isRelinking = false
      } catch {
        isRelinking = false
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }
}
