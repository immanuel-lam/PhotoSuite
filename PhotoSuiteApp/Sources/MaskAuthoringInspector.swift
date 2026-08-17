// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct MaskAuthoringInspector: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var selectedTool: MaskAuthoringTool = .brush
  @State private var selectedOperation: MaskCombinationOperation = .add
  @State private var selectedMaskID: UUID?

  private var selectedMask: MaskDefinition? {
    guard let selectedMaskID else { return nil }
    return workspace.currentMasks.first { $0.id == selectedMaskID }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GlassControlGroup {
        HStack(spacing: 10) {
          Image(systemName: "circle.dashed.inset.filled")
            .foregroundStyle(.tint)
          VStack(alignment: .leading, spacing: 1) {
            Text("Masks")
              .font(.headline)
            Text("Local, recipe-backed selections")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Button {
            addMask()
          } label: {
            Label("New mask", systemImage: "plus")
          }
          .modifier(GlassButtonWhenAvailable(prominent: true))
          .disabled(!selectedTool.availability.isAvailable || workspace.selectedAsset == nil)
          .accessibilityIdentifier("mask-authoring-new-mask")
        }
      }
      .padding(.bottom, 14)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          toolSection
          operationSection
          maskListSection
          Text(
            "Manual masks are stored as version-one MaskGraph recipes. Smart selections remain unavailable until a verified local model is installed."
          )
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .scrollIndicators(.hidden)
    }
    .padding(14)
    .background(Color(nsColor: .controlBackgroundColor))
    .accessibilityIdentifier(ModernUIAccessibility.maskAuthoringInspector)
    .task(id: workspace.selectedAssetID) {
      selectFirstMaskIfNeeded()
    }
    .onChange(of: workspace.currentRecipe?.revision) { _, _ in
      selectFirstMaskIfNeeded()
    }
  }

  private var toolSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Create selection")
        .font(.subheadline.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
        ForEach(MaskAuthoringTool.manualTools) { tool in
          MaskToolTile(
            tool: tool,
            isSelected: selectedTool == tool,
            action: { selectedTool = tool }
          )
        }
      }
      .accessibilityIdentifier(ModernUIAccessibility.maskAuthoringToolPicker)

      Text("Smart selections")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.top, 2)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
        ForEach(MaskAuthoringTool.smartTools) { tool in
          MaskToolTile(
            tool: tool,
            isSelected: selectedTool == tool,
            action: { selectedTool = tool }
          )
        }
      }

      if selectedTool.availability == .unavailable {
        MaskCapabilityNotice(tool: selectedTool)
      }
    }
  }

  private var operationSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Combine with mask")
        .font(.subheadline.weight(.semibold))

      Picker("Mask operation", selection: $selectedOperation) {
        ForEach([MaskCombinationOperation.add, .subtract, .intersect], id: \.self) { operation in
          Label(operation.title, systemImage: operation.systemImage)
            .tag(operation)
        }
      }
      .pickerStyle(.segmented)
      .disabled(selectedTool.availability == .unavailable || selectedMask == nil)
      .accessibilityIdentifier(ModernUIAccessibility.maskAuthoringOperationPicker)

      HStack(spacing: 8) {
        Button {
          applySelectedOperation()
        } label: {
          Label("Add to selected", systemImage: "plus.circle.fill")
        }
        .modifier(GlassButtonWhenAvailable(prominent: true))
        .disabled(
          selectedMask == nil
            || selectedTool.availability == .unavailable
            || workspace.selectedAsset == nil
        )
        .accessibilityIdentifier("mask-authoring-apply-operation")

        Button {
          guard let selectedMaskID else { return }
          Task { await workspace.toggleMaskInverted(id: selectedMaskID) }
        } label: {
          Label("Invert", systemImage: "circle.lefthalf.filled")
        }
        .modifier(GlassButtonWhenAvailable())
        .disabled(selectedMask == nil || workspace.selectedAsset == nil)
        .accessibilityIdentifier("mask-authoring-invert")
      }

      if selectedMask == nil {
        Text("Create or select a mask before adding another component.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var maskListSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("Masks in this recipe")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("\(workspace.currentMasks.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if workspace.currentMasks.isEmpty {
        ContentUnavailableView {
          Label("No masks yet", systemImage: "circle.dashed")
        } description: {
          Text("Choose a manual tool, then create a mask to store its graph in the recipe.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityIdentifier("mask-authoring-empty")
      } else {
        VStack(spacing: 6) {
          ForEach(workspace.currentMasks) { mask in
            MaskAuthoringRow(
              mask: mask,
              isSelected: selectedMaskID == mask.id,
              select: { selectedMaskID = mask.id },
              invert: { Task { await workspace.toggleMaskInverted(id: mask.id) } },
              remove: { Task { await workspace.removeMask(id: mask.id) } }
            )
          }
        }
      }
    }
  }

  private func addMask() {
    guard
      selectedTool.availability == .available,
      let assetID = workspace.selectedAssetID,
      let revision = workspace.currentRecipe?.revision,
      let mask = MaskAuthoringModel.makeMask(
        kind: selectedTool.kind,
        operation: .add
      )
    else { return }
    Task {
      await workspace.applyGeneratedMask(
        mask,
        assetID: assetID,
        expectedRevision: revision
      )
    }
  }

  private func applySelectedOperation() {
    guard
      selectedTool.availability == .available,
      let selectedMask,
      let updated = MaskAuthoringModel.append(
        to: selectedMask,
        kind: selectedTool.kind,
        operation: selectedOperation
      ),
      let graph = MaskAuthoringModel.graph(from: updated)
    else { return }
    Task { await workspace.replaceMaskGraph(id: selectedMask.id, graph: graph) }
  }

  private func selectFirstMaskIfNeeded() {
    guard let selectedMaskID, workspace.currentMasks.contains(where: { $0.id == selectedMaskID })
    else {
      selectedMaskID = workspace.currentMasks.first?.id
      return
    }
  }
}

private struct MaskToolTile: View {
  let tool: MaskAuthoringTool
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 5) {
        Image(systemName: tool.systemImage)
          .font(.title3)
          .frame(height: 22)
        Text(tool.title)
          .font(.caption.weight(.medium))
          .lineLimit(1)
        HStack(spacing: 3) {
          Text(tool.subtitle)
            .font(.caption2)
            .lineLimit(1)
          if tool.availability == .unavailable {
            Image(systemName: "lock.fill")
              .font(.caption2)
          }
        }
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 64)
      .padding(.horizontal, 5)
      .padding(.vertical, 6)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(
      tool.availability == .unavailable ? Color.secondary : Color.primary
    )
    .opacity(tool.availability == .unavailable ? 0.72 : 1)
    .help(tool.unavailableReason ?? tool.title)
  }
}

