// SPDX-License-Identifier: MPL-2.0

import PhotoDomain
import PhotoWorkflow
import SwiftUI

@MainActor
struct LibraryFolderControls: View {
  @Bindable var workspace: PhotoWorkspace
  @State private var expandedIDs: Set<UUID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("FOLDERS")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
          .tracking(0.7)
        Spacer()
        Button {
          Task {
            await workspace.createDurableFolder(
              named: "Folder \(workspace.folders.count + 1)",
              parentID: workspace.activeFolderID
            )
          }
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.plain)
        .help("Create a Library folder")
        .accessibilityIdentifier("new-library-folder")
      }

      Button {
        workspace.selectFolder(nil)
      } label: {
        HStack {
          Label("All Folders", systemImage: "folder")
          Spacer()
          Text(workspace.assets.count, format: .number)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .font(.callout)

      if workspace.folders.isEmpty {
        Text("No saved folders")
          .font(.caption)
          .foregroundStyle(.tertiary)
      } else {
        ForEach(rootFolders) { folder in
          LibraryFolderRow(
            workspace: workspace,
            folder: folder,
            expandedIDs: $expandedIDs,
            depth: 0
          )
        }
      }
    }
    .accessibilityIdentifier("library-folder-controls")
  }

  private var rootFolders: [LibraryFolder] {
    workspace.folders.filter { $0.parentID == nil }
  }
}

@MainActor
private struct LibraryFolderRow: View {
  @Bindable var workspace: PhotoWorkspace
  let folder: LibraryFolder
  @Binding var expandedIDs: Set<UUID>
  let depth: Int

  private var children: [LibraryFolder] {
    workspace.folders.filter { $0.parentID == folder.id }
  }

  private var assetCount: Int {
    let ids = workspace.folderIDs(including: folder.id)
    return ids.reduce(into: Set<UUID>()) { result, id in
      result.formUnion(workspace.folderAssetIDs[id] ?? [])
    }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        if !children.isEmpty {
          Button {
            if expandedIDs.contains(folder.id) {
              expandedIDs.remove(folder.id)
            } else {
              expandedIDs.insert(folder.id)
            }
          } label: {
            Image(systemName: expandedIDs.contains(folder.id) ? "chevron.down" : "chevron.right")
              .font(.caption2.weight(.bold))
              .frame(width: 14, height: 20)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(expandedIDs.contains(folder.id) ? "Collapse folder" : "Expand folder")
        } else {
          Color.clear.frame(width: 14, height: 20)
        }

        Button {
          workspace.selectFolder(folder.id)
        } label: {
          HStack {
            Label(
              folder.name,
              systemImage: workspace.activeFolderID == folder.id ? "folder.fill" : "folder"
            )
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(assetCount, format: .number)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .padding(.vertical, 2)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .accessibilityAddTraits(workspace.activeFolderID == folder.id ? .isSelected : [])
      }
      .padding(.leading, CGFloat(depth) * 16)

      if expandedIDs.contains(folder.id) {
        ForEach(children) { child in
          LibraryFolderRow(
            workspace: workspace,
            folder: child,
            expandedIDs: $expandedIDs,
            depth: depth + 1
          )
        }
      }
    }
  }
}

@MainActor
struct LibraryFolderAssignmentControls: View {
  @Bindable var workspace: PhotoWorkspace
  let asset: PhotoAsset

  var body: some View {
    Menu {
      Button {
        Task { await workspace.assignAsset(asset.id, toFolder: nil) }
      } label: {
        Label("No Folder", systemImage: "tray")
      }
      if !workspace.folders.isEmpty {
        Divider()
        ForEach(workspace.folders) { folder in
          Button {
            Task { await workspace.assignAsset(asset.id, toFolder: folder.id) }
          } label: {
            Label(workspace.folderPath(for: folder), systemImage: "folder")
          }
        }
      }
    } label: {
      Label(currentFolderName, systemImage: "folder")
        .font(.caption)
        .lineLimit(1)
    }
    .menuStyle(.borderlessButton)
    .help("Assign this photograph to a Library folder")
    .accessibilityIdentifier("library-folder-assignment")
  }

  private var currentFolderName: String {
    guard
      let folderID = workspace.folderAssetIDs.first(where: { $0.value.contains(asset.id) })?.key,
      let folder = workspace.folders.first(where: { $0.id == folderID })
    else {
      return "No Folder"
    }
    return workspace.folderPath(for: folder)
  }
}
