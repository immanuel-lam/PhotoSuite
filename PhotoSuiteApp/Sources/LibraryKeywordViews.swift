// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct LibraryKeywordControls: View {
  @Bindable var workspace: PhotoWorkspace
  let asset: PhotoAsset

  @State private var selectedIDs: Set<UUID> = []
  @State private var isExpanded = false

  private var selectedNames: String {
    let names = workspace.selectedAssetKeywords.map { workspace.keywordPath(for: $0) }
    return names.isEmpty ? "No keywords" : names.joined(separator: ", ")
  }

  var body: some View {
    DisclosureGroup("Keywords", isExpanded: $isExpanded) {
      if workspace.keywordNodes.isEmpty {
        Text("No keyword nodes in this catalog")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(workspace.keywordNodes) { keyword in
            Button {
              if selectedIDs.contains(keyword.id) {
                selectedIDs.remove(keyword.id)
              } else {
                selectedIDs.insert(keyword.id)
              }
            } label: {
              HStack(spacing: 8) {
                Image(
                  systemName: selectedIDs.contains(keyword.id) ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(selectedIDs.contains(keyword.id) ? Color.accentColor : .secondary)
                Text(workspace.keywordPath(for: keyword))
                  .lineLimit(1)
                Spacer(minLength: 0)
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
          }
        }
        Button("Apply Keywords") {
          Task { await workspace.assignKeywords(to: asset.id, keywordIDs: Array(selectedIDs)) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("library.keywords.apply")
      }
      Text(selectedNames)
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(2)
    }
    .font(.callout.weight(.medium))
    .task(id: asset.id) {
      selectedIDs = Set(workspace.selectedAssetKeywords.map(\.id))
    }
    .onChange(of: workspace.selectedAssetKeywords) { _, keywords in
      selectedIDs = Set(keywords.map(\.id))
    }
    .accessibilityIdentifier("library.keywords")
  }
}

@MainActor
struct LibraryVirtualCopyControls: View {
  @Bindable var workspace: PhotoWorkspace
  let asset: PhotoAsset

  @State private var isExpanded = false
  @State private var newName = ""

  private var copies: [VirtualCopy] {
    workspace.virtualCopies.filter { $0.sourceAssetID == asset.id }
  }

  var body: some View {
    DisclosureGroup("Virtual Copies", isExpanded: $isExpanded) {
      if copies.isEmpty {
        Text("No virtual copies")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(copies) { copy in
          Button {
            Task { await workspace.selectVirtualCopy(copy.id) }
          } label: {
            HStack(spacing: 8) {
              Image(
                systemName: workspace.selectedVirtualCopyID == copy.id
                  ? "checkmark.circle.fill" : "circle"
              )
              .foregroundStyle(
                workspace.selectedVirtualCopyID == copy.id ? Color.accentColor : .secondary
              )
              Text(copy.name)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
      }

      HStack(spacing: 6) {
        TextField("Copy name", text: $newName)
          .textFieldStyle(.roundedBorder)
        Button {
          let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
          let fallback = "Copy \(copies.count + 1)"
          Task {
            await workspace.createVirtualCopy(named: name.isEmpty ? fallback : name)
            newName = ""
          }
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Create virtual copy")
      }

      if let selectedID = workspace.selectedVirtualCopyID,
        copies.contains(where: { $0.id == selectedID })
      {
        Button("Delete Selected Copy", role: .destructive) {
          Task { await workspace.deleteVirtualCopy(selectedID) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .font(.callout.weight(.medium))
    .accessibilityIdentifier("library.virtual-copies")
  }
}
