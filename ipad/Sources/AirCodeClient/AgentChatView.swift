import SwiftUI

public struct AgentChatView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var promptFocused = false
    @State private var prompt = ""
    @State private var promptHistory = PromptHistoryNavigator()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            if let activeGoal = store.activeGoal {
                ActiveGoalCard(goal: activeGoal)
                    .environmentObject(store)
                Divider().overlay(theme.border)
            }
            if store.isPermissionPanelVisible, let snapshot = store.permissionSnapshot {
                PermissionPolicyCard(snapshot: snapshot)
                    .environmentObject(store)
                Divider().overlay(theme.border)
            }
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
                modelSettingsMenu
                Spacer()
                sessionMenu
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

    private struct ActiveGoalCard: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme
        let goal: ActiveGoal

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundStyle(statusColor)
                    Text("Active Goal")
                        .font(.caption.weight(.semibold))
                    Text(goal.status.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(statusColor.opacity(0.16))
                        .foregroundStyle(statusColor)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Spacer()
                    Button {
                        Task { await store.resumeActiveGoal() }
                    } label: {
                        Image(systemName: "play.fill")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume Active Goal")
                    Button {
                        Task { await store.clearActiveGoal() }
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Active Goal")
                }
                Text(goal.objective)
                    .font(.caption)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Label(store.displayName(for: goal.agent), systemImage: "sparkles")
                    if let model = goal.model, !model.isEmpty {
                        Label(model, systemImage: "cpu")
                    }
                    Label(shortRunId(goal.runId), systemImage: "number")
                }
                .font(.caption2)
                .foregroundStyle(theme.muted)
            }
            .padding(10)
            .background(theme.elevated.opacity(0.65))
        }

        private var statusColor: Color {
            switch goal.status {
            case "running": return theme.yellow
            case "completed": return theme.green
            case "failed": return theme.red
            case "stopped": return theme.orange
            default: return theme.accent
            }
        }

        private func shortRunId(_ runId: String) -> String {
            guard runId.count > 12 else { return runId }
            return "\(runId.prefix(8))...\(runId.suffix(4))"
        }
    }

    private struct PermissionPolicyCard: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme
        let snapshot: PermissionSnapshot

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .foregroundStyle(theme.accent)
                    Text("Permissions")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        Task { await store.loadPermissionSnapshot(showPanel: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Permissions")
                    Button {
                        store.closePermissionPanel()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Permissions")
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.agents) { policy in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(riskColor(policy.riskLevel))
                                .frame(width: 7, height: 7)
                            Text(policy.displayName)
                                .font(.caption.weight(.semibold))
                            Text(policy.enabled ? "enabled" : "disabled")
                                .font(.caption2)
                                .foregroundStyle(policy.enabled ? theme.green : theme.muted)
                            Spacer()
                            Text(policy.approvalMode)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.muted)
                            Text(policy.sandboxMode)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Label(snapshot.commandPolicy.terminalEnabled ? "Terminal on" : "Terminal off", systemImage: "terminal")
                    Label("\(snapshot.commandPolicy.maxSessions) sessions", systemImage: "rectangle.stack")
                    if !snapshot.commandPolicy.allowedCommands.isEmpty {
                        Label("\(snapshot.commandPolicy.allowedCommands.count) commands", systemImage: "checklist")
                    }
                }
                .font(.caption2)
                .foregroundStyle(theme.muted)
            }
            .padding(10)
            .background(theme.elevated.opacity(0.65))
        }

        private func riskColor(_ riskLevel: String) -> Color {
            switch riskLevel {
            case "high": return theme.red
            case "medium": return theme.yellow
            default: return theme.green
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

    @ViewBuilder
    private var emptyState: some View {
        if let session = store.selectedAgentSession, selectedAgent.supportsSession {
            savedSessionEmptyState(session)
        } else {
            defaultEmptyState
        }
    }

    private func savedSessionEmptyState(_ session: AgentSessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved session available.")
                        .font(.callout.weight(.semibold))
                    Text(sessionSummary(session))
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
            Text(store.resumeAgentSession ? "Your next prompt will continue this session." : "Your next prompt will start a new session.")
                .font(.caption)
                .foregroundStyle(theme.muted)
            HStack(spacing: 7) {
                Button {
                    store.setResumeAgentSession(true)
                } label: {
                    Label("Continue", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(store.resumeAgentSession ? theme.accent.opacity(0.22) : theme.elevated)
                .foregroundStyle(store.resumeAgentSession ? theme.accent : theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    store.setResumeAgentSession(false)
                } label: {
                    Label("New", systemImage: "plus.message")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(!store.resumeAgentSession ? theme.accent.opacity(0.22) : theme.elevated)
                .foregroundStyle(!store.resumeAgentSession ? theme.accent : theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var defaultEmptyState: some View {
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
            if shouldShowSlashCommands {
                slashCommandPalette
            } else if shouldShowMentionSuggestions {
                mentionPalette
            }
            if shouldShowContextBar {
                contextAttachmentBar
            }
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(promptPlaceholder)
                        .font(.body)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                PromptInputView(
                    text: $prompt,
                    isFocused: $promptFocused,
                    theme: theme,
                    onHistoryPrevious: recallPreviousPrompt,
                    onHistoryNext: recallNextPrompt
                ) {
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

    private var slashCommandPalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text("Commands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                Spacer()
                Text("Tap to insert")
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            ForEach(slashCommandSuggestions) { command in
                Button {
                    acceptSlashCommand(command)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: command.symbol)
                            .font(.callout)
                            .foregroundStyle(theme.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(command.command)
                                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(theme.foreground)
                                Text(command.title)
                                    .font(.caption)
                                    .foregroundStyle(theme.muted)
                                if let badge = command.badge {
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.yellow)
                                        .padding(.horizontal, 5)
                                        .frame(height: 18)
                                        .background(theme.yellow.opacity(0.13))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                            Text(command.detail)
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.editor)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composerToolbar: some View {
        HStack(spacing: 6) {
            modeMenu
            reasoningMenu
            speedMenu
            TogglePill(
                title: "Context",
                symbol: store.isAutoContextEnabled ? "paperclip" : "paperclip.circle",
                isOn: store.isAutoContextEnabled
            ) {
                store.setAutoContextEnabled(!store.isAutoContextEnabled)
            }
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

    private var mentionPalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                Text("Files")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                Spacer()
                Text("Attach as context")
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            ForEach(mentionSuggestions) { suggestion in
                Button {
                    acceptMentionSuggestion(suggestion)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: suggestion.isOpen ? "doc.text.fill" : "doc.text")
                            .font(.callout)
                            .foregroundStyle(suggestion.isOpen ? theme.accent : theme.muted)
                            .frame(width: 20)
                        Text(suggestion.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.foreground)
                            .lineLimit(1)
                        Spacer()
                        if suggestion.isOpen {
                            Text("open")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.editor)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var contextAttachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if store.isAutoContextEnabled {
                    ContextChip(title: autoContextTitle, symbol: "paperclip", removable: false) {}
                }
                ForEach(store.pendingContextAttachments) { attachment in
                    ContextChip(title: attachment.path, symbol: "at", removable: true) {
                        store.removeContextAttachment(id: attachment.id)
                    }
                }
                if !store.pendingContextAttachments.isEmpty {
                    Button {
                        store.clearContextAttachments()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.muted)
                    .accessibilityLabel("Clear context attachments")
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var modelSettingsMenu: some View {
        Menu {
            switch store.selectedAgent {
            case "hermes":
                Menu {
                    ForEach(HermesProviderOption.allCases) { provider in
                        Button {
                            store.setHermesProvider(provider)
                        } label: {
                            Label(provider.menuTitle, systemImage: provider.symbol)
                        }
                    }
                } label: {
                    Label("Provider: \(store.selectedHermesProvider.title)", systemImage: store.selectedHermesProvider.symbol)
                }
                Menu {
                    ForEach(HermesModelOption.allCases) { model in
                        Button {
                            store.setHermesModel(model)
                        } label: {
                            Label(model.menuTitle, systemImage: model.symbol)
                        }
                    }
                } label: {
                    Label("Model: \(store.selectedHermesModel.title)", systemImage: store.selectedHermesModel.symbol)
                }
                Button {
                    store.setHermesProvider(.auto)
                    store.setHermesModel(.auto)
                } label: {
                    Label("Use Hermes Defaults", systemImage: "arrow.counterclockwise")
                }
            case "codex":
                Section("Codex Model") {
                    ForEach(CodexModelOption.allCases) { model in
                        Button {
                            store.setCodexModel(model)
                        } label: {
                            Label(model.title, systemImage: model == .auto ? "sparkles" : "cpu")
                        }
                    }
                }
            case "claude":
                Section("Claude Model") {
                    ForEach(ClaudeModelOption.allCases) { model in
                        Button {
                            store.setClaudeModel(model)
                        } label: {
                            Label(model.title, systemImage: model == .auto ? "sparkles" : "circle.hexagongrid")
                        }
                    }
                }
            default:
                Label("\(selectedAgent.name) uses server model settings.", systemImage: "server.rack")
            }
        } label: {
            ControlPill(title: modelSettingsTitle, symbol: modelSettingsSymbol, active: modelSettingsActive)
        }
        .menuStyle(.button)
    }

    private var agentMenu: some View {
        Menu {
            ForEach(agentOptions) { agent in
                Button {
                    Task { await store.selectAgent(agent.id) }
                } label: {
                    Label(agent.menuTitle, systemImage: agent.symbol)
                }
                .disabled(!agent.isSelectable)
            }
        } label: {
            ControlPill(title: selectedAgent.name, symbol: selectedAgent.symbol, active: false)
        }
        .menuStyle(.button)
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
        .menuStyle(.button)
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
        .menuStyle(.button)
    }

    private var speedMenu: some View {
        Menu {
            Section("Speed") {
                ForEach(AgentSpeedMode.allCases) { speedMode in
                    Button {
                        store.setSpeedMode(speedMode)
                    } label: {
                        Label(speedMenuLabel(speedMode), systemImage: speedMode.symbol)
                    }
                    .disabled(!speedMode.isSupported(by: store.selectedAgent))
                }
            }
            if store.selectedAgent == "claude" {
                Label("Claude Fast requires Claude Code 2.1.36+ and Opus 4.6/4.7, so Air Code leaves Claude speed at provider default.", systemImage: "info.circle")
            } else if store.selectedAgent != "codex" {
                Label("Speed overrides are currently available for Codex only.", systemImage: "info.circle")
            }
        } label: {
            ControlPill(
                title: selectedSpeedModeTitle,
                symbol: store.selectedSpeedMode.symbol,
                active: store.selectedSpeedMode != .auto && store.selectedSpeedMode.isSupported(by: store.selectedAgent)
            )
        }
        .menuStyle(.button)
    }

    private var sessionMenu: some View {
        Menu {
            if selectedAgent.supportsSession {
                if let session = store.selectedAgentSession {
                    Section("Saved Session") {
                        Label(shortSessionID(session.sessionId), systemImage: "number")
                        if let lastMode = session.lastMode, !lastMode.isEmpty {
                            Label("Last mode: \(lastMode)", systemImage: "list.bullet.clipboard")
                        }
                        if let effort = session.reasoningEffort, !effort.isEmpty {
                            Label("Reasoning: \(effort)", systemImage: "brain")
                        }
                        if let speed = session.speedMode, !speed.isEmpty {
                            Label("Speed: \(speed)", systemImage: "speedometer")
                        }
                    }
                    Button {
                        store.setResumeAgentSession(true)
                    } label: {
                        Label("Continue Saved Session", systemImage: "arrow.clockwise")
                    }
                    Button {
                        store.setResumeAgentSession(false)
                    } label: {
                        Label("Start New Session", systemImage: "plus.message")
                    }
                    Button(role: .destructive) {
                        Task { await store.clearSelectedAgentSession() }
                    } label: {
                        Label("Forget Session", systemImage: "trash")
                    }
                } else {
                    Label("No saved session", systemImage: "tray")
                    Button {
                        store.setResumeAgentSession(true)
                    } label: {
                        Label("Auto-continue Future Session", systemImage: "arrow.clockwise")
                    }
                }
                Button {
                    Task { await store.loadAgentSessions() }
                } label: {
                    Label("Refresh Sessions", systemImage: "arrow.clockwise.circle")
                }
            } else {
                Label("Session resume unavailable", systemImage: "nosign")
            }
        } label: {
            ControlPill(
                title: sessionTitle,
                symbol: store.resumeAgentSession ? "arrow.clockwise" : "plus.message",
                active: selectedAgent.supportsSession && store.resumeAgentSession && store.selectedAgentSession != nil
            )
        }
        .menuStyle(.button)
        .disabled(!selectedAgent.supportsSession)
    }

    private var sessionTitle: String {
        guard selectedAgent.supportsSession else { return "No Session" }
        guard store.selectedAgentSession != nil else { return "No Saved" }
        guard store.resumeAgentSession else { return "New" }
        return "Continue"
    }

    private func shortSessionID(_ sessionID: String) -> String {
        guard sessionID.count > 12 else { return sessionID }
        return "\(sessionID.prefix(8))...\(sessionID.suffix(4))"
    }

    private func sessionSummary(_ session: AgentSessionInfo) -> String {
        var parts = ["Session \(shortSessionID(session.sessionId))"]
        if let lastMode = session.lastMode, !lastMode.isEmpty {
            parts.append("mode \(lastMode)")
        }
        if let effort = session.reasoningEffort, !effort.isEmpty {
            parts.append(effort)
        }
        if let speed = session.speedMode, !speed.isEmpty {
            parts.append("speed \(speed)")
        }
        return parts.joined(separator: " / ")
    }

    private var modelSettingsTitle: String {
        switch store.selectedAgent {
        case "hermes":
            if store.selectedHermesProvider == .auto && store.selectedHermesModel == .auto {
                return "Hermes Defaults"
            }
            if store.selectedHermesProvider != .auto && store.selectedHermesModel != .auto {
                return "\(store.selectedHermesProvider.title) / \(store.selectedHermesModel.title)"
            }
            if store.selectedHermesProvider != .auto {
                return store.selectedHermesProvider.title
            }
            return store.selectedHermesModel.title
        case "codex":
            return store.selectedCodexModel.title
        case "claude":
            return store.selectedClaudeModel.title
        default:
            return "Model"
        }
    }

    private var modelSettingsSymbol: String {
        switch store.selectedAgent {
        case "hermes":
            return store.selectedHermesProvider != .auto ? store.selectedHermesProvider.symbol : store.selectedHermesModel.symbol
        case "claude":
            return store.selectedClaudeModel == .auto ? "sparkles" : "circle.hexagongrid"
        case "codex":
            return store.selectedCodexModel == .auto ? "sparkles" : "cpu"
        default:
            return "slider.horizontal.3"
        }
    }

    private var modelSettingsActive: Bool {
        switch store.selectedAgent {
        case "hermes":
            return store.selectedHermesProvider != .auto || store.selectedHermesModel != .auto
        case "codex":
            return store.selectedCodexModel != .auto
        case "claude":
            return store.selectedClaudeModel != .auto
        default:
            return false
        }
    }

    private var selectedSpeedModeTitle: String {
        guard store.selectedSpeedMode.isSupported(by: store.selectedAgent) else {
            return "Default"
        }
        return store.selectedSpeedMode.title(for: store.selectedAgent)
    }

    private func speedMenuLabel(_ speedMode: AgentSpeedMode) -> String {
        switch (speedMode, store.selectedAgent) {
        case (.fast, "codex"):
            return "Fast 1.5x"
        case (.fast, "claude"):
            return "Fast (Claude CLI/version gated)"
        case (.fast, _):
            return "Fast (unsupported)"
        default:
            return speedMode.title
        }
    }

    private var selectedAgent: AgentOption {
        agentOptions.first(where: { $0.id == store.selectedAgent }) ?? agentOptions[0]
    }

    private var agentOptions: [AgentOption] {
        let capabilities = store.agentCapabilities
        if capabilities.isEmpty {
            return [AgentOption(id: "codex", name: "Codex", symbol: "sparkles", isSelectable: true, supportsSession: true, installStatus: "unknown")]
        }
        return capabilities.sorted { left, right in
            agentSortIndex(left.id) < agentSortIndex(right.id)
        }.map { capability in
            AgentOption(
                id: capability.id,
                name: capability.displayName,
                symbol: store.symbol(for: capability.id),
                isSelectable: capability.isSelectable,
                supportsSession: capability.supportsSession,
                installStatus: capability.installStatus ?? (capability.isSelectable ? "ready" : "missing")
            )
        }
    }

    private func agentSortIndex(_ agent: String) -> Int {
        switch agent.lowercased() {
        case "codex": return 0
        case "claude": return 1
        case "hermes": return 2
        case "opencode": return 3
        default: return 10
        }
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
        store.activeRunId == nil
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.connectionState == .connected
            && (store.agentCapabilities.isEmpty || selectedAgent.isSelectable)
    }

    private var slashCommandQuery: String? {
        guard prompt.hasPrefix("/") else { return nil }
        let firstLine = prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? prompt
        guard !firstLine.contains(where: { $0.isWhitespace }) else { return nil }
        return String(firstLine.dropFirst())
    }

    private var slashCommandSuggestions: [SlashCommandOption] {
        guard let slashCommandQuery else { return [] }
        return Array(SlashCommandOption.matching(slashCommandQuery, agent: store.selectedAgent).prefix(8))
    }

    private var mentionQuery: String? {
        ContextMentionParser.activeQuery(in: prompt)
    }

    private var mentionSuggestions: [ContextMentionSuggestion] {
        guard let mentionQuery else { return [] }
        return store.contextMentionSuggestions(matching: mentionQuery)
    }

    private var promptRecallHistory: [String] {
        store.agentMessages
            .filter { $0.role == .user }
            .map(\.text)
    }

    private var shouldShowSlashCommands: Bool {
        slashCommandQuery != nil && !slashCommandSuggestions.isEmpty
    }

    private var shouldShowMentionSuggestions: Bool {
        mentionQuery != nil && !mentionSuggestions.isEmpty
    }

    private var shouldShowContextBar: Bool {
        store.isAutoContextEnabled || !store.pendingContextAttachments.isEmpty
    }

    private var autoContextTitle: String {
        if let selectedFilePath = store.selectedFilePath {
            return "Auto: \(selectedFilePath)"
        }
        return "Auto context"
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
        if shouldAutocompleteSlashCommandOnSubmit, let command = slashCommandSuggestions.first {
            acceptSlashCommand(command)
            return
        }
        let value = prompt
        prompt = ""
        promptHistory.reset()
        promptFocused = false
        Task { await store.runAgent(prompt: value) }
    }

    private var shouldAutocompleteSlashCommandOnSubmit: Bool {
        guard let slashCommandQuery else { return false }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let exactCommand = SlashCommandOption.matching("", agent: store.selectedAgent).contains { $0.command == trimmed }
        return !slashCommandQuery.isEmpty && !exactCommand
    }

    private func acceptSlashCommand(_ command: SlashCommandOption) {
        prompt = "\(command.command) "
        promptHistory.reset()
        promptFocused = true
    }

    private func acceptMentionSuggestion(_ suggestion: ContextMentionSuggestion) {
        prompt = ContextMentionParser.replacingActiveMention(in: prompt, with: suggestion.path)
        store.attachContextFile(path: suggestion.path)
        promptHistory.reset()
        promptFocused = true
    }

    private func recallPreviousPrompt() -> Bool {
        guard let recalled = promptHistory.previous(current: prompt, history: promptRecallHistory) else {
            return false
        }
        prompt = recalled
        promptFocused = true
        return true
    }

    private func recallNextPrompt() -> Bool {
        guard let recalled = promptHistory.next(history: promptRecallHistory) else {
            return false
        }
        prompt = recalled
        promptFocused = true
        return true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

struct PromptHistoryNavigator: Equatable {
    private var index: Int?
    private var draft = ""

    mutating func previous(current: String, history: [String]) -> String? {
        let items = normalized(history)
        guard !items.isEmpty else {
            reset()
            return nil
        }
        if let currentIndex = index {
            index = max(0, currentIndex - 1)
        } else {
            draft = current
            index = items.count - 1
        }
        return index.flatMap { items[$0] }
    }

    mutating func next(history: [String]) -> String? {
        let items = normalized(history)
        guard let currentIndex = index else { return nil }
        let nextIndex = currentIndex + 1
        guard nextIndex < items.count else {
            let value = draft
            reset()
            return value
        }
        index = nextIndex
        return items[nextIndex]
    }

    mutating func reset() {
        index = nil
        draft = ""
    }

    private func normalized(_ history: [String]) -> [String] {
        history.reduce(into: [String]()) { result, entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if result.last != trimmed {
                result.append(trimmed)
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
            ChangeListMessage(runId: message.runId, changes: message.changes)
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
    @State private var isRunRevertConfirmPresented = false
    let runId: String?
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
                if let runId {
                    Button {
                        isRunRevertConfirmPresented = true
                    } label: {
                        Label("Revert Run", systemImage: "arrow.uturn.backward.circle")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel("Revert Run \(runId)")
                }
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
        .alert("Revert this run?", isPresented: $isRunRevertConfirmPresented) {
            Button("Revert Run", role: .destructive) {
                if let runId {
                    Task { await store.revertRun(runId: runId) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only changes made by this agent run will be reverted. Files changed after the run will be skipped.")
        }
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
    @State private var expanded = false
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
        VStack(alignment: .leading, spacing: 8) {
            Text(visibleText)
                .font(font)
                .transcriptTextSelection()
                .foregroundStyle(foreground)
                .frame(maxWidth: message.role == .user ? 280 : .infinity, alignment: .leading)
            if isCollapsible {
                Button {
                    expanded.toggle()
                } label: {
                    Label(expanded ? "Collapse output" : "Show full output", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: message.role == .user ? 280 : .infinity, alignment: .leading)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleText: String {
        guard isCollapsible, !expanded else { return message.text }
        let lines = message.text.split(separator: "\n", omittingEmptySubsequences: false)
        let prefix = lines.prefix(32).joined(separator: "\n")
        return "\(prefix)\n\n... \(lines.count - 32) more lines hidden"
    }

    private var isCollapsible: Bool {
        message.role == .agent && message.text.split(separator: "\n", omittingEmptySubsequences: false).count > 48
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
        .contentShape(RoundedRectangle(cornerRadius: 6))
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

private struct ContextChip: View {
    @Environment(\.airCodeTheme) private var theme
    let title: String
    let symbol: String
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            if removable {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(theme.accent.opacity(0.14))
        .foregroundStyle(theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct AgentOption: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let isSelectable: Bool
    let supportsSession: Bool
    let installStatus: String

    var menuTitle: String {
        isSelectable ? name : "\(name) (\(installStatus))"
    }
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
