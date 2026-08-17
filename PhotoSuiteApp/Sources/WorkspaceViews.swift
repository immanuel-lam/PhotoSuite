// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import ImageIO
import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct WorkspaceSidebar: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    List {
      Section("Workspaces") {
        ForEach(WorkspaceSection.allCases) { section in
          Button {
            workspace.section = section
          } label: {
            Label(section.title, systemImage: section.symbol)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowBackground(
            workspace.section == section ? Color.accentColor.opacity(0.18) : Color.clear
          )
          .accessibilityIdentifier("workspace-\(section.rawValue)")
          .accessibilityAddTraits(workspace.section == section ? .isSelected : [])
        }
      }

      Section("Catalog") {
        LabeledContent {
          Text(workspace.assets.count, format: .number).foregroundStyle(.secondary)
        } label: {
          Label("All Photographs", systemImage: "photo.on.rectangle.angled")
        }
      }
    }
    .listStyle(.sidebar)
    .accessibilityIdentifier("workspace-navigation")
  }
}

extension WorkspaceSection {
  fileprivate var title: String {
    switch self {
    case .library: "Library"
    case .develop: "Develop"
    case .deliver: "Deliver"
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .library: "square.grid.2x2"
    case .develop: "slider.horizontal.3"
    case .deliver: "square.and.arrow.up"
    }
  }
}

@MainActor
struct LibraryView: View {
  @Bindable var workspace: PhotoWorkspace
  private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)]

  var body: some View {
    Group {
      if workspace.isLoading && workspace.assets.isEmpty {
        ProgressView("Opening catalog…").accessibilityIdentifier("library-loading")
      } else if workspace.filteredAssets.isEmpty {
        ContentUnavailableView {
          Label(
            workspace.searchText.isEmpty ? "No Photographs" : "No Matches",
            systemImage: workspace.searchText.isEmpty ? "photo.badge.plus" : "magnifyingglass"
          )
        } description: {
          Text(
            workspace.searchText.isEmpty
              ? "Import a photograph to start a non-destructive edit."
              : "No filename contains \"\(workspace.searchText)\"."
          )
        } actions: {
          if workspace.searchText.isEmpty {
            Button("Import Photographs…") { workspace.isImporting = true }
          }
        }
        .accessibilityIdentifier("library-empty")
      } else {
        ScrollView {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(workspace.filteredAssets) { asset in
              Button {
                Task {
                  await workspace.selectAsset(asset.id)
                  workspace.section = .develop
                }
              } label: {
                AssetTile(
                  asset: asset,
                  preview: workspace.cachedPreview(for: asset.id),
                  isSelected: workspace.selectedAssetID == asset.id
                )
              }
              .buttonStyle(.plain)
              .draggable(asset.sourceURL)
              .accessibilityIdentifier("asset-\(asset.id.uuidString)")
            }
          }
          .padding(20)
        }
        .accessibilityIdentifier("library-grid")
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct AssetTile: View {
  let asset: PhotoAsset
  let preview: PreviewFrame?
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        Color(nsColor: .underPageBackgroundColor)
        if let image = previewImage {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
          Image(systemName: asset.isMissing ? "photo.badge.exclamationmark" : "photo")
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(.secondary)
        }
      }
      .aspectRatio(4 / 3, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .stroke(
            isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
            lineWidth: isSelected ? 2 : 1
          )
      }

      HStack(spacing: 6) {
        Text(asset.filename).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 4)
        if asset.rating > 0 {
          Image(systemName: "star.fill")
            .foregroundStyle(.yellow)
            .accessibilityLabel("\(asset.rating) stars")
        }
        if asset.isMissing {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityLabel("Source file missing")
        }
      }
      .font(.caption)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(asset.filename)
    .accessibilityValue(asset.isMissing ? "Source file missing" : "Available")
  }

  private var previewImage: CGImage? {
    guard
      let data = preview?.imageData as CFData?,
      let source = CGImageSourceCreateWithData(data, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }
}

@MainActor
struct DeliverView: View {
  @Bindable var workspace: PhotoWorkspace
  @Binding var quality: Double
  let chooseDestination: () -> Void

  var body: some View {
    Group {
      if let asset = workspace.selectedAsset {
        Form {
          Section("Photograph") {
            LabeledContent("Source", value: asset.filename)
            if let dimensions = asset.pixelDimensions {
              LabeledContent("Dimensions", value: "\(dimensions.width) × \(dimensions.height)")
            }
            LabeledContent("Recipe revision", value: "\(workspace.currentRecipe?.revision ?? 0)")
          }
          Section("JPEG") {
            LabeledContent("Color space", value: "sRGB")
            LabeledContent("Metadata", value: "Basic source metadata")
            LabeledContent("Quality") {
              Slider(value: $quality, in: 0.4...1, step: 0.01).frame(maxWidth: 280)
              Text(quality, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
          }
          Section {
            Button(action: chooseDestination) {
              if workspace.isExporting {
                ProgressView().controlSize(.small)
              } else {
                Label("Export JPEG…", systemImage: "square.and.arrow.up")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(workspace.isExporting)
            .accessibilityIdentifier("export-jpeg-button")

            if let export = workspace.lastExport {
              Text("Exported to \(export.outputURL.path(percentEncoded: false))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .padding()
      } else {
        ContentUnavailableView(
          "No Photograph Selected",
          systemImage: "square.and.arrow.up",
          description: Text("Select and develop a photograph before export.")
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier("deliver-workspace")
  }
}
