import SwiftUI

public struct ProjectSidebarView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(theme.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    workspaceSection
                    Divider()
                        .overlay(theme.border)
                        .padding(.vertical, 6)
                    ForEach(store.treeEntries["."] ?? []) { entry in
                        TreeNodeView(entry: entry, depth: 0)
                            .environmentObject(store)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .background(theme.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Explorer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                Text(store.selectedProject?.name ?? "No Folder")
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                if !store.projects.isEmpty {
                    Section("Open Projects") {
                        ForEach(store.projects) { project in
                            Button {
                                Task {
                                    store.selectedProject = project
                                    store.treeEntries.removeAll()
                                    await store.loadTree(path: ".", project: project)
                                    await store.refreshGitStatus()
                                }
                            } label: {
                                Label(project.name, systemImage: "folder")
                            }
                        }
                    }
                }
                Section("Workspace Roots") {
                    ForEach(store.workspaceRoots) { root in
                        Button {
                            Task {
                                await store.loadWorkspaceTree(rootId: root.id, path: ".")
                            }
                        } label: {
                            Label(root.name, systemImage: "externaldrive")
                        }
                    }
                }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 28, height: 28)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Remote Folder")
        }
        .padding(10)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Remote Folders")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.muted)
                Spacer()
                if let root = store.workspaceRoots.first(where: { $0.id == store.selectedWorkspaceRootID }) {
                    Text(root.name)
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            ForEach(store.workspaceTreeEntries["."] ?? []) { entry in
                WorkspaceFolderNode(entry: entry, depth: 0)
                    .environmentObject(store)
            }
        }
    }
}

private struct TreeNodeView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await store.open(entry: entry) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                        .font(.caption)
                        .foregroundStyle(entry.isDirectory ? theme.accent : theme.muted)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth * 12))
                .padding(.horizontal, 6)
                .frame(height: 26)
                .background(store.selectedFilePath == entry.path ? theme.elevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if entry.isDirectory, let children = store.treeEntries[entry.path] {
                ForEach(children) { child in
                    TreeNodeView(entry: child, depth: depth + 1)
                }
            }
        }
    }
}

private struct WorkspaceFolderNode: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let depth: Int

    var body: some View {
        if entry.isDirectory {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Button {
                        Task { await store.loadWorkspaceTree(path: entry.path) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.workspaceTreeEntries[entry.path] == nil ? "chevron.right" : "chevron.down")
                                .font(.caption2)
                                .frame(width: 10)
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundStyle(theme.accent)
                            Text(entry.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.leading, CGFloat(depth * 12))
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await store.openWorkspaceFolder(path: entry.path) }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.muted)
                    .accessibilityLabel("Open \(entry.name)")
                }
                .background(theme.elevated.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if let children = store.workspaceTreeEntries[entry.path] {
                    ForEach(children.filter(\.isDirectory)) { child in
                        WorkspaceFolderNode(entry: child, depth: depth + 1)
                    }
                }
            }
        }
    }
}
