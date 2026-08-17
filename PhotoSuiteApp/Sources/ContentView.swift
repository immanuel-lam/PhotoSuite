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
  private let sidebarWidth: CGFloat = 300

  var body: some View {
    ZStack(alignment: .leading) {
      workspaceContent
        .ignoresSafeArea()

      if workspace.section == .library {
        WorkspaceSidebar(workspace: workspace)
          .frame(width: sidebarWidth)
          .padding(.leading, 14)
          .padding(.vertical, 14)
          .transition(.move(edge: .leading).combined(with: .opacity))
          .zIndex(2)
      }
    }
    .overlay(alignment: .topTrailing) {
      WorkspaceCommandBar(workspace: workspace)
        .padding(.top, 14)
        .padding(.trailing, 16)
        .zIndex(3)
    }
    .inspector(isPresented: $inspectorPresented) {
      DevelopInspector(workspace: workspace)
        .inspectorColumnWidth(min: 300, ideal: 320, max: 380)
    }
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
    .overlay(alignment: .bottom) {
      if let error = workspace.errorMessage {
        ErrorBanner(message: error) { workspace.errorMessage = nil }
          .padding(.bottom, 18)
          .zIndex(4)
      }
    }
  }

  @ViewBuilder
  private var workspaceContent: some View {
    switch workspace.section {
    case .library:
      LibraryView(workspace: workspace, sidebarWidth: sidebarWidth)
    case .develop:
      DevelopView(workspace: workspace)
    case .deliver:
      DeliverView(workspace: workspace, quality: $jpegQuality) {
        workspace.isChoosingExportDestination = true
      }
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

@MainActor
private struct WorkspaceCommandBar: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    HStack(spacing: 10) {
      if workspace.section == .library {
        GlassControlGroup {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            TextField("Search Library", text: $workspace.searchText)
              .textFieldStyle(.plain)
              .frame(width: 170)
              .accessibilityIdentifier(ModernUIAccessibility.librarySearchField)
            if !workspace.searchText.isEmpty {
              Button {
                workspace.searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .accessibilityLabel("Clear search")
            }
          }
          .padding(.horizontal, 8)
          .frame(height: 28)
        }
      } else {
        WorkspaceModeControl(workspace: workspace)
      }

      GlassControlGroup {
        HStack(spacing: 4) {
          Button {
            workspace.isImporting = true
          } label: {
            Label("Import Photographs", systemImage: "plus")
          }
          .labelStyle(.iconOnly)
          .help("Import common images or Apple-supported RAW photographs")
          .accessibilityIdentifier(ModernUIAccessibility.importButton)
          .modifier(GlassButtonWhenAvailable())

          Toggle(isOn: $workspace.proofMode) {
            Label("Proof Mode", systemImage: "rectangle.inset.filled")
          }
          .toggleStyle(.button)
          .labelStyle(.iconOnly)
          .help("Hide canvas controls and use a neutral surround")
          .accessibilityIdentifier(ModernUIAccessibility.proofModeToggle)
          .modifier(GlassButtonWhenAvailable(prominent: workspace.proofMode))
        }
      }
    }
  }
}

@MainActor
private struct WorkspaceModeControl: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    GlassControlGroup {
      HStack(spacing: 4) {
        ForEach(WorkspaceSection.allCases) { section in
          Button {
            workspace.section = section
          } label: {
            Label(section.title, systemImage: section.symbol)
          }
          .labelStyle(.iconOnly)
          .help(section.title)
          .accessibilityIdentifier(section.accessibilityIdentifier)
          .accessibilityAddTraits(workspace.section == section ? .isSelected : [])
          .modifier(GlassButtonWhenAvailable(prominent: workspace.section == section))
        }
      }
    }
    .accessibilityIdentifier(ModernUIAccessibility.workspaceNavigation)
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
    .modifier(NavigationGlassSurface(cornerRadius: 12))
    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    .accessibilityIdentifier("error-banner")
  }
}
