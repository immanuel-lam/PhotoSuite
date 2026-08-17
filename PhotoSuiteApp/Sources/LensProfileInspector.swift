// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

struct LensProfileInspectorModel: Equatable, Sendable {
  var database: LensProfileDatabaseV1
  private(set) var selectedProfileID: String?

  init(database: LensProfileDatabaseV1, selectedProfileID: String? = nil) {
    self.database = database
    self.selectedProfileID = nil
    select(selectedProfileID)
  }

  var selectedProfile: LensProfileV1? {
    guard let selectedProfileID else { return nil }
    return database.profiles.first { $0.identifier == selectedProfileID }
  }

  var operation: EditOperation? {
    selectedProfile?.opticsAdjustment().map(EditOperation.optics)
  }

  mutating func select(_ identifier: String?) {
    guard
      let identifier,
      database.profiles.contains(where: { $0.identifier == identifier })
    else {
      selectedProfileID = nil
      return
    }
    selectedProfileID = identifier
  }

  mutating func clearSelection() {
    selectedProfileID = nil
  }

  mutating func replaceDatabase(_ database: LensProfileDatabaseV1) {
    let previousSelection = selectedProfileID
    self.database = database
    select(previousSelection)
  }
}

@MainActor
struct LensProfileInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var model: LensProfileInspectorModel
  @State private var query = ""
  @State private var isImporting = false
  @State private var statusMessage: String?

  init(
    workspace: PhotoWorkspace,
    database: LensProfileDatabaseV1 = .empty()
  ) {
    self.workspace = workspace
    _model = State(initialValue: LensProfileInspectorModel(database: database))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Lens Profile")
            .font(.headline)
          Text("Attribution-aware optical correction")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        GlassControlGroup {
          Button("Import XML…") {
            isImporting = true
          }
          .modifier(GlassButtonWhenAvailable())
          .controlSize(.small)
          .accessibilityIdentifier(ModernUIAccessibility.lensProfileImportButton)
        }
      }

      TextField("Filter profiles", text: $query)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Filter lens profiles")

      Picker(
        "Lens profile",
        selection: Binding(
          get: { model.selectedProfileID ?? "" },
          set: { identifier in
            model.select(identifier.isEmpty ? nil : identifier)
            commitSelection()
          }
        )
      ) {
        Text("Manual corrections").tag("")
        ForEach(model.database.search(query)) { profile in
          Text(profile.displayName)
            .tag(profile.identifier)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier(ModernUIAccessibility.lensProfilePicker)

      if let profile = model.selectedProfile {
        VStack(alignment: .leading, spacing: 3) {
          Text(profile.displayName)
            .font(.caption.weight(.medium))
          Text(profile.mount.map { "Mount \($0)" } ?? "Mount not specified")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(
            "Distortion \(profile.distortion, format: .number.precision(.fractionLength(2))) · Vignetting \(profile.vignetting, format: .number.precision(.fractionLength(2)))"
          )
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
      } else if model.database.profiles.isEmpty {
        Text("Import a licensed Lensfun XML database to enable measured profiles.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(alignment: .top, spacing: 7) {
        Image(systemName: "checkmark.seal")
          .foregroundStyle(.secondary)
        Text(
          "\(model.database.attribution.source) · \(model.database.attribution.license) · "
            + model.database.attribution.notice
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityIdentifier(ModernUIAccessibility.lensProfileAttribution)

      if let statusMessage {
        Text(statusMessage)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier(ModernUIAccessibility.lensProfileStatus)
      }
    }
    .padding(.top, 2)
    .accessibilityIdentifier(ModernUIAccessibility.lensProfileInspector)
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.xml],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      importDatabase(from: url)
    }
    .task(id: workspace.selectedAssetID) {
      syncSelectionFromRecipe()
    }
    .onChange(of: workspace.currentRecipe?.revision) { _, _ in
      syncSelectionFromRecipe()
    }
  }

  private func commitSelection() {
    guard let operation = model.operation else {
      Task { await workspace.clearDevelopOperation(.optics) }
      return
    }
    Task { await workspace.commitDevelopOperation(operation) }
  }

  private func syncSelectionFromRecipe() {
    let profileID = workspace.currentDevelopOperations.reversed().compactMap {
      (operation: EditOperation) -> String? in
      guard case .optics(let adjustment) = operation else { return nil }
      return adjustment.lensProfileID
    }.first
    model.select(profileID)
  }

  private func importDatabase(from url: URL) {
    let didStartScope = url.startAccessingSecurityScopedResource()
    defer {
      if didStartScope { url.stopAccessingSecurityScopedResource() }
    }
    do {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let database = try LensProfileXMLLoader.load(data: data)
      model.replaceDatabase(database)
      syncSelectionFromRecipe()
      statusMessage = "Loaded \(database.profiles.count) profile(s) from \(url.lastPathComponent)."
    } catch {
      statusMessage = error.localizedDescription
    }
  }
}
