// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import AppKit
import ImageIO
import MapKit
import PhotoWorkflow
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ProfessionalWorkspaceView: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    HStack(spacing: 0) {
      ProfessionalToolRail(workspace: workspace)
        .frame(width: 250)
        .padding(.leading, 14)
        .padding(.vertical, 14)

      ProfessionalToolDetail(workspace: workspace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.top, 50)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier(ModernUIAccessibility.professionalWorkspace)
  }
}

@MainActor
private struct ProfessionalToolRail: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Workspace")
          .font(.system(size: 26, weight: .bold))
        Text("Professional tools and capability status")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 18)
      .padding(.top, 18)
      .padding(.bottom, 16)

      Divider().padding(.horizontal, 12)

      VStack(spacing: 4) {
        ForEach(ProfessionalTool.allCases) { tool in
          Button {
            workspace.professionalTool = tool
          } label: {
            HStack(spacing: 11) {
              Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
              Text(tool.title)
                .fontWeight(workspace.professionalTool == tool ? .semibold : .regular)
              Spacer()
              ProfessionalStatusIndicator(status: workspace.professionalStatus(for: tool))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(.rect)
            .background(
              workspace.professionalTool == tool ? Color.accentColor.opacity(0.14) : .clear,
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(tool.title), \(workspace.professionalStatus(for: tool).label)")
          .accessibilityAddTraits(workspace.professionalTool == tool ? .isSelected : [])
        }
      }
      .padding(10)

      Spacer()

      Text("Unavailable operations stay disabled until a tested native adapter is installed.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(18)
    }
    .modifier(NavigationGlassSurface(cornerRadius: 22))
    .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
    .accessibilityIdentifier(ModernUIAccessibility.professionalToolRail)
  }
}

private struct ProfessionalStatusIndicator: View {
  let status: ProfessionalCapabilityStatus

  var body: some View {
    Circle()
      .fill(status.indicatorColor)
      .frame(width: 7, height: 7)
      .accessibilityHidden(true)
  }
}

@MainActor
private struct ProfessionalToolDetail: View {
  @Bindable var workspace: PhotoWorkspace

  @ViewBuilder
  var body: some View {
    switch workspace.professionalTool {
    case .map:
      ProfessionalMapView(workspace: workspace)
    case .tether:
      TetherStatusView(workspace: workspace)
    case .print:
      PrintToolView(workspace: workspace)
    case .book:
      ProfessionalOutputToolView(
        workspace: workspace,
        tool: .book,
        description: "Create a portable PDF book from the active Library selection. "
          + "Each page contains a colour-managed rendered photograph and caption."
      )
    case .slideshow:
      ProfessionalOutputToolView(
        workspace: workspace,
        tool: .slideshow,
        description: "Create a silent H.264 slideshow movie from the active Library selection."
      )
    case .webGallery:
      ProfessionalOutputToolView(
        workspace: workspace,
        tool: .webGallery,
        description: "Create a self-contained static WebKit gallery for local hosting or upload."
      )
    case .plugins:
      UnavailableToolView(
        tool: .plugins,
        status: workspace.professionalStatus(for: .plugins),
        action: "Open Plug-in Manager"
      )
    case .adobeMigration:
      UnavailableToolView(
        tool: .adobeMigration,
        status: workspace.professionalStatus(for: .adobeMigration),
        action: "Choose Lightroom Catalog"
      )
    }
  }
}

@MainActor
private struct ProfessionalMapView: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    ZStack(alignment: .topLeading) {
      if workspace.isLoadingPhotoLocations {
        ProgressView("Reading photograph locations…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if workspace.photoLocations.isEmpty {
        ContentUnavailableView(
          "No Photograph Locations",
          systemImage: "map",
          description: Text(ProfessionalCapabilityBlocker.locationMetadataUnavailable.message)
        )
      } else {
        Map {
          ForEach(workspace.photoLocations) { location in
            Marker(
              location.filename,
              coordinate: CLLocationCoordinate2D(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
              )
            )
          }
        }
        .mapStyle(.standard)
      }

      ProfessionalHeader(
        title: "Map",
        subtitle: locationSummary,
        symbol: ProfessionalTool.map.symbol
      )
      .padding(20)
    }
    .task(id: workspace.assets.map(\.id)) {
      await workspace.loadPhotoLocations()
    }
    .accessibilityIdentifier(ModernUIAccessibility.professionalMap)
  }

  private var locationSummary: String {
    let count = workspace.photoLocations.count
    return count == 1 ? "1 photograph with GPS metadata" : "\(count) photographs with GPS metadata"
  }
}