struct MaskCapabilityNotice: View {
  let tool: MaskAuthoringTool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 3) {
        Text("\(tool.title) unavailable")
          .font(.caption.weight(.semibold))
        Text(tool.unavailableReason ?? "This selection is not available in the current build.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.orange.opacity(0.35), lineWidth: 0.75)
    }
    .accessibilityIdentifier(ModernUIAccessibility.maskAuthoringUnavailable)
  }
}

private struct MaskAuthoringRow: View {
  let mask: MaskDefinition
  let isSelected: Bool
  let select: () -> Void
  let invert: () -> Void
  let remove: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 9) {
        Image(systemName: symbol(for: mask.kind))
          .frame(width: 20)
          .foregroundStyle(
            isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor)
          )
        VStack(alignment: .leading, spacing: 2) {
          Text(mask.name ?? title(for: mask.kind))
            .font(.callout.weight(.medium))
            .lineLimit(1)
          Text(mask.isInverted ? "Inverted" : "Version-one graph")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 4)
        Button(action: invert) {
          Image(systemName: mask.isInverted ? "circle.lefthalf.filled" : "circle")
        }
        .buttonStyle(.plain)
        .help(mask.isInverted ? "Use mask normally" : "Invert mask")
        .accessibilityLabel(mask.isInverted ? "Use mask normally" : "Invert mask")
        Button(role: .destructive, action: remove) {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .help("Delete mask")
        .accessibilityLabel("Delete mask")
      }
      .padding(10)
      .background(
        isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(isSelected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .contain)
  }

  private func title(for kind: MaskKind) -> String {
    switch kind {
    case .brush: "Brush"
    case .linearGradient: "Linear gradient"
    case .radialGradient: "Radial gradient"
    case .colorRange: "Colour range"
    case .luminanceRange: "Luminance range"
    case .depthRange: "Depth range"
    case .subject: "Subject"
    case .sky: "Sky"
    case .background: "Background"
    case .object: "Object"
    case .unknown(let value): value
    }
  }

  private func symbol(for kind: MaskKind) -> String {
    switch kind {
    case .brush: "paintbrush.pointed"
    case .linearGradient: "rectangle.lefthalf.inset.filled"
    case .radialGradient: "circle.dashed"
    case .colorRange: "eyedropper"
    case .luminanceRange: "sun.max"
    case .depthRange: "square.3.layers.3d"
    case .subject, .background, .object: "person.crop.rectangle"
    case .sky: "cloud.sun"
    case .unknown: "questionmark"
    }
  }
}

extension MaskCombinationOperation {
  var title: String {
    switch self {
    case .add: "Add"
    case .subtract: "Subtract"
    case .intersect: "Intersect"
    case .unknown(let value): value
    }
  }

  var systemImage: String {
    switch self {
    case .add: "plus"
    case .subtract: "minus"
    case .intersect: "square.on.square"
    case .unknown: "questionmark"
    }
  }
}
