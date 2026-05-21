import SwiftUI

public struct BottomPanelView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Terminal", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                statusBadge
                Spacer()
                Button {
                    store.clearTerminal()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Clear Terminal")
                Button {
                    Task { await store.reconnectTerminal() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Reconnect Terminal")
                Button {
                    Task { await store.closeTerminal() }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Close Terminal")
                Button {
                    Task { await store.startTerminal() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("New Terminal")
            }
            .padding(8)
            .background(theme.panel)
            Divider().overlay(theme.border)
            ZStack {
                RemoteTerminalView(
                    output: store.terminalOutput,
                    theme: theme,
                    onInput: { store.sendTerminalInput($0) },
                    onResize: { cols, rows in store.resizeTerminal(cols: cols, rows: rows) }
                )
                .background(theme.editor)

                if store.terminalConnectionState == .connecting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.accent)
                } else if store.terminalConnectionState == .failed {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.red)
                        Text(store.terminalError ?? "Terminal connection failed.")
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                    }
                }
            }
        }
        .background(theme.editor)
        .task {
            await store.ensureTerminal()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusTitle: String {
        switch store.terminalConnectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return store.terminalSession?.shell.components(separatedBy: "/").last ?? "Connected"
        case .exited:
            return "Exited"
        case .failed:
            return "Failed"
        }
    }

    private var statusColor: Color {
        switch store.terminalConnectionState {
        case .connected:
            return theme.green
        case .connecting:
            return theme.accent
        case .failed:
            return theme.red
        case .exited:
            return theme.yellow
        case .disconnected:
            return theme.muted
        }
    }
}
