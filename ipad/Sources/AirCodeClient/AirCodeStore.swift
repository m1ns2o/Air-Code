import Foundation
import SwiftUI

@MainActor
public final class AirCodeStore: ObservableObject {
    @Published public var settings: ConnectionSettings
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var eventConnectionState: EventConnectionState = .disconnected
    @Published public var selectedThemeID: AirCodeThemeID
    @Published public var isSidebarVisible = true
    @Published public var isBottomPanelVisible = true
    @Published public var projects: [ProjectSummary] = []
    @Published public var recentProjects: [RecentProjectSummary] = []
    @Published public var workspaceRoots: [WorkspaceRootSummary] = []
    @Published public var selectedWorkspaceRootID: String?
    @Published public var workspaceTreeEntries: [String: [TreeEntry]] = [:]
    @Published public var isOpenFolderPickerPresented = false
    @Published public var selectedProject: ProjectSummary?
    @Published public var treeEntries: [String: [TreeEntry]] = [:]
    @Published public var openFiles: [OpenFile] = []
    @Published public var selectedFilePath: String?
    @Published public var gitChanges: [GitChange] = []
    @Published public var selectedDiffPath: String?
    @Published public var selectedDiff = ""
    @Published public var isDiffViewerVisible = false
    @Published public var agentMessages: [AgentMessage] = []
    @Published public var transientAgentText: String?
    @Published public var agentCapabilities: [AgentCapability] = []
    @Published public var selectedAgent = "codex"
    @Published public var selectedAgentMode: AgentMode = .agent
    @Published public var selectedCodexModel: CodexModelOption = .auto
    @Published public var selectedClaudeModel: ClaudeModelOption = .auto
    @Published public var selectedHermesProvider: HermesProviderOption = .auto
    @Published public var selectedHermesModel: HermesModelOption = .auto
    @Published public var selectedReasoningEffort: ReasoningEffort = .auto
    @Published public var selectedSpeedMode: AgentSpeedMode = .auto
    @Published public var resumeAgentSession: Bool
    @Published public var isCavemanEnabled: Bool
    @Published public var activeRunId: String?
    @Published public var currentAgentName: String?
    @Published public var agentRunStatus: AgentRunStatus = .idle
    @Published public var lastAgentError: String?
    @Published public var agentSessions: [AgentSessionInfo] = []
    @Published public var terminalSession: TerminalSessionResponse?
    @Published public var terminalConnectionState: TerminalConnectionState = .disconnected
    @Published public var terminalOutput = ""
    @Published public var terminalError: String?
    @Published public var errorMessage: String?

    private let tokenStore: TokenStore
    private let themeDefaultsKey = "AirCode.selectedTheme"
    private let modeDefaultsKey = "AirCode.selectedAgentMode"
    private let modelDefaultsKey = "AirCode.selectedCodexModel"
    private let claudeModelDefaultsKey = "AirCode.selectedClaudeModel"
    private let hermesProviderDefaultsKey = "AirCode.selectedHermesProvider"
    private let hermesModelDefaultsKey = "AirCode.selectedHermesModel"
    private let reasoningDefaultsKey = "AirCode.reasoningEffort"
    private let speedModeDefaultsKey = "AirCode.speedMode"
    private let resumeSessionDefaultsKey = "AirCode.resumeAgentSession"
    private let cavemanDefaultsKey = "AirCode.cavemanEnabled"
    private var api: AirCodeAPI?
    private var eventTask: Task<Void, Never>?
    private var terminalTask: URLSessionWebSocketTask?
    private var terminalReceiveTask: Task<Void, Never>?
    private var finalLogCounts: [String: Int] = [:]

    public enum ConnectionState: String {
        case disconnected
        case connecting
        case connected
        case failed
    }

    public enum EventConnectionState: String {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed
    }

    public enum AgentRunStatus: String {
        case idle
        case starting
        case running
        case completed
        case failed
        case stopped
    }

    public enum TerminalConnectionState: String {
        case disconnected
        case connecting
        case connected
        case exited
        case failed
    }

    public init(tokenStore: TokenStore = KeychainTokenStore()) {
        self.tokenStore = tokenStore
        if let savedSettings = tokenStore.load() {
            self.settings = savedSettings
        } else {
            let settings = ConnectionSettings.developmentDefault
            tokenStore.save(settings)
            self.settings = settings
        }
        let rawTheme = UserDefaults.standard.string(forKey: themeDefaultsKey)
        self.selectedThemeID = rawTheme.flatMap(AirCodeThemeID.init(rawValue:)) ?? .materialOceanic
        let rawMode = UserDefaults.standard.string(forKey: modeDefaultsKey)
        self.selectedAgentMode = rawMode.flatMap(AgentMode.init(rawValue:)) ?? .agent
        let rawModel = UserDefaults.standard.string(forKey: modelDefaultsKey)
        self.selectedCodexModel = rawModel.flatMap(CodexModelOption.init(rawValue:)) ?? .auto
        let rawClaudeModel = UserDefaults.standard.string(forKey: claudeModelDefaultsKey)
        self.selectedClaudeModel = rawClaudeModel.flatMap(ClaudeModelOption.init(rawValue:)) ?? .auto
        let rawHermesProvider = UserDefaults.standard.string(forKey: hermesProviderDefaultsKey)
        self.selectedHermesProvider = rawHermesProvider.flatMap(HermesProviderOption.init(rawValue:)) ?? .auto
        let rawHermesModel = UserDefaults.standard.string(forKey: hermesModelDefaultsKey)
        self.selectedHermesModel = rawHermesModel.flatMap(HermesModelOption.init(rawValue:)) ?? .auto
        let rawReasoning = UserDefaults.standard.string(forKey: reasoningDefaultsKey)
        if let rawReasoning, let effort = ReasoningEffort(rawValue: rawReasoning) {
            self.selectedReasoningEffort = effort
        } else {
            self.selectedReasoningEffort = UserDefaults.standard.bool(forKey: "AirCode.ultrathinkEnabled") ? .xhigh : .auto
        }
        let rawSpeedMode = UserDefaults.standard.string(forKey: speedModeDefaultsKey)
        self.selectedSpeedMode = rawSpeedMode.flatMap(AgentSpeedMode.init(rawValue:)) ?? .auto
        self.resumeAgentSession = UserDefaults.standard.object(forKey: resumeSessionDefaultsKey) as? Bool ?? true
        self.isCavemanEnabled = UserDefaults.standard.bool(forKey: cavemanDefaultsKey)
    }

