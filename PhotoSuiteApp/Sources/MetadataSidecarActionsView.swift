// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

public enum MetadataSidecarAccessibility {
  public static let view = "metadata-sidecar-actions"
  public static let importButton = "metadata-sidecar-import"
  public static let exportButton = "metadata-sidecar-export"
  public static let status = "metadata-sidecar-status"
}

/// Native XMP sidecar actions for the Library metadata inspector.
///
/// The view deliberately describes sidecar interchange only. It does not imply embedded XMP,
/// complete IPTC/EXIF coverage, or Lightroom catalog compatibility.
@MainActor
public struct MetadataSidecarActionsView: View {
  public typealias ImportHandler = @MainActor (URL) -> Void
  public typealias ExportHandler = @MainActor () -> Void

  public let status: MetadataSidecarStatus
  public let onExport: ExportHandler
  public let onImport: ImportHandler

  @State private var isImporting = false

  public init(
    status: MetadataSidecarStatus,
    onExport: @escaping ExportHandler,
    onImport: @escaping ImportHandler
  ) {
    self.status = status
    self.onExport = onExport
    self.onImport = onImport
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Label("XMP sidecar", systemImage: "doc.text.magnifyingglass")
          .font(.caption.weight(.medium))
        Spacer()
        GlassControlGroup {
          HStack(spacing: 6) {
            Button("Import…") {
              isImporting = true
            }
            .modifier(GlassButtonWhenAvailable())
            .controlSize(.small)
            .disabled(isBusy)
            .accessibilityIdentifier(MetadataSidecarAccessibility.importButton)

            Button("Write XMP") {
              onExport()
            }
            .modifier(GlassButtonWhenAvailable(prominent: true))
            .controlSize(.small)
            .disabled(isBusy)
            .accessibilityIdentifier(MetadataSidecarAccessibility.exportButton)
          }
        }
      }

      HStack(spacing: 6) {
        if isBusy { ProgressView().controlSize(.small) }
        Text(status.message)
          .font(.caption2)
          .foregroundStyle(statusColor)
          .lineLimit(2)
      }
      .accessibilityIdentifier(MetadataSidecarAccessibility.status)
    }
    .padding(.top, 8)
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: Self.importTypes,
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      onImport(url)
    }
    .accessibilityIdentifier(MetadataSidecarAccessibility.view)
  }

  private var isBusy: Bool {
    switch status {
    case .exporting, .importing: true
    default: false
    }
  }

  private var statusColor: Color {
    switch status {
    case .failed: .orange
    case .exported, .imported: .green
    default: .secondary
    }
  }

  private static var importTypes: [UTType] {
    var types = [UTType(filenameExtension: "xmp")].compactMap { $0 }
    if !types.contains(.xml) { types.append(.xml) }
    return types
  }
}
