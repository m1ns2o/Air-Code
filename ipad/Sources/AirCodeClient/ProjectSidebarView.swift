import SwiftUI

public struct ProjectSidebarView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var isOpenFolderPresented = false
    @State private var mode: SidebarMode = .explorer

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(theme.border)
            switch mode {
            case .explorer:
                explorer
            case .search:
                ProjectSearchView()
                    .environmentObject(store)
            }
        }
        .background(theme.panel)
        .sheet(isPresented: $isOpenFolderPresented) {
            RemoteFolderPickerView()
                .environmentObject(store)
                .environment(\.airCodeTheme, theme)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    Text(store.selectedProject?.name ?? "No Folder")
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    isOpenFolderPresented = true
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Remote Folder")
            }

            HStack(spacing: 4) {
                ForEach(SidebarMode.allCases) { item in
                    Button {
                        mode = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .labelStyle(.iconOnly)
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 26)
                            .background(mode == item ? theme.accent.opacity(0.2) : theme.elevated.opacity(0.7))
                            .foregroundStyle(mode == item ? theme.accent : theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
                Spacer()
            }
        }
        .padding(10)
    }

    private var explorer: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.treeEntries["."] ?? []) { entry in
                    TreeNodeView(entry: entry, depth: 0)
                        .environmentObject(store)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }
}

private enum SidebarMode: String, CaseIterable, Identifiable {
    case explorer
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explorer: return "Explorer"
        case .search: return "Search"
        }
    }

    var symbol: String {
        switch self {
        case .explorer: return "folder"
        case .search: return "magnifyingglass"
        }
    }
}

private struct ProjectSearchView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                TextField("Search files", text: $store.searchQuery)
                    .font(.caption)
                    .onSubmit {
                        Task { await store.searchFiles() }
                    }
                if store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(theme.editor)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 6) {
                Button {
                    Task { await store.searchFiles() }
                } label: {
                    Label("Search", systemImage: "arrow.right.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(theme.accent.opacity(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.12 : 0.22))
                .foregroundStyle(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.muted : theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.searchQuery = ""
                    store.searchResults = []
                    store.searchMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(theme.elevated)
                .foregroundStyle(theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Clear Search")
            }

            if let message = store.searchMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(message.hasPrefix("HTTP") ? theme.red : theme.muted)
                    .lineLimit(2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(store.searchResults) { result in
                        SearchResultRow(result: result)
                            .environmentObject(store)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
    }
}

private struct SearchResultRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let result: SearchResult

    var body: some View {
        Button {
            Task { await store.openSearchResult(result) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(theme.accent)
                    Text(result.path)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(result.lineNumber):\(result.column)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.muted)
                }
                Text(result.line.trimmingCharacters(in: .whitespaces))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevated.opacity(store.selectedFilePath == result.path ? 1 : 0.65))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(store.selectedFilePath == result.path ? theme.accent.opacity(0.5) : theme.border.opacity(0.55)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Menu {
                    ForEach(store.workspaceRoots) { root in
                        Button {
                            selectRoot(root.id)
                        } label: {
                            Label(root.name, systemImage: root.id == selectedRootID ? "checkmark" : (root.pinned ? "star.fill" : "externaldrive"))
                        }
                    }
                } label: {
                    Label(selectedRoot?.name ?? "Root", systemImage: "externaldrive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.button)
            } else if let root = selectedRoot {
                Text(root.name)
                    .font(.caption)
                    .foregroundStyle(theme.muted)
            }
            if let root = selectedRoot {
                Button {
                    Task { await store.toggleWorkspaceRootPinned(root) }
                } label: {
                    Image(systemName: root.pinned ? "star.fill" : "star")
                        .frame(width: 28, height: 28)
                        .background(theme.elevated)
                        .foregroundStyle(root.pinned ? theme.yellow : theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(root.pinned ? "Unpin Workspace Root" : "Pin Workspace Root")
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
                if selectedRoot?.pinned == true {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.yellow)
                }
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

    private var selectedRoot: WorkspaceRootSummary? {
        store.workspaceRoots.first { $0.id == selectedRootID }
    }

    private func selectRoot(_ rootID: String) {
        selectedRootID = rootID
        selectedPath = "."
        Task { await store.loadWorkspaceTree(rootId: rootID, path: ".") }
    }

    private func displayPath(_ path: String) -> String {
        path == "." ? selectedRoot?.name ?? "Workspace Root" : path
    }

    private func createAndOpenFolder() {
        let name = newFolderName
        Task {
            let didOpen = await store.createAndOpenWorkspaceFolder(rootId: selectedRootID, parentPath: selectedPath, name: name)
            if didOpen {
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
