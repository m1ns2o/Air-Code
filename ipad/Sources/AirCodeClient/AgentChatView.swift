import SwiftUI

public struct AgentChatView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var promptFocused = false
    @State private var prompt = ""
    @State private var promptHistory = PromptHistoryNavigator()
    @State private var isTimelineExpanded = false
    @State private var isRunSettingsPresented = false
    @State private var pendingScrollWorkItem: DispatchWorkItem?
    @State private var pendingFollowUpScrollWorkItem: DispatchWorkItem?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            if !store.agentTimelineEvents.isEmpty {
                RuntimeTimelineCard(events: store.agentTimelineEvents, isExpanded: $isTimelineExpanded)
                Divider().overlay(theme.border)
            }
            if let pendingApproval = store.pendingApproval {
                PendingApprovalCard(approval: pendingApproval)
                    .environmentObject(store)
                Divider().overlay(theme.border)
            }
            transcript
            Divider().overlay(theme.border)
            composer
        }
        .background(theme.panel)
        .foregroundStyle(theme.foreground)
        .sheet(isPresented: integrationSheetBinding) {
            IntegrationManagementSheet()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: runSettingsSheetBinding) {
            RunSettingsSheet()
                .environmentObject(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
                runSettingsButton
                integrationsButton
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

    private var integrationSheetBinding: Binding<Bool> {
        Binding(
            get: { store.isIntegrationPanelVisible },
            set: { isPresented in
                if !isPresented {
                    store.closeIntegrationPanel()
                }
            }
        )
    }

    private var runSettingsSheetBinding: Binding<Bool> {
        Binding(
            get: { isRunSettingsPresented || store.isPermissionPanelVisible },
            set: { isPresented in
                if !isPresented {
                    isRunSettingsPresented = false
                    store.closePermissionPanel()
                }
            }
        )
    }

    private var runSettingsButton: some View {
        Button {
            isRunSettingsPresented = true
            Task { await store.loadPermissionSnapshot(showPanel: false) }
        } label: {
            Image(systemName: runSettingsActive ? "shield.lefthalf.filled" : "shield")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(runSettingsActive ? theme.accent.opacity(0.18) : theme.elevated)
        .foregroundStyle(runSettingsActive ? theme.accent : theme.foreground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Run Settings")
    }

    private var runSettingsActive: Bool {
        store.selectedCodexApprovalMode.isOverride ||
            store.selectedCodexSandboxMode.isOverride ||
            store.selectedClaudePermissionMode.isOverride ||
            store.selectedHermesPermissionMode.isOverride ||
            store.isCavemanEnabled ||
            !store.isAutoContextEnabled
    }

    private var integrationsButton: some View {
        Button {
            Task {
                await store.loadIntegrationStatus(showPanel: true)
                await store.loadIntegrationInventory()
            }
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(store.isIntegrationPanelVisible ? theme.accent.opacity(0.18) : theme.elevated)
        .foregroundStyle(store.isIntegrationPanelVisible ? theme.accent : theme.foreground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Manage MCP and Integrations")
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

    private struct PendingApprovalCard: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme
        let approval: PendingApprovalRequest

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(riskColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(approval.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.foreground)
                        if !approval.detail.isEmpty {
                            Text(approval.detail)
                                .font(.caption2)
                                .foregroundStyle(theme.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await store.resolvePendingApproval(approved: false) }
                    } label: {
                        Text("Deny")
                            .font(.caption.weight(.semibold))
                            .frame(height: 26)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .background(theme.red.opacity(0.16))
                    .foregroundStyle(theme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        Task { await store.resolvePendingApproval(approved: true) }
                    } label: {
                        Text("Approve")
                            .font(.caption.weight(.semibold))
                            .frame(height: 26)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .background(theme.green.opacity(0.18))
                    .foregroundStyle(theme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if !approval.command.isEmpty || !approval.path.isEmpty {
                    Text([approval.command, approval.path].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(2)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.editor.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
            .background(riskColor.opacity(0.08))
        }

        private var riskColor: Color {
            switch approval.risk {
            case "high": return theme.red
            case "low": return theme.green
            default: return theme.yellow
            }
        }
    }

    private struct RunSettingsSheet: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsSection("Permissions", symbol: "shield.lefthalf.filled") {
                            permissionControls
                            permissionSnapshotSummary
                        }
                        settingsSection("Context", symbol: "paperclip") {
                            Toggle(isOn: Binding(
                                get: { store.isAutoContextEnabled },
                                set: { store.setAutoContextEnabled($0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto Context")
                                        .font(.caption.weight(.semibold))
                                    Text(contextSummary)
                                        .font(.caption2)
                                        .foregroundStyle(theme.muted)
                                }
                            }
                            .tint(theme.accent)
                            if !store.pendingContextAttachments.isEmpty {
                                HStack(spacing: 6) {
                                    Label("\(store.pendingContextAttachments.count) @ path", systemImage: "at")
                                    Spacer()
                                    Button("Clear") {
                                        store.clearContextAttachments()
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                            }
                        }
                        settingsSection("Response Style", symbol: "text.bubble") {
                            Toggle(isOn: Binding(
                                get: { store.isCavemanEnabled },
                                set: { store.setCavemanEnabled($0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Caveman")
                                        .font(.caption.weight(.semibold))
                                    Text("Use terse, low-ceremony answers for future prompts.")
                                        .font(.caption2)
                                        .foregroundStyle(theme.muted)
                                }
                            }
                            .tint(theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .background(theme.panel)
                .foregroundStyle(theme.foreground)
                .navigationTitle("Run Settings")
                .airCodeInlineNavigationTitle()
                .tint(theme.accent)
                .themedIntegrationNavigationBar(theme)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            store.closePermissionPanel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await store.loadPermissionSnapshot(showPanel: false) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .task {
                    if store.permissionSnapshot == nil {
                        await store.loadPermissionSnapshot(showPanel: false)
                    }
                }
            }
            .preferredColorScheme(theme.isLight ? .light : .dark)
        }

        @ViewBuilder
        private var permissionControls: some View {
            switch store.selectedAgent {
            case "codex":
                VStack(alignment: .leading, spacing: 7) {
                    Text("Codex Approval")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    ForEach(CodexApprovalMode.allCases) { mode in
                        optionButton(title: mode.title, detail: codexApprovalDetail(mode), symbol: mode.symbol, isSelected: store.selectedCodexApprovalMode == mode, isDanger: mode == .never) {
                            store.setCodexApprovalMode(mode)
                        }
                    }
                    Text("Codex Sandbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .padding(.top, 4)
                    ForEach(CodexSandboxMode.allCases) { mode in
                        optionButton(title: mode.title, detail: codexSandboxDetail(mode), symbol: mode.symbol, isSelected: store.selectedCodexSandboxMode == mode, isDanger: mode == .fullAccess) {
                            store.setCodexSandboxMode(mode)
                        }
                    }
                }
            case "claude":
                VStack(alignment: .leading, spacing: 7) {
                    Text("Claude Code Permission Mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    ForEach(ClaudePermissionMode.allCases) { mode in
                        optionButton(title: mode.title, detail: mode.detail, symbol: mode.symbol, isSelected: store.selectedClaudePermissionMode == mode, isDanger: mode == .bypassPermissions) {
                            store.setClaudePermissionMode(mode)
                        }
                    }
                }
            case "hermes":
                VStack(alignment: .leading, spacing: 7) {
                    Text("Hermes Native Approval")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    ForEach(HermesPermissionMode.allCases) { mode in
                        optionButton(title: mode.title, detail: mode.detail, symbol: mode.symbol, isSelected: store.selectedHermesPermissionMode == mode, isDanger: mode == .yolo) {
                            store.setHermesPermissionMode(mode)
                        }
                    }
                    Text("Hermes also supports native /approve and /deny while a provider session is waiting for a decision.")
                        .font(.caption2)
                        .foregroundStyle(theme.muted)
                }
            default:
                Label("This provider uses server defaults.", systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
            }
        }

        @ViewBuilder
        private var permissionSnapshotSummary: some View {
            if let snapshot = store.permissionSnapshot {
                VStack(alignment: .leading, spacing: 7) {
                    Divider().overlay(theme.border)
                    ForEach(snapshot.agents.filter { $0.id == store.selectedAgent }) { policy in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(riskColor(policy.riskLevel))
                                .frame(width: 7, height: 7)
                            Text("Server")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(policy.approvalMode)
                                .font(.system(.caption2, design: .monospaced))
                            Text(policy.sandboxMode)
                                .font(.system(.caption2, design: .monospaced))
                        }
                        .foregroundStyle(theme.muted)
                    }
                    HStack(spacing: 8) {
                        Label(snapshot.commandPolicy.terminalEnabled ? "Terminal on" : "Terminal off", systemImage: "terminal")
                        Label("\(snapshot.commandPolicy.maxSessions) sessions", systemImage: "rectangle.stack")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
                }
            }
        }

        private func settingsSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                content()
            }
            .padding(12)
            .background(theme.elevated.opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private func optionButton(title: String, detail: String, symbol: String, isSelected: Bool, isDanger: Bool = false, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : symbol)
                        .foregroundStyle(isSelected ? theme.accent : (isDanger ? theme.red : theme.muted))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.foreground)
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(8)
                .background(isSelected ? theme.accent.opacity(0.12) : theme.panel.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }

        private var contextSummary: String {
            if store.isAutoContextEnabled, let path = store.selectedFilePath {
                return "Open file: \(path)"
            }
            if store.isAutoContextEnabled {
                return "Selection and cursor context will appear here when available."
            }
            return "Off. Only explicit @ path attachments are sent."
        }

        private func codexApprovalDetail(_ mode: CodexApprovalMode) -> String {
            switch mode {
            case .serverDefault: return "Use the server configured Codex approval policy."
            case .ask: return "Let Codex ask before actions that need approval."
            case .onFailure: return "Ask only after a command fails and escalation is needed."
            case .never: return "Never pause for approval; safest only inside trusted sandboxes."
            }
        }

        private func codexSandboxDetail(_ mode: CodexSandboxMode) -> String {
            switch mode {
            case .serverDefault: return "Use the server configured Codex sandbox."
            case .readOnly: return "Allow inspection without file writes."
            case .workspaceWrite: return "Allow edits inside the opened project workspace."
            case .fullAccess: return "Allow full filesystem access from the Codex run."
            }
        }

        private func riskColor(_ riskLevel: String) -> Color {
            switch riskLevel {
            case "high": return theme.red
            case "medium": return theme.yellow
            default: return theme.green
            }
        }
    }

    private struct IntegrationManagementSheet: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme

        var body: some View {
            NavigationStack {
                Group {
                    if let status = store.integrationStatus {
                        ScrollView {
                            IntegrationStatusCard(status: status)
                                .environmentObject(store)
                                .padding(12)
                        }
                        .background(theme.panel)
                        .foregroundStyle(theme.foreground)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading integrations")
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.panel)
                        .foregroundStyle(theme.foreground)
                    }
                }
                .navigationTitle("Integrations")
                .airCodeInlineNavigationTitle()
                .tint(theme.accent)
                .themedIntegrationNavigationBar(theme)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            store.closeIntegrationPanel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                await store.loadIntegrationStatus(showPanel: true)
                                await store.loadIntegrationInventory()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .task {
                    if store.integrationStatus == nil {
                        await store.loadIntegrationStatus(showPanel: true)
                    }
                    if store.integrationInventory == nil {
                        await store.loadIntegrationInventory()
                    }
                }
            }
            .preferredColorScheme(theme.isLight ? .light : .dark)
        }
    }

    private struct IntegrationStatusCard: View {
        @EnvironmentObject private var store: AirCodeStore
        @Environment(\.airCodeTheme) private var theme
        let status: IntegrationStatus
        @State private var isMCPInstallPresented = false
        @State private var isInventoryPresented = false
        @State private var mcpName = ""
        @State private var mcpMode: MCPInstallMode = .stdio
        @State private var mcpCommand = ""
        @State private var mcpURL = ""
        @State private var mcpArgs = ""
        @State private var mcpEnv = ""
        @State private var mcpProviders: Set<String> = ["codex", "claude", "hermes"]
        @State private var mcpEditProvider: String?
        @State private var isInstallingMCP = false
        @State private var mcpInstallResponse: MCPInstallResponse?
        @State private var pendingRemoval: IntegrationInventoryItem?
        @State private var isRunningShortcut = false
        @State private var shortcutResultTitle = ""
        @State private var shortcutResult: IntegrationActionResponse?
        @State private var focusedInventorySectionID: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(theme.accent)
                    Text("Integrations")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.foreground)
                    Spacer()
                    Button {
                        Task {
                            await store.loadIntegrationInventory()
                            isInventoryPresented = true
                        }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage Integrations")
                    Button {
                        beginAddMCP()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add MCP Server")
                    Button {
                        Task {
                            await store.loadIntegrationStatus(showPanel: true)
                            await store.loadIntegrationInventory()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh Integrations")
                    Button {
                        store.closeIntegrationPanel()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Integrations")
                }
                integrationGroup(status.mcp, symbol: "point.3.connected.trianglepath.dotted")
                integrationGroup(status.skills, symbol: "puzzlepiece.extension")
                integrationGroup(status.hooks, symbol: "link")
                integrationGroup(status.codexConnectors, symbol: "app.connected.to.app.below.fill")
                integrationGroup(status.codexPlugins, symbol: "shippingbox")
                integrationGroup(status.claudePlugins, symbol: "puzzlepiece")
                providerCommandShortcuts
                shortcutResultView
            }
            .padding(10)
            .background(theme.elevated.opacity(0.65))
            .foregroundStyle(theme.foreground)
            .tint(theme.accent)
            .sheet(isPresented: $isMCPInstallPresented) {
                mcpInstallSheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isInventoryPresented) {
                integrationInventorySheet
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Remove Integration Item?", isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    pendingRemoval = nil
                }
                Button("Remove", role: .destructive) {
                    if let pendingRemoval {
                        Task {
                            _ = await store.removeIntegrationItem(pendingRemoval)
                            self.pendingRemoval = nil
                        }
                    }
                }
            } message: {
                if let pendingRemoval {
                    Text("Remove \(pendingRemoval.title) from \(pendingRemoval.providerName)?")
                }
            }
        }

        private func integrationGroup(_ group: IntegrationGroup, symbol: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.foreground)
                    Spacer()
                }
                Text(group.description)
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
                Text(group.commandHint)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    ForEach(group.providers) { provider in
                        Label(provider.displayName, systemImage: provider.available ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(provider.available ? theme.green : theme.muted)
                    }
                }
            }
            .padding(8)
            .background(theme.panel.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }

        private var providerCommandShortcuts: some View {
            let shortcuts = integrationShortcuts(for: store.selectedAgent)
            return ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shortcuts) { shortcut in
                        Button {
                            Task { await runShortcut(shortcut) }
                        } label: {
                            Label(shortcut.title, systemImage: shortcut.symbol)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(theme.panel.opacity(0.85))
                                .foregroundStyle(theme.foreground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunningShortcut)
                        .accessibilityLabel(shortcut.title)
                    }
                }
            }
        }

        private func integrationShortcuts(for agent: String) -> [IntegrationShortcut] {
            [
                IntegrationShortcut(command: "/mcp", sectionID: "mcp", kind: "mcp", action: "list", title: "MCP", symbol: "point.3.connected.trianglepath.dotted"),
                IntegrationShortcut(command: "/skills", sectionID: "skills", kind: "skills", action: "list", title: "Skills", symbol: "puzzlepiece.extension", providerCommandAgents: ["hermes"]),
                IntegrationShortcut(command: "/hooks", sectionID: "hooks", kind: "hooks", action: "list", title: "Hooks", symbol: "link", providerCommandAgents: ["hermes"]),
                IntegrationShortcut(command: "/apps", sectionID: "apps", title: "Apps", symbol: "app.connected.to.app.below.fill", supportedAgents: ["codex"]),
                IntegrationShortcut(command: "/plugins", sectionID: "plugins", kind: "plugins", action: "list", title: "Plugins", symbol: "shippingbox", providerCommandAgents: ["claude", "hermes"]),
                IntegrationShortcut(command: "/doctor", sectionID: nil, kind: "doctor", action: "check", title: "Doctor", symbol: "cross.case", supportedAgents: ["hermes"], providerCommandAgents: ["hermes"])
            ].filter { shortcut in
                guard shortcut.supports(agent: agent) else { return false }
                guard let action = AgentPromptCommand.parse(shortcut.command, agent: agent).localAction else {
                    return false
                }
                if case .message = action {
                    return false
                }
                return true
            }
        }

        private struct IntegrationShortcut: Identifiable {
            let command: String
            let sectionID: String?
            let kind: String?
            let action: String?
            let title: String
            let symbol: String
            var supportedAgents: Set<String>?
            var providerCommandAgents: Set<String>?

            var id: String { command }

            init(command: String, sectionID: String?, kind: String? = nil, action: String? = nil, title: String, symbol: String, supportedAgents: Set<String>? = nil, providerCommandAgents: Set<String>? = nil) {
                self.command = command
                self.sectionID = sectionID
                self.kind = kind
                self.action = action
                self.title = title
                self.symbol = symbol
                self.supportedAgents = supportedAgents
                self.providerCommandAgents = providerCommandAgents
            }

            func supports(agent: String) -> Bool {
                guard let supportedAgents else { return true }
                return supportedAgents.contains(agent.lowercased())
            }

            func usesProviderCommand(agent: String) -> Bool {
                guard let providerCommandAgents else {
                    return kind != nil && action != nil
                }
                return providerCommandAgents.contains(agent.lowercased())
            }
        }

        @ViewBuilder
        private var shortcutResultView: some View {
            if isRunningShortcut {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Running \(shortcutResultTitle)")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                    Spacer()
                }
                .padding(9)
                .background(theme.panel.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            } else if let shortcutResult {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: shortcutResult.status == "failed" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(shortcutResult.status == "failed" ? theme.red : theme.green)
                        Text(shortcutResultTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.foreground)
                        Spacer()
                        Button {
                            self.shortcutResult = nil
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 24, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.muted)
                    }
                    if let command = shortcutResult.command, !command.isEmpty {
                        Text(command.joined(separator: " "))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.muted)
                            .lineLimit(2)
                    }
                    let output = (shortcutResult.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !output.isEmpty {
                        Text(output)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.foreground)
                            .lineLimit(10)
                    }
                    let error = (shortcutResult.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(theme.red)
                            .lineLimit(6)
                    }
                }
                .padding(9)
                .background(theme.panel.opacity(0.78))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }

        private func runShortcut(_ shortcut: IntegrationShortcut) async {
            if !shortcut.usesProviderCommand(agent: store.selectedAgent) {
                focusedInventorySectionID = shortcut.sectionID
                shortcutResult = nil
                await store.loadIntegrationInventory()
                isInventoryPresented = true
                return
            }
            guard let kind = shortcut.kind, let action = shortcut.action else { return }
            isRunningShortcut = true
            shortcutResultTitle = shortcut.title
            shortcutResult = nil
            defer { isRunningShortcut = false }
            shortcutResult = await store.runIntegrationPanelCommand(kind: kind, command: action)
        }

        private var integrationInventorySheet: some View {
            NavigationStack {
                List {
                    if let inventory = store.integrationInventory {
                        ForEach(filteredInventorySections(inventory.sections)) { section in
                            Section {
                                if section.items.isEmpty {
                                    inventoryEmptyRow(section)
                                        .listRowBackground(theme.elevated)
                                } else {
                                    ForEach(section.items) { item in
                                        integrationInventoryRow(item)
                                            .listRowBackground(theme.elevated)
                                    }
                                }
                            } header: {
                                Text(section.title)
                                    .foregroundStyle(theme.foreground)
                            } footer: {
                                Text(section.description)
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    } else {
                        ProgressView("Loading integrations")
                            .tint(theme.accent)
                            .listRowBackground(theme.elevated)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.panel)
                .foregroundStyle(theme.foreground)
                .tint(theme.accent)
                .navigationTitle(focusedInventoryTitle)
                .airCodeInlineNavigationTitle()
                .themedIntegrationNavigationBar(theme)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isInventoryPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 8) {
                            if focusedInventorySectionID != nil {
                                Button("All") {
                                    focusedInventorySectionID = nil
                                }
                            }
                            Button {
                                Task { await store.loadIntegrationInventory() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .preferredColorScheme(theme.isLight ? .light : .dark)
        }

        private var focusedInventoryTitle: String {
            guard let focusedInventorySectionID else { return "Manage Integrations" }
            switch focusedInventorySectionID {
            case "mcp": return "MCP Servers"
            case "skills": return "Skills"
            case "hooks": return "Hooks"
            case "apps": return "Apps"
            case "plugins": return "Plugins"
            default: return "Manage Integrations"
            }
        }

        private func filteredInventorySections(_ sections: [IntegrationInventorySection]) -> [IntegrationInventorySection] {
            guard let focusedInventorySectionID else { return sections }
            return sections.filter { $0.id == focusedInventorySectionID }
        }

        private func inventoryEmptyRow(_ section: IntegrationInventorySection) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("No items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                Text(emptyInventoryMessage(for: section))
                    .font(.caption2)
                    .foregroundStyle(theme.muted)
            }
            .padding(.vertical, 3)
        }

        private func emptyInventoryMessage(for section: IntegrationInventorySection) -> String {
            switch section.id {
            case "skills":
                return "No provider skill folders were discovered. This is not a CLI error; install or create skills on the server to show them here."
            case "hooks":
                return "No hook files were discovered in the provider homes."
            case "apps":
                return "No Codex apps/connectors were found in the local app cache."
            case "plugins":
                return "No plugin entries were discovered for the configured providers."
            case "mcp":
                return "No MCP servers are currently registered."
            default:
                return "Nothing has been registered for this integration type yet."
            }
        }

        private func integrationInventoryRow(_ item: IntegrationInventoryItem) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(for: item))
                        .foregroundStyle(theme.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.foreground)
                            Text(item.providerName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.foreground)
                                .padding(.horizontal, 5)
                                .frame(height: 18)
                                .background(theme.panel.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(theme.muted)
                                .lineLimit(2)
                        }
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    if let command = item.openCommand, !command.isEmpty {
                        Button("Show") {
                            focusedInventorySectionID = sectionID(for: item, fallbackCommand: command)
                            shortcutResult = nil
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    }
                    if item.kind == "mcp", item.editable {
                        Button("Edit") {
                            beginEditMCP(item)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    }
                    if item.removable {
                        Button("Remove", role: .destructive) {
                            pendingRemoval = item
                        }
                        .font(.caption2.weight(.semibold))
                    }
                    Spacer()
                    if let status = item.status, !status.isEmpty {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(theme.muted)
                    }
                }
            }
            .padding(.vertical, 3)
        }

        private func sectionID(for item: IntegrationInventoryItem, fallbackCommand: String) -> String? {
            switch item.kind {
            case "mcp":
                return "mcp"
            case "skill":
                return "skills"
            case "hook":
                return "hooks"
            case "app", "codex-app":
                return "apps"
            case "plugin", "codex-plugin", "codex-plugin-marketplace", "claude-plugin", "hermes-plugin":
                return "plugins"
            default:
                switch fallbackCommand {
                case "/mcp": return "mcp"
                case "/skills": return "skills"
                case "/hooks": return "hooks"
                case "/apps": return "apps"
                case "/plugins", "/plugin": return "plugins"
                default: return nil
                }
            }
        }

        private var mcpInstallSheet: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        mcpSheetSection("MCP Server", symbol: "point.3.connected.trianglepath.dotted") {
                            themedTextField("Name", text: $mcpName)
                            Picker("Transport", selection: $mcpMode) {
                                ForEach(MCPInstallMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(theme.accent)
                            if mcpMode == .stdio {
                                themedTextField("Command", text: $mcpCommand)
                                themedTextEditor("Arguments", text: $mcpArgs)
                            } else {
                                themedTextField("URL", text: $mcpURL)
                            }
                            themedTextEditor("Environment", text: $mcpEnv)
                        }

                        mcpSheetSection("Providers", symbol: "square.stack.3d.up") {
                            ForEach(["codex", "claude", "hermes"], id: \.self) { provider in
                                Button {
                                    toggleMCPProvider(provider)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: mcpProviders.contains(provider) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(mcpProviders.contains(provider) ? theme.accent : theme.muted)
                                        Text(providerTitle(provider))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(theme.foreground)
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(theme.panel.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let response = mcpInstallResponse {
                            mcpSheetSection("Result", symbol: "checklist") {
                                ForEach(response.results) { result in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(result.provider, systemImage: result.status == "configured" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(result.status == "configured" ? theme.green : theme.red)
                                        Text(result.commandText)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(theme.muted)
                                        if let error = result.error, !error.isEmpty {
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundStyle(theme.red)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.panel.opacity(0.65))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                                if let error = response.error, !error.isEmpty {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(theme.red)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .background(theme.panel)
                .foregroundStyle(theme.foreground)
                .tint(theme.accent)
                .navigationTitle(mcpEditProvider == nil ? "Add MCP Server" : "Edit MCP Server")
                .airCodeInlineNavigationTitle()
                .themedIntegrationNavigationBar(theme)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isMCPInstallPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isInstallingMCP ? "Installing" : "Install") {
                            Task { await installMCPFromSheet() }
                        }
                        .disabled(isInstallingMCP || !canInstallMCP)
                    }
                }
            }
            .preferredColorScheme(theme.isLight ? .light : .dark)
        }

        private func mcpSheetSection<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                content()
            }
            .padding(12)
            .background(theme.elevated.opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private func themedTextField(_ title: String, text: Binding<String>) -> some View {
            TextField(title, text: text)
                .autocorrectionDisabled()
                .font(.caption)
                .padding(9)
                .background(theme.editor)
                .foregroundStyle(theme.foreground)
                .tint(theme.accent)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }

        private func themedTextEditor(_ title: String, text: Binding<String>) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                TextEditor(text: text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                    .scrollContentBackground(.hidden)
                    .background(theme.editor)
                    .frame(minHeight: 72)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }

        private var canInstallMCP: Bool {
            let hasTarget = mcpMode == .stdio ? !mcpCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !mcpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return !mcpName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasTarget && !mcpProviders.isEmpty
        }

        private func installMCPFromSheet() async {
            guard canInstallMCP else { return }
            isInstallingMCP = true
            defer { isInstallingMCP = false }
            mcpInstallResponse = await store.installSharedMCPServer(
                name: mcpName.trimmingCharacters(in: .whitespacesAndNewlines),
                command: mcpMode == .stdio ? mcpCommand.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                url: mcpMode == .http ? mcpURL.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                args: mcpArgs.lineValues,
                env: mcpEnv.lineValues,
                providers: Array(mcpProviders).sorted()
            )
            await store.loadIntegrationInventory()
        }

        private func beginAddMCP() {
            mcpEditProvider = nil
            mcpName = ""
            mcpMode = .stdio
            mcpCommand = ""
            mcpURL = ""
            mcpArgs = ""
            mcpEnv = ""
            mcpProviders = ["codex", "claude", "hermes"]
            mcpInstallResponse = nil
            isMCPInstallPresented = true
        }

        private func beginEditMCP(_ item: IntegrationInventoryItem) {
            mcpEditProvider = item.provider
            mcpName = item.name
            mcpMode = .stdio
            mcpCommand = ""
            mcpURL = ""
            mcpArgs = ""
            mcpEnv = ""
            mcpProviders = [item.provider]
            mcpInstallResponse = nil
            isMCPInstallPresented = true
        }

        private func toggleMCPProvider(_ provider: String) {
            if mcpProviders.contains(provider) {
                mcpProviders.remove(provider)
            } else {
                mcpProviders.insert(provider)
            }
        }

        private func providerTitle(_ provider: String) -> String {
            switch provider {
            case "codex": return "Codex"
            case "claude": return "Claude Code"
            case "hermes": return "Hermes"
            default: return provider
            }
        }

        private func symbol(for item: IntegrationInventoryItem) -> String {
            switch item.kind {
            case "mcp": return "point.3.connected.trianglepath.dotted"
            case "skill": return "puzzlepiece.extension"
            case "hook": return "link"
            case "app": return "app.connected.to.app.below.fill"
            default: return "shippingbox"
            }
        }

        private enum MCPInstallMode: String, CaseIterable, Identifiable {
            case stdio
            case http

            var id: String { rawValue }

            var title: String {
                switch self {
                case .stdio: return "Command"
                case .http: return "HTTP"
                }
            }
        }
    }

    private struct RuntimeTimelineCard: View {
        @Environment(\.airCodeTheme) private var theme
        let events: [AgentRuntimeEvent]
        @Binding var isExpanded: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "timeline.selection")
                        .foregroundStyle(theme.accent)
                    Text("Runtime")
                        .font(.caption.weight(.semibold))
                    if let last = events.last {
                        Text(last.shortRunId)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse Runtime Timeline" : "Expand Runtime Timeline")
                }
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleEvents) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: symbol(for: event.kind))
                                    .font(.caption)
                                    .foregroundStyle(color(for: event.kind))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.caption)
                                        .foregroundStyle(theme.foreground)
                                        .lineLimit(1)
                                    if !event.detail.isEmpty {
                                        Text(event.detail)
                                            .font(.caption2)
                                            .foregroundStyle(theme.muted)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(theme.elevated.opacity(0.5))
        }

        private var visibleEvents: [AgentRuntimeEvent] {
            Array(events.suffix(8))
        }

        private func symbol(for kind: String) -> String {
            switch kind {
            case "started": return "play.circle"
            case "completed": return "checkmark.circle"
            case "failed", "error": return "exclamationmark.triangle"
            case "stopped": return "stop.circle"
            case "final": return "text.bubble"
            case "session": return "number"
            case "steering": return "arrow.triangle.turn.up.right.diamond"
            default: return "circle.dotted"
            }
        }

        private func color(for kind: String) -> Color {
            switch kind {
            case "completed": return theme.green
            case "failed", "error": return theme.red
            case "stopped": return theme.yellow
            case "started", "final", "session", "steering": return theme.accent
            default: return theme.muted
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
            .onChange(of: store.agentMessages.count) { _, _ in scheduleScrollToBottom(proxy) }
            .onChange(of: store.transientAgentText) { _, _ in scheduleScrollToBottom(proxy) }
            .onChange(of: store.isAgentStreaming) { _, _ in scheduleScrollToBottom(proxy) }
            .onDisappear {
                pendingScrollWorkItem?.cancel()
                pendingFollowUpScrollWorkItem?.cancel()
                pendingScrollWorkItem = nil
                pendingFollowUpScrollWorkItem = nil
            }
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
            .background(theme.promptInputBackground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(promptFocused ? theme.cursor : theme.border))
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
        .background(theme.promptInputBackground)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composerToolbar: some View {
        HStack(spacing: 6) {
            modeMenu
            reasoningMenu
            Spacer(minLength: 4)
            Button {
                submitPrompt()
            } label: {
                Image(systemName: sendButtonSymbol)
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
        .background(theme.promptInputBackground)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var contextAttachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    store.setAutoContextEnabled(!store.isAutoContextEnabled)
                } label: {
                    Label(autoContextTitle, systemImage: store.isAutoContextEnabled ? "paperclip" : "paperclip.circle")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(store.isAutoContextEnabled ? theme.accent.opacity(0.14) : theme.elevated.opacity(0.8))
                        .foregroundStyle(store.isAutoContextEnabled ? theme.accent : theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isAutoContextEnabled ? "Disable Auto Context" : "Enable Auto Context")
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
                if store.selectedHermesProvider == .openAICodex {
                    Menu {
                        ForEach(HermesFastMode.allCases) { mode in
                            Button {
                                Task { await store.setHermesFastMode(mode) }
                            } label: {
                                Label(mode.title, systemImage: mode.symbol)
                            }
                        }
                    } label: {
                        Label("Hermes Fast: \(store.selectedHermesFastMode.title)", systemImage: store.selectedHermesFastMode.symbol)
                    }
                }
                Button {
                    store.setHermesProvider(.auto)
                    store.setHermesModel(.auto)
                    store.setHermesFastModePreference(.normal)
                } label: {
                    Label("Use Hermes Defaults", systemImage: "arrow.counterclockwise")
                }
            case "codex":
                Menu {
                    ForEach(CodexModelOption.allCases) { model in
                        Button {
                            store.setCodexModel(model)
                        } label: {
                            Label(model.title, systemImage: model == .auto ? "sparkles" : "cpu")
                        }
                    }
                } label: {
                    Label("Model: \(store.selectedCodexModel.title)", systemImage: store.selectedCodexModel == .auto ? "sparkles" : "cpu")
                }
                Menu {
                    ForEach(AgentSpeedMode.allCases) { speedMode in
                        Button {
                            store.setSpeedMode(speedMode)
                        } label: {
                            Label(codexSpeedTitle(speedMode), systemImage: speedMode.symbol)
                        }
                    }
                } label: {
                    Label("Speed: \(codexSpeedTitle(store.selectedSpeedMode))", systemImage: store.selectedSpeedMode.symbol)
                }
            case "claude":
                Menu {
                    ForEach(ClaudeModelOption.allCases) { model in
                        Button {
                            store.setClaudeModel(model)
                        } label: {
                            Label(model.title, systemImage: model == .auto ? "sparkles" : "circle.hexagongrid")
                        }
                    }
                } label: {
                    Label("Model: \(store.selectedClaudeModel.title)", systemImage: store.selectedClaudeModel == .auto ? "sparkles" : "circle.hexagongrid")
                }
                Menu {
                    ForEach(ClaudeFastMode.allCases) { mode in
                        Button {
                            store.setClaudeFastMode(mode)
                        } label: {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                } label: {
                    Label("Claude Fast: \(store.selectedClaudeFastMode.title)", systemImage: store.selectedClaudeFastMode.symbol)
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

    private var sessionMenu: some View {
        Menu {
            if selectedAgent.supportsSession {
                if let session = store.selectedAgentSession {
                    Section("Saved Session") {
                        Label(sessionProjectTag(session), systemImage: "tag")
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
                Section("\(selectedAgent.name) Native Sessions") {
                    Button {
                        Task { await store.loadNativeAgentSessions() }
                    } label: {
                        Label(store.isLoadingNativeAgentSessions ? "Loading Project Session" : "Load Project Session", systemImage: "arrow.down.circle")
                    }
                    if currentProjectNativeSessions.isEmpty {
                        Label("No current project session found", systemImage: "tray")
                    }
                }
                if !currentProjectNativeSessions.isEmpty {
                    Section("Current Project") {
                        ForEach(currentProjectNativeSessions.prefix(1)) { session in
                            nativeSessionButton(session)
                        }
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

    private var currentProjectNativeSessions: [ProviderNativeSessionInfo] {
        store.nativeAgentSessions.filter { $0.matchesProject }
    }

    private func nativeSessionButton(_ session: ProviderNativeSessionInfo) -> some View {
        Button {
            Task { await store.importNativeAgentSession(session) }
        } label: {
            Label(nativeSessionMenuTitle(session), systemImage: nativeSessionSymbol(session))
        }
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

    private func sessionProjectTag(_ session: AgentSessionInfo) -> String {
        if let tag = session.projectTag, !tag.isEmpty {
            return tag
        }
        return store.selectedProject?.name ?? selectedAgent.name
    }

    private func sessionSummary(_ session: AgentSessionInfo) -> String {
        var parts = [sessionProjectTag(session)]
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

    private func nativeSessionMenuTitle(_ session: ProviderNativeSessionInfo) -> String {
        if let tag = session.projectTag, !tag.isEmpty {
            return session.imported ? "\(tag) · Imported" : tag
        }
        return store.selectedProject?.name ?? selectedAgent.name
    }

    private func nativeSessionSymbol(_ session: ProviderNativeSessionInfo) -> String {
        if session.imported { return "checkmark.circle" }
        if session.agent == "codex" {
            return "sparkles"
        }
        if session.agent == "claude" {
            return "text.bubble"
        }
        switch session.source.lowercased() {
        case "discord", "slack", "telegram", "whatsapp", "signal", "matrix", "teams":
            return "bubble.left.and.text.bubble.right"
        case "cli":
            return "terminal"
        default:
            return "rectangle.stack"
        }
    }

    private var modelSettingsTitle: String {
        switch store.selectedAgent {
        case "hermes":
            let suffix = store.selectedHermesProvider == .openAICodex && store.selectedHermesFastMode == .fast ? " · Fast" : ""
            if store.selectedHermesProvider == .auto && store.selectedHermesModel == .auto {
                return "Hermes Defaults\(suffix)"
            }
            if store.selectedHermesProvider != .auto && store.selectedHermesModel != .auto {
                return "\(store.selectedHermesProvider.title) / \(store.selectedHermesModel.title)\(suffix)"
            }
            if store.selectedHermesProvider != .auto {
                return "\(store.selectedHermesProvider.title)\(suffix)"
            }
            return "\(store.selectedHermesModel.title)\(suffix)"
        case "codex":
            if store.selectedSpeedMode == .fast {
                return "\(store.selectedCodexModel.title) · 1.5x"
            }
            return store.selectedCodexModel.title
        case "claude":
            if store.selectedClaudeFastMode == .fast {
                return "\(store.selectedClaudeModel.title) · Fast"
            }
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
            return store.selectedClaudeFastMode == .fast ? "bolt.fill" : (store.selectedClaudeModel == .auto ? "sparkles" : "circle.hexagongrid")
        case "codex":
            return store.selectedCodexModel == .auto ? "sparkles" : "cpu"
        default:
            return "slider.horizontal.3"
        }
    }

    private var modelSettingsActive: Bool {
        switch store.selectedAgent {
        case "hermes":
            return store.selectedHermesProvider != .auto || store.selectedHermesModel != .auto || (store.selectedHermesProvider == .openAICodex && store.selectedHermesFastMode == .fast)
        case "codex":
            return store.selectedCodexModel != .auto || store.selectedSpeedMode == .fast
        case "claude":
            return store.selectedClaudeModel != .auto || store.selectedClaudeFastMode == .fast
        default:
            return false
        }
    }

    private func codexSpeedTitle(_ speedMode: AgentSpeedMode) -> String {
        switch speedMode {
        case .auto:
            return "1x"
        case .fast:
            return "1.5x"
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
        guard !trimmedPrompt.isEmpty, store.connectionState == .connected else { return false }
        if store.activeRunId != nil || store.agentRunStatus == .starting {
            return true
        }
        return store.agentCapabilities.isEmpty || selectedAgent.isSelectable
    }

    private var sendButtonSymbol: String {
        if store.activeRunId == nil && store.agentRunStatus != .starting {
            return "arrow.up"
        }
        return "arrow.up"
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
        true
    }

    private var autoContextTitle: String {
        guard store.isAutoContextEnabled else {
            return "Auto context off"
        }
        if let selectedFilePath = store.selectedFilePath {
            return "Open file: \(selectedFilePath)"
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

    private func scheduleScrollToBottom(_ proxy: ScrollViewProxy) {
        pendingScrollWorkItem?.cancel()
        pendingFollowUpScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
        let followUpWorkItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
        pendingScrollWorkItem = workItem
        pendingFollowUpScrollWorkItem = followUpWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36, execute: followUpWorkItem)
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
        agentRunStatus == .starting || (activeRunId != nil && agentRunStatus == .running)
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
            Text(visibleText)
                .font(.caption.monospaced())
                .foregroundStyle(theme.muted)
                .lineLimit(3)
        }
        .padding(10)
        .background(theme.elevated.opacity(0.82))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleText: String {
        text.airCodeDisplaySuffix(limit: 1_800)
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
                .lineLimit(isCollapsible && !expanded ? collapsedLineLimit + 3 : nil)
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
        if !expanded, message.text.count > maxCollapsedCharacters {
            return message.text.airCodeDisplayPrefix(limit: maxCollapsedCharacters)
        }
        if expanded, message.text.count > maxExpandedCharacters {
            return message.text.airCodeDisplayPrefix(limit: maxExpandedCharacters)
        }
        guard isCollapsible, !expanded else { return message.text }
        let lines = message.text.split(separator: "\n", omittingEmptySubsequences: false)
        let prefix = lines.prefix(collapsedLineLimit).joined(separator: "\n")
        return "\(prefix)\n\n... \(lines.count - collapsedLineLimit) more lines hidden"
    }

    private var isCollapsible: Bool {
        guard message.role != .user, message.role != .changes else { return false }
        return message.text.split(separator: "\n", omittingEmptySubsequences: false).count > collapsedLineLimit + 8
    }

    private var maxCollapsedCharacters: Int { 12_000 }

    private var maxExpandedCharacters: Int { 80_000 }

    private var collapsedLineLimit: Int {
        switch message.role {
        case .status, .error:
            return 8
        default:
            return 24
        }
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

private extension String {
    var lineValues: [String] {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func airCodeDisplayPrefix(limit: Int) -> String {
        guard count > limit else { return self }
        let prefix = String(prefix(limit))
        return "\(prefix)\n\n... output trimmed in the live transcript for performance."
    }

    func airCodeDisplaySuffix(limit: Int) -> String {
        guard count > limit else { return self }
        return "... " + String(suffix(limit))
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

    @ViewBuilder
    func airCodeInlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func themedIntegrationNavigationBar(_ theme: AirCodeTheme) -> some View {
        #if os(iOS) || os(visionOS)
        self
            .toolbarBackground(theme.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isLight ? .light : .dark, for: .navigationBar)
        #else
        self
        #endif
    }
}
