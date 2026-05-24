import SwiftUI

public struct EditorPaneView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider().overlay(theme.border)
            if store.isDiffViewerVisible {
                SideBySideDiffView(path: store.selectedDiffPath ?? "Diff", diff: store.selectedDiff)
                    .environmentObject(store)
            } else if let selected = bindingForSelectedFile {
                NativeCodeEditor(text: selected, path: store.selectedFilePath ?? "")
                    .background(theme.editor)
            } else if store.selectedProject == nil {
                RecentProjectsView()
                    .environmentObject(store)
            } else {
                ContentUnavailableView("No File", systemImage: "doc.text", description: Text("Open a file from the folder tree."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.editor)
            }
        }
        .background(theme.editor)
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(store.openFiles) { file in
                    Button {
                        store.selectedFilePath = file.path
                        store.isDiffViewerVisible = false
                    } label: {
                        HStack(spacing: 6) {
                            Text((file.path as NSString).lastPathComponent)
                                .font(.caption)
                            if file.isDirty {
                                Circle()
                                    .fill(theme.yellow)
                                    .frame(width: 6, height: 6)
                            }
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .onTapGesture {
                                    store.close(path: file.path)
                                }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(store.selectedFilePath == file.path ? theme.elevated : theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(theme.panel)
    }

    private var bindingForSelectedFile: Binding<String>? {
        guard let path = store.selectedFilePath,
              let index = store.openFiles.firstIndex(where: { $0.path == path }) else { return nil }
        return Binding(
            get: { store.openFiles[index].content },
            set: { store.openFiles[index].content = $0 }
        )
    }
}

private struct RecentProjectsView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Recent")
                        .font(.title2.weight(.semibold))
                    Text("Choose a remote folder from this server or open a new one.")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Button {
                    store.showOpenFolderPicker()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }

            if store.recentProjects.isEmpty {
                ContentUnavailableView("No Recent Projects", systemImage: "clock", description: Text("Open a remote folder to pin it here for the next launch."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.recentProjects) { recent in
                            RecentProjectRow(recent: recent)
                                .environmentObject(store)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.editor)
    }
}

private struct RecentProjectRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let recent: RecentProjectSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            Button {
                Task { await store.openRecentProject(recent) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(recent.path == "." ? recent.rootId : "\(recent.rootId) / \(recent.path)")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                Task { await store.forgetRecentProject(recent) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Remove \(recent.name) from recent projects")
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
