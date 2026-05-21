import SwiftUI

public struct SideBySideDiffView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let path: String
    let diff: String

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(path)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    store.isDiffViewerVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(theme.panel)
            Divider().overlay(theme.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line))
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: String(line)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(background(for: String(line)))
                    }
                }
                .padding(8)
            }
        }
        .background(theme.editor)
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") { return theme.green }
        if line.hasPrefix("-") { return theme.red }
        return theme.foreground
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") { return theme.green.opacity(0.12) }
        if line.hasPrefix("-") { return theme.red.opacity(0.12) }
        return Color.clear
    }
}