@MainActor
private struct TetherStatusView: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var cameraNames: [String] = []
  @State private var nativeDevices: [CaptureDeviceStatus] = []
  @State private var discovery: ImageCaptureCoreCameraDiscovery?
  @State private var cameraError: String?
  @State private var importReview: LibraryImportReview?

  var body: some View {
    ProfessionalStatusSurface(
      tool: .tether,
      status: workspace.professionalStatus(for: .tether)
    ) {
      VStack(alignment: .leading, spacing: 12) {
        Text("AVFoundation camera discovery")
          .font(.headline)
        if cameraNames.isEmpty {
          Text("No external video device is visible to AVFoundation.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(cameraNames, id: \.self) { name in
            Label(name, systemImage: "camera")
          }
        }
        Divider()
        Text("ImageCaptureCore")
          .font(.headline)
        if nativeDevices.isEmpty {
          Text(
            "No ImageCaptureCore camera is connected. Vendor SDK adapters can be installed separately."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        } else {
          ForEach(nativeDevices) { device in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                  .font(.callout.weight(.medium))
                Text(device.state.displayName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Capture") {
                do {
                  try discovery?.requestCapture(deviceID: device.id)
                } catch {
                  cameraError = error.localizedDescription
                }
              }
              .buttonStyle(.bordered)
              .disabled(!device.supportsTetheredCapture || device.state == .capturing)
            }
          }
        }
        if let cameraError {
          Label(cameraError, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Text(
          "Physical camera transfer and vendor-specific controls remain subject to the installed adapter."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
    .task {
      refreshDevices()
      #if canImport(ImageCaptureCore)
        let adapter = ImageCaptureCoreCameraDiscovery()
        discovery = adapter
        adapter.start()
        nativeDevices = adapter.devices
        for await change in adapter.makeEventStream() {
          nativeDevices = adapter.devices
          if case .mediaAdded(let deviceID, let items) = change {
            importReview = LibraryImportReview(
              deviceID: deviceID,
              mediaItems: items,
              existingAssets: workspace.assets
            )
          }
        }
      #endif
    }
    .onDisappear {
      discovery?.stop()
      discovery = nil
    }
    .sheet(item: $importReview) { review in
      LibraryImportReviewView(
        review: review,
        onImport: { items in
          let urls = items.compactMap(\.fileURL)
          guard !urls.isEmpty else {
            cameraError = "The camera did not provide local file URLs for the selected media."
            return
          }
          Task { @MainActor in
            await workspace.importURLs(urls)
          }
        },
        onCancel: {}
      )
    }
  }

  private func refreshDevices() {
    cameraNames = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.external],
      mediaType: .video,
      position: .unspecified
    ).devices.map(\.localizedName)
  }
}

@MainActor
private struct PrintToolView: View {
  @Bindable var workspace: PhotoWorkspace

  var body: some View {
    ProfessionalStatusSurface(
      tool: .print,
      status: workspace.professionalStatus(for: .print)
    ) {
      PhotoProofPreview(preview: workspace.preview)
        .frame(maxWidth: 700, minHeight: 360, maxHeight: 520)
      Button("Print Photograph…") { runPrintPanel() }
        .buttonStyle(.borderedProminent)
        .disabled(workspace.preview == nil)
    }
  }

  private func runPrintPanel() {
    guard let data = workspace.preview?.imageData, let image = NSImage(data: data) else { return }
    let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    NSPrintOperation(view: imageView).run()
  }
}

@MainActor
private struct ProfessionalOutputToolView: View {
  @Bindable var workspace: PhotoWorkspace
  let tool: ProfessionalTool
  let description: String

  @State private var draft: ProfessionalOutputDraft
  @State private var exportTask: Task<Void, Never>?

  init(workspace: PhotoWorkspace, tool: ProfessionalTool, description: String) {
    self.workspace = workspace
    self.tool = tool
    self.description = description
    _draft = State(initialValue: ProfessionalOutputDraft(tool: tool))
  }

  var body: some View {
    ProfessionalStatusSurface(tool: tool, status: workspace.professionalStatus(for: tool)) {
      Text(description)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 700, alignment: .leading)
      PhotoProofPreview(preview: workspace.preview)
        .frame(maxWidth: 700, minHeight: 360, maxHeight: 520)
      outputSettings
      outputActions
      if let output = workspace.lastProfessionalOutput {
        Label("Published \(output.lastPathComponent)", systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.green)
          .textSelection(.enabled)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputResult)
      }
      if let error = workspace.errorMessage, !error.isEmpty {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputError)
      }
    }
    .onDisappear { exportTask?.cancel() }
  }

  @ViewBuilder
  private var outputSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Output settings", systemImage: "slider.horizontal.3")
        .font(.headline)

      switch tool {
      case .book:
        TextField("Book title", text: $draft.title)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputTitle)
        TextField("Author (optional)", text: $draft.author)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputAuthor)
        Picker("Page size", selection: $draft.pageSize) {
          ForEach(PhotoBookPageSize.allCases, id: \.self) { size in
            Text(size.displayTitle).tag(size)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(ModernUIAccessibility.professionalOutputPageSize)
      case .slideshow:
        TextField("Slideshow title", text: $draft.title)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputTitle)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Seconds per slide")
            Spacer()
            Text("\(draft.slideshowDuration, specifier: "%.1f") s")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(value: $draft.secondsPerSlide, in: 0.1...30, step: 0.1)
            .accessibilityIdentifier(ModernUIAccessibility.professionalOutputDuration)
        }
        Picker("Frame rate", selection: $draft.framesPerSecond) {
          ForEach([15, 24, 25, 30, 50, 60], id: \.self) { rate in
            Text("\(rate) fps").tag(rate)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(ModernUIAccessibility.professionalOutputFrameRate)
        HStack(spacing: 12) {
          Stepper(value: $draft.canvasWidth, in: 320...16_384, step: 10) {
            Text("Width \(draft.canvasWidth) px")
              .monospacedDigit()
          }
          Stepper(value: $draft.canvasHeight, in: 180...16_384, step: 10) {
            Text("Height \(draft.canvasHeight) px")
              .monospacedDigit()
          }
        }
        .accessibilityIdentifier(ModernUIAccessibility.professionalOutputCanvas)
      case .webGallery:
        TextField("Gallery title", text: $draft.title)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputTitle)
        TextField("Subtitle (optional)", text: $draft.subtitle)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputSubtitle)
        Toggle("Limit image size", isOn: $draft.galleryMaximumDimensionEnabled)
        Stepper(value: $draft.galleryMaximumDimension, in: 256...32_768, step: 256) {
          Text("Maximum \(draft.galleryMaximumDimension) px")
            .monospacedDigit()
        }
        .disabled(!draft.galleryMaximumDimensionEnabled)
        .accessibilityIdentifier(ModernUIAccessibility.professionalOutputMaximumDimension)
      default:
        EmptyView()
      }
    }
    .frame(maxWidth: 700, alignment: .leading)
    .padding(18)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.78),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
    }
    .accessibilityIdentifier(ModernUIAccessibility.professionalOutputSettings)
  }

  private var outputActions: some View {
    HStack(spacing: 12) {
      GlassControlGroup {
        Button(actionTitle) { presentSavePanel() }
          .modifier(GlassButtonWhenAvailable(prominent: true))
          .disabled(
            workspace.isProfessionalExporting
              || workspace.professionalOutputAssets.isEmpty
          )
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputStart)
        if workspace.isProfessionalExporting {
          Button("Cancel") {
            exportTask?.cancel()
          }
          .modifier(GlassButtonWhenAvailable())
          .accessibilityIdentifier(ModernUIAccessibility.professionalOutputCancel)
        }
      }
      if workspace.isProfessionalExporting {
        ProgressView("Rendering and publishing…")
          .controlSize(.small)
          .accessibilityLabel("Rendering and publishing")
      }
    }
  }

  private var actionTitle: String {
    switch tool {
    case .book: "Export PDF Book…"
    case .slideshow: "Export Slideshow…"
    case .webGallery: "Export Web Gallery…"
    default: "Export…"
    }
  }

  private func presentSavePanel() {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    switch tool {
    case .book:
      panel.title = "Export PDF Book"
      panel.allowedContentTypes = [.pdf]
      panel.nameFieldStringValue = "PhotoSuite-Book.pdf"
    case .slideshow:
      panel.title = "Export Slideshow"
      panel.allowedContentTypes = [.quickTimeMovie]
      panel.nameFieldStringValue = "PhotoSuite-Slideshow.mov"
    case .webGallery:
      panel.title = "Export Web Gallery"
      panel.allowedContentTypes = [.folder]
      panel.nameFieldStringValue = "PhotoSuite-Gallery"
    default:
      return
    }
    panel.begin { response in
      guard response == .OK, let destination = panel.url else { return }
      beginExport(to: destination)
    }
  }

  private func beginExport(to destination: URL) {
    exportTask?.cancel()
    let exportTool = tool
    let exportDraft = draft
    let exportWorkspace = workspace
    exportTask = Task { @MainActor in
      switch exportTool {
      case .book:
        await exportWorkspace.exportBook(
          to: destination,
          title: exportDraft.normalizedTitle,
          author: exportDraft.normalizedAuthor,
          pageSize: exportDraft.pageSize
        )
      case .slideshow:
        await exportWorkspace.exportSlideshow(
          to: destination,
          title: exportDraft.normalizedTitle,
          secondsPerSlide: exportDraft.slideshowDuration,
          framesPerSecond: exportDraft.slideshowFrameRate,
          canvas: exportDraft.slideshowCanvas
        )
      case .webGallery:
        await exportWorkspace.exportWebGallery(
          to: destination,
          title: exportDraft.normalizedTitle,
          subtitle: exportDraft.normalizedSubtitle,
          maximumPixelDimension: exportDraft.galleryMaximumPixelDimension
        )
      default:
        break
      }
    }
  }
}

