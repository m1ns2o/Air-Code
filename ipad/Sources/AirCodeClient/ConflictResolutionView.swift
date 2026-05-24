import SwiftUI

public struct ConflictResolutionView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let conflict: FileConflict
    @State private var saveAsPath: String

    public init(conflict: FileConflict) {
        self.conflict = conflict
        _saveAsPath = State(initialValue: ConflictSavePath.suggestedPath(for: conflict.path))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            HStack(spacing: 0) {
                conflictPane(title: "Local", subtitle: "Your unsaved changes", content: conflict.localContent, tint: theme.green)
                Divider().overlay(theme.border)
                conflictPane(title: "Server", subtitle: "Latest remote version", content: conflict.serverContent, tint: theme.orange)
            }
            Divider().overlay(theme.border)
            footer
        }
        .background(theme.editor)
        .onChange(of: conflict.path) { _, newPath in
            saveAsPath = ConflictSavePath.suggestedPath(for: newPath)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save Conflict")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                Text(conflict.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await store.keepLocalConflict(path: conflict.path) }
            } label: {
                Label("Keep Local", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.green)
            Button {
                store.acceptServerConflict(path: conflict.path)
            } label: {
                Label("Accept Server", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(theme.panel)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Save local copy as")
                .font(.caption)
                .foregroundStyle(theme.muted)
            TextField("path", text: $saveAsPath)
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(theme.elevated)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Button {
                Task { await store.saveConflictAs(path: conflict.path, newPath: saveAsPath) }
            } label: {
                Label("Save As", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
        .padding(10)
        .background(theme.panel)
    }

    private func conflictPane(title: String, subtitle: String, content: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.foreground)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(theme.panel.opacity(0.7))
            ScrollView([.vertical, .horizontal]) {
                Text(content.isEmpty ? " " : content)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
