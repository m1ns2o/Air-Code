import SwiftUI

public struct AgentChatView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var promptFocused = false
    @State private var prompt = ""

    private let agents = [
        AgentOption(id: "codex", name: "Codex", symbol: "sparkles"),
        AgentOption(id: "claude", name: "Claude", symbol: "circle.hexagongrid"),
        AgentOption(id: "opencode", name: "OpenCode", symbol: "terminal")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            transcript
            Divider().overlay(theme.border)
            composer
        }
        .background(theme.panel)
        .foregroundStyle(theme.foreground)
    }

    private var header: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text("Chat")
                    .font(.headline)
                agentMenu
                sessionMenu
                Spacer()
                if store.activeRunId != nil {
                    Button {
                        Task { await store.stopAgent() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Stop")
                }
            }
            runStatusBar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var runStatusBar: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            Spacer()
            if store.eventConnectionState != .connected {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(theme.yellow)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if store.agentMessages.isEmpty {
                        emptyState
                    }
                    ForEach(store.agentMessages) { message in
                        TranscriptMessageRow(message: message)
                            .id(message.id)
                    }
                    if let transient = store.transientAgentText, store.isAgentStreaming {
                        StreamingScratchpad(agentName: store.displayName(for: store.currentAgentName ?? store.selectedAgent), text: transient)
                            .id("agent-transient")
                    } else if store.isAgentStreaming {
                        StreamingIndicator(agentName: store.displayName(for: store.currentAgentName ?? store.selectedAgent))
                            .id("agent-streaming")
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .onChange(of: store.agentMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.transientAgentText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.isAgentStreaming) { _, _ in scrollToBottom(proxy) }
        }
        .background(theme.editor.opacity(theme.isLight ? 0.45 : 0.28))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "message.badge")
                .font(.title2)
                .foregroundStyle(theme.accent)
            Text("No conversation yet.")
                .font(.callout.weight(.semibold))
            Text(store.connectionState == .connected ? "Ask \(selectedAgent.name)" : "Waiting for server connection.")
                .font(.caption)
                .foregroundStyle(theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(promptPlaceholder)
                        .font(.body)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                PromptInputView(text: $prompt, isFocused: $promptFocused, theme: theme) {
                    submitPrompt()
                }
                .frame(minHeight: 76, maxHeight: 132)
                .background(Color.clear)
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .background(theme.editor)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(promptFocused ? theme.accent : theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            composerToolbar
        }
        .padding(10)
        .background(theme.panel)
    }

    private var composerToolbar: some View {
        HStack(spacing: 6) {
            codexModelMenu
            modeMenu
            reasoningMenu
            TogglePill(
                title: "Caveman",
                symbol: store.isCavemanEnabled ? "bolt.fill" : "bolt",
                isOn: store.isCavemanEnabled
            ) {
                store.setCavemanEnabled(!store.isCavemanEnabled)
            }
            Spacer(minLength: 4)
            Button {
                submitPrompt()
            } label: {
                Image(systemName: store.activeRunId == nil ? "arrow.up" : "hourglass")
                    .font(.headline)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .background(canSubmit ? theme.accent : theme.elevated)
            .foregroundStyle(canSubmit ? theme.background : theme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canSubmit)
            .accessibilityLabel("Run")
        }
    }

    private var agentMenu: some View {
        Menu {
            ForEach(agents) { agent in
                Button {
                    store.selectedAgent = agent.id
                } label: {
                    Label(agent.name, systemImage: agent.symbol)
                }
            }
        } label: {
            ControlPill(title: selectedAgent.name, symbol: selectedAgent.symbol, active: false)
        }
        .buttonStyle(.plain)
    }

    private var codexModelMenu: some View {
        Menu {
            ForEach(CodexModelOption.allCases) { model in
                Button {
                    store.setCodexModel(model)
                } label: {
                    Label(model.title, systemImage: model == .auto ? "sparkles" : "cpu")
                }
            }
        } label: {
            ControlPill(
                title: store.selectedCodexModel.title,
                symbol: store.selectedCodexModel == .auto ? "sparkles" : "cpu",
                active: store.selectedCodexModel != .auto
            )
        }
        .buttonStyle(.plain)
    }

    private var modeMenu: some View {
        Menu {
            ForEach(AgentMode.allCases) { mode in
                Button {
                    store.setAgentMode(mode)
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                }
            }
        } label: {
            ControlPill(title: store.selectedAgentMode.title, symbol: store.selectedAgentMode.symbol, active: store.selectedAgentMode != .agent)
        }
        .buttonStyle(.plain)
    }

    private var reasoningMenu: some View {
        Menu {
            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    store.setReasoningEffort(effort)
                } label: {
                    Label(effort.title, systemImage: effort.symbol)
                }
            }
        } label: {
            ControlPill(
                title: store.selectedReasoningEffort.title,
                symbol: store.selectedReasoningEffort.symbol,
                active: store.selectedReasoningEffort != .auto
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionMenu: some View {
        Menu {
            Button {
                store.setResumeAgentSession(!store.resumeAgentSession)
            } label: {
                Label(store.resumeAgentSession ? "Start New Next" : "Continue Session", systemImage: store.resumeAgentSession ? "plus.message" : "arrow.clockwise")
            }
            if store.selectedAgentSession != nil {
                Button(role: .destructive) {
                    Task { await store.clearSelectedAgentSession() }
                } label: {
                    Label("Forget Session", systemImage: "trash")
                }
            }
        } label: {
            ControlPill(
                title: sessionTitle,
                symbol: store.resumeAgentSession ? "arrow.clockwise" : "plus.message",
                active: store.resumeAgentSession && store.selectedAgentSession != nil
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionTitle: String {
        guard store.resumeAgentSession else { return "New" }
        return store.selectedAgentSession == nil ? "Session" : "Continue"
    }

    private var selectedAgent: AgentOption {
        agents.first(where: { $0.id == store.selectedAgent }) ?? agents[0]
    }

    private var promptPlaceholder: String {
        switch store.selectedAgentMode {
        case .goal:
            return "Goal: objective and stopping condition"
        case .plan:
            return "Plan with \(selectedAgent.name)"
        case .agent:
            return "Ask \(selectedAgent.name)"
        }
    }

    private var canSubmit: Bool {
        store.activeRunId == nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.connectionState == .connected
    }

    private var statusText: String {
        switch store.agentRunStatus {
        case .idle:
            return store.connectionState == .connected ? "Ready" : "Disconnected"
        case .starting:
            return "Starting \(selectedAgent.name)"
        case .running:
            return "\(store.displayName(for: store.currentAgentName ?? store.selectedAgent)) running"
        case .completed:
            return "Completed"
        case .failed:
            return store.lastAgentError ?? "Failed"
        case .stopped:
            return "Stopped"
        }
    }

    private var statusColor: Color {
        switch store.agentRunStatus {
        case .idle:
            return store.connectionState == .connected ? theme.green : theme.muted
        case .starting, .running:
            return theme.accent
        case .completed:
            return theme.green
        case .failed:
            return theme.red
        case .stopped:
            return theme.yellow
        }
    }

    private func submitPrompt() {
        guard canSubmit else { return }
        let value = prompt
        prompt = ""
        promptFocused = false
        Task { await store.runAgent(prompt: value) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

private extension AirCodeStore {
    var isAgentStreaming: Bool {
        activeRunId != nil && (agentRunStatus == .starting || agentRunStatus == .running)
    }
}

private struct TranscriptMessageRow: View {
    let message: AgentMessage

    var body: some View {
        if message.role == .changes {
            ChangeListMessage(changes: message.changes)
        } else {
            AgentMessageRow(message: message)
        }
    }
}

private struct StreamingIndicator: View {
    @Environment(\.airCodeTheme) private var theme
    let agentName: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
            Text("\(agentName) is thinking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
            StreamingDots()
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StreamingScratchpad: View {
    @Environment(\.airCodeTheme) private var theme
    let agentName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.accent)
                Text("\(agentName) is working")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                Spacer()
            }
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(theme.muted)
                .lineLimit(3)
        }
        .padding(10)
        .background(theme.elevated.opacity(0.82))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StreamingDots: View {
    @State private var phase = 0

    var body: some View {
        Text(String(repeating: ".", count: phase + 1))
            .font(.caption.monospacedDigit())
            .frame(width: 20, alignment: .leading)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(350))
                    phase = (phase + 1) % 3
                }
            }
    }
}

private struct ChangeListMessage: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var expanded = false
    let changes: [GitChange]

    private var visibleChanges: [GitChange] {
        expanded ? changes : Array(changes.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "square.split.2x1")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                Text("Changes")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(changes.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.muted)
                Button {
                    Task { await store.revert(paths: changes.map(\.path)) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Revert These Changes")
            }
            ForEach(visibleChanges) { change in
                ChangeRow(change: change)
            }
            if changes.count > 3 {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                        Text(expanded ? "Collapse scaffold" : "Scaffold hidden: \(changes.count - 3) more")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(theme.elevated)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
            }
        }
        .padding(9)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChangeRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let change: GitChange

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(kind.color(theme))
                .frame(width: 16)
            Text(kind.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(kind.color(theme))
                .frame(width: 58, alignment: .leading)
            Button {
                Task { await store.loadDiff(path: change.path) }
            } label: {
                Text(change.path)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                Task { await store.revert(path: change.path) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Revert \(change.path)")
            Button {
                Task { await store.loadDiff(path: change.path) }
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.caption)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Open Diff")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(kind.color(theme).opacity(theme.isLight ? 0.12 : 0.16))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(kind.color(theme).opacity(0.28)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var kind: ChangeKind {
        ChangeKind(status: change.status)
    }
}

private enum ChangeKind {
    case added
    case modified
    case deleted
    case renamed
    case conflicted
    case unknown

    init(status: String) {
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("U") {
            self = .conflicted
        } else if value.contains("D") {
            self = .deleted
        } else if value.contains("R") {
            self = .renamed
        } else if value.contains("A") || value.contains("??") {
            self = .added
        } else if value.contains("M") {
            self = .modified
        } else {
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .conflicted: return "Conflict"
        case .unknown: return "Changed"
        }
    }

    var symbol: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .conflicted: return "exclamationmark.triangle.fill"
        case .unknown: return "circle.dashed"
        }
    }

    func color(_ theme: AirCodeTheme) -> Color {
        switch self {
        case .added: return theme.green
        case .modified: return theme.yellow
        case .deleted: return theme.red
        case .renamed: return theme.blue
        case .conflicted: return theme.orange
        case .unknown: return theme.muted
        }
    }
}

private struct AgentMessageRow: View {
    @Environment(\.airCodeTheme) private var theme
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 28)
                bubble
            } else {
                icon
                bubble
                if message.role == .agent {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.caption)
            .foregroundStyle(iconColor)
            .frame(width: 18, height: 18)
            .padding(.top, 7)
    }

    private var bubble: some View {
        Text(message.text)
            .font(font)
            .transcriptTextSelection()
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: message.role == .user ? 280 : .infinity, alignment: .leading)
            .background(background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var font: Font {
        switch message.role {
        case .agent:
            return .system(.body, design: .monospaced)
        case .status, .error:
            return .caption
        case .user:
            return .body
        case .changes:
            return .caption
        }
    }

    private var background: Color {
        switch message.role {
        case .user:
            return theme.accent.opacity(theme.isLight ? 0.20 : 0.16)
        case .agent:
            return theme.elevated
        case .status:
            return theme.panel
        case .error:
            return theme.red.opacity(0.14)
        case .changes:
            return theme.panel
        }
    }

    private var foreground: Color {
        switch message.role {
        case .status:
            return theme.muted
        case .error:
            return theme.red
        default:
            return theme.foreground
        }
    }

    private var border: Color {
        switch message.role {
        case .error:
            return theme.red.opacity(0.5)
        case .status, .changes:
            return theme.border
        default:
            return Color.clear
        }
    }

    private var iconName: String {
        switch message.role {
        case .agent:
            return "sparkles"
        case .error:
            return "exclamationmark.triangle.fill"
        case .status:
            return "checkmark.circle"
        case .user:
            return "person.crop.circle"
        case .changes:
            return "square.split.2x1"
        }
    }

    private var iconColor: Color {
        message.role == .error ? theme.red : theme.accent
    }
}

private struct ControlPill: View {
    @Environment(\.airCodeTheme) private var theme
    let title: String
    let symbol: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(active ? theme.accent : theme.muted)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(active ? theme.accent.opacity(0.22) : theme.elevated)
        .foregroundStyle(active ? theme.accent : theme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct TogglePill: View {
    @Environment(\.airCodeTheme) private var theme
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isOn ? theme.accent.opacity(0.22) : theme.elevated)
            .foregroundStyle(isOn ? theme.accent : theme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentOption: Identifiable {
    let id: String
    let name: String
    let symbol: String
}

private extension View {
    @ViewBuilder
    func transcriptTextSelection() -> some View {
        #if os(macOS)
        textSelection(.enabled)
        #else
        self
        #endif
    }
}