private struct UnavailableToolView: View {
  let tool: ProfessionalTool
  let status: ProfessionalCapabilityStatus
  let action: String

  var body: some View {
    ProfessionalStatusSurface(tool: tool, status: status) {
      Button(action) {}
        .disabled(true)
    }
  }
}

private struct ProfessionalStatusSurface<Content: View>: View {
  let tool: ProfessionalTool
  let status: ProfessionalCapabilityStatus
  @ViewBuilder let content: Content

  init(
    tool: ProfessionalTool,
    status: ProfessionalCapabilityStatus,
    @ViewBuilder content: () -> Content
  ) {
    self.tool = tool
    self.status = status
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ProfessionalHeader(title: tool.title, subtitle: status.message, symbol: tool.symbol)
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(32)
    }
    .accessibilityIdentifier(ModernUIAccessibility.professionalStatus)
  }
}

private struct ProfessionalHeader: View {
  let title: String
  let subtitle: String
  let symbol: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .semibold))
        .frame(width: 42, height: 42)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 30, weight: .bold))
        Text(subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .modifier(NavigationGlassSurface(cornerRadius: 18))
  }
}

private struct PhotoProofPreview: View {
  let preview: PreviewFrame?

  var body: some View {
    ZStack {
      Color(white: 0.14)
      if let image = previewImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .padding(24)
      } else {
        ContentUnavailableView(
          "No Photograph Selected",
          systemImage: "photo",
          description: Text("Select a photograph to prepare this proof.")
        )
        .foregroundStyle(.white.opacity(0.78))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
    }
  }

