// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

/// A compact catalog metadata editor for the Library sidebar.
///
/// The editor writes only the durable catalog record. It never writes to the source file. The
/// source fingerprint remains unchanged, which makes the distinction clear for photographers who
/// use sidecar or delivery workflows later.
@MainActor
struct MetadataEditorView: View {
  @Bindable var workspace: PhotoWorkspace
  let asset: PhotoAsset

  @State private var isExpanded = false
  @State private var title = ""
  @State private var creator = ""
  @State private var description = ""
  @State private var keywords = ""
  @State private var isSaving = false
  @State private var validationMessage: String?

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        TextField("Title", text: $title)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("metadata-title-field")

        TextField("Creator", text: $creator)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("metadata-creator-field")

        TextField("Keywords, separated by commas", text: $keywords)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("metadata-keywords-field")

        TextEditor(text: $description)
          .font(.callout)
          .frame(minHeight: 58, maxHeight: 92)
          .padding(4)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .accessibilityIdentifier("metadata-description-field")

        if let validationMessage {
          Label(validationMessage, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        HStack {
          Text("Catalog only")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Save") {
            Task { await save() }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(isSaving)
          .accessibilityIdentifier("metadata-save-button")
        }

        MetadataSidecarActionsView(
          status: workspace.metadataSidecarStatus,
          onExport: {
            Task { await workspace.exportSelectedMetadataSidecar() }
          },
          onImport: { url in
            Task { await workspace.importSelectedMetadataSidecar(from: url) }
          }
        )
      }
      .padding(.top, 8)
    } label: {
      Label("Metadata", systemImage: "info.circle")
        .font(.callout.weight(.medium))
    }
    .accessibilityIdentifier("metadata-editor")
    .task(id: asset.id) {
      load(asset.metadata)
    }
    .onChange(of: asset.metadata) { _, metadata in
      load(metadata)
    }
  }

  private func load(_ metadata: PhotoMetadata) {
    title = metadata.title ?? ""
    creator = metadata.creator ?? ""
    description = metadata.description ?? ""
    keywords = metadata.keywords.joined(separator: ", ")
    validationMessage = nil
  }

  private func save() async {
    validationMessage = nil
    let parsedKeywords =
      keywords
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard
      let metadata = PhotoMetadata(
        title: title,
        description: description,
        creator: creator,
        keywords: parsedKeywords
      )
    else {
      validationMessage = "The metadata values are not valid."
      return
    }
    isSaving = true
    await workspace.updateSelectedMetadata(metadata)
    isSaving = false
    if let error = workspace.lastError {
      validationMessage = error.localizedDescription
    }
  }
}
