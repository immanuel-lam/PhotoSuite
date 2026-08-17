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
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Label("PhotoSuite", systemImage: "camera.aperture")
          .font(.headline.weight(.semibold))
        Text("Your photographs")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 18)
      .padding(.top, 54)
      .padding(.bottom, 18)

      Divider().padding(.horizontal, 12)

      VStack(spacing: 4) {
        ForEach(WorkspaceSection.allCases) { section in
          Button {
            workspace.section = section
          } label: {
            HStack(spacing: 11) {
              Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
              Text(section.title)
                .fontWeight(workspace.section == section ? .semibold : .regular)
              Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(.rect)
            .background(
              workspace.section == section ? Color.accentColor.opacity(0.14) : .clear,
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(section.accessibilityIdentifier)
          .accessibilityAddTraits(workspace.section == section ? .isSelected : [])
        }
      }
      .padding(10)

      Divider().padding(.horizontal, 12)

      VStack(alignment: .leading, spacing: 12) {
        Text("CATALOG")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
          .tracking(0.7)

        HStack {
          Label("All Photographs", systemImage: "photo.on.rectangle.angled")
          Spacer()
          Text(workspace.assets.count, format: .number)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .font(.callout)
      }
      .padding(18)

      Spacer(minLength: 16)

      if let asset = workspace.selectedAsset {
        VStack(alignment: .leading, spacing: 6) {
          Text("SELECTED")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.7)
          Text(asset.filename)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
          if let dimensions = asset.pixelDimensions {
            Text("\(dimensions.width) × \(dimensions.height)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(18)
      }
    }
    .modifier(NavigationGlassSurface(cornerRadius: 22))
    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
    .accessibilityIdentifier(ModernUIAccessibility.workspaceNavigation)
  }
}

extension WorkspaceSection {
  var title: String {
    switch self {
    case .library: "Library"
    case .develop: "Develop"
    case .deliver: "Deliver"
    }
  }

  var symbol: String {
    switch self {
    case .library: "square.grid.2x2"
    case .develop: "slider.horizontal.3"
    case .deliver: "square.and.arrow.up"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .library: ModernUIAccessibility.library
    case .develop: ModernUIAccessibility.develop
    case .deliver: ModernUIAccessibility.deliver
    }
  }
}

@MainActor
struct LibraryView: View {
  @Bindable var workspace: PhotoWorkspace
  let sidebarWidth: CGFloat
  private let columns = [GridItem(.adaptive(minimum: 240, maximum: 380), spacing: 14)]

  var body: some View {
    ZStack {
      LibraryBackdrop(preview: backdropPreview)

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          LibraryHeader(workspace: workspace)

          if workspace.isLoading && workspace.assets.isEmpty {
            ProgressView("Opening catalog…")
              .frame(maxWidth: .infinity, minHeight: 320)
              .accessibilityIdentifier("library-loading")
          } else if workspace.filteredAssets.isEmpty {
            LibraryEmptyState(workspace: workspace)
          } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
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
            .accessibilityIdentifier("library-grid")
          }
        }
        .padding(.top, 78)
        .padding(.trailing, 22)
        .padding(.bottom, 26)
        .padding(.leading, sidebarWidth + 34)
      }
    }
  }

  private var backdropPreview: PreviewFrame? {
    guard let asset = workspace.filteredAssets.first else { return nil }
    return workspace.cachedPreview(for: asset.id)
  }
}

private struct LibraryBackdrop: View {
  let preview: PreviewFrame?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)
      if let image = previewCGImage(preview) {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFill()
          .blur(radius: 70)
          .opacity(colorScheme == .dark ? 0.20 : 0.14)
      }
      RadialGradient(
        colors: [
          Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
          Color.clear,
        ],
        center: .topLeading,
        startRadius: 20,
        endRadius: 760
      )
    }
    .ignoresSafeArea()
  }
}

@MainActor
private struct LibraryHeader: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Library")
        .font(.system(size: 34, weight: .bold, design: .default))
        .tracking(-0.7)
      Text(summary)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var summary: String {
    if workspace.assets.isEmpty {
      return "A focused place for your original photographs."
    }
    return "\(workspace.filteredAssets.count) of \(workspace.assets.count) photographs"
  }
}