  private var previewImage: NSImage? {
    preview.flatMap { NSImage(data: $0.imageData) }
  }
}

extension ProfessionalTool {
  fileprivate var title: String {
    switch self {
    case .map: "Map"
    case .tether: "Tethered Capture"
    case .print: "Print"
    case .book: "Book"
    case .slideshow: "Slideshow"
    case .webGallery: "Web Gallery"
    case .plugins: "Plug-ins"
    case .adobeMigration: "Adobe Migration"
    }
  }

  fileprivate var symbol: String {
    switch self {
    case .map: "map"
    case .tether: "camera.viewfinder"
    case .print: "printer"
    case .book: "book.closed"
    case .slideshow: "play.rectangle"
    case .webGallery: "globe"
    case .plugins: "puzzlepiece.extension"
    case .adobeMigration: "arrow.trianglehead.2.clockwise.rotate.90"
    }
  }
}

extension PhotoBookPageSize {
  fileprivate var displayTitle: String {
    switch self {
    case .a4: "A4"
    case .letter: "US Letter"
    case .square: "Square"
    }
  }
}

extension ProfessionalCapabilityStatus {
  fileprivate var label: String {
    switch self {
    case .available: "Available"
    case .previewOnly: "Preview only"
    case .unavailable: "Unavailable"
    }
  }

  fileprivate var message: String {
    switch self {
    case .available:
      "Available with the current photograph."
    case .previewOnly(let blocker), .unavailable(let blocker):
      blocker.message
    }
  }

  fileprivate var indicatorColor: Color {
    switch self {
    case .available: .green
    case .previewOnly: .orange
    case .unavailable: .secondary
    }
  }
}

extension ProfessionalCapabilityBlocker {
  fileprivate var message: String {
    switch self {
    case .locationMetadataUnavailable:
      "No valid GPS metadata is available for catalog photographs."
    case .selectionRequired:
      "Select a photograph and wait for its preview."
    case .cameraAdapterRequired:
      "Camera discovery is available. Tethered still capture needs a tested camera adapter."
    case .bookExportUnavailable:
      "PDF book export is available with the current page settings. Advanced templates and print-order services are not implemented."
    case .webPublishingUnavailable:
      "Local gallery proof is available. Hosting and publishing are not implemented."
    case .pluginHostUnavailable:
      "No signed plug-in host or supported plug-in SDK is installed."
    case .adobeCatalogParserUnavailable:
      "No tested Adobe Lightroom catalog parser is installed."
    }
  }
}

extension CaptureDeviceState {
  fileprivate var displayName: String {
    switch self {
    case .discovered: "Discovered"
    case .ready: "Ready"
    case .capturing: "Capturing"
    case .unavailable(let reason): "Unavailable: \(reason)"
    case .failed(let reason): "Failed: \(reason)"
    }
  }
}
