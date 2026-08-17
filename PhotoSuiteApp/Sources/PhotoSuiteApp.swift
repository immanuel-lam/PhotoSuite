// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Observation
import PhotoDomain
import PhotoWorkflow
import SwiftUI

@main
struct PhotoSuiteApp: App {
  @State private var environment = PhotoSuiteEnvironment()

  var body: some Scene {
    WindowGroup("PhotoSuite") {
      if let workspace = environment.workspace {
        ContentView(workspace: workspace)
          .frame(minWidth: 1_100, minHeight: 700)
      } else {
        ContentUnavailableView(
          "PhotoSuite Could Not Start",
          systemImage: "exclamationmark.triangle",
          description: Text(environment.startupError ?? "PhotoSuite could not start.")
        )
        .accessibilityIdentifier("startup-error")
        .frame(minWidth: 1_100, minHeight: 700)
      }
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1_280, height: 820)
    .commands {
      InspectorCommands()
      PhotoSuiteCommands(workspace: environment.workspace)
    }

    Settings {
      PhotoSuiteSettingsView()
    }
  }
}

@MainActor
@Observable
private final class PhotoSuiteEnvironment {
  let workspace: PhotoWorkspace?
  let startupError: String?

  init() {
    do {
      workspace = try PhotoWorkspaceComposition.live()
      startupError = nil
    } catch {
      workspace = nil
      startupError = error.localizedDescription
    }
  }
}

@MainActor
private struct PhotoSuiteCommands: Commands {
  let workspace: PhotoWorkspace?

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Import Photographs…") { workspace?.isImporting = true }
        .keyboardShortcut("i")
        .disabled(workspace == nil)
    }

    CommandGroup(replacing: .undoRedo) {
      Button("Undo Edit") { Task { await workspace?.undo() } }
        .keyboardShortcut("z")
        .disabled(workspace?.canUndo != true)
      Button("Redo Edit") { Task { await workspace?.redo() } }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .disabled(workspace?.canRedo != true)
    }

    CommandMenu("Photograph") {
      Button("Library") { workspace?.section = .library }
        .keyboardShortcut("1", modifiers: .command)
      Button("Develop") { workspace?.section = .develop }
        .keyboardShortcut("2", modifiers: .command)
      Button("Deliver") { workspace?.section = .deliver }
        .keyboardShortcut("3", modifiers: .command)
      Button("Workspace") { workspace?.section = .workspace }
        .keyboardShortcut("4", modifiers: .command)
      Divider()
      Button("Toggle Before and After") { workspace?.toggleBeforeAfter() }
        .keyboardShortcut("\\")
        .disabled(workspace?.selectedAsset == nil)
      Button("Toggle Proof Mode") { workspace?.proofMode.toggle() }
        .keyboardShortcut("p", modifiers: [.command, .control])
      Divider()
      Button("Export JPEG…") { workspace?.isChoosingExportDestination = true }
        .keyboardShortcut("e")
        .disabled(workspace?.selectedAsset == nil)
    }

    CommandMenu("Library") {
      Button("Unrated") { Task { await workspace?.setRating(0) } }
        .keyboardShortcut("0", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("1 Star") { Task { await workspace?.setRating(1) } }
        .keyboardShortcut("1", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("2 Stars") { Task { await workspace?.setRating(2) } }
        .keyboardShortcut("2", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("3 Stars") { Task { await workspace?.setRating(3) } }
        .keyboardShortcut("3", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("4 Stars") { Task { await workspace?.setRating(4) } }
        .keyboardShortcut("4", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("5 Stars") { Task { await workspace?.setRating(5) } }
        .keyboardShortcut("5", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)

      Divider()
      Button("Red Colour Label") { Task { await workspace?.setColorLabel(.red) } }
        .keyboardShortcut("6", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("Yellow Colour Label") { Task { await workspace?.setColorLabel(.yellow) } }
        .keyboardShortcut("7", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("Green Colour Label") { Task { await workspace?.setColorLabel(.green) } }
        .keyboardShortcut("8", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("Blue Colour Label") { Task { await workspace?.setColorLabel(.blue) } }
        .keyboardShortcut("9", modifiers: [])
        .disabled(workspace?.selectedAsset == nil)
      Button("Purple Colour Label") { Task { await workspace?.setColorLabel(.purple) } }
        .disabled(workspace?.selectedAsset == nil)
      Button("Clear Colour Label") { Task { await workspace?.setColorLabel(nil) } }
        .disabled(workspace?.selectedAsset == nil)

      Divider()
      Button("New Collection with Selected") {
        guard let workspace else { return }
        let collection = workspace.createCollection(
          named: "Collection \(workspace.collections.count + 1)"
        )
        if let assetID = workspace.selectedAssetID {
          workspace.addAsset(assetID, toCollection: collection.id)
        }
      }
      .keyboardShortcut("n", modifiers: [.command, .option])
      .disabled(workspace?.selectedAsset == nil)

      Button("Stack Visible Photographs") {
        guard let workspace else { return }
        _ = workspace.createStack(
          named: "Stack \(workspace.stacks.count + 1)",
          assetIDs: workspace.filteredAssets.map(\.id)
        )
      }
      .keyboardShortcut("g")
      .disabled((workspace?.filteredAssets.count ?? 0) < 2)
    }
  }
}

private struct PhotoSuiteSettingsView: View {
  @AppStorage("jpegQuality") private var jpegQuality = 0.9

  var body: some View {
    Form {
      LabeledContent("JPEG quality") {
        Slider(value: $jpegQuality, in: 0.4...1, step: 0.01)
          .frame(width: 220)
        Text(jpegQuality, format: .percent.precision(.fractionLength(0)))
          .monospacedDigit()
          .frame(width: 44, alignment: .trailing)
      }
      Text("Previews are rebuildable and remain in memory for this version.")
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 520, height: 180)
  }
}