@MainActor
private struct LibraryEmptyState: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: workspace.searchText.isEmpty ? "photo.stack" : "magnifyingglass")
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.secondary)
      Text(workspace.searchText.isEmpty ? "Build your library" : "No matches")
        .font(.title2.weight(.semibold))
      Text(
        workspace.searchText.isEmpty
          ? "Import a photograph to start a non-destructive edit."
          : "No filename contains “\(workspace.searchText)”."
      )
      .foregroundStyle(.secondary)
      .frame(maxWidth: 360, alignment: .leading)

      if workspace.searchText.isEmpty {
        Button {
          workspace.isImporting = true
        } label: {
          Label("Import Photographs…", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(.top, 48)
    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    .accessibilityIdentifier("library-empty")
  }
}

private struct AssetTile: View {
  let asset: PhotoAsset
  let preview: PreviewFrame?
  let isSelected: Bool

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Color(nsColor: .underPageBackgroundColor)

      if let image = previewCGImage(preview) {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: asset.isMissing ? "photo.badge.exclamationmark" : "photo")
          .font(.system(size: 32, weight: .light))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      LinearGradient(
        colors: [.clear, .black.opacity(0.76)],
        startPoint: .center,
        endPoint: .bottom
      )

      HStack(spacing: 6) {
        Text(asset.filename)
          .lineLimit(1)
          .truncationMode(.middle)
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
      .font(.caption.weight(.medium))
      .foregroundStyle(.white)
      .padding(11)
    }
    .aspectRatio(4 / 3, contentMode: .fit)
    .clipShape(.rect(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7),
          lineWidth: isSelected ? 3 : 0.5
        )
    }
    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(asset.filename)
    .accessibilityValue(asset.isMissing ? "Source file missing" : "Available")
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
        HStack(spacing: 0) {
          DeliveryPreview(workspace: workspace, filename: asset.filename)
          DeliverySettings(
            workspace: workspace,
            quality: $quality,
            chooseDestination: chooseDestination
          )
          .frame(width: 410)
        }
      } else {
        ZStack {
          Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
          ContentUnavailableView(
            "No Photograph Selected",
            systemImage: "square.and.arrow.up",
            description: Text("Select and develop a photograph before export.")
          )
        }
      }
    }
    .accessibilityIdentifier("deliver-workspace")
  }
}

@MainActor
private struct DeliveryPreview: View {
  @Bindable var workspace: PhotoWorkspace
  let filename: String

  var body: some View {
    ZStack {
      Color(white: workspace.proofMode ? 0.20 : 0.13)
      if let image = previewCGImage(workspace.preview) {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFit()
          .padding(34)
          .shadow(color: .black.opacity(0.38), radius: 24, y: 10)
      } else {
        if workspace.errorMessage == nil {
          ProgressView("Preparing preview…")
            .foregroundStyle(.white)
        } else {
          Label("Preview unavailable", systemImage: "photo.badge.exclamationmark")
            .foregroundStyle(.white.opacity(0.78))
        }
      }
    }
    .overlay(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Deliver")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(.white)
        Text(filename)
          .font(.callout)
          .foregroundStyle(.white.opacity(0.68))
      }
      .padding(.top, 76)
      .padding(.leading, 24)
    }
    .ignoresSafeArea()
  }
}

@MainActor
private struct DeliverySettings: View {
  @Bindable var workspace: PhotoWorkspace
  @Binding var quality: Double
  let chooseDestination: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
          Text("JPEG Export")
            .font(.title2.weight(.bold))
          Text("A standard sRGB copy from the current edit.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Divider()

        if let asset = workspace.selectedAsset {
          SettingsSection(title: "PHOTOGRAPH") {
            LabeledContent("Source", value: asset.filename)
            if let dimensions = asset.pixelDimensions {
              LabeledContent("Dimensions", value: "\(dimensions.width) × \(dimensions.height)")
            }
            LabeledContent("Recipe revision", value: "\(workspace.currentRecipe?.revision ?? 0)")
          }
        }

        SettingsSection(title: "OUTPUT") {
          LabeledContent("Color space", value: "sRGB")
          LabeledContent("Metadata", value: "Basic source metadata")
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Quality")
              Spacer()
              Text(quality, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
            }
            Slider(value: $quality, in: 0.4...1, step: 0.01)
          }
        }

        Button(action: chooseDestination) {
          HStack {
            if workspace.isExporting {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "square.and.arrow.up")
            }
            Text(workspace.isExporting ? "Exporting…" : "Export JPEG…")
            Spacer()
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(workspace.isExporting)
        .accessibilityIdentifier(ModernUIAccessibility.exportJPEGButton)

        if let export = workspace.lastExport {
          Text("Exported to \(export.outputURL.path(percentEncoded: false))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .padding(.top, 76)
      .padding(.horizontal, 24)
      .padding(.bottom, 28)
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(width: 0.5)
    }
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .tracking(0.7)
      content
    }
  }
}

private func previewCGImage(_ preview: PreviewFrame?) -> CGImage? {
  guard
    let data = preview?.imageData as CFData?,
    let source = CGImageSourceCreateWithData(data, nil)
  else { return nil }
  return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
