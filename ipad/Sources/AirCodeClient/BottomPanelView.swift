import SwiftUI

public struct BottomPanelView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var terminalIMEText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            switch store.selectedBottomPanelTab {
            case .terminal:
                terminalBody
            case .problems:
                problemsBody
            }
        }
        .background(theme.terminalBackground)
        .task(id: store.selectedProject?.id) {
            await store.ensureTerminal()
        }
        .task(id: store.connectionState.rawValue) {
            await store.ensureTerminal()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            bottomPanelTabButton(.terminal, title: "Terminal", systemImage: "terminal")
            bottomPanelTabButton(.problems, title: "Problems", systemImage: "exclamationmark.triangle")
            if store.selectedBottomPanelTab == .terminal {
                statusBadge
            } else {
                problemCountBadge
            }
            Spacer()
            if store.selectedBottomPanelTab == .terminal {
                terminalActions
            } else {
                Button {
                    Task { await store.refreshLSPDiagnostics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Refresh Problems")
            }
        }
        .padding(8)
        .background(theme.terminalBackground)
    }

    private func bottomPanelTabButton(_ tab: AirCodeStore.BottomPanelTab, title: String, systemImage: String) -> some View {
        Button {
            store.selectedBottomPanelTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .frame(height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.selectedBottomPanelTab == tab ? theme.foreground : theme.muted)
        .background(store.selectedBottomPanelTab == tab ? theme.elevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var terminalActions: some View {
        HStack(spacing: 4) {
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
    }

    private var terminalBody: some View {
        VStack(spacing: 0) {
            ZStack {
                RemoteTerminalView(
                    output: store.terminalOutput,
                    theme: theme,
                    onInput: { store.sendTerminalInput($0) },
                    onResize: { cols, rows in store.resizeTerminal(cols: cols, rows: rows) }
                )
                .background(theme.terminalBackground)

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
            #if os(iOS) || os(visionOS)
            terminalIMEBar
            #endif
        }
    }

    #if os(iOS) || os(visionOS)
    private var terminalIMEBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
                .frame(width: 20)
            TextField("IME input", text: $terminalIMEText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
                .foregroundStyle(theme.foreground)
                .lineLimit(1...3)
                .submitLabel(.return)
                .onSubmit {
                    sendTerminalIMEText(appendingNewline: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Button {
                pasteTerminalIMEText()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Paste To Terminal IME Input")
            Button {
                sendTerminalIMEText(appendingNewline: false)
            } label: {
                Image(systemName: "arrow.right")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(terminalIMEText.isEmpty ? theme.muted.opacity(0.45) : theme.accent)
            .disabled(terminalIMEText.isEmpty)
            .accessibilityLabel("Send Terminal IME Text")
            Button {
                sendTerminalIMEText(appendingNewline: true)
            } label: {
                Image(systemName: "return")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .accessibilityLabel("Send Terminal Return")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.terminalBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }

    private func sendTerminalIMEText(appendingNewline: Bool) {
        let text = terminalIMEText + (appendingNewline ? "\n" : "")
        guard !text.isEmpty else { return }
        store.sendTerminalText(text)
        terminalIMEText = ""
    }

    private func pasteTerminalIMEText() {
        guard let paste = UIPasteboard.general.string, !paste.isEmpty else { return }
        terminalIMEText += paste
    }
    #endif

    private var problemsBody: some View {
        Group {
            if store.allLSPProblems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(theme.green)
                    Text("No Problems")
                        .font(.caption.weight(.semibold))
                    if let message = store.lspStatusMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.terminalBackground)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.allLSPProblems) { problem in
                            HStack(spacing: 4) {
                                Button {
                                    Task { await store.openLSPProblem(problem) }
                                } label: {
                                    problemRow(problem)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    Task { await store.applyFirstLSPCodeAction(for: problem) }
                                } label: {
                                    Image(systemName: "wand.and.sparkles")
                                        .font(.caption.weight(.semibold))
                                        .frame(width: 30, height: 30)
                                        .background(theme.elevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.accent)
                                .accessibilityLabel("Apply Quick Fix")
                            }
                        }
                    }
                    .padding(8)
                }
                .background(theme.terminalBackground)
            }
        }
    }

    private func problemRow(_ problem: LSPProblem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: problemIcon(problem.diagnostic))
                .font(.caption.weight(.semibold))
                .foregroundStyle(problemColor(problem.diagnostic))
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(problem.diagnostic.message)
                    .font(.caption)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(problem.path)
                        .lineLimit(1)
                    Text("\(problem.diagnostic.range.start.line + 1):\(problem.diagnostic.range.start.character + 1)")
                }
                .font(.caption2.monospaced())
                .foregroundStyle(theme.muted)
            }
            Spacer(minLength: 8)
            Text(problem.diagnostic.severityTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(problemColor(problem.diagnostic))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var problemCountBadge: some View {
        Text("\(store.allLSPProblems.count)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func problemIcon(_ diagnostic: LSPDiagnostic) -> String {
        switch diagnostic.severity {
        case 1:
            return "xmark.octagon.fill"
        case 2:
            return "exclamationmark.triangle.fill"
        default:
            return "info.circle.fill"
        }
    }

    private func problemColor(_ diagnostic: LSPDiagnostic) -> Color {
        switch diagnostic.severity {
        case 1:
            return theme.red
        case 2:
            return theme.yellow
        default:
            return theme.accent
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
