// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
  @Bindable var workspace: PhotoWorkspace
  @AppStorage("jpegQuality") private var jpegQuality = 0.9
  @State private var inspectorPresented = false

  var body: some View {
    NavigationSplitView {
      WorkspaceSidebar(workspace: workspace)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    } detail: {
      workspaceContent
        .navigationTitle(navigationTitle)
        .toolbar { toolbarContent }
    }
    .navigationSplitViewStyle(.balanced)
    .inspector(isPresented: $inspectorPresented) {
      DevelopInspector(workspace: workspace)
        .inspectorColumnWidth(min: 280, ideal: 310, max: 380)
    }
    .searchable(text: $workspace.searchText, placement: .toolbar, prompt: "Search filenames")
    .fileImporter(
      isPresented: $workspace.isImporting,
      allowedContentTypes: [.image],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls): Task { await workspace.importURLs(urls) }
      case .failure(let error): workspace.errorMessage = error.localizedDescription
      }
    } onCancellation: {
    }
    .onChange(of: workspace.section, initial: true) { _, section in
      inspectorPresented = section == .develop
    }
    .onChange(of: workspace.isChoosingExportDestination) { _, requested in
      guard requested else { return }
      workspace.isChoosingExportDestination = false
      presentExportPanel()
    }
    .task { await workspace.reopen() }
    .overlay(alignment: .top) {
      if let error = workspace.errorMessage {
        ErrorBanner(message: error) { workspace.errorMessage = nil }
          .padding(.top, 8)
      }
    }
  }

  @ViewBuilder
  private var workspaceContent: some View {
    switch workspace.section {
    case .library: LibraryView(workspace: workspace)
    case .develop: DevelopView(workspace: workspace)
    case .deliver:
      DeliverView(workspace: workspace, quality: $jpegQuality) {
        workspace.isChoosingExportDestination = true
      }
    }
  }

  private var navigationTitle: String {
    switch workspace.section {
    case .library: "Library"
    case .develop: workspace.selectedAsset?.filename ?? "Develop"
    case .deliver: "Deliver"
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        workspace.isImporting = true
      } label: {
        Label("Import Photographs", systemImage: "square.and.arrow.down")
      }
      .help("Import common images or Apple-supported RAW photographs")
      .accessibilityIdentifier("import-button")

      Toggle(isOn: $workspace.proofMode) {
        Label("Proof Mode", systemImage: "rectangle.inset.filled")
      }
      .help("Hide canvas controls and use a neutral surround")
      .accessibilityIdentifier("proof-mode-toggle")
    }
  }

  private func presentExportPanel() {
    let panel = NSSavePanel()
    panel.title = "Export JPEG"
    panel.allowedContentTypes = [.jpeg]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    let baseName = workspace.selectedAsset?.sourceURL.deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = "\(baseName ?? "Photo")-edited.jpg"
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      Task { @MainActor in
        await workspace.exportJPEG(to: destination, quality: jpegQuality)
      }
    }
  }
}

private struct ErrorBanner: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
      Text(message).lineLimit(2)
      Button("Dismiss", action: dismiss).buttonStyle(.borderless)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .shadow(radius: 6, y: 2)
    .accessibilityIdentifier("error-banner")
  }
}
