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
    @Published public var selectedProject: ProjectSummary?
    @Published public var treeEntries: [String: [TreeEntry]] = [:]
    @Published public var openFiles: [OpenFile] = []
    @Published public var selectedFilePath: String?
    @Published public var fileConflicts: [String: FileConflict] = [:]
    @Published public var gitChanges: [GitChange] = []
    @Published public var selectedDiffPath: String?
    @Published public var selectedDiff = ""
    @Published public var isDiffViewerVisible = false
    @Published public var searchQuery = ""
    @Published public var searchResults: [SearchResult] = []
    @Published public var isSearching = false
    @Published public var searchMessage: String?
    @Published public var permissionSnapshot: PermissionSnapshot?
    @Published public var providerStatus: ProviderStatusResponse?
    @Published public var isPermissionPanelVisible = false
    @Published public var integrationStatus: IntegrationStatus?
    @Published public var integrationInventory: IntegrationInventory?
    @Published public var isIntegrationPanelVisible = false
    @Published public var agentMessages: [AgentMessage] = []
    @Published public var transientAgentText: String?
    @Published public var agentTimelineEvents: [AgentRuntimeEvent] = []
    @Published public var pendingApproval: PendingApprovalRequest?
    @Published public var approvalRecords: [ApprovalRecord] = []
    @Published public var approvalHistory: [ApprovalRecord] = []
    @Published public var resolvedEditApprovalRunIds: Set<String> = []
    @Published public var agentCapabilities: [AgentCapability] = []
    @Published public var selectedAgent = "codex"
    @Published public var selectedAgentMode: AgentMode = .agent
    @Published public var selectedCodexModel: CodexModelOption = .auto
    @Published public var selectedClaudeModel: ClaudeModelOption = .auto
    @Published public var selectedClaudeFastMode: ClaudeFastMode = .normal
    @Published public var selectedHermesProvider: HermesProviderOption = .auto
    @Published public var selectedHermesModel: HermesModelOption = .auto
    @Published public var selectedHermesFastMode: HermesFastMode = .normal
    @Published public var selectedReasoningEffort: ReasoningEffort = .auto
    @Published public var selectedSpeedMode: AgentSpeedMode = .auto
    @Published public var selectedCodexApprovalMode: CodexApprovalMode = .serverDefault
    @Published public var selectedCodexSandboxMode: CodexSandboxMode = .serverDefault
    @Published public var selectedClaudePermissionMode: ClaudePermissionMode = .serverDefault
    @Published public var selectedHermesPermissionMode: HermesPermissionMode = .serverDefault
    @Published public var resumeAgentSession: Bool
    @Published public var isCavemanEnabled: Bool
    @Published public var isAutoContextEnabled: Bool
    @Published public var promptSteeringText: String
    @Published public var pendingContextAttachments: [ContextAttachment] = []
    @Published public var pendingPromptAttachments: [AgentAttachment] = []
    @Published public var isUploadingAttachment = false
    @Published public var mcpCatalogItems: [MCPCatalogItem] = []
    @Published public var isSearchingMCPCatalog = false
    @Published public var mcpCatalogError: String?
    @Published public var editorContextSnapshot: EditorContextSnapshot?
    @Published public var activeRunId: String?
    @Published public var currentAgentName: String?
    @Published public var agentRunStatus: AgentRunStatus = .idle
    @Published public var lastAgentError: String?
    @Published public var agentSessions: [AgentSessionInfo] = []
    @Published public var nativeAgentSessions: [ProviderNativeSessionInfo] = []
    @Published public var isLoadingNativeAgentSessions = false
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
    private let claudeFastModeDefaultsKey = "AirCode.selectedClaudeFastMode"
    private let hermesProviderDefaultsKey = "AirCode.selectedHermesProvider"
    private let hermesModelDefaultsKey = "AirCode.selectedHermesModel"
    private let hermesFastModeDefaultsKey = "AirCode.selectedHermesFastMode"
    private let reasoningDefaultsKey = "AirCode.reasoningEffort"
    private let speedModeDefaultsKey = "AirCode.speedMode"
    private let codexApprovalDefaultsKey = "AirCode.codexApprovalMode"
    private let codexSandboxDefaultsKey = "AirCode.codexSandboxMode"
    private let claudePermissionDefaultsKey = "AirCode.claudePermissionMode"
    private let hermesPermissionDefaultsKey = "AirCode.hermesPermissionMode"
    private let resumeSessionDefaultsKey = "AirCode.resumeAgentSession"
    private let cavemanDefaultsKey = "AirCode.cavemanEnabled"
    private let autoContextDefaultsKey = "AirCode.autoContextEnabled"
    private let promptSteeringDefaultsKey = "AirCode.promptSteeringText"
    private var api: AirCodeAPI?
    private var eventTask: Task<Void, Never>?
    private var terminalTask: URLSessionWebSocketTask?
    private var terminalReceiveTask: Task<Void, Never>?
    private var finalLogCounts: [String: Int] = [:]
    private var pendingProgressLog: PendingAgentProgress?
    private var progressLogFlushTask: Task<Void, Never>?
    private var lastProgressLogFlush = Date.distantPast
    private var pendingRuntimeSteeringPrompts: [String] = []
    private var reviewRunIds: Set<String> = []

    private struct PendingAgentProgress {
        let runId: String?
        let agent: String
        let line: String
        let time: Date?
    }

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
        let rawClaudeFastMode = UserDefaults.standard.string(forKey: claudeFastModeDefaultsKey)
        self.selectedClaudeFastMode = rawClaudeFastMode.flatMap(ClaudeFastMode.init(rawValue:)) ?? .normal
        let rawHermesProvider = UserDefaults.standard.string(forKey: hermesProviderDefaultsKey)
        self.selectedHermesProvider = rawHermesProvider.flatMap(HermesProviderOption.init(rawValue:)) ?? .auto
        let rawHermesModel = UserDefaults.standard.string(forKey: hermesModelDefaultsKey)
        self.selectedHermesModel = rawHermesModel.flatMap(HermesModelOption.init(rawValue:)) ?? .auto
        let rawHermesFastMode = UserDefaults.standard.string(forKey: hermesFastModeDefaultsKey)
        self.selectedHermesFastMode = rawHermesFastMode.flatMap(HermesFastMode.init(rawValue:)) ?? .normal
        let rawReasoning = UserDefaults.standard.string(forKey: reasoningDefaultsKey)
        if let rawReasoning, let effort = ReasoningEffort(rawValue: rawReasoning) {
            self.selectedReasoningEffort = effort
        } else {
            self.selectedReasoningEffort = UserDefaults.standard.bool(forKey: "AirCode.ultrathinkEnabled") ? .xhigh : .auto
        }
        let rawSpeedMode = UserDefaults.standard.string(forKey: speedModeDefaultsKey)
        self.selectedSpeedMode = rawSpeedMode.flatMap(AgentSpeedMode.init(rawValue:)) ?? .auto
        let rawCodexApproval = UserDefaults.standard.string(forKey: codexApprovalDefaultsKey)
        self.selectedCodexApprovalMode = rawCodexApproval.flatMap(CodexApprovalMode.init(rawValue:)) ?? .serverDefault
        let rawCodexSandbox = UserDefaults.standard.string(forKey: codexSandboxDefaultsKey)
        self.selectedCodexSandboxMode = rawCodexSandbox.flatMap(CodexSandboxMode.init(rawValue:)) ?? .serverDefault
        let rawClaudePermission = UserDefaults.standard.string(forKey: claudePermissionDefaultsKey)
        self.selectedClaudePermissionMode = rawClaudePermission.flatMap(ClaudePermissionMode.init(rawValue:)) ?? .serverDefault
        let rawHermesPermission = UserDefaults.standard.string(forKey: hermesPermissionDefaultsKey)
        self.selectedHermesPermissionMode = rawHermesPermission.flatMap(HermesPermissionMode.init(rawValue:)) ?? .serverDefault
        self.resumeAgentSession = UserDefaults.standard.object(forKey: resumeSessionDefaultsKey) as? Bool ?? true
        self.isCavemanEnabled = UserDefaults.standard.bool(forKey: cavemanDefaultsKey)
        self.isAutoContextEnabled = UserDefaults.standard.object(forKey: autoContextDefaultsKey) as? Bool ?? true
        self.promptSteeringText = UserDefaults.standard.string(forKey: promptSteeringDefaultsKey) ?? ""
    }

    deinit {
        eventTask?.cancel()
        progressLogFlushTask?.cancel()
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

    public var selectedFileConflict: FileConflict? {
        guard let selectedFilePath else { return nil }
        return fileConflicts[selectedFilePath]
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

    public func setClaudeFastMode(_ mode: ClaudeFastMode) {
        selectedClaudeFastMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: claudeFastModeDefaultsKey)
    }

    public func setHermesProvider(_ provider: HermesProviderOption) {
        selectedHermesProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: hermesProviderDefaultsKey)
    }

    public func setHermesModel(_ model: HermesModelOption) {
        selectedHermesModel = model
        UserDefaults.standard.set(model.rawValue, forKey: hermesModelDefaultsKey)
    }

    public func setHermesFastModePreference(_ mode: HermesFastMode) {
        selectedHermesFastMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: hermesFastModeDefaultsKey)
    }

    public func setHermesFastMode(_ mode: HermesFastMode) async {
        setHermesFastModePreference(mode)
        await runHermesFastCommand(mode.commandValue)
    }

    public func setReasoningEffort(_ effort: ReasoningEffort) {
        selectedReasoningEffort = effort
        UserDefaults.standard.set(effort.rawValue, forKey: reasoningDefaultsKey)
    }

    public func setSpeedMode(_ speedMode: AgentSpeedMode) {
        selectedSpeedMode = speedMode
        UserDefaults.standard.set(speedMode.rawValue, forKey: speedModeDefaultsKey)
    }

    public func setCodexApprovalMode(_ mode: CodexApprovalMode) {
        selectedCodexApprovalMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: codexApprovalDefaultsKey)
    }

    public func setCodexSandboxMode(_ mode: CodexSandboxMode) {
        selectedCodexSandboxMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: codexSandboxDefaultsKey)
    }

    public func setClaudePermissionMode(_ mode: ClaudePermissionMode) {
        selectedClaudePermissionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: claudePermissionDefaultsKey)
    }

    public func setHermesPermissionMode(_ mode: HermesPermissionMode) {
        selectedHermesPermissionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: hermesPermissionDefaultsKey)
    }

    public func setResumeAgentSession(_ isEnabled: Bool) {
        resumeAgentSession = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: resumeSessionDefaultsKey)
    }

    public func setCavemanEnabled(_ isEnabled: Bool) {
        isCavemanEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: cavemanDefaultsKey)
    }

    public func setAutoContextEnabled(_ isEnabled: Bool) {
        isAutoContextEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: autoContextDefaultsKey)
    }

    public func updateEditorContext(_ snapshot: EditorContextSnapshot) {
        guard snapshot.path == selectedFilePath else { return }
        if editorContextSnapshot != snapshot {
            editorContextSnapshot = snapshot
        }
    }

    public var autoContextChipTitle: String {
        guard isAutoContextEnabled else { return "Auto context off" }
        guard let attachment = currentAutoContextAttachment() else { return "Auto context" }
        switch attachment.type {
        case "selection":
            return "Selection: \(attachment.path)"
        case "cursor":
            if let start = attachment.startLine, let end = attachment.endLine {
                return "Around cursor: \(attachment.path):\(start)-\(end)"
            }
            return "Around cursor: \(attachment.path)"
        default:
            return "Open file: \(attachment.path)"
        }
    }

    public func setPromptSteeringText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        promptSteeringText = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: promptSteeringDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: promptSteeringDefaultsKey)
        }
    }

    public func attachContextFile(path: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        let attachment = ContextAttachment.file(path: trimmedPath)
        if !pendingContextAttachments.contains(where: { $0.id == attachment.id }) {
            pendingContextAttachments.append(attachment)
        }
    }

    public func removeContextAttachment(id: ContextAttachment.ID) {
        pendingContextAttachments.removeAll { $0.id == id }
    }

    public func clearContextAttachments() {
        pendingContextAttachments.removeAll()
    }

    public func uploadPromptAttachment(name: String, mimeType: String, data: Data) async {
        guard let api, let selectedProject else { return }
        guard pendingPromptAttachments.count < 8 else {
            agentMessages.append(AgentMessage(role: .error, text: "You can attach up to 8 files per prompt."))
            return
        }
        isUploadingAttachment = true
        defer { isUploadingAttachment = false }
        do {
            let attachment = try await api.uploadAttachment(projectId: selectedProject.id, name: name, mimeType: mimeType, data: data)
            pendingPromptAttachments.append(attachment)
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Attachment upload failed: \(error.localizedDescription)"))
        }
    }

    public func removePromptAttachment(id: AgentAttachment.ID) {
        pendingPromptAttachments.removeAll { $0.id == id }
    }

    public func clearPromptAttachments() {
        pendingPromptAttachments.removeAll()
    }

    public func contextMentionSuggestions(matching query: String) -> [ContextMentionSuggestion] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var paths = Set<String>()
        for file in openFiles {
            paths.insert(file.path)
        }
        for entries in treeEntries.values {
            for entry in entries where !entry.isDirectory {
                paths.insert(entry.path)
            }
        }
        for result in searchResults {
            paths.insert(result.path)
        }
        return paths
            .filter { path in
                normalizedQuery.isEmpty || path.lowercased().contains(normalizedQuery)
            }
            .sorted { left, right in
                let leftOpen = openFiles.contains { $0.path == left }
                let rightOpen = openFiles.contains { $0.path == right }
                if leftOpen != rightOpen { return leftOpen && !rightOpen }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            .prefix(8)
            .map { path in
                ContextMentionSuggestion(path: path, isOpen: openFiles.contains { $0.path == path })
            }
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
            await loadRecentProjects()
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
        editorContextSnapshot = nil
        fileConflicts.removeAll()
        isDiffViewerVisible = false
        searchResults = []
        searchMessage = nil
        permissionSnapshot = nil
        providerStatus = nil
        isPermissionPanelVisible = false
        integrationStatus = nil
        integrationInventory = nil
        isIntegrationPanelVisible = false
        agentTimelineEvents = []
        reviewRunIds.removeAll()
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

    public func toggleRecentProjectPinned(_ recent: RecentProjectSummary) async {
        guard let api else { return }
        do {
            _ = try await api.setRecentProjectPinned(id: recent.id, pinned: !recent.pinned)
            await loadRecentProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleWorkspaceRootPinned(_ root: WorkspaceRootSummary) async {
        guard let api else { return }
        do {
            try await api.setWorkspaceRootPinned(rootId: root.id, pinned: !root.pinned)
            let previousSelection = selectedWorkspaceRootID
            workspaceRoots = try await api.workspaceRoots()
            selectedWorkspaceRootID = previousSelection ?? workspaceRoots.first?.id
        } catch {
            errorMessage = error.localizedDescription
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
            fileConflicts.removeValue(forKey: path)
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
            fileConflicts.removeValue(forKey: file.path)
            await refreshGitStatus()
        } catch {
            await markConflict(for: file, at: index, error: error)
        }
    }

    private func markConflict(for file: OpenFile, at index: Int, error: Error) async {
        guard let api, let selectedProject else {
            openFiles[index].conflictVersion = "conflict"
            errorMessage = error.localizedDescription
            return
        }
        do {
            let serverFile = try await api.readFile(projectId: selectedProject.id, path: file.path)
            openFiles[index].conflictVersion = serverFile.version
            fileConflicts[file.path] = FileConflict(
                path: file.path,
                localContent: file.content,
                serverContent: serverFile.content,
                localBaseVersion: file.version,
                serverVersion: serverFile.version
            )
            errorMessage = "File changed on the server. Resolve the conflict before saving."
        } catch {
            openFiles[index].conflictVersion = "conflict"
            errorMessage = error.localizedDescription
        }
    }

    public func close(path: String) {
        openFiles.removeAll { $0.path == path }
        fileConflicts.removeValue(forKey: path)
        if selectedFilePath == path {
            selectedFilePath = openFiles.last?.path
        }
    }

    public func acceptServerConflict(path: String) {
        guard let conflict = fileConflicts[path],
              let index = openFiles.firstIndex(where: { $0.path == path }) else { return }
        openFiles[index].content = conflict.serverContent
        openFiles[index].savedContent = conflict.serverContent
        openFiles[index].version = conflict.serverVersion
        openFiles[index].conflictVersion = nil
        fileConflicts.removeValue(forKey: path)
    }

    public func keepLocalConflict(path: String) async {
        guard let api,
              let selectedProject,
              let conflict = fileConflicts[path],
              let index = openFiles.firstIndex(where: { $0.path == path }) else { return }
        do {
            let saved = try await api.saveFile(projectId: selectedProject.id, path: path, content: conflict.localContent, baseVersion: conflict.serverVersion)
            openFiles[index].content = saved.content
            openFiles[index].savedContent = saved.content
            openFiles[index].version = saved.version
            openFiles[index].conflictVersion = nil
            fileConflicts.removeValue(forKey: path)
            await refreshGitStatus()
        } catch {
            await markConflict(for: openFiles[index], at: index, error: error)
        }
    }

    public func saveConflictAs(path originalPath: String, newPath: String) async {
        guard let api,
              let selectedProject,
              let conflict = fileConflicts[originalPath] else { return }
        let targetPath = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetPath.isEmpty else {
            errorMessage = "Save As path is required."
            return
        }
        do {
            let created = try await api.createFile(projectId: selectedProject.id, path: targetPath, content: conflict.localContent)
            acceptServerConflict(path: originalPath)
            if let existingIndex = openFiles.firstIndex(where: { $0.path == created.path }) {
                openFiles[existingIndex].content = created.content
                openFiles[existingIndex].savedContent = created.content
                openFiles[existingIndex].version = created.version
                openFiles[existingIndex].conflictVersion = nil
            } else {
                openFiles.append(OpenFile(path: created.path, content: created.content, savedContent: created.content, version: created.version, conflictVersion: nil))
            }
            selectedFilePath = created.path
            await loadTree(path: ".")
            await refreshGitStatus()
        } catch {
            errorMessage = error.localizedDescription
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

    public func searchFiles(query: String? = nil) async {
        let requestedQuery = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = requestedQuery
        guard let api, let selectedProject else { return }
        guard !requestedQuery.isEmpty else {
            searchResults = []
            searchMessage = nil
            return
        }
        isSearching = true
        searchMessage = nil
        do {
            let response = try await api.search(projectId: selectedProject.id, query: requestedQuery, limit: 100)
            searchResults = response.results
            if response.truncated {
                searchMessage = "Showing first \(response.results.count) results."
            } else if response.results.isEmpty {
                searchMessage = "No results."
            } else {
                searchMessage = "\(response.results.count) results."
            }
        } catch {
            searchResults = []
            searchMessage = error.localizedDescription
        }
        isSearching = false
    }

    public func openSearchResult(_ result: SearchResult) async {
        isDiffViewerVisible = false
        await openFile(path: result.path)
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
            resolvedEditApprovalRunIds.insert(runId)
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

    public func acceptEditApproval(runId: String?) {
        guard let runId, !runId.isEmpty else { return }
        resolvedEditApprovalRunIds.insert(runId)
        approvalRecords.removeAll { $0.id == "edit-\(runId)" }
        agentMessages.append(AgentMessage(role: .status, text: "Approved changes from run \(shortRunId(runId)).", runId: runId))
    }

    public func loadAgentSessions() async {
        guard let api, let selectedProject else { return }
        do {
            agentSessions = try await api.agentSessions(projectId: selectedProject.id)
        } catch {
            agentSessions = []
        }
    }

    public func loadNativeAgentSessions() async {
        guard let api, let selectedProject else { return }
        let agent = selectedAgent
        guard agent == "codex" || agent == "claude" || agent == "hermes" else {
            nativeAgentSessions = []
            return
        }
        isLoadingNativeAgentSessions = true
        defer { isLoadingNativeAgentSessions = false }
        do {
            let sessions = try await api.nativeAgentSessions(projectId: selectedProject.id, agent: agent, limit: 20)
            guard selectedAgent == agent else { return }
            nativeAgentSessions = sessions
        } catch {
            nativeAgentSessions = []
            errorMessage = error.localizedDescription
        }
    }

    public func importNativeAgentSession(_ session: ProviderNativeSessionInfo) async {
        await importNativeAgentSession(sessionId: session.sessionId)
    }

    public func importNativeAgentSession(sessionId: String, showFailure: Bool = true, appendStatus: Bool = true) async {
        guard let api, let selectedProject else { return }
        let agent = selectedAgent
        do {
            let response = try await api.importNativeAgentSession(projectId: selectedProject.id, agent: agent, sessionId: sessionId)
            agentSessions.removeAll { $0.agent == agent }
            agentSessions.append(response.session)
            agentMessages = normalizedConversationMessages(response.conversation.messages)
            setResumeAgentSession(true)
            await loadNativeAgentSessions()
            if appendStatus {
                let tag = response.session.projectTag ?? selectedProject.name
                agentMessages.append(AgentMessage(role: .status, text: "Imported \(displayName(for: agent)) session for \(tag). Your next prompt will continue it."))
            }
        } catch {
            if showFailure {
                errorMessage = error.localizedDescription
                agentMessages.append(AgentMessage(role: .error, text: "\(displayName(for: agent)) session import failed: \(error.localizedDescription)"))
            }
        }
    }

    public func continueSelectedAgentSession() async {
        guard let session = selectedAgentSession else {
            setResumeAgentSession(true)
            agentMessages.append(AgentMessage(role: .status, text: "Resume selected. The next provider session will be saved for this project."))
            return
        }
        setResumeAgentSession(true)
        await loadSelectedAgentConversation()
        if agentMessages.isEmpty {
            await importNativeAgentSession(sessionId: session.sessionId, showFailure: false, appendStatus: false)
        }
        if agentMessages.isEmpty {
            let tag = session.projectTag ?? selectedProject?.name ?? displayName(for: session.agent)
            agentMessages.append(AgentMessage(role: .status, text: "\(displayName(for: session.agent)) saved session for \(tag) is selected. The next prompt will continue it."))
        }
    }

    public func startNewAgentSession() async {
        setResumeAgentSession(false)
        guard let api, let selectedProject else {
            agentSessions.removeAll { $0.agent == selectedAgent }
            agentMessages = [AgentMessage(role: .status, text: "New session selected. Your next prompt will start a clean transcript.")]
            return
        }
        let agent = selectedAgent
        do {
            try await api.clearAgentSession(projectId: selectedProject.id, agent: agent)
            agentSessions.removeAll { $0.agent == agent }
            agentMessages = [AgentMessage(role: .status, text: "New \(displayName(for: agent)) session selected. Your next prompt will start a clean transcript.")]
            await loadNativeAgentSessions()
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to start a clean \(displayName(for: agent)) session: \(error.localizedDescription)"))
        }
    }

    public func loadSelectedAgentConversation() async {
        guard activeRunId == nil else { return }
        guard let api, let selectedProject else { return }
        do {
            let conversation = try await api.agentConversation(projectId: selectedProject.id, agent: selectedAgent)
            agentMessages = normalizedConversationMessages(conversation.messages)
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
        nativeAgentSessions = []
        await loadAgentSessions()
        await loadNativeAgentSessions()
        await loadSelectedAgentConversation()
    }

    public func clearSelectedAgentSession() async {
        guard let api, let selectedProject else { return }
        do {
            try await api.clearAgentSession(projectId: selectedProject.id, agent: selectedAgent)
            agentSessions.removeAll { $0.agent == selectedAgent }
            agentMessages = []
            setResumeAgentSession(false)
            await loadNativeAgentSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runAgent(prompt: String) async {
        await runAgent(prompt: prompt, appendUserMessage: true)
    }

    private func runAgent(prompt: String, appendUserMessage: Bool, forcedResumeSession: Bool? = nil) async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, let selectedProject, !trimmedPrompt.isEmpty else { return }
        let command = AgentPromptCommand.parse(trimmedPrompt, agent: selectedAgent)
        if let localAction = command.localAction {
            await applySlashCommandAction(localAction)
            return
        }
        let displayPrompt = command.prompt.isEmpty ? trimmedPrompt : command.prompt
        let isReviewRun = isReviewPrompt(displayPrompt)
        if activeRunId != nil || agentRunStatus == .starting {
            await steerActiveRun(prompt: displayPrompt)
            return
        }
        guard !displayPrompt.isEmpty else { return }
        let runMode = command.mode ?? selectedAgentMode
        let runReasoning = command.reasoningEffort ?? selectedReasoningEffort
        let runSpeedMode = command.speedMode ?? selectedRunSpeedMode
        let runResumeSession = forcedResumeSession ?? command.resumeSession ?? resumeAgentSession
        let runCaveman = command.caveman ?? isCavemanEnabled
        let requestPrompt = applyPromptSteering(to: displayPrompt)
        let contextAttachments = buildContextAttachments(for: displayPrompt)
        let promptAttachments = pendingPromptAttachments
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
        if appendUserMessage {
            agentMessages.append(AgentMessage(role: .user, text: displayPrompt))
        }
        do {
            let response = try await api.startAgent(
                projectId: selectedProject.id,
                agent: selectedAgent,
                prompt: requestPrompt,
                mode: runMode,
                provider: selectedAgentProviderID,
                model: selectedAgentModelID,
                reasoningEffort: runReasoning,
                speedMode: runSpeedMode,
                approvalMode: selectedRunApprovalMode,
                sandboxMode: selectedRunSandboxMode,
                resumeSession: runResumeSession,
                caveman: runCaveman,
                context: contextAttachments,
                attachments: promptAttachments
            )
            pendingContextAttachments.removeAll()
            pendingPromptAttachments.removeAll()
            activeRunId = response.runId
            currentAgentName = response.agent
            finalLogCounts[response.runId] = 0
            if isReviewRun {
                reviewRunIds.insert(response.runId)
            }
            agentRunStatus = .running
        } catch {
            agentRunStatus = .failed
            lastAgentError = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to start \(displayName(for: selectedAgent)): \(error.localizedDescription)"))
            errorMessage = error.localizedDescription
        }
    }

    private func runHermesFastCommand(_ command: String) async {
        guard selectedAgent == "hermes", selectedHermesProvider == .openAICodex else {
            agentMessages.append(AgentMessage(role: .status, text: "Hermes Fast is available when Hermes provider is OpenAI Codex."))
            return
        }
        guard activeRunId == nil, agentRunStatus != .starting else {
            agentMessages.append(AgentMessage(role: .status, text: "Hermes is busy. Send `/fast \(command)` after the current run finishes."))
            return
        }
        agentMessages.append(AgentMessage(role: .status, text: "Sending Hermes `/fast \(command)` to the current session."))
        await runAgent(prompt: "/fast \(command)", appendUserMessage: false, forcedResumeSession: true)
    }

    private func steerActiveRun(prompt: String, appendUserMessage: Bool = true) async {
        let steeringPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !steeringPrompt.isEmpty else { return }
        guard let api, let selectedProject else { return }
        let agentName = currentAgentName ?? selectedAgent
        if appendUserMessage {
            agentMessages.append(AgentMessage(role: .user, text: steeringPrompt, runId: activeRunId))
        }
        guard let runId = activeRunId else {
            pendingRuntimeSteeringPrompts.append(steeringPrompt)
            agentMessages.append(AgentMessage(role: .status, text: "\(displayName(for: agentName)) is starting. Steering will be sent as soon as the active turn is ready."))
            return
        }
        do {
            let response = try await api.steerAgent(projectId: selectedProject.id, runId: runId, prompt: steeringPrompt)
            recordTimeline(runId: runId, agent: agentName, kind: "steering", title: "Steering sent", detail: steeringPrompt, time: Date())
            if !response.message.isEmpty {
                agentMessages.append(AgentMessage(role: .status, text: response.message, runId: runId))
            }
        } catch {
            let message = "Failed to steer \(displayName(for: agentName)): \(error.localizedDescription)"
            lastAgentError = message
            agentMessages.append(AgentMessage(role: .error, text: message, runId: runId))
        }
    }

    private func flushPendingRuntimeSteeringPrompts() async {
        guard activeRunId != nil, !pendingRuntimeSteeringPrompts.isEmpty else { return }
        let prompts = pendingRuntimeSteeringPrompts
        pendingRuntimeSteeringPrompts.removeAll()
        for prompt in prompts {
            await steerActiveRun(prompt: prompt, appendUserMessage: false)
        }
    }

    public func loadPermissionSnapshot(showPanel: Bool = true) async {
        guard let api, let selectedProject else { return }
        do {
            permissionSnapshot = try await api.permissions(projectId: selectedProject.id)
            isPermissionPanelVisible = showPanel
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to load permissions: \(error.localizedDescription)"))
        }
    }

    public func loadProviderStatus() async {
        guard let api, let selectedProject else { return }
        do {
            providerStatus = try await api.agentStatus(projectId: selectedProject.id, agent: selectedAgent)
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to load provider usage: \(error.localizedDescription)"))
        }
    }

    public func closePermissionPanel() {
        isPermissionPanelVisible = false
    }

    public func resolvePendingApproval(approved: Bool) async {
        guard let api, let selectedProject, let pendingApproval else { return }
        let action = approved ? "Approve" : "Deny"
        recordTimeline(
            runId: pendingApproval.runId,
            agent: currentAgentName ?? selectedAgent,
            kind: "approval",
            title: "\(action) selected",
            detail: pendingApproval.title,
            time: Date()
        )
        do {
            let response = try await api.resolveApproval(
                projectId: selectedProject.id,
                runId: pendingApproval.runId,
                approvalId: pendingApproval.id,
                decision: approved ? "approve" : "deny"
            )
            agentMessages.append(AgentMessage(role: .status, text: response.message, runId: pendingApproval.runId))
            approvalRecords.removeAll { $0.id == pendingApproval.id }
            self.pendingApproval = nil
            await loadApprovalCenter(status: "history")
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            recordTimeline(
                runId: pendingApproval.runId,
                agent: currentAgentName ?? selectedAgent,
                kind: "error",
                title: "Approval \(action.lowercased()) failed",
                detail: message,
                time: Date()
            )
            agentMessages.append(AgentMessage(role: .error, text: "Approval \(action.lowercased()) failed: \(message)", runId: pendingApproval.runId))
        }
    }

    public func resolveApproval(_ record: ApprovalRecord, approved: Bool) async {
        pendingApproval = PendingApprovalRequest(
            id: record.id,
            runId: record.runId,
            title: record.title,
            detail: record.detail ?? "",
            command: record.command ?? "",
            path: record.path ?? "",
            risk: record.risk
        )
        await resolvePendingApproval(approved: approved)
        await loadApprovalCenter(status: "pending")
        await loadApprovalCenter(status: "history")
    }

    public func loadApprovalCenter(status: String = "pending") async {
        guard let api, let selectedProject else { return }
        do {
            let response = try await api.approvals(projectId: selectedProject.id, status: status)
            if status == "history" {
                approvalHistory = response.approvals
            } else {
                var records = response.approvals
                if let pendingApproval, !records.contains(where: { $0.id == pendingApproval.id }) {
                    records.insert(approvalRecord(from: pendingApproval), at: 0)
                }
                approvalRecords = records
                pendingApproval = records.first.map {
                    PendingApprovalRequest(
                        id: $0.id,
                        runId: $0.runId,
                        title: $0.title,
                        detail: $0.detail ?? "",
                        command: $0.command ?? "",
                        path: $0.path ?? "",
                        risk: $0.risk
                    )
                } ?? pendingApproval
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approvalRecord(from approval: PendingApprovalRequest) -> ApprovalRecord {
        ApprovalRecord(
            id: approval.id,
            runId: approval.runId,
            projectId: selectedProject?.id ?? "",
            agent: currentAgentName ?? selectedAgent,
            title: approval.title,
            detail: approval.detail,
            command: approval.command,
            path: approval.path,
            risk: approval.risk,
            kind: "approval",
            status: "pending",
            decision: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            resolvedAt: nil
        )
    }

    public func loadIntegrationStatus(showPanel: Bool = true) async {
        guard let api else { return }
        do {
            integrationStatus = try await api.integrationStatus()
            isIntegrationPanelVisible = showPanel
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to load integrations: \(error.localizedDescription)"))
        }
    }

    public func loadIntegrationInventory() async {
        guard let api else { return }
        do {
            integrationInventory = try await api.integrationInventory()
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Failed to load integration items: \(error.localizedDescription)"))
        }
    }

    public func searchMCPCatalog(query: String, source: String) async {
        guard let api else { return }
        isSearchingMCPCatalog = true
        mcpCatalogError = nil
        defer { isSearchingMCPCatalog = false }
        do {
            mcpCatalogItems = try await api.searchMCPCatalog(query: query, source: source).items
        } catch {
            mcpCatalogError = error.localizedDescription
            mcpCatalogItems = []
        }
    }

    public func installCatalogMCP(_ item: MCPCatalogItem, env: [String]) async -> MCPInstallResponse? {
        let name = item.name.isEmpty ? item.displayName.lowercased().replacingOccurrences(of: " ", with: "-") : item.name
        return await installSharedMCPServer(
            name: name,
            command: item.command ?? "",
            url: item.remoteUrl ?? "",
            args: item.args ?? [],
            env: env,
            providers: []
        )
    }

    public func installSharedMCPServer(name: String, command: String, url: String, args: [String], env: [String], providers: [String] = ["codex", "claude", "hermes"]) async -> MCPInstallResponse? {
        guard let api else { return nil }
        do {
            let response = try await api.installMCP(MCPInstallRequest(
                name: name,
                command: command,
                args: args,
                url: url,
                env: env,
                providers: providers
            ))
            await loadIntegrationStatus(showPanel: true)
            await loadIntegrationInventory()
            let configured = response.results.filter { $0.status == "configured" }.map(\.provider).joined(separator: ", ")
            if let error = response.error, !error.isEmpty {
                agentMessages.append(AgentMessage(role: .error, text: "MCP install completed with errors: \(error)"))
            } else {
                agentMessages.append(AgentMessage(role: .status, text: "MCP server \(name) registered for \(configured.isEmpty ? "providers" : configured)."))
            }
            return response
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "MCP install failed: \(error.localizedDescription)"))
            return nil
        }
    }

    public func removeIntegrationItem(_ item: IntegrationInventoryItem) async -> IntegrationActionResponse? {
        guard let api else { return nil }
        do {
            let response = try await api.integrationAction(IntegrationActionRequest(
                action: "remove",
                provider: item.provider,
                kind: item.kind,
                name: item.name,
                path: item.path ?? "",
                command: "",
                args: [],
                url: "",
                env: [],
                providers: []
            ))
            await loadIntegrationStatus(showPanel: true)
            await loadIntegrationInventory()
            if let error = response.error, !error.isEmpty {
                agentMessages.append(AgentMessage(role: .error, text: "Remove failed: \(error)"))
            } else {
                agentMessages.append(AgentMessage(role: .status, text: "Removed \(item.title) from \(item.providerName)."))
            }
            return response
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "Remove failed: \(error.localizedDescription)"))
            return nil
        }
    }

    public func runProviderIntegrationCommand(kind: String, command: String) async {
        guard let api else { return }
        do {
            let response = try await api.integrationAction(IntegrationActionRequest(
                action: "command",
                provider: selectedAgent,
                kind: kind,
                name: command,
                path: "",
                command: "",
                args: [],
                url: "",
                env: [],
                providers: []
            ))
            if kind == "mcp" {
                await loadIntegrationStatus(showPanel: true)
                await loadIntegrationInventory()
            }
            let commandText = (response.command ?? []).joined(separator: " ")
            let output = (response.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let error = (response.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var lines: [String] = [
                "\(displayName(for: selectedAgent)) \(kind) \(command) executed on the server."
            ]
            if !commandText.isEmpty {
                lines.append("`\(commandText)`")
            }
            if !output.isEmpty {
                lines.append(output)
            }
            if !error.isEmpty {
                lines.append("Error: \(error)")
            }
            agentMessages.append(AgentMessage(role: response.status == "failed" ? .error : .status, text: lines.joined(separator: "\n\n")))
        } catch {
            errorMessage = error.localizedDescription
            agentMessages.append(AgentMessage(role: .error, text: "\(kind) command failed: \(error.localizedDescription)"))
        }
    }

    public func runIntegrationPanelCommand(kind: String, command: String) async -> IntegrationActionResponse? {
        guard let api else {
            return IntegrationActionResponse(status: "failed", command: nil, results: nil, output: nil, error: "Server connection is not ready.")
        }
        do {
            let response = try await api.integrationAction(IntegrationActionRequest(
                action: "command",
                provider: selectedAgent,
                kind: kind,
                name: command,
                path: "",
                command: "",
                args: [],
                url: "",
                env: [],
                providers: []
            ))
            integrationStatus = try? await api.integrationStatus()
            integrationInventory = try? await api.integrationInventory()
            return response
        } catch {
            errorMessage = error.localizedDescription
            return IntegrationActionResponse(status: "failed", command: nil, results: nil, output: nil, error: error.localizedDescription)
        }
    }

    public func closeIntegrationPanel() {
        isIntegrationPanelVisible = false
    }

    public func contextUsageText() -> String {
        let messageChars = agentMessages.reduce(0) { $0 + $1.text.count }
        let attachmentCount = pendingContextAttachments.count + pendingPromptAttachments.count + (currentAutoContextAttachment() == nil ? 0 : 1)
        let selectedFileText = selectedFilePath ?? "none"
        let sessionText = selectedAgentSession?.sessionId ?? "none"
        let autoContextText = currentAutoContextAttachment().map { "\($0.type) \($0.path)" } ?? "none"
        return """
Context usage
Messages: \(agentMessages.count)
Approx transcript chars: \(messageChars)
Pending attachments: \(attachmentCount)
Selected file: \(selectedFileText)
Auto context: \(autoContextText)
Session: \(sessionText)
Auto Context sends selection first, otherwise cursor-nearby lines. Use @file or /mention for full files.
"""
    }

    private func buildContextAttachments(for prompt: String) -> [ContextAttachment] {
        var attachments: [ContextAttachment] = []
        var paths = Set<String>()
        func add(_ attachment: ContextAttachment) {
            let key = attachment.path
            guard !key.isEmpty else { return }
            if let existingIndex = attachments.firstIndex(where: { $0.path == key }) {
                if attachments[existingIndex].type != "file", attachment.type == "file" {
                    attachments[existingIndex] = attachment
                }
                return
            }
            guard paths.insert(key).inserted else { return }
            attachments.append(attachment)
        }
        for attachment in pendingContextAttachments {
            add(attachment)
        }
        for path in ContextMentionParser.mentionedPaths(in: prompt) {
            add(.file(path: path))
        }
        if let autoAttachment = currentAutoContextAttachment() {
            add(autoAttachment)
        }
        return attachments
    }

    private func currentAutoContextAttachment() -> ContextAttachment? {
        guard isAutoContextEnabled,
              let selectedFilePath,
              let file = openFiles.first(where: { $0.path == selectedFilePath }) else { return nil }
        if let snapshot = editorContextSnapshot, snapshot.path == selectedFilePath, let attachment = snapshot.attachment {
            return attachment
        }
        return EditorContextSnapshot.make(path: selectedFilePath, text: file.content, selection: .zero).attachment
    }

    private func applyPromptSteering(to prompt: String) -> String {
        let steering = promptSteeringText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !steering.isEmpty else { return prompt }
        return """
<air_code_prompt_steering>
\(steering)
</air_code_prompt_steering>

\(prompt)
"""
    }

    private func isReviewPrompt(_ prompt: String) -> Bool {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "/review" ||
            normalized.hasPrefix("/review ") ||
            normalized == "/security-review" ||
            normalized.hasPrefix("/security-review ") ||
            normalized == "/code-review" ||
            normalized.hasPrefix("/code-review ")
    }

    private func applySlashCommandAction(_ action: AgentPromptCommand.LocalAction) async {
        switch action {
        case .help:
            agentMessages.append(AgentMessage(role: .status, text: AgentPromptCommand.helpText))
        case .newSession:
            await startNewAgentSession()
        case .resumeSession:
            await continueSelectedAgentSession()
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
        case .attachFile(let path):
            attachContextFile(path: path)
            agentMessages.append(AgentMessage(role: .status, text: "Attached @\(path) to the next prompt."))
        case .setAutoContext(let isEnabled):
            if let isEnabled {
                setAutoContextEnabled(isEnabled)
            }
            agentMessages.append(AgentMessage(role: .status, text: "Auto context is \(isAutoContextEnabled ? "on" : "off"). When enabled, the selected open file is sent with each prompt."))
        case .setSteering(let text):
            if let text {
                setPromptSteeringText(text)
            }
            if promptSteeringText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentMessages.append(AgentMessage(role: .status, text: "Prompt steering is off."))
            } else {
                agentMessages.append(AgentMessage(role: .status, text: "Prompt steering is on. Future prompts will include the steering note."))
            }
        case .showPermissions:
            await loadPermissionSnapshot(showPanel: true)
            if let snapshot = permissionSnapshot {
                agentMessages.append(AgentMessage(role: .status, text: "Permissions loaded for \(snapshot.projectId). Review them in Run Settings."))
            }
        case .showIntegrations(let focus):
            await loadIntegrationStatus(showPanel: true)
            await loadIntegrationInventory()
            if let integrationStatus {
                let title: String
                switch focus {
                case "skills": title = integrationStatus.skills.title
                case "hooks": title = integrationStatus.hooks.title
                case "apps": title = integrationStatus.codexConnectors.title
                case "plugins": title = integrationStatus.codexPlugins.title
                default: title = integrationStatus.mcp.title
                }
                agentMessages.append(AgentMessage(role: .status, text: "\(title) integration status loaded. Use the Integrations sheet from the chat header to manage items."))
            }
        case .providerCommand(let kind, let command):
            await runProviderIntegrationCommand(kind: kind, command: command)
        case .stopRun:
            await stopAgent()
            agentMessages.append(AgentMessage(role: .status, text: "Stop requested."))
        case .showContextUsage:
            agentMessages.append(AgentMessage(role: .status, text: contextUsageText()))
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
        case .search(let query):
            await searchFiles(query: query)
            agentMessages.append(AgentMessage(role: .status, text: "Search completed for \"\(query)\". \(searchMessage ?? "")"))
        case .message(let text):
            agentMessages.append(AgentMessage(role: .status, text: text))
        case .missingPrompt(let command):
            agentMessages.append(AgentMessage(role: .status, text: "Add instructions after \(command), then press Enter."))
        }
    }

    private func slashStatusText() -> String {
        let sessionText = selectedAgentSession?.sessionId ?? "none"
        let speedText = selectedSpeedStatusText
        return """
Agent: \(displayName(for: selectedAgent))
Mode: \(selectedAgentMode.title)
Model: \(selectedModelStatusText())
Reasoning: \(selectedReasoningEffort.title)
Speed: \(speedText)
Steering: \(promptSteeringText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "off" : "on")
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

    private var selectedRunSpeedMode: AgentSpeedMode {
        switch selectedAgent {
        case "codex":
            return selectedSpeedMode
        case "claude":
            return selectedClaudeFastMode.speedMode
        default:
            return .auto
        }
    }

    private var selectedRunApprovalMode: String {
        switch selectedAgent {
        case "codex":
            return selectedCodexApprovalMode.rawValue
        case "claude":
            return selectedClaudePermissionMode.rawValue
        case "hermes":
            return selectedHermesPermissionMode.rawValue
        default:
            return ""
        }
    }

    private var selectedRunSandboxMode: String {
        selectedAgent == "codex" ? selectedCodexSandboxMode.rawValue : ""
    }

    private var selectedSpeedStatusText: String {
        switch selectedAgent {
        case "codex":
            return selectedSpeedMode.title(for: selectedAgent)
        case "claude":
            return selectedClaudeFastMode == .fast ? "Fast" : "Normal"
        case "hermes":
            guard selectedHermesProvider == .openAICodex else { return "Default" }
            return selectedHermesFastMode == .fast ? "Fast" : "Normal"
        default:
            return "Default"
        }
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
            Task {
                await refreshGitStatus()
            }
        case "agent.approval", "approval.requested":
            handleApprovalRequested(event)
        case "approval.resolved":
            handleApprovalResolved(event)
        case "agent.tool.started", "agent.tool.output", "agent.tool.finished", "agent.tool.failed":
            handleToolEvent(event)
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
            let mode = event.payload?["mode"]?.stringValue ?? selectedAgentMode.rawValue
            let model = event.payload?["model"]?.stringValue ?? selectedModelStatusText()
            recordTimeline(runId: runId, agent: agent, kind: "started", title: "\(displayName(for: agent)) started", detail: "\(mode) / \(model)", time: event.time)
        }
        currentAgentName = agent
        agentRunStatus = .running
        if !pendingRuntimeSteeringPrompts.isEmpty {
            Task { await flushPendingRuntimeSteeringPrompts() }
        }
    }

    private func handleAgentLog(_ event: EventEnvelope) {
        guard let line = event.payload?["line"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return }
        let kind = event.payload?["kind"]?.stringValue ?? "progress"
        let runId = event.payload?["runId"]?.stringValue
        agentRunStatus = .running

        switch kind {
        case "session":
            clearPendingProgressLog()
            if let runId {
                recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "session", title: "Session updated", detail: line, time: event.time)
            }
            Task { await loadAgentSessions() }
        case "steering":
            clearPendingProgressLog()
            if let runId {
                recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "steering", title: "Steering update", detail: line, time: event.time)
            }
        case "final", "answer":
            clearPendingProgressLog()
            if let runId { finalLogCounts[runId, default: 0] += 1 }
            transientAgentText = nil
            if let runId {
                recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "final", title: "Final answer", detail: line, time: event.time)
            }
            if let runId, reviewRunIds.contains(runId) {
                let source = displayName(for: currentAgentName ?? selectedAgent)
                let findings = ReviewFindingParser.findings(in: line, source: source)
                if findings.isEmpty {
                    agentMessages.append(AgentMessage(role: .agent, text: line, runId: runId))
                } else {
                    agentMessages.append(AgentMessage(role: .review, text: line, runId: runId, reviewFindings: findings))
                }
            } else {
                agentMessages.append(AgentMessage(role: .agent, text: line, runId: runId))
            }
        case "error":
            clearPendingProgressLog()
            transientAgentText = nil
            if let runId {
                recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "error", title: "Error", detail: line, time: event.time)
            }
            agentMessages.append(AgentMessage(role: .error, text: line))
        default:
            enqueueProgressLog(runId: runId, agent: currentAgentName ?? selectedAgent, line: line, time: event.time)
        }
    }

    private func handleApprovalRequested(_ event: EventEnvelope) {
        guard let runId = event.payload?["runId"]?.stringValue ?? activeRunId else { return }
        let approvalID = event.payload?["approvalId"]?.stringValue ?? UUID().uuidString
        let title = event.payload?["title"]?.stringValue ?? "Approval requested"
        let detail = event.payload?["detail"]?.stringValue ?? event.payload?["message"]?.stringValue ?? ""
        let command = event.payload?["command"]?.stringValue ?? ""
        let path = event.payload?["path"]?.stringValue ?? ""
        let risk = event.payload?["risk"]?.stringValue ?? "medium"
        pendingApproval = PendingApprovalRequest(id: approvalID, runId: runId, title: title, detail: detail, command: command, path: path, risk: risk)
        let record = ApprovalRecord(
            id: approvalID,
            runId: runId,
            projectId: selectedProject?.id ?? "",
            agent: currentAgentName ?? selectedAgent,
            title: title,
            detail: detail,
            command: command,
            path: path,
            risk: risk,
            kind: event.payload?["kind"]?.stringValue ?? "approval",
            status: "pending",
            decision: nil,
            createdAt: ISO8601DateFormatter().string(from: event.time ?? Date()),
            resolvedAt: nil
        )
        approvalRecords.removeAll { $0.id == approvalID }
        approvalRecords.insert(record, at: 0)
        recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "approval", title: title, detail: command.isEmpty ? detail : command, time: event.time)
    }

    private func handleApprovalResolved(_ event: EventEnvelope) {
        let approvalID = event.payload?["approvalId"]?.stringValue
        let decision = event.payload?["decision"]?.stringValue ?? "resolved"
        if let approvalID {
            approvalRecords.removeAll { $0.id == approvalID }
        }
        pendingApproval = approvalRecords.first.map {
            PendingApprovalRequest(id: $0.id, runId: $0.runId, title: $0.title, detail: $0.detail ?? "", command: $0.command ?? "", path: $0.path ?? "", risk: $0.risk)
        }
        if let runId = event.payload?["runId"]?.stringValue {
            recordTimeline(runId: runId, agent: currentAgentName ?? selectedAgent, kind: "approval", title: "Approval \(decision)", detail: approvalID ?? "", time: event.time)
        }
    }

    private func handleToolEvent(_ event: EventEnvelope) {
        guard let runId = event.payload?["runId"]?.stringValue ?? activeRunId else { return }
        let status = event.payload?["status"]?.stringValue ?? event.type.replacingOccurrences(of: "agent.tool.", with: "")
        let title = event.payload?["toolName"]?.stringValue ?? event.payload?["title"]?.stringValue ?? "Tool call"
        let detail = event.payload?["command"]?.stringValue ?? event.payload?["path"]?.stringValue ?? event.payload?["output"]?.stringValue ?? ""
        recordTimeline(runId: runId, agent: event.payload?["agent"]?.stringValue ?? currentAgentName ?? selectedAgent, kind: "tool", title: "\(title) \(status)", detail: detail, time: event.time)
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
        clearPendingProgressLog()
        transientAgentText = nil
        if let runId {
            finalLogCounts.removeValue(forKey: runId)
            let changedText = changedFiles.isEmpty ? "No changed files" : "\(changedFiles.count) changed files"
            recordTimeline(runId: runId, agent: agent, kind: status, title: "\(displayName(for: agent)) \(status)", detail: changedText, time: event.time)
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
        }
    }

    private func normalizedConversationMessages(_ messages: [AgentTranscriptMessage]) -> [AgentMessage] {
        let maxMessages = 80
        let latest = Array(messages.suffix(maxMessages))
        var normalized = latest.map(\.agentMessage)
        if messages.count > maxMessages {
            normalized.insert(
                AgentMessage(
                    role: .status,
                    text: "Showing the latest \(maxMessages) messages. Older session history remains on the server."
                ),
                at: 0
            )
        }
        return normalized
    }

    private func enqueueProgressLog(runId: String?, agent: String, line: String, time: Date?) {
        pendingProgressLog = PendingAgentProgress(runId: runId, agent: agent, line: line, time: time)
        let elapsed = Date().timeIntervalSince(lastProgressLogFlush)
        if elapsed >= 0.18 {
            flushPendingProgressLog()
            return
        }
        guard progressLogFlushTask == nil else { return }
        let delay = UInt64(max(0.04, 0.18 - elapsed) * 1_000_000_000)
        progressLogFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            self?.flushPendingProgressLog()
        }
    }

    private func flushPendingProgressLog() {
        guard let pendingProgressLog else {
            progressLogFlushTask = nil
            return
        }
        self.pendingProgressLog = nil
        progressLogFlushTask = nil
        lastProgressLogFlush = Date()
        transientAgentText = pendingProgressLog.line
        if let runId = pendingProgressLog.runId {
            recordTimeline(
                runId: runId,
                agent: pendingProgressLog.agent,
                kind: "progress",
                title: pendingProgressLog.line,
                detail: "",
                time: pendingProgressLog.time
            )
        }
    }

    private func clearPendingProgressLog() {
        pendingProgressLog = nil
        progressLogFlushTask?.cancel()
        progressLogFlushTask = nil
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

    private func recordTimeline(runId: String, agent: String, kind: String, title: String, detail: String, time: Date?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == "progress",
           let last = agentTimelineEvents.last,
           last.runId == runId,
           last.kind == kind,
           last.title == trimmedTitle,
           last.detail == trimmedDetail {
            return
        }
        agentTimelineEvents.append(AgentRuntimeEvent(
            runId: runId,
            agent: agent,
            kind: kind,
            title: trimmedTitle,
            detail: trimmedDetail,
            time: time ?? Date()
        ))
        if agentTimelineEvents.count > 80 {
            agentTimelineEvents.removeFirst(agentTimelineEvents.count - 80)
        }
    }

    private func shortRunId(_ runId: String) -> String {
        guard runId.count > 12 else { return runId }
        return "\(runId.prefix(8))...\(runId.suffix(4))"
    }

    private func shortSessionID(_ sessionID: String) -> String {
        guard sessionID.count > 12 else { return sessionID }
        return "\(sessionID.prefix(8))...\(sessionID.suffix(4))"
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
        case attachFile(String)
        case setAutoContext(Bool?)
        case setSteering(String?)
        case showPermissions
        case showIntegrations(String)
        case providerCommand(kind: String, command: String)
        case stopRun
        case showContextUsage
        case openDiff(String)
        case search(String)
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
/plan <prompt> - forward provider-native plan mode with Air Code run metadata
/goal <prompt> - forward provider-native goal mode with Air Code run metadata
/new <prompt> - start a clean session
/resume <prompt> - continue the saved session
/effort <level> <prompt> - forward provider effort command when supported, otherwise set Air Code run effort
/speed <1x|1.5x> - choose Codex speed
/fast [on|off|status] - set Codex 1.5x; Hermes forwards native /fast normal|fast|status
/ultrathink <prompt> - use xhigh reasoning
/caveman <prompt> - use terse output
/review, /verify, /debug, /run, /simplify, /security-review, /init - forwarded through provider adapters when supported
/diff - forward provider-native diff when supported
/search <query> - search files in the opened project
/mention <path> - attach a project file to the next prompt
/auto-context on|off|status - send the selected open file with prompts
While a run is active, send a normal prompt to steer the current turn.
/mcp - run the selected provider's MCP list command on the server
/skills, /hooks, /apps, /plugins, /permissions, /context, /status - handled by server CLI adapters or Air Code panels
/compact - forwarded through the selected provider adapter when supported
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

        if let utilityCommand = parseUtilityCommand(command: command, remainder: remainder, agent: agent) {
            return utilityCommand
        }

        if agent.lowercased() == "hermes", hermesNativePassthroughCommands.contains(command) {
            if command == "plan" {
                return providerNative(trimmed, mode: .plan)
            }
            if command == "goal", !remainder.isEmpty {
                return providerNative(trimmed, mode: .goal)
            }
            return providerNative(trimmed)
        }
        if ProviderCommandAdapter.shouldForwardBeforeLocalHandling(command: command, agent: agent) {
            if command == "plan" {
                return providerNative(trimmed, mode: .plan)
            }
            if command == "goal", !remainder.isEmpty {
                return providerNative(trimmed, mode: .goal)
            }
            return providerNative(trimmed)
        }

        switch command {
        case "help", "?":
            return local(.help)
        case "plan":
            return remainder.isEmpty ? local(.missingPrompt("/plan")) : AgentPromptCommand(prompt: remainder, mode: .plan, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        case "goal":
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
            if agent.lowercased() == "claude" {
                return providerNative(trimmed)
            }
            return parseFastCommand(remainder)
        case "ultrathink":
            return remainder.isEmpty ? local(.ultrathink) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: nil, reasoningEffort: .xhigh, caveman: nil, localAction: nil)
        case "caveman":
            return remainder.isEmpty ? local(.caveman) : AgentPromptCommand(prompt: remainder, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: true, localAction: nil)
        case "review", "security-review", "debug", "run", "verify", "simplify", "init":
            if ProviderCommandAdapter.supportsSlashCommand(command, agent: agent) {
                return providerNative(trimmed)
            }
            return fallbackTaskCommand(command: command, remainder: remainder, agent: agent)
        case "diff":
            return local(.openDiff(remainder))
        case "search":
            return remainder.isEmpty ? local(.missingPrompt("/search")) : local(.search(remainder))
        case "mention":
            return remainder.isEmpty ? local(.missingPrompt("/mention")) : local(.attachFile(remainder))
        case "auto-context":
            return parseAutoContextCommand(remainder)
        case "steering":
            return parseSteeringCommand(remainder)
        case "compact":
            if ProviderCommandAdapter.supportsSlashCommand(command, agent: agent) {
                return providerNative(trimmed)
            }
            return local(.message(ProviderCommandAdapter.unsupportedMessage(command: command, agent: agent)))
        case "permissions", "allowed-tools", "skills", "hooks", "apps", "plugins", "plugin", "context", "status", "cost", "usage", "stats", "doctor", "sessions":
            return local(.message(ProviderCommandAdapter.unsupportedMessage(command: command, agent: agent)))
        case "model":
            return local(.message("Use the model menu in the chat header. Air Code sends the selected model to Codex, Claude Code, or Hermes on each run."))
        case "ide", "keymap", "keybindings", "vim", "experimental", "approve", "memories", "memory", "rename", "fork", "collab", "agent", "side", "copy", "raw", "title", "statusline", "theme", "logout", "login", "agents", "batch", "branch", "btw", "rewind", "tasks", "ultraplan", "ultrareview", "add-dir", "background", "color", "config", "export", "feedback", "focus", "loop", "recap", "release-notes", "reload-plugins", "stop", "terminal-setup", "voice", "web-setup":
            if ProviderCommandAdapter.supportsSlashCommand(command, agent: agent) {
                return providerNative(trimmed)
            }
            return local(.message(ProviderCommandAdapter.unsupportedMessage(command: command, agent: agent)))
        default:
            return AgentPromptCommand(prompt: trimmed, mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        }
    }

    private static func local(_ action: LocalAction) -> AgentPromptCommand {
        AgentPromptCommand(prompt: "", mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: action)
    }

    private static func providerNative(_ prompt: String, mode: AgentMode = .agent) -> AgentPromptCommand {
        AgentPromptCommand(prompt: prompt, mode: mode, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
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
            return local(.message("Use /speed 1x|1.5x, or /fast on|off|status."))
        }
        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawMode = parts.first, let speedMode = speed(from: String(rawMode)) else {
            return local(.message("Unknown speed mode. Use 1x, 1.5x, on, or off."))
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

    private static func parseAutoContextCommand(_ remainder: String) -> AgentPromptCommand {
        if remainder.isEmpty {
            return local(.setAutoContext(nil))
        }
        switch remainder.lowercased() {
        case "on", "true", "yes", "1", "enable", "enabled":
            return local(.setAutoContext(true))
        case "off", "false", "no", "0", "disable", "disabled":
            return local(.setAutoContext(false))
        case "status":
            return local(.setAutoContext(nil))
        default:
            return local(.message("Use /auto-context on, /auto-context off, or /auto-context status."))
        }
    }

    private static func parseSteeringCommand(_ remainder: String) -> AgentPromptCommand {
        if remainder.isEmpty || remainder.lowercased() == "status" {
            return local(.setSteering(nil))
        }
        switch remainder.lowercased() {
        case "off", "clear", "disable", "disabled", "false", "0":
            return local(.setSteering(""))
        default:
            return local(.setSteering(remainder))
        }
    }

    private static func parseUtilityCommand(command: String, remainder: String, agent: String) -> AgentPromptCommand? {
        let provider = agent.lowercased()
        switch command {
        case "mcp":
            return parseListOnlyProviderCommand(kind: "mcp", remainder: remainder, installMessage: "Use the Integrations panel to add, edit, or remove MCP servers safely.")
        case "debug-config", "config":
            return local(.showStatus)
        case "reload-mcp":
            return local(.showIntegrations("mcp"))
        case "reload-skills":
            return local(.showIntegrations("skills"))
        case "reload-plugins":
            return local(.showIntegrations("plugins"))
        case "ps":
            if ProviderCommandAdapter.supportsSlashCommand(command, agent: agent) {
                return providerNative(remainder.isEmpty ? "/ps" : "/ps \(remainder)")
            }
            return local(.message(ProviderCommandAdapter.unsupportedMessage(command: command, agent: agent)))
        case "stop":
            return local(.stopRun)
        case "permissions", "allowed-tools":
            return local(.showPermissions)
        case "context":
            return local(.showContextUsage)
        case "status", "usage", "cost", "stats":
            if provider == "hermes", command == "status" {
                return local(.providerCommand(kind: "status", command: "show"))
            }
            return local(.showStatus)
        case "skills":
            if provider == "hermes" {
                return parseListOnlyProviderCommand(kind: "skills", remainder: remainder, installMessage: "Use the Integrations panel or Hermes terminal commands to install or remove skills.")
            }
            return local(.showIntegrations("skills"))
        case "hooks":
            if provider == "hermes" {
                return parseListOnlyProviderCommand(kind: "hooks", remainder: remainder, installMessage: "Use the Integrations panel or Hermes terminal commands to change hooks.")
            }
            return local(.showIntegrations("hooks"))
        case "apps":
            return local(.showIntegrations("apps"))
        case "plugins", "plugin":
            if provider == "claude" || provider == "hermes" {
                return parseListOnlyProviderCommand(kind: "plugins", remainder: remainder, installMessage: "Use the Integrations panel or provider terminal commands to install or remove plugins.")
            }
            return local(.showIntegrations("plugins"))
        case "doctor":
            if provider == "hermes" {
                return local(.providerCommand(kind: "doctor", command: "check"))
            }
            return local(.message("\(displayName(forAgent: provider)) does not expose a safe headless doctor command here. Use `/status` for Air Code settings or run the provider doctor/debug command in the terminal."))
        case "sessions":
            if provider == "hermes" {
                return local(.providerCommand(kind: "sessions", command: "list"))
            }
            return nil
        default:
            return nil
        }
    }

    private static func parseListOnlyProviderCommand(kind: String, remainder: String, installMessage: String) -> AgentPromptCommand {
        if remainder.isEmpty {
            return local(.providerCommand(kind: kind, command: "list"))
        }
        let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let subcommand = parts.first.map { String($0).lowercased() } ?? "list"
        switch subcommand {
        case "list", "ls":
            return local(.providerCommand(kind: kind, command: "list"))
        case "add", "install", "remove", "rm", "delete", "uninstall":
            return local(.message("\(installMessage) `/\(kind)` and `/\(kind) list` run a read-only provider CLI list command."))
        default:
            return local(.message("Unsupported \(kind) command. Use `/\(kind)` or `/\(kind) list`; changes are handled from the Integrations panel or provider terminal commands."))
        }
    }

    private static func displayName(forAgent agent: String) -> String {
        switch agent {
        case "codex": return "Codex"
        case "claude": return "Claude Code"
        case "hermes": return "Hermes"
        default: return agent
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
        case "auto", "default", "provider", "provider-default", "1x": return .auto
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

    private static func fallbackTaskCommand(command: String, remainder: String, agent: String) -> AgentPromptCommand {
        switch command {
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
        default:
            return AgentPromptCommand(prompt: "/\(command)" + (remainder.isEmpty ? "" : " \(remainder)"), mode: nil, resumeSession: nil, reasoningEffort: nil, caveman: nil, localAction: nil)
        }
    }

    private static func nativeCommandMessage(command: String, agent: String) -> String {
        if command == "mcp" {
            return "Use `aircoded mcp install -name <server> (-command <cmd> [args...] | -url <url>)` on the server to register one MCP server with Codex, Claude Code, and Hermes together. Provider-native MCP screens can still be opened in the server terminal."
        }
        let provider: String
        switch agent.lowercased() {
        case "claude":
            provider = "Claude Code"
        case "hermes":
            provider = "Hermes"
        default:
            provider = "Codex"
        }
        return "/\(command) is a \(provider) native terminal command. Air Code forwards it through the selected adapter when the provider supports headless slash input; use the full terminal for interactive TUI-only flows."
    }

    static let hermesNativePassthroughCommands: Set<String> = [
        "plan",
        "goal",
        "new",
        "reset",
        "model",
        "provider",
        "personality",
        "status",
        "stop",
        "resume",
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
        "approve",
        "deny",
        "thread",
        "help",
        "update",
        "restart",
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

enum ProviderCommandAdapter {
    private static let codexSlashCommands: Set<String> = [
        "plan",
        "goal",
        "model",
        "fast",
        "diff",
        "new",
        "resume",
        "stop",
        "sandbox-add-read-dir",
        "mention",
        "review",
        "security-review",
        "debug",
        "run",
        "verify",
        "simplify",
        "init",
        "clear",
        "personality",
        "debug-config",
        "ps",
        "apps",
        "feedback",
        "quit",
        "exit",
        "permissions",
        "ide",
        "keymap",
        "vim",
        "experimental",
        "approve",
        "memories",
        "mcp",
        "skills",
        "hooks",
        "compact",
        "collab",
        "agent",
        "side",
        "copy",
        "raw",
        "title",
        "statusline",
        "theme",
        "plugins",
        "plugin",
        "logout",
        "login",
        "fork",
        "context",
        "status",
        "usage",
        "cost"
    ]

    private static let claudeSlashCommands: Set<String> = [
        "plan",
        "goal",
        "model",
        "effort",
        "fast",
        "diff",
        "resume",
        "continue",
        "review",
        "code-review",
        "security-review",
        "debug",
        "run",
        "verify",
        "simplify",
        "init",
        "reset",
        "new",
        "bg",
        "desktop",
        "app",
        "exit",
        "quit",
        "settings",
        "sandbox",
        "schedule",
        "routines",
        "scroll-speed",
        "tui",
        "teleport",
        "tp",
        "remote-control",
        "autofix-pr",
        "run-skill-generator",
        "fewer-permission-prompts",
        "heapdump",
        "insights",
        "install-github-app",
        "install-slack-app",
        "mobile",
        "ios",
        "android",
        "passes",
        "usage-credits",
        "extra-usage",
        "team-onboarding",
        "upgrade",
        "allowed-tools",
        "copy",
        "ide",
        "theme",
        "rename",
        "fork",
        "checkpoint",
        "undo",
        "stats",
        "bashes",
        "bug",
        "share",
        "rc",
        "proactive",
        "chrome",
        "claude-api",
        "plugin",
        "powerup",
        "privacy-settings",
        "radio",
        "remote-env",
        "setup-bedrock",
        "setup-vertex",
        "stickers",
        "permissions",
        "mcp",
        "skills",
        "hooks",
        "compact",
        "context",
        "status",
        "usage",
        "cost",
        "doctor",
        "memory",
        "agents",
        "batch",
        "branch",
        "btw",
        "clear",
        "rewind",
        "tasks",
        "ultraplan",
        "ultrareview",
        "add-dir",
        "background",
        "color",
        "config",
        "export",
        "feedback",
        "focus",
        "keybindings",
        "login",
        "logout",
        "loop",
        "recap",
        "release-notes",
        "reload-plugins",
        "stop",
        "terminal-setup",
        "voice",
        "web-setup"
    ]

    static func supportsSlashCommand(_ command: String, agent: String) -> Bool {
        let normalizedCommand = command.lowercased()
        switch agent.lowercased() {
        case "codex":
            return codexSlashCommands.contains(normalizedCommand)
        case "claude":
            return claudeSlashCommands.contains(normalizedCommand)
        case "hermes":
            return AgentPromptCommand.hermesNativePassthroughCommands.contains(normalizedCommand)
        default:
            return false
        }
    }

    static func shouldForwardBeforeLocalHandling(command: String, agent: String) -> Bool {
        let normalizedCommand = command.lowercased()
        guard supportsSlashCommand(normalizedCommand, agent: agent) else { return false }
        switch normalizedCommand {
        case "help", "?",
             "new",
             "clear",
             "resume",
             "continue",
             "effort",
             "fast",
             "model",
             "diff",
             "search",
             "mention",
             "auto-context",
             "speed",
             "ultrathink",
             "caveman",
             "stop",
             "ps",
             "debug-config",
             "config",
             "reload-mcp",
             "reload-skills",
             "reload-plugins":
            return false
        default:
            return true
        }
    }

    static func unsupportedMessage(command: String, agent: String) -> String {
        "/\(command) is not available through the \(agentDisplayName(agent)) adapter yet. Use the full terminal for provider-native interactive commands that require a TUI."
    }

    private static func agentDisplayName(_ agent: String) -> String {
        switch agent.lowercased() {
        case "codex": return "Codex"
        case "claude": return "Claude Code"
        case "hermes": return "Hermes"
        default: return agent
        }
    }
}

private extension JSONEncoder {
    static var airCode: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
