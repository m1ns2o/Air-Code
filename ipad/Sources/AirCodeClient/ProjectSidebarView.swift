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
            Button {
                store.showOpenFolderPicker()
            } label: {
                Image(systemName: "folder")
                    .frame(width: 28, height: 28)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Remote Folder")
        }
        .padding(10)
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

struct RemoteFolderPickerView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRootID: String?
    @State private var selectedPath = "."
    @State private var isNewFolderPresented = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            if store.workspaceRoots.isEmpty {
                ContentUnavailableView("No Remote Roots", systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.panel)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        rootRow
                        ForEach((store.workspaceTreeEntries["."] ?? []).filter(\.isDirectory)) { entry in
                            RemoteFolderPickerNode(entry: entry, depth: 0, selectedPath: $selectedPath)
                                .environmentObject(store)
                        }
                    }
                    .padding(10)
                }
                .background(theme.panel)
            }
            Divider().overlay(theme.border)
            footer
        }
        .frame(minWidth: 440, minHeight: 520)
        .background(theme.panel)
        .foregroundStyle(theme.foreground)
        .task {
            if selectedRootID == nil {
                selectedRootID = store.selectedWorkspaceRootID ?? store.workspaceRoots.first?.id
            }
            if let selectedRootID {
                await store.loadWorkspaceTree(rootId: selectedRootID, path: ".")
            }
        }
        .alert("New Folder", isPresented: $isNewFolderPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createAndOpenFolder()
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Create under \(displayPath(selectedPath)) and open it.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(theme.accent)
            Text("Open Folder")
                .font(.headline)
            Spacer()
            if store.workspaceRoots.count > 1 {
                Picker("Root", selection: rootBinding) {
                    ForEach(store.workspaceRoots) { root in
                        Text(root.name).tag(Optional(root.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.accent)
            } else if let root = selectedRoot {
                Text(root.name)
                    .font(.caption)
                    .foregroundStyle(theme.muted)
            }
            Button {
                newFolderName = ""
                isNewFolderPresented = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 28, height: 28)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(selectedRootID == nil)
            .accessibilityLabel("Create New Folder")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(displayPath(selectedPath))
                .font(.caption)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.borderless)
            Button {
                Task {
                    await store.openWorkspaceFolder(rootId: selectedRootID, path: selectedPath)
                    store.hideOpenFolderPicker()
                    dismiss()
                }
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(selectedRootID == nil)
        }
        .padding(12)
    }

    private var rootRow: some View {
        Button {
            selectedPath = "."
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(theme.accent)
                Text(selectedRoot?.name ?? "Workspace Root")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if selectedPath == "." {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selectedPath == "." ? theme.elevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var rootBinding: Binding<String?> {
        Binding(
            get: { selectedRootID },
            set: { newValue in
                selectedRootID = newValue
                selectedPath = "."
                if let newValue {
                    Task { await store.loadWorkspaceTree(rootId: newValue, path: ".") }
                }
            }
        )
    }

    private var selectedRoot: WorkspaceRootSummary? {
        store.workspaceRoots.first { $0.id == selectedRootID }
    }

    private func displayPath(_ path: String) -> String {
        path == "." ? selectedRoot?.name ?? "Workspace Root" : path
    }

    private func createAndOpenFolder() {
        let name = newFolderName
        Task {
            let didOpen = await store.createAndOpenWorkspaceFolder(rootId: selectedRootID, parentPath: selectedPath, name: name)
            if didOpen {
                store.hideOpenFolderPicker()
                dismiss()
            }
            newFolderName = ""
        }
    }
}

private struct RemoteFolderPickerNode: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let depth: Int
    @Binding var selectedPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    Task { await store.loadWorkspaceTree(path: entry.path) }
                } label: {
                    Image(systemName: store.workspaceTreeEntries[entry.path] == nil ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .frame(width: 14, height: 26)
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    selectedPath = entry.path
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                        Text(entry.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if selectedPath == entry.path {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.trailing, 8)
                    .frame(height: 26)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth * 14))
            .padding(.horizontal, 4)
            .background(selectedPath == entry.path ? theme.elevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let children = store.workspaceTreeEntries[entry.path] {
                ForEach(children.filter(\.isDirectory)) { child in
                    RemoteFolderPickerNode(entry: child, depth: depth + 1, selectedPath: $selectedPath)
                }
            }
        }
    }
}
