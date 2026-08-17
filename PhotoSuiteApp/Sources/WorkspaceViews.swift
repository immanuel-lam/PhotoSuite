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

        Button {
          workspace.activeCollectionID = nil
        } label: {
          HStack {
            Label("All Photographs", systemImage: "photo.on.rectangle.angled")
            Spacer()
            Text(workspace.assets.count, format: .number)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.callout)

        HStack {
          Text("COLLECTIONS")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.7)
          Spacer()
          Button {
            let collection = workspace.createCollection(
              named: "Collection \(workspace.collections.count + 1)"
            )
            if let assetID = workspace.selectedAssetID {
              workspace.addAsset(assetID, toCollection: collection.id)
            }
            workspace.activeCollectionID = collection.id
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.plain)
          .help("Create a session collection")
          .accessibilityIdentifier(ModernUIAccessibility.newCollectionButton)
        }

        if workspace.collections.isEmpty {
          Text("No session collections")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          ForEach(workspace.collections) { collection in
            Button {
              workspace.activeCollectionID = collection.id
            } label: {
              HStack {
                Label(collection.name, systemImage: "rectangle.stack")
                  .lineLimit(1)
                Spacer()
                Text(collection.assetIDs.count, format: .number)
                  .foregroundStyle(.secondary)
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .font(.callout)
          }
        }

        if workspace.filteredAssets.count >= 2 || !workspace.stacks.isEmpty {
          HStack {
            Text("STACKS")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .tracking(0.7)
            Spacer()
            Button {
              _ = workspace.createStack(
                named: "Stack \(workspace.stacks.count + 1)",
                assetIDs: workspace.filteredAssets.map(\.id)
              )
            } label: {
              Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
            .disabled(workspace.filteredAssets.count < 2)
            .help("Stack visible photographs for this session")
            .accessibilityIdentifier(ModernUIAccessibility.newStackButton)
          }

          ForEach(workspace.stacks) { stack in
            Button {
              workspace.toggleStack(stack.id)
            } label: {
              HStack {
                Label(
                  stack.name,
                  systemImage: stack.isExpanded ? "square.stack.3d.up.fill" : "square.stack.3d.up"
                )
                .lineLimit(1)
                Spacer()
                Text(stack.assetIDs.count, format: .number)
                  .foregroundStyle(.secondary)
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .font(.callout)
          }
        }

        if workspace.supportsDurableLibrary {
          HStack {
            Text("SAVED COLLECTIONS")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .tracking(0.7)
            Spacer()
            Button {
              Task {
                await workspace.createDurableCollection(
                  named: "Collection \(workspace.durableCollections.count + 1)",
                  assetIDs: workspace.filteredAssets.map(\.id)
                )
              }
            } label: {
              Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Create a durable collection from the visible set")
          }

          if workspace.durableCollections.isEmpty {
            Text("No saved collections")
              .font(.caption)
              .foregroundStyle(.tertiary)
          } else {
            ForEach(workspace.durableCollections) { collection in
              Button {
                workspace.activeCollectionID = collection.id
              } label: {
                HStack {
                  Label(
                    collection.name,
                    systemImage: collection.kind == .smart
                      ? "gearshape.2"
                      : "rectangle.stack"
                  )
                  .lineLimit(1)
                  Spacer()
                  if collection.kind == .smart {
                    Text("Smart")
                      .foregroundStyle(.secondary)
                  } else {
                    Text(collection.assetIDs.count, format: .number)
                      .foregroundStyle(.secondary)
                  }
                }
                .contentShape(.rect)
              }
              .buttonStyle(.plain)
              .font(.callout)
            }
          }

          HStack {
            Text("SAVED STACKS")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .tracking(0.7)
            Spacer()
            Button {
              Task {
                await workspace.createDurableStack(
                  assetIDs: workspace.filteredAssets.map(\.id)
                )
              }
            } label: {
              Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
            .disabled(workspace.filteredAssets.isEmpty)
            .help("Save the visible photographs as a durable stack")
          }

          if workspace.durableStacks.isEmpty {
            Text("No saved stacks")
              .font(.caption)
              .foregroundStyle(.tertiary)
          } else {
            ForEach(workspace.durableStacks) { stack in
              Button {
                Task { await workspace.toggleDurableStack(stack.id) }
              } label: {
                HStack {
                  Label(
                    "Stack \(stack.assetIDs.count)",
                    systemImage: stack.isCollapsed
                      ? "square.stack.3d.up"
                      : "square.stack.3d.up.fill"
                  )
                  .lineLimit(1)
                  Spacer()
                  Text(stack.isCollapsed ? "Collapsed" : "Expanded")
                    .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
              }
              .buttonStyle(.plain)
              .font(.callout)
              .help("Toggle saved stack visibility")
            }
          }
        }

        Text(
          workspace.supportsDurableLibrary
            ? "Saved collections and stacks persist in the catalog. Session collections remain temporary."
            : "Collections and stacks are session-only in this version."
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
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
          LibraryMetadataControls(workspace: workspace, asset: asset)
          LibraryKeywordControls(workspace: workspace, asset: asset)
          LibraryVirtualCopyControls(workspace: workspace, asset: asset)
          MetadataEditorView(workspace: workspace, asset: asset)
        }
        .padding(18)
      }
    }
    .modifier(NavigationGlassSurface(cornerRadius: 22))
    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
    .accessibilityIdentifier(ModernUIAccessibility.workspaceNavigation)
  }
}

@MainActor
private struct LibraryMetadataControls: View {
  @Bindable var workspace: PhotoWorkspace
  let asset: PhotoAsset

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 3) {
        ForEach(1...5, id: \.self) { rating in
          Button {
            Task { await workspace.setRating(asset.rating == rating ? 0 : rating) }
          } label: {
            Image(systemName: asset.rating >= rating ? "star.fill" : "star")
          }
          .buttonStyle(.plain)
          .foregroundStyle(asset.rating >= rating ? Color.yellow : Color.secondary)
          .help("Set \(rating)-star rating")
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Rating")

      HStack(spacing: 7) {
        ForEach(ColorLabel.allCases, id: \.rawValue) { label in
          Button {
            Task { await workspace.setColorLabel(asset.colorLabel == label ? nil : label) }
          } label: {
            Circle()
              .fill(label.color)
              .frame(width: 11, height: 11)
              .overlay {
                if asset.colorLabel == label {
                  Circle().stroke(.primary, lineWidth: 1.5).padding(-3)
                }
              }
          }
          .buttonStyle(.plain)
          .help("Set \(label.title.lowercased()) colour label")
          .accessibilityLabel("\(label.title) colour label")
        }
      }
    }
    .accessibilityIdentifier(ModernUIAccessibility.libraryMetadataControls)
  }
}

extension ColorLabel {
  fileprivate var color: Color {
    switch self {
    case .red: .red
    case .yellow: .yellow
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    case .unknown: .secondary
    }
  }
}

extension WorkspaceSection {
  var title: String {
    switch self {
    case .library: "Library"
    case .develop: "Develop"
    case .deliver: "Deliver"
    case .workspace: "Workspace"
    }
  }

  var symbol: String {
    switch self {
    case .library: "square.grid.2x2"
    case .develop: "slider.horizontal.3"
    case .deliver: "square.and.arrow.up"
    case .workspace: "rectangle.3.group"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .library: ModernUIAccessibility.library
    case .develop: ModernUIAccessibility.develop
    case .deliver: ModernUIAccessibility.deliver
    case .workspace: ModernUIAccessibility.professionalWorkspace
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
                .contextMenu {
                  Menu("Rating") {
                    ForEach(0...5, id: \.self) { rating in
                      Button(rating == 0 ? "Unrated" : "\(rating) stars") {
                        Task {
                          await workspace.selectAsset(asset.id)
                          await workspace.setRating(rating)
                        }
                      }
                    }
                  }
                  Menu("Colour Label") {
                    Button("None") {
                      Task {
                        await workspace.selectAsset(asset.id)
                        await workspace.setColorLabel(nil)
                      }
                    }
                    ForEach(ColorLabel.allCases, id: \.rawValue) { label in
                      Button(label.title) {
                        Task {
                          await workspace.selectAsset(asset.id)
                          await workspace.setColorLabel(label)
                        }
                      }
                    }
                  }
                  if !workspace.collections.isEmpty {
                    Menu("Add to Collection") {
                      ForEach(workspace.collections) { collection in
                        Button(collection.name) {
                          workspace.addAsset(asset.id, toCollection: collection.id)
                        }
                      }
                    }
                  }
                }
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
  let chooseBatchDestination: () -> Void

  init(
    workspace: PhotoWorkspace,
    quality: Binding<Double>,
    chooseDestination: @escaping () -> Void,
    chooseBatchDestination: @escaping () -> Void = {}
  ) {
    self.workspace = workspace
    self._quality = quality
    self.chooseDestination = chooseDestination
    self.chooseBatchDestination = chooseBatchDestination
  }

  var body: some View {
    Group {
      if let asset = workspace.selectedAsset {
        HStack(spacing: 0) {
          DeliveryPreview(workspace: workspace, filename: asset.filename)
          DeliverySettings(
            workspace: workspace,
            quality: $quality,
            chooseDestination: chooseDestination,
            chooseBatchDestination: chooseBatchDestination
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
  let chooseBatchDestination: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Image Export")
            .font(.title2.weight(.bold))
          Text("A colour-managed copy from the current edit.")
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
          Picker("Format", selection: $workspace.deliverOptions.format) {
            ForEach(DeliverFormat.allCases, id: \.self) { format in
              Text(format.title).tag(format)
            }
          }
          LabeledContent("Color space", value: "sRGB")
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

        SettingsSection(title: "PROCESSING") {
          Toggle("Resize to long edge", isOn: resizeEnabled)
            .accessibilityIdentifier(ModernUIAccessibility.deliverResizeToggle)
          if case .longEdge = workspace.deliverOptions.resize {
            Stepper(
              "Long edge: \(longEdgePixels.wrappedValue) px",
              value: longEdgePixels,
              in: 320...16_384,
              step: 160
            )
          }

          Picker("Metadata", selection: $workspace.deliverOptions.metadata) {
            ForEach(DeliverMetadata.allCases, id: \.self) { metadata in
              Text(metadata.title).tag(metadata)
            }
          }
          .accessibilityIdentifier(ModernUIAccessibility.deliverMetadataPicker)

          Toggle("Text watermark", isOn: watermarkEnabled)
            .accessibilityIdentifier(ModernUIAccessibility.deliverWatermarkToggle)
          if case .text = workspace.deliverOptions.watermark {
            TextField("Watermark text", text: watermarkText)
          }

          Picker("Output sharpening", selection: $workspace.deliverOptions.outputSharpening) {
            ForEach(DeliverOutputSharpening.allCases, id: \.self) { sharpening in
              Text(sharpening.title).tag(sharpening)
            }
          }
          .accessibilityIdentifier(ModernUIAccessibility.deliverSharpeningPicker)
        }

        if !workspace.deliverOptions.unsupportedFeatures.isEmpty {
          Label(
            "Not available in the current image engine: \(workspace.deliverOptions.unsupportedFeatures.joined(separator: ", ")).",
            systemImage: "info.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(ModernUIAccessibility.deliverUnsupportedOptions)
        }

        HStack(spacing: 10) {
          Button(action: chooseDestination) {
            HStack {
              if workspace.isExporting {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: "square.and.arrow.up")
              }
              Text(
                workspace.isExporting
                  ? "Exporting…"
                  : "Export \(workspace.deliverOptions.format.title)…"
              )
              Spacer()
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(
            workspace.isExporting
              || workspace.isBatchExporting
              || !workspace.deliverOptions.unsupportedFeatures.isEmpty
          )
          .accessibilityIdentifier(ModernUIAccessibility.exportJPEGButton)

          Button(action: chooseBatchDestination) {
            if workspace.isBatchExporting {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "square.stack.3d.up")
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.large)
          .help("Export the visible Library set to a folder")
          .accessibilityLabel("Export visible Library set")
          .disabled(
            workspace.isExporting
              || workspace.isBatchExporting
              || workspace.filteredAssets.isEmpty
              || !workspace.deliverOptions.unsupportedFeatures.isEmpty
          )
          .accessibilityIdentifier(ModernUIAccessibility.deliverBatchExportButton)
        }

        if !workspace.lastBatchExports.isEmpty {
          Text("Exported \(workspace.lastBatchExports.count) photographs to the selected folder.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

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

  private var resizeEnabled: Binding<Bool> {
    Binding(
      get: {
        if case .original = workspace.deliverOptions.resize { return false }
        return true
      },
      set: { enabled in
        workspace.deliverOptions.resize = enabled ? .longEdge(2_560) : .original
      }
    )
  }

  private var longEdgePixels: Binding<Int> {
    Binding(
      get: {
        if case .longEdge(let pixels) = workspace.deliverOptions.resize { return pixels }
        return 2_560
      },
      set: { workspace.deliverOptions.resize = .longEdge($0) }
    )
  }

  private var watermarkEnabled: Binding<Bool> {
    Binding(
      get: {
        if case .none = workspace.deliverOptions.watermark { return false }
        return true
      },
      set: { enabled in
        workspace.deliverOptions.watermark = enabled ? .text("PhotoSuite") : .none
      }
    )
  }

  private var watermarkText: Binding<String> {
    Binding(
      get: {
        if case .text(let text) = workspace.deliverOptions.watermark { return text }
        return ""
      },
      set: { workspace.deliverOptions.watermark = .text($0) }
    )
  }
}

extension DeliverMetadata {
  fileprivate var title: String {
    switch self {
    case .basic: "Basic source metadata"
    case .copyrightOnly: "Copyright only"
    case .all: "All metadata"
    case .none: "No metadata"
    }
  }
}

extension DeliverOutputSharpening {
  fileprivate var title: String {
    switch self {
    case .none: "None"
    case .screenStandard: "Screen — standard"
    case .screenHigh: "Screen — high"
    case .printStandard: "Print — standard"
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
