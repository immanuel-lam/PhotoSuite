// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

enum MetadataEditorAccessibility {
  static let editor = "metadata-editor"
  static let titleField = "metadata-title-field"
  static let creatorField = "metadata-creator-field"
  static let keywordsField = "metadata-keywords-field"
  static let descriptionField = "metadata-description-field"
  static let cityField = "metadata-city-field"
  static let stateProvinceField = "metadata-state-province-field"
  static let countryField = "metadata-country-field"
  static let copyrightNoticeField = "metadata-copyright-field"
  static let rightsUsageTermsField = "metadata-rights-field"
  static let saveButton = "metadata-save-button"
}

enum MetadataEditorFieldLabel {
  static let title = "Title"
  static let creator = "Creator"
  static let keywords = "Keywords, separated by commas"
  static let description = "Description"
  static let city = "City"
  static let stateProvince = "State / Province"
  static let country = "Country"
  static let copyrightNotice = "Copyright notice"
  static let rightsUsageTerms = "Rights / usage terms"
}

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
  @State private var city = ""
  @State private var stateProvince = ""
  @State private var country = ""
  @State private var copyrightNotice = ""
  @State private var rightsUsageTerms = ""
  @State private var isSaving = false
  @State private var validationMessage: String?

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 8) {
        TextField(MetadataEditorFieldLabel.title, text: $title)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.titleField)

        TextField(MetadataEditorFieldLabel.creator, text: $creator)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.creatorField)

        TextField(MetadataEditorFieldLabel.keywords, text: $keywords)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.keywordsField)

        TextEditor(text: $description)
          .font(.callout)
          .frame(minHeight: 58, maxHeight: 92)
          .padding(4)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay(alignment: .topLeading) {
            if description.isEmpty {
              Text(MetadataEditorFieldLabel.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 9)
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
          }
          .accessibilityIdentifier(MetadataEditorAccessibility.descriptionField)

        TextField(MetadataEditorFieldLabel.city, text: $city)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.cityField)

        TextField(MetadataEditorFieldLabel.stateProvince, text: $stateProvince)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.stateProvinceField)

        TextField(MetadataEditorFieldLabel.country, text: $country)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.countryField)

        TextField(MetadataEditorFieldLabel.copyrightNotice, text: $copyrightNotice)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.copyrightNoticeField)

        TextField(MetadataEditorFieldLabel.rightsUsageTerms, text: $rightsUsageTerms)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(MetadataEditorAccessibility.rightsUsageTermsField)

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
          .accessibilityIdentifier(MetadataEditorAccessibility.saveButton)
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
    .accessibilityIdentifier(MetadataEditorAccessibility.editor)
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
    city = metadata.city ?? ""
    stateProvince = metadata.stateProvince ?? ""
    country = metadata.country ?? ""
    copyrightNotice = metadata.copyrightNotice ?? ""
    rightsUsageTerms = metadata.rightsUsageTerms ?? ""
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
        copyrightNotice: copyrightNotice,
        rightsUsageTerms: rightsUsageTerms,
        city: city,
        stateProvince: stateProvince,
        country: country,
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
