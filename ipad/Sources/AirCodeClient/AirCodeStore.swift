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
    @Published public var workspaceRoots: [WorkspaceRootSummary] = []
    @Published public var selectedWorkspaceRootID: String?
    @Published public var workspaceTreeEntries: [String: [TreeEntry]] = [:]
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
    @Published public var selectedReasoningEffort: ReasoningEffort = .auto
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
    private let reasoningDefaultsKey = "AirCode.reasoningEffort"
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
        let rawReasoning = UserDefaults.standard.string(forKey: reasoningDefaultsKey)
        if let rawReasoning, let effort = ReasoningEffort(rawValue: rawReasoning) {
            self.selectedReasoningEffort = effort
        } else {
            self.selectedReasoningEffort = UserDefaults.standard.bool(forKey: "AirCode.ultrathinkEnabled") ? .xhigh : .auto
        }
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

    public func setReasoningEffort(_ effort: ReasoningEffort) {
        selectedReasoningEffort = effort
        UserDefaults.standard.set(effort.rawValue, forKey: reasoningDefaultsKey)
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
            selectedProject = projects.first
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
        if isBottomPanelVisible {
            await ensureTerminal()
        }
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

    public func loadAgentSessions() async {
        guard let api, let selectedProject else { return }
        do {
            agentSessions = try await api.agentSessions(projectId: selectedProject.id)
        } catch {
            agentSessions = []
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

    public func clearSelectedAgentSession() async {
        guard let api, let selectedProject else { return }
        do {
            try await api.clearAgentSession(projectId: selectedProject.id, agent: selectedAgent)
            agentSessions.removeAll { $0.agent == selectedAgent }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runAgent(prompt: String) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let selectedProject, !trimmedPrompt.isEmpty else { return }
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
        agentMessages.append(AgentMessage(role: .user, text: trimmedPrompt))
        do {
            let response = try await api.startAgent(
                projectId: selectedProject.id,
                agent: selectedAgent,
                prompt: trimmedPrompt,
                mode: selectedAgentMode,
                model: selectedCodexModel,
                reasoningEffort: selectedReasoningEffort,
                resumeSession: resumeAgentSession,
                caveman: isCavemanEnabled
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

    private func selectDefaultAgentIfNeeded() {
        guard !agentCapabilities.isEmpty else { return }
        if selectedAgentCapability?.isSelectable == true {
            return
        }
        let preferredOrder = ["codex", "claude", "opencode", "hermes"]
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
        Task { await loadAgentSessions() }

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
            agentMessages.append(AgentMessage(role: .changes, text: "Changes", changes: changedFiles))
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
}

private extension JSONDecoder {
    static var airCode: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var airCode: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
