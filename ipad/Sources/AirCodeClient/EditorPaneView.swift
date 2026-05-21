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