    deinit {
        eventTask?.cancel()
        terminalReceiveTask?.cancel()
        terminalTask?.cancel(with: .goingAway, reason: nil)
    }

    public var theme: AirCodeTheme {
        selectedThemeID.theme
    }

    public var selectedAgentSession: AgentSessionInfo? {
        agentSessions.first { $0.agent == selectedAgent }
    }

    public var selectableAgentCapabilities: [AgentCapability] {
        agentCapabilities.filter(\.isSelectable)
    }

    public var selectedAgentCapability: AgentCapability? {
        agentCapabilities.first { $0.id == selectedAgent }
    }

    public func setTheme(_ themeID: AirCodeThemeID) {
        selectedThemeID = themeID
        UserDefaults.standard.set(themeID.rawValue, forKey: themeDefaultsKey)
    }

    public func setAgentMode(_ mode: AgentMode) {
        selectedAgentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: modeDefaultsKey)
    }

    public func setCodexModel(_ model: CodexModelOption) {
        selectedCodexModel = model
        UserDefaults.standard.set(model.rawValue, forKey: modelDefaultsKey)
    }

    public func setClaudeModel(_ model: ClaudeModelOption) {
        selectedClaudeModel = model
        UserDefaults.standard.set(model.rawValue, forKey: claudeModelDefaultsKey)
    }

    public func setHermesProvider(_ provider: HermesProviderOption) {
        selectedHermesProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: hermesProviderDefaultsKey)
    }

    public func setHermesModel(_ model: HermesModelOption) {
        selectedHermesModel = model
        UserDefaults.standard.set(model.rawValue, forKey: hermesModelDefaultsKey)
    }

    public func setReasoningEffort(_ effort: ReasoningEffort) {
        selectedReasoningEffort = effort
        UserDefaults.standard.set(effort.rawValue, forKey: reasoningDefaultsKey)
    }

    public func setSpeedMode(_ speedMode: AgentSpeedMode) {
        selectedSpeedMode = speedMode
        UserDefaults.standard.set(speedMode.rawValue, forKey: speedModeDefaultsKey)
    }

    public func setResumeAgentSession(_ isEnabled: Bool) {
        resumeAgentSession = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: resumeSessionDefaultsKey)
    }

    public func setCavemanEnabled(_ isEnabled: Bool) {
        isCavemanEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: cavemanDefaultsKey)
    }

    public func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    public func toggleBottomPanel() {
        isBottomPanelVisible.toggle()
    }

    public func connect() async {
        guard connectionState != .connecting else { return }
        guard let url = URL(string: settings.serverURL), !settings.token.isEmpty else {
            connectionState = .failed
            errorMessage = AirCodeAPIError.missingConnection.localizedDescription
            return
        }
        connectionState = .connecting
        let api = AirCodeAPI(baseURL: url, token: settings.token)
        do {
            try await api.checkAuth()
            tokenStore.save(settings)
            self.api = api
            await loadAgentCapabilities()
            workspaceRoots = try await api.workspaceRoots()
            selectedWorkspaceRootID = workspaceRoots.first?.id
            projects = try await api.projects()
            recentProjects = try await api.recentProjects()
            connectionState = .connected
            errorMessage = nil
            startEventStream(api)
            if let selectedWorkspaceRootID {
                await loadWorkspaceTree(rootId: selectedWorkspaceRootID, path: ".")
            }
            if let selectedProject {
                await loadTree(path: ".", project: selectedProject)
                await refreshGitStatus()
                await loadAgentSessions()
                await loadSelectedAgentConversation()
                if isBottomPanelVisible {
                    await ensureTerminal()
                }
            }
        } catch {
            connectionState = .failed
            eventConnectionState = .disconnected
            errorMessage = error.localizedDescription
        }
    }

    public func maintainConnection() async {
        while !Task.isCancelled {
            if connectionState == .disconnected || connectionState == .failed {
                await connect()
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    public func loadTree(path: String, project: ProjectSummary? = nil) async {
        guard let api, let project = project ?? selectedProject else { return }
        do {
            treeEntries[path] = try await api.tree(projectId: project.id, path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadWorkspaceTree(rootId: String? = nil, path: String) async {
        guard let api, let rootId = rootId ?? selectedWorkspaceRootID else { return }
        do {
            selectedWorkspaceRootID = rootId
            workspaceTreeEntries[path] = try await api.workspaceTree(rootId: rootId, path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openWorkspaceFolder(rootId: String? = nil, path: String) async {
        guard let api, let rootId = rootId ?? selectedWorkspaceRootID else { return }
        do {
            let project = try await api.openWorkspace(rootId: rootId, path: path)
            await open(project: project)
            await loadRecentProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func createAndOpenWorkspaceFolder(rootId: String? = nil, parentPath: String, name: String) async -> Bool {
        guard let api, let rootId = rootId ?? selectedWorkspaceRootID else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name is required."
            return false
        }
        do {
            let project = try await api.createWorkspaceFolder(rootId: rootId, parentPath: parentPath, name: trimmedName)
            workspaceTreeEntries.removeAll()
            await loadWorkspaceTree(rootId: rootId, path: ".")
            await open(project: project)
            await loadRecentProjects()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func open(project: ProjectSummary) async {
        if !projects.contains(where: { $0.id == project.id }) {
            projects.append(project)
        }
        await closeTerminal()
        selectedProject = project
        treeEntries.removeAll()
        openFiles.removeAll()
        selectedFilePath = nil
        isDiffViewerVisible = false
        await loadTree(path: ".", project: project)
        await refreshGitStatus()
        await loadAgentSessions()
        await loadSelectedAgentConversation()
        if isBottomPanelVisible {
            await ensureTerminal()
        }
    }

    public func loadRecentProjects() async {
        guard let api else { return }
        do {
            recentProjects = try await api.recentProjects()
        } catch {
            recentProjects = []
        }
    }

    public func openRecentProject(_ recent: RecentProjectSummary) async {
        guard let api else { return }
        do {
            let project = try await api.openRecentProject(id: recent.id)
            await open(project: project)
            await loadRecentProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func forgetRecentProject(_ recent: RecentProjectSummary) async {
        guard let api else { return }
        do {
            try await api.deleteRecentProject(id: recent.id)
            await loadRecentProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func showOpenFolderPicker() {
        isOpenFolderPickerPresented = true
    }

    public func hideOpenFolderPicker() {
        isOpenFolderPickerPresented = false
    }

    public func open(entry: TreeEntry) async {
        if entry.isDirectory {
            await loadTree(path: entry.path)
            return
        }
        await openFile(path: entry.path)
    }

    public func openFile(path: String) async {
        if openFiles.contains(where: { $0.path == path }) {
            selectedFilePath = path
            return
        }
        guard let api, let selectedProject else { return }
        do {
            let file = try await api.readFile(projectId: selectedProject.id, path: path)
            openFiles.append(OpenFile(path: path, content: file.content, savedContent: file.content, version: file.version, conflictVersion: nil))
            selectedFilePath = path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateSelectedFileContent(_ content: String) {
        guard let selectedFilePath,
              let index = openFiles.firstIndex(where: { $0.path == selectedFilePath }) else { return }
        openFiles[index].content = content
    }

    public func saveSelectedFile() async {
        guard let api,
              let selectedProject,
              let selectedFilePath,
              let index = openFiles.firstIndex(where: { $0.path == selectedFilePath }) else { return }
        let file = openFiles[index]
        do {
            let saved = try await api.saveFile(projectId: selectedProject.id, path: file.path, content: file.content, baseVersion: file.version)
            openFiles[index].content = saved.content
            openFiles[index].savedContent = saved.content
            openFiles[index].version = saved.version
            openFiles[index].conflictVersion = nil
            await refreshGitStatus()
        } catch {
            openFiles[index].conflictVersion = "conflict"
            errorMessage = error.localizedDescription
        }
    }

    public func close(path: String) {
        openFiles.removeAll { $0.path == path }
        if selectedFilePath == path {
            selectedFilePath = openFiles.last?.path
        }
    }

    public func refreshGitStatus() async {
        guard let api, let selectedProject else { return }
        do {
            gitChanges = try await api.gitStatus(projectId: selectedProject.id)
        } catch {
            gitChanges = []
        }
    }

    public func loadDiff(path: String) async {
        guard let api, let selectedProject else { return }
        do {
            let response = try await api.diff(projectId: selectedProject.id, path: path)
            selectedDiffPath = path
            selectedDiff = response.diff
            isDiffViewerVisible = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revert(path: String) async {
        guard let api, let selectedProject else { return }
        do {
            try await api.revert(projectId: selectedProject.id, path: path)
            await refreshGitStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revert(paths: [String]) async {
        for path in paths {
            await revert(path: path)
        }
    }

    public func revertRun(runId: String) async {
        guard let api, let selectedProject else { return }
        do {
            let response = try await api.revertAgentRun(projectId: selectedProject.id, runId: runId)
            await refreshGitStatus()
            let revertedCount = response.reverted.count
            if response.conflicts.isEmpty {
                agentMessages.append(AgentMessage(role: .status, text: "Reverted \(revertedCount) files from run \(shortRunId(runId))."))
            } else {
                let skipped = response.conflicts.map { "\($0.path): \($0.reason)" }.joined(separator: "\n")
                agentMessages.append(AgentMessage(role: .status, text: "Reverted \(revertedCount) files from run \(shortRunId(runId)). Some files changed after the run and were skipped:\n\(skipped)"))
            }
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Run revert failed: \(error.localizedDescription)"))
        }
    }

    public func loadAgentSessions() async {
        guard let api, let selectedProject else { return }
        do {
            agentSessions = try await api.agentSessions(projectId: selectedProject.id)
        } catch {
            agentSessions = []
        }
    }

    public func loadSelectedAgentConversation() async {
        guard activeRunId == nil else { return }
        guard let api, let selectedProject else { return }
        do {
            let conversation = try await api.agentConversation(projectId: selectedProject.id, agent: selectedAgent)
            agentMessages = conversation.messages.map(\.agentMessage)
        } catch {
            agentMessages = []
        }
    }

    public func loadAgentCapabilities() async {
        guard let api else { return }
        do {
            agentCapabilities = try await api.agentCapabilities()
            selectDefaultAgentIfNeeded()
        } catch {
            agentCapabilities = []
        }
    }

    public func selectAgent(_ agent: String) async {
        selectedAgent = agent
        transientAgentText = nil
        currentAgentName = nil
        if activeRunId == nil {
            agentRunStatus = .idle
        }
        await loadAgentSessions()
        await loadSelectedAgentConversation()
    }

    public func clearSelectedAgentSession() async {
        guard let api, let selectedProject else { return }
        do {
            try await api.clearAgentSession(projectId: selectedProject.id, agent: selectedAgent)
            agentSessions.removeAll { $0.agent == selectedAgent }
            agentMessages = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runAgent(prompt: String) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let selectedProject, !trimmedPrompt.isEmpty else { return }
        let command = AgentPromptCommand.parse(trimmedPrompt, agent: selectedAgent)
        if let localAction = command.localAction {
            await applySlashCommandAction(localAction)
            return
        }
        let runPrompt = command.prompt
        guard !runPrompt.isEmpty else { return }
        let runMode = command.mode ?? selectedAgentMode
        let runReasoning = command.reasoningEffort ?? selectedReasoningEffort
        let runSpeedMode = command.speedMode ?? selectedSpeedMode
        let runResumeSession = command.resumeSession ?? resumeAgentSession
        let runCaveman = command.caveman ?? isCavemanEnabled
        if runMode == .goal && !["codex", "claude", "hermes"].contains(selectedAgent) {
            agentMessages.append(AgentMessage(role: .error, text: "Goal mode is currently available only for Codex, Claude Code, and Hermes."))
            return
        }
        if !agentCapabilities.isEmpty && selectedAgentCapability?.isSelectable != true {
            let message = "\(displayName(for: selectedAgent)) is not installed or configured on the server."
            lastAgentError = message
            agentRunStatus = .failed
            agentMessages.append(AgentMessage(role: .error, text: message))
            return
        }
        lastAgentError = nil
        transientAgentText = nil
        agentRunStatus = .starting
        currentAgentName = selectedAgent
        if !runResumeSession {
            agentMessages = []
        }
        agentMessages.append(AgentMessage(role: .user, text: runPrompt))
        do {
            let response = try await api.startAgent(
                projectId: selectedProject.id,
                agent: selectedAgent,
                prompt: runPrompt,
                mode: runMode,
                provider: selectedAgentProviderID,
                model: selectedAgentModelID,
                reasoningEffort: runReasoning,
                speedMode: runSpeedMode,
                resumeSession: runResumeSession,
                caveman: runCaveman
            )
            activeRunId = response.runId
            currentAgentName = response.agent
            finalLogCounts[response.runId] = 0
            agentRunStatus = .running
        } catch {
            agentRunStatus = .failed
            lastAgentError = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to start \(displayName(for: selectedAgent)): \(error.localizedDescription)"))
            errorMessage = error.localizedDescription
        }
    }

    private func applySlashCommandAction(_ action: AgentPromptCommand.LocalAction) async {
        switch action {
        case .help:
            agentMessages.append(AgentMessage(role: .status, text: AgentPromptCommand.helpText))
        case .newSession:
            setResumeAgentSession(false)
            agentMessages = [AgentMessage(role: .status, text: "New session selected. Your next prompt will start a clean transcript.")]
        case .resumeSession:
            setResumeAgentSession(true)
            agentMessages.append(AgentMessage(role: .status, text: "Resume selected. Your next prompt will continue the saved session when one exists."))
        case .ultrathink:
            setReasoningEffort(.xhigh)
            agentMessages.append(AgentMessage(role: .status, text: "Ultrathink selected. Future prompts will use xhigh reasoning until you change it."))
        case .caveman:
            setCavemanEnabled(true)
            agentMessages.append(AgentMessage(role: .status, text: "Caveman mode selected. Future prompts will use terse output until you turn it off."))
        case .setReasoning(let effort):
            setReasoningEffort(effort)
            agentMessages.append(AgentMessage(role: .status, text: "Reasoning effort set to \(effort.title)."))
        case .setSpeed(let speedMode):
            if !speedMode.isSupported(by: selectedAgent) {
                agentMessages.append(AgentMessage(role: .status, text: "Speed overrides are available for Codex only in Air Code right now. \(displayName(for: selectedAgent)) will use its provider default."))
                return
            }
            setSpeedMode(speedMode)
            let title = speedMode.title(for: selectedAgent)
            agentMessages.append(AgentMessage(role: .status, text: "Speed mode set to \(title)."))
        case .showStatus:
            agentMessages.append(AgentMessage(role: .status, text: slashStatusText()))
        case .openDiff(let path):
            let requestedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requestedPath.isEmpty {
                await loadDiff(path: requestedPath)
            } else {
                if gitChanges.isEmpty {
                    await refreshGitStatus()
                }
                if let firstChange = gitChanges.first {
                    await loadDiff(path: firstChange.path)
                } else {
                    agentMessages.append(AgentMessage(role: .status, text: "No changed files to diff."))
                }
            }
        case .message(let text):
            agentMessages.append(AgentMessage(role: .status, text: text))
        case .missingPrompt(let command):
            agentMessages.append(AgentMessage(role: .status, text: "Add instructions after \(command), then press Enter."))
        }
    }

    private func slashStatusText() -> String {
        let sessionText = selectedAgentSession?.sessionId ?? "none"
        let speedText = selectedSpeedMode.isSupported(by: selectedAgent) ? selectedSpeedMode.title(for: selectedAgent) : "Default"
        return """
Agent: \(displayName(for: selectedAgent))
Mode: \(selectedAgentMode.title)
Model: \(selectedModelStatusText())
Reasoning: \(selectedReasoningEffort.title)
Speed: \(speedText)
Resume: \(resumeAgentSession ? "on" : "off")
Session: \(sessionText)
"""
    }

    private func selectedModelStatusText() -> String {
        switch selectedAgent {
        case "codex":
            return selectedCodexModel.title
        case "claude":
            return selectedClaudeModel.title
        case "hermes":
            return "\(selectedHermesProvider.title) / \(selectedHermesModel.title)"
        default:
            return "server default"
        }
    }

    public func stopAgent() async {
        guard let api, let selectedProject, let activeRunId else { return }
        do {
            try await api.stopAgent(projectId: selectedProject.id, runId: activeRunId)
            self.activeRunId = nil
            transientAgentText = nil
            agentRunStatus = .stopped
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runCommand(line: String) async {
        terminalOutput += "\n$ \(line)\n"
    }

    public func ensureTerminal(cols: UInt16 = 120, rows: UInt16 = 32) async {
        guard terminalSession == nil || terminalConnectionState == .failed || terminalConnectionState == .exited else { return }
        await startTerminal(cols: cols, rows: rows)
    }

    public func startTerminal(cols: UInt16 = 120, rows: UInt16 = 32) async {
        guard let api, let selectedProject else {
            terminalConnectionState = .disconnected
            return
        }
        terminalReceiveTask?.cancel()
        terminalTask?.cancel(with: .goingAway, reason: nil)
        terminalSession = nil
        terminalConnectionState = .connecting
        terminalError = nil
        do {
            let session = try await api.createTerminal(projectId: selectedProject.id, cols: cols, rows: rows)
            terminalSession = session
            terminalOutput = ""
            connectTerminalStream(api: api, session: session)
        } catch {
            terminalConnectionState = .failed
            terminalError = error.localizedDescription
            terminalOutput += "\n[terminal] \(error.localizedDescription)\n"
        }
    }

    public func reconnectTerminal() async {
        if terminalConnectionState == .failed || terminalConnectionState == .exited {
            terminalSession = nil
            await startTerminal()
            return
        }
        guard let api, let session = terminalSession else {
            await startTerminal()
            return
        }
        terminalReceiveTask?.cancel()
        terminalTask?.cancel(with: .goingAway, reason: nil)
        terminalConnectionState = .connecting
        terminalError = nil
        connectTerminalStream(api: api, session: session)
    }

    public func sendTerminalInput(_ data: Data) {
        guard !data.isEmpty else { return }
        sendTerminalFrame(TerminalFrame.dataFrame(data))
    }

    public func resizeTerminal(cols: UInt16, rows: UInt16) {
        sendTerminalFrame(TerminalFrame.resizeFrame(cols: cols, rows: rows))
    }

    public func clearTerminal() {
        terminalOutput = ""
    }

    public func closeTerminal() async {
        let session = terminalSession
        sendTerminalFrame(TerminalFrame.closeFrame)
        terminalReceiveTask?.cancel()
        terminalTask?.cancel(with: .goingAway, reason: nil)
        terminalTask = nil
        terminalReceiveTask = nil
        terminalSession = nil
        terminalConnectionState = .disconnected
        if let api, let selectedProject, let session {
            try? await api.closeTerminal(projectId: selectedProject.id, terminalId: session.terminalId)
        }
    }

    public func displayName(for agent: String) -> String {
        if let capability = agentCapabilities.first(where: { $0.id == agent }) {
            return capability.displayName
        }
        switch agent.lowercased() {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "opencode": return "OpenCode"
        case "hermes": return "Hermes"
        default: return agent
        }
    }

    public func symbol(for agent: String) -> String {
        switch agent.lowercased() {
        case "codex": return "sparkles"
        case "claude": return "circle.hexagongrid"
        case "opencode": return "terminal"
        case "hermes": return "h.circle"
        default: return "wand.and.stars"
        }
    }

    private var selectedAgentProviderID: String {
        selectedAgent == "hermes" ? selectedHermesProvider.providerID : ""
    }

    private var selectedAgentModelID: String {
        switch selectedAgent {
        case "codex":
            return selectedCodexModel.modelID
        case "claude":
            return selectedClaudeModel.modelID
        case "hermes":
            return selectedHermesModel.modelID
        default:
            return ""
        }
    }

    private func selectDefaultAgentIfNeeded() {
        guard !agentCapabilities.isEmpty else { return }
        if selectedAgentCapability?.isSelectable == true {
            return
        }
        let preferredOrder = ["codex", "claude", "hermes", "opencode"]
        if let preferred = preferredOrder.compactMap({ id in
            agentCapabilities.first { $0.id == id && $0.isSelectable }
        }).first {
            selectedAgent = preferred.id
        } else if let first = agentCapabilities.first {
            selectedAgent = first.id
        }
    }

    private func connectTerminalStream(api: AirCodeAPI, session: TerminalSessionResponse) {
        do {
            let task = try api.makeTerminalWebSocketTask(projectId: session.projectId, terminalId: session.terminalId)
            terminalTask = task
            task.resume()
            terminalConnectionState = .connected
            terminalReceiveTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .data(let payload):
                            self.handleTerminalFrame(payload)
                        case .string(let text):
                            self.handleLegacyTerminalMessage(text)
                        @unknown default:
                            continue
                        }
                    } catch {
                        if Task.isCancelled { return }
                        self.terminalConnectionState = .failed
                        self.terminalError = error.localizedDescription
                        self.terminalOutput += "\n[terminal] \(error.localizedDescription)\n"
                        return
                    }
                }
            }
        } catch {
            terminalConnectionState = .failed
            terminalError = error.localizedDescription
            terminalOutput += "\n[terminal] \(error.localizedDescription)\n"
        }
    }

    private func handleTerminalFrame(_ frame: Data) {
        guard let frameType = frame.first else { return }
        let payload = frame.dropFirst()
        switch frameType {
        case TerminalFrame.data:
            terminalOutput += String(decoding: payload, as: UTF8.self)
        case TerminalFrame.exit:
            terminalConnectionState = .exited
            terminalOutput += "\n[terminal exited]\n"
        case TerminalFrame.error:
            terminalConnectionState = .failed
            let messageText = String(decoding: payload, as: UTF8.self)
            terminalError = messageText
            terminalOutput += "\n[terminal] \(messageText)\n"
        default:
            break
        }
    }

    private func handleLegacyTerminalMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder.airCode.decode(TerminalServerMessage.self, from: data) else {
            terminalOutput += text
            return
        }
        switch message.type {
        case "output":
            terminalOutput += message.data ?? ""
        case "exit":
            terminalConnectionState = .exited
            terminalOutput += "\n[terminal exited]\n"
        case "error":
            terminalConnectionState = .failed
            let messageText = message.message ?? "Terminal error."
            terminalError = messageText
            terminalOutput += "\n[terminal] \(messageText)\n"
        default:
            break
        }
    }

    private func sendTerminalFrame(_ frame: Data) {
        guard let terminalTask else { return }
        Task {
            do {
                try await terminalTask.send(.data(frame))
            } catch {
                terminalConnectionState = .failed
                terminalError = error.localizedDescription
            }
        }
    }

    private func startEventStream(_ api: AirCodeAPI) {
        eventTask?.cancel()
        eventConnectionState = .connecting
        eventTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    self?.eventConnectionState = .connected
                    for try await event in api.eventStream() {
                        self?.handle(event)
                    }
                    self?.eventConnectionState = .reconnecting
                } catch {
                    if Task.isCancelled { return }
                    self?.eventConnectionState = .failed
                    self?.errorMessage = error.localizedDescription
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func handle(_ event: EventEnvelope) {
        switch event.type {
        case "agent.started":
            handleAgentStarted(event)
        case "agent.log":
            handleAgentLog(event)
        case "agent.finished":
            handleAgentFinished(event)
            Task { await refreshGitStatus() }
        case "file.batchChanged":
            Task { await refreshGitStatus() }
        default:
            break
        }
    }

    private func handleAgentStarted(_ event: EventEnvelope) {
        let runId = event.payload?["runId"]?.stringValue
        let agent = event.payload?["agent"]?.stringValue ?? selectedAgent
        if let runId {
            activeRunId = runId
            finalLogCounts[runId] = finalLogCounts[runId] ?? 0
        }
        currentAgentName = agent
        agentRunStatus = .running
    }

    private func handleAgentLog(_ event: EventEnvelope) {
        guard let line = event.payload?["line"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return }
        let kind = event.payload?["kind"]?.stringValue ?? "progress"
        let runId = event.payload?["runId"]?.stringValue
        agentRunStatus = .running

        switch kind {
        case "session":
            Task { await loadAgentSessions() }
        case "final", "answer":
            if let runId { finalLogCounts[runId, default: 0] += 1 }
            transientAgentText = nil
            agentMessages.append(AgentMessage(role: .agent, text: line))
        case "error":
            transientAgentText = nil
            agentMessages.append(AgentMessage(role: .error, text: line))
        default:
            transientAgentText = line
        }
    }

    private func handleAgentFinished(_ event: EventEnvelope) {
        let runId = event.payload?["runId"]?.stringValue
        let agent = event.payload?["agent"]?.stringValue ?? currentAgentName ?? selectedAgent
        let status = event.payload?["status"]?.stringValue ?? "completed"
        let error = event.payload?["error"]?.stringValue
        let changedFiles = gitChanges(from: event.payload?["changedFiles"])
        let finalCount = runId.flatMap { finalLogCounts[$0] } ?? 0

        activeRunId = nil
        currentAgentName = agent
        transientAgentText = nil
        if let runId {
            finalLogCounts.removeValue(forKey: runId)
        }

        switch status {
        case "completed":
            agentRunStatus = .completed
            if finalCount == 0 && changedFiles.isEmpty {
                agentMessages.append(AgentMessage(role: .status, text: "\(displayName(for: agent)) completed without text output."))
            }
        case "stopped":
            agentRunStatus = .stopped
            agentMessages.append(AgentMessage(role: .status, text: "\(displayName(for: agent)) stopped."))
        default:
            agentRunStatus = .failed
            let message = error ?? "No error detail was returned by the server."
            lastAgentError = message
            agentMessages.append(AgentMessage(role: .error, text: "\(displayName(for: agent)) failed: \(message)"))
        }

        if !changedFiles.isEmpty {
            agentMessages.append(AgentMessage(role: .changes, text: "Changes", runId: runId, changes: changedFiles))
        }
        Task {
            await loadAgentSessions()
            if agent == selectedAgent {
                await loadSelectedAgentConversation()
            }
        }
    }

    private func gitChanges(from value: JSONValue?) -> [GitChange] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { item in
            guard case .object(let object) = item,
                  let path = object["path"]?.stringValue,
                  let status = object["status"]?.stringValue else { return nil }
            return GitChange(path: path, status: status)
        }
    }

    private func shortRunId(_ runId: String) -> String {
        guard runId.count > 12 else { return runId }
        return "\(runId.prefix(8))...\(runId.suffix(4))"
    }
}

private extension JSONDecoder {
    static var airCode: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct AgentPromptCommand: Equatable, Sendable {
    enum LocalAction: Equatable, Sendable {
        case help
        case newSession
        case resumeSession
        case ultrathink
        case caveman
        case setReasoning(ReasoningEffort)
        case setSpeed(AgentSpeedMode)
        case showStatus
        case openDiff(String)
        case message(String)
        case missingPrompt(String)
    }

    let prompt: String
    let mode: AgentMode?
    let resumeSession: Bool?
    let reasoningEffort: ReasoningEffort?
    let speedMode: AgentSpeedMode?
    let caveman: Bool?
    let localAction: LocalAction?

    init(prompt: String, mode: AgentMode?, resumeSession: Bool?, reasoningEffort: ReasoningEffort?, speedMode: AgentSpeedMode? = nil, caveman: Bool?, localAction: LocalAction?) {
        self.prompt = prompt
        self.mode = mode
        self.resumeSession = resumeSession
        self.reasoningEffort = reasoningEffort
        self.speedMode = speedMode
        self.caveman = caveman
        self.localAction = localAction
    }

    static let helpText = """
Supported slash commands:
/plan <prompt> - ask for a plan first
/goal <prompt> - run Codex, Claude, or Hermes goal mode
/new <prompt> - start a clean session
/resume <prompt> - continue the saved session
/effort <level> <prompt> - use low, medium, high, xhigh, or max
/speed <default|fast> - choose provider default or Codex fast mode
/fast [on|off|status] - shortcut for Codex fast mode
/ultrathink <prompt> - use xhigh reasoning
/caveman <prompt> - use terse output
/review, /verify, /debug, /run, /simplify, /security-review - task shortcuts
/diff - open the first changed file in the side-by-side diff view
/status - show current agent settings
Hermes also accepts native commands such as /rollback, /history, /sessions, /commands, /skills, /tools, /reasoning, /queue, /steer, and /yolo.
"""

    static func parse(_ text: String, agent: String = "codex") -> AgentPromptCommand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return AgentPromptCommand(prompt: trimmed, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        }

        let body = String(trimmed.dropFirst())
        let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawCommand = parts.first else {
            return AgentPromptCommand(prompt: trimmed, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: .help)
        }
        let command = rawCommand.lowercased()
        let remainder = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if agent.lowercased() == "hermes", hermesNativePassthroughCommands.contains(command) {
            return providerNative(trimmed)
        }

        switch command {
        case "help", "?":
            return local(.help)
        case "plan":
            return remainder.isEmpty ? local(.missingPrompt("/plan")) : AgentPromptCommand(prompt: remainder, mode: .plan, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "goal", "goals":
            return remainder.isEmpty ? local(.missingPrompt("/goal")) : AgentPromptCommand(prompt: remainder, mode: .goal, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "new", "clear":
            return remainder.isEmpty ? local(.newSession) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: false, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "resume", "continue":
            return remainder.isEmpty ? local(.resumeSession) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: true, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "effort":
            return parseEffortCommand(remainder)
        case "speed":
            return parseSpeedCommand(remainder)
        case "fast":
            return parseFastCommand(remainder)
        case "ultrathink":
            return remainder.isEmpty ? local(.ultrathink) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: nil, reasoningEffort: .xhigh, caveman: nil, localAction: nil)
        case "caveman":
            return remainder.isEmpty ? local(.caveman) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: true, localAction: nil)
        case "review":
            return AgentPromptCommand(prompt: taskPrompt(remainder, fallback: "Review the current changes for bugs, behavioral regressions, and missing tests. Lead with findings and include file references when possible."), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "security-review":
            return AgentPromptCommand(prompt: taskPrompt(remainder, fallback: "Review the current project changes for security risks, unsafe command execution, credential exposure, path traversal, and authentication issues. Lead with actionable findings."), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "debug":
            return remainder.isEmpty ? local(.missingPrompt("/debug")) : AgentPromptCommand(prompt: "Debug this issue and identify the root cause before changing code: \(remainder)", mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "run":
            return AgentPromptCommand(prompt: taskPrompt(remainder, fallback: "Run the app or the most relevant smoke path, inspect failures, and report the exact result."), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "verify":
            return AgentPromptCommand(prompt: taskPrompt(remainder, fallback: "Build, test, and verify the current implementation end to end. Fix issues found during verification."), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "simplify":
            return AgentPromptCommand(prompt: taskPrompt(remainder, fallback: "Simplify the current implementation without changing behavior. Prefer existing project patterns and keep the change scoped."), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "init":
            return AgentPromptCommand(prompt: initPrompt(agent: agent, remainder: remainder), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "diff":
            return local(.openDiff(remainder))
        case "status", "cost", "usage":
            return local(.showStatus)
        case "model":
            return local(.message("Use the model menu in the chat header. Air Code sends the selected model to Codex, Claude Code, or Hermes on each run."))
        case "doctor":
            return local(.message("Run `aircoded doctor -config config.json` on the server, or use the provider CLI doctor command in the terminal."))
        case "ide", "permissions", "keymap", "keybindings", "vim", "experimental", "approve", "memories", "memory", "skills", "hooks", "rename", "fork", "compact", "collab", "agent", "side", "copy", "raw", "mention", "title", "statusline", "theme", "mcp", "plugins", "plugin", "logout", "login", "agents", "batch", "branch", "btw", "context", "rewind", "tasks", "ultraplan", "ultrareview", "add-dir", "background", "color", "config", "export", "feedback", "focus", "loop", "recap", "release-notes", "reload-plugins", "stop", "terminal-setup", "voice", "web-setup":
            return local(.message(nativeCommandMessage(command: command, agent: agent)))
        default:
            return AgentPromptCommand(prompt: trimmed, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        }
    }

    private static func local(_ action: LocalAction) -> AgentPromptCommand {
        AgentPromptCommand(prompt: "", mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: action)
    }

    private static func providerNative(_ prompt: String) -> AgentPromptCommand {
        AgentPromptCommand(prompt: prompt, mode: .agent, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
    }

    private static func parseEffortCommand(_ remainder: String) -> AgentPromptCommand {
        guard !remainder.isEmpty else {
            return local(.message("Use /effort low|medium|high|xhigh|max, or add a prompt after the level."))
        }
        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawLevel = parts.first, let effort = effort(from: String(rawLevel)) else {
            return local(.message("Unknown effort level. Use low, medium, high, xhigh, ultrathink, or max."))
        }
        let prompt = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if prompt.isEmpty {
            return local(.setReasoning(effort))
        }
        return AgentPromptCommand(prompt: prompt, mode: nil, resumeSession: nil, reasoningEffort: effort, caveman: nil, localAction: nil)
    }

    private static func parseSpeedCommand(_ remainder: String) -> AgentPromptCommand {
        guard !remainder.isEmpty else {
            return local(.message("Use /speed default|fast, or /fast on|off|status."))
        }
        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawMode = parts.first, let speedMode = speed(from: String(rawMode)) else {
            return local(.message("Unknown speed mode. Use default, fast, on, or off."))
        }
        let prompt = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if prompt.isEmpty {
            return local(.setSpeed(speedMode))
        }
        return AgentPromptCommand(prompt: prompt, mode: nil, resumeSession: nil, reasoningEffort: nil, speedMode: speedMode, caveman: nil, localAction: nil)
    }

    private static func parseFastCommand(_ remainder: String) -> AgentPromptCommand {
        if remainder.isEmpty {
            return local(.setSpeed(.fast))
        }
        let command = remainder.lowercased()
        switch command {
        case "on", "true", "yes", "1":
            return local(.setSpeed(.fast))
        case "off", "false", "no", "0":
            return local(.setSpeed(.auto))
        case "status":
            return local(.showStatus)
        default:
            return local(.message("Use /fast on, /fast off, or /fast status."))
        }
    }

    private static func effort(from rawLevel: String) -> ReasoningEffort? {
        switch rawLevel.lowercased() {
        case "auto": return .auto
        case "low": return .low
        case "medium", "med": return .medium
        case "high": return .high
        case "xhigh", "ultra", "ultrathink": return .xhigh
        case "max": return .max
        default: return nil
        }
    }

    private static func speed(from rawMode: String) -> AgentSpeedMode? {
        switch rawMode.lowercased() {
        case "auto", "default", "provider", "provider-default": return .auto
        case "standard", "normal", "off": return .auto
        case "fast", "on", "1.5", "1.5x", "priority": return .fast
        default: return nil
        }
    }

    private static func taskPrompt(_ remainder: String, fallback: String) -> String {
        remainder.isEmpty ? fallback : "\(fallback)\n\nUser focus: \(remainder)"
    }

    private static func initPrompt(agent: String, remainder: String) -> String {
        let target = agent.lowercased() == "claude" ? "CLAUDE.md" : "AGENTS.md"
        let extra = remainder.isEmpty ? "" : "\n\nUser focus: \(remainder)"
        return "Inspect this project and create or update \(target) with concise project-specific guidance for future agent runs. Keep it practical and avoid over-documenting obvious details.\(extra)"
    }

    private static func nativeCommandMessage(command: String, agent: String) -> String {
        let provider: String
        switch agent.lowercased() {
        case "claude":
            provider = "Claude Code"
        case "hermes":
            provider = "Hermes"
        default:
            provider = "Codex"
        }
        return "/\(command) is a \(provider) native terminal command. Air Code keeps the equivalent control in its native UI or server config; run the provider CLI in the terminal when you need that exact interactive command."
    }

    private static let hermesNativePassthroughCommands: Set<String> = [
        "plan",
        "goal",
        "subgoal",
        "rollback",
        "history",
        "save",
        "retry",
        "undo",
        "title",
        "compress",
        "sessions",
        "commands",
        "tools",
        "toolsets",
        "skills",
        "reasoning",
        "usage",
        "queue",
        "q",
        "steer",
        "background",
        "bg",
        "btw",
        "fast",
        "footer",
        "curator",
        "kanban",
        "reload-mcp",
        "reload_mcp",
        "reload-skills",
        "yolo",
        "voice"
    ]
}

private extension JSONEncoder {
    static var airCode: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
