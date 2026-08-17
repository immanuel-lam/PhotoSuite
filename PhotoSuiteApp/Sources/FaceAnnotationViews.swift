// SPDX-License-Identifier: MPL-2.0

import PhotoDomain
import PhotoWorkflow
import SwiftUI

extension ModernUIAccessibility {
  static let faceAnnotationInspector = "face-annotation-inspector"
  static let faceAnnotationList = "face-annotation-list"
  static let faceAnnotationLabelField = "face-annotation-label-field"
  static let faceAnnotationSaveButton = "face-annotation-save-button"
  static let faceAnnotationEmptyState = "face-annotation-empty-state"
}

/// A compact people-annotation inspector shared by the Library sidebar and
/// the Develop precision inspector. It edits optional user labels only; it
/// does not recognise a person or produce a biometric identity claim.
@MainActor
struct FaceAnnotationInspector: View {
  enum Placement: Sendable {
    case library
    case develop
  }

  @Bindable var workspace: PhotoWorkspace
  let placement: Placement

  @State private var isExpanded = true
  @State private var draftLabel = ""

  init(workspace: PhotoWorkspace, placement: Placement = .develop) {
    self.workspace = workspace
    self.placement = placement
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      annotationContent
        .padding(.top, 4)
    } label: {
      HStack(spacing: 8) {
        Label("People", systemImage: "person.2")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 4)
        if !workspace.selectedAssetFaces.isEmpty {
          Text(workspace.selectedAssetFaces.count, format: .number)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.callout.weight(.medium))
    .task(id: workspace.selectedAssetID) {
      await workspace.loadSelectedAssetFaces()
      syncDraftLabel()
    }
    .onChange(of: workspace.selectedFaceID) { _, _ in
      syncDraftLabel()
    }
    .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationInspector)
  }

  @ViewBuilder
  private var annotationContent: some View {
    if workspace.selectedAsset == nil {
      Text("Select a photograph to inspect face annotations.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationEmptyState)
    } else if !workspace.supportsPeopleMetadata {
      Text("This catalog does not support durable face annotations.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationEmptyState)
    } else if workspace.selectedAssetFaces.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Label("No face annotations", systemImage: "person.crop.circle.badge.questionmark")
          .font(.caption.weight(.medium))
        Text("Vision geometry and labels appear here when available. Names are optional metadata.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationEmptyState)
    } else {
      FaceAnnotationSurface {
        VStack(alignment: .leading, spacing: 10) {
          faceList
          if let face = workspace.selectedFace {
            Divider()
            labelEditor(for: face)
          }
        }
      }
    }
  }

  private var faceList: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(workspace.selectedAssetFaces) { face in
        Button {
          workspace.selectFace(face.id)
        } label: {
          HStack(spacing: 8) {
            Image(
              systemName: workspace.selectedFaceID == face.id
                ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(workspace.selectedFaceID == face.id ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
              Text(face.label ?? "Unlabelled")
                .lineLimit(1)
              Text(faceDetail(face))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationList)
  }

  private func labelEditor(for face: PhotoFace) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Optional label")
        .font(.caption.weight(.medium))
      TextField("Name this person", text: $draftLabel)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationLabelField)
      Text("PhotoSuite stores this as user metadata. It does not infer identity.")
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Button("Save Label") {
          Task { await workspace.saveFaceLabel(draftLabel, for: face.id) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityIdentifier(ModernUIAccessibility.faceAnnotationSaveButton)
        Button("Clear") {
          draftLabel = ""
          Task { await workspace.saveFaceLabel(nil, for: face.id) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        Button {
          Task { await workspace.deleteFaceAnnotation(face.id) }
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Delete this face annotation")
        .accessibilityLabel("Delete face annotation")
      }
    }
  }

  private func faceDetail(_ face: PhotoFace) -> String {
    var detail = face.source == .vision ? "Vision geometry" : "User geometry"
    if let confidence = face.confidence {
      detail += " · \(confidence.formatted(.percent.precision(.fractionLength(0)))) confidence"
    }
    return detail
  }

  private func syncDraftLabel() {
    draftLabel = workspace.selectedFace?.label ?? ""
  }
}

private struct FaceAnnotationSurface<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    if #available(macOS 26.0, *) {
      GlassEffectContainer(spacing: 8) {
        content()
          .padding(10)
          .glassEffect(.regular, in: .rect(cornerRadius: 12))
      }
    } else {
      content()
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
    }
  }
}
