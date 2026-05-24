import SwiftUI

public struct SideBySideDiffView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var showAllRows = false
    let path: String
    let diff: String

    private let initialRowLimit = 800

    private var rows: [SideBySideDiffRow] {
        UnifiedDiffParser.rows(from: diff)
    }

    private var visibleRows: [SideBySideDiffRow] {
        showAllRows ? rows : Array(rows.prefix(initialRowLimit))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleRows) { row in
                        DiffRowView(row: row)
                    }
                    if rows.count > initialRowLimit {
                        Button {
                            showAllRows.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: showAllRows ? "chevron.up" : "chevron.down")
                                Text(showAllRows ? "Show first \(initialRowLimit) rows" : "Show \(rows.count - initialRowLimit) more rows")
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.panel)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                    }
                }
                .padding(8)
                .frame(minWidth: 720, alignment: .leading)
            }
        }
        .background(theme.editor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(theme.accent)
            Text(path)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text("\(rows.count) rows")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.muted)
            Button {
                store.isDiffViewerVisible = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Diff")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(theme.panel)
    }
}

private struct DiffRowView: View {
    @Environment(\.airCodeTheme) private var theme
    let row: SideBySideDiffRow

    var body: some View {
        if row.kind == .header || row.kind == .hunk || row.kind == .folded {
            metadataRow
        } else {
            HStack(spacing: 0) {
                lineNumber(row.leftLine)
                Text(row.leftText)
                    .frame(width: 300, alignment: .leading)
                    .padding(.horizontal, 8)
                Divider().overlay(theme.border)
                lineNumber(row.rightLine)
                Text(row.rightText)
                    .frame(width: 300, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .font(.caption.monospaced())
            .frame(height: 24)
            .foregroundStyle(foreground)
            .background(background)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if row.kind == .folded {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.muted)
            }
            Text(row.text)
                .font(.caption.monospaced())
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 690, height: 25, alignment: .leading)
        .foregroundStyle(row.kind == .hunk ? theme.accent : theme.muted)
        .background(row.kind == .hunk ? theme.accent.opacity(0.12) : theme.panel.opacity(0.55))
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(theme.muted)
            .frame(width: 42, alignment: .trailing)
            .padding(.trailing, 6)
            .background(theme.panel.opacity(0.65))
    }

    private var foreground: Color {
        switch row.kind {
        case .added: return theme.green
        case .removed: return theme.red
        default: return theme.foreground
        }
    }

    private var background: Color {
        switch row.kind {
        case .added: return theme.green.opacity(0.12)
        case .removed: return theme.red.opacity(0.12)
        default: return Color.clear
        }
    }
}
