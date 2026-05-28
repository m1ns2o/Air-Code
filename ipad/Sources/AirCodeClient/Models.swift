import Foundation

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var serverURL: String
    public var token: String

    public init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
    }

    public static let developmentDefault = ConnectionSettings(
        serverURL: "http://127.0.0.1:8080",
        token: "dev-token-change-me"
    )
}

public struct ProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct WorkspaceRootSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let pinned: Bool
}

public struct RecentProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rootId: String
    public let path: String
    public let projectId: String
    public let openedAt: String
    public let pinned: Bool
}

public struct TreeEntry: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String
    public let type: String

    public var id: String { path }
    public var isDirectory: Bool { type == "dir" || type == "directory" }
}

public struct FileResponse: Codable, Sendable {
    public let path: String
    public let content: String
    public let version: String
}

public struct SaveFileRequest: Codable, Sendable {
    public let path: String
    public let content: String
    public let baseVersion: String
}

public struct CreateFileRequest: Codable, Sendable {
    public let path: String
    public let content: String
    public let overwrite: Bool
}

public struct FileConflict: Identifiable, Hashable, Sendable {
    public let path: String
    public let localContent: String
    public let serverContent: String
    public let localBaseVersion: String
    public let serverVersion: String

    public var id: String { path }
}

public struct GitChange: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let status: String
    public let indexStatus: String?
    public let worktreeStatus: String?

    public init(path: String, status: String, indexStatus: String? = nil, worktreeStatus: String? = nil) {
        self.path = path
        self.status = status
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
    }

    public var id: String { "\(status):\(path)" }

    public var isStaged: Bool {
        guard let indexStatus else { return false }
        return indexStatus != " " && indexStatus != "?"
    }

    public var isUnstaged: Bool {
        guard let worktreeStatus else { return true }
        return worktreeStatus != " " || indexStatus == "?"
    }
}

public struct GitCommitRequest: Codable, Sendable {
    public let message: String
}

public struct GitCommitResponse: Codable, Sendable {
    public let hash: String
    public let summary: String
}

public struct ReviewFinding: Identifiable, Hashable, Sendable {
    public let severity: String
    public let path: String
    public let line: Int?
    public let message: String
    public let source: String

    public var id: String {
        "\(source):\(severity):\(path):\(line.map(String.init) ?? "0"):\(message)"
    }
}

public enum ReviewFindingParser {
    public static func findings(in text: String, source: String) -> [ReviewFinding] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { parseLine(String($0), source: source) }
    }

    private static func parseLine(_ line: String, source: String) -> ReviewFinding? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let finding = parseSeverityFirst(trimmed, source: source) {
            return finding
        }
        return parsePathFirst(trimmed, source: source)
    }

    private static func parseSeverityFirst(_ line: String, source: String) -> ReviewFinding? {
        let pattern = #"(?i)^\s*(?:[-*]\s*)?(?:\[(critical|high|medium|low|info|warning|error)\]|(critical|high|medium|low|info|warning|error))\W+([A-Za-z0-9_./@+-]+\.[A-Za-z0-9_+-]+):(\d+)\W*(.+)$"#
        guard let match = firstMatch(pattern: pattern, in: line) else { return nil }
        let bracketSeverity = capture(match, in: line, index: 1)
        let severity = bracketSeverity.isEmpty ? capture(match, in: line, index: 2) : bracketSeverity
        return ReviewFinding(
            severity: normalizeSeverity(severity),
            path: capture(match, in: line, index: 3),
            line: Int(capture(match, in: line, index: 4)),
            message: capture(match, in: line, index: 5),
            source: source
        )
    }

    private static func parsePathFirst(_ line: String, source: String) -> ReviewFinding? {
        let pattern = #"(?i)^\s*(?:[-*]\s*)?([A-Za-z0-9_./@+-]+\.[A-Za-z0-9_+-]+):(\d+)\W+(?:(critical|high|medium|low|info|warning|error)\W+)?(.+)$"#
        guard let match = firstMatch(pattern: pattern, in: line) else { return nil }
        let severity = capture(match, in: line, index: 3)
        return ReviewFinding(
            severity: normalizeSeverity(severity.isEmpty ? "info" : severity),
            path: capture(match, in: line, index: 1),
            line: Int(capture(match, in: line, index: 2)),
            message: capture(match, in: line, index: 4),
            source: source
        )
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private static func capture(_ match: NSTextCheckingResult, in text: String, index: Int) -> String {
        guard match.numberOfRanges > index else { return "" }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let stringRange = Range(range, in: text) else { return "" }
        return text[stringRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSeverity(_ value: String) -> String {
        switch value.lowercased() {
        case "critical": return "critical"
        case "high", "error": return "high"
        case "medium", "warning": return "medium"
        case "low": return "low"
        default: return "info"
        }
    }
}

public struct DiffResponse: Codable, Sendable {
    public let diff: String
}

public struct SearchResponse: Codable, Sendable {
    public let query: String
    public let results: [SearchResult]
    public let truncated: Bool
}

public struct SearchResult: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let lineNumber: Int
    public let column: Int
    public let line: String

    public var id: String { "\(path):\(lineNumber):\(column):\(line)" }
}

public struct CommandRequest: Codable, Sendable {
    public let command: String
    public let args: [String]
}

public struct CommandResponse: Codable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int
}

public struct PermissionSnapshot: Codable, Hashable, Sendable {
    public let projectId: String
    public let commandPolicy: ProjectCommandPolicySummary
    public let agents: [AgentPermissionPolicy]
}

public struct ProjectCommandPolicySummary: Codable, Hashable, Sendable {
    public let enabled: Bool
    public let allowedCommands: [String]
    public let timeoutSeconds: Int
    public let terminalEnabled: Bool
    public let allowedShells: [String]
    public let maxSessions: Int
    public let idleTimeoutSeconds: Int
    public let detachedTimeoutSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case enabled
        case allowedCommands
        case timeoutSeconds
        case terminalEnabled
        case allowedShells
        case maxSessions
        case idleTimeoutSeconds
        case detachedTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        allowedCommands = try container.decodeIfPresent([String].self, forKey: .allowedCommands) ?? []
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 0
        terminalEnabled = try container.decodeIfPresent(Bool.self, forKey: .terminalEnabled) ?? false
        allowedShells = try container.decodeIfPresent([String].self, forKey: .allowedShells) ?? []
        maxSessions = try container.decodeIfPresent(Int.self, forKey: .maxSessions) ?? 0
        idleTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .idleTimeoutSeconds) ?? 0
        detachedTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .detachedTimeoutSeconds) ?? 0
    }
}

public struct AgentPermissionPolicy: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let enabled: Bool
    public let approvalMode: String
    public let sandboxMode: String
    public let riskLevel: String
    public let notes: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case enabled
        case approvalMode
        case sandboxMode
        case riskLevel
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "unknown"
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        approvalMode = try container.decodeIfPresent(String.self, forKey: .approvalMode) ?? "provider-default"
        sandboxMode = try container.decodeIfPresent(String.self, forKey: .sandboxMode) ?? "provider-default"
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel) ?? "medium"
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct IntegrationStatus: Codable, Hashable, Sendable {
    public let mcp: IntegrationGroup
    public let skills: IntegrationGroup
    public let hooks: IntegrationGroup
    public let codexConnectors: IntegrationGroup
    public let codexPlugins: IntegrationGroup
    public let claudePlugins: IntegrationGroup
}

public struct IntegrationInventory: Codable, Hashable, Sendable {
    public let sections: [IntegrationInventorySection]
}

public struct IntegrationInventorySection: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let items: [IntegrationInventoryItem]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case items
    }

    public init(id: String, title: String, description: String, items: [IntegrationInventoryItem]) {
        self.id = id
        self.title = title
        self.description = description
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        items = try container.decodeIfPresent([IntegrationInventoryItem].self, forKey: .items) ?? []
    }
}

public struct IntegrationInventoryItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let provider: String
    public let providerName: String
    public let kind: String
    public let kindTitle: String
    public let name: String
    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let status: String?
    public let source: String?
    public let path: String?
    public let editable: Bool
    public let removable: Bool
    public let openCommand: String?
    public let editCommand: String?
    public let removeHint: String?
}

public struct IntegrationActionRequest: Codable, Hashable, Sendable {
    public let action: String
    public let provider: String
    public let kind: String
    public let name: String
    public let path: String
    public let command: String
    public let args: [String]
    public let url: String
    public let env: [String]
    public let providers: [String]
}

public struct IntegrationActionResponse: Codable, Hashable, Sendable {
    public let status: String
    public let command: [String]?
    public let results: [MCPInstallResult]?
    public let output: String?
    public let error: String?
}

public struct MCPInstallRequest: Codable, Hashable, Sendable {
    public let name: String
    public let command: String
    public let args: [String]
    public let url: String
    public let env: [String]
    public let providers: [String]
}

public struct MCPInstallResponse: Codable, Hashable, Sendable {
    public let results: [MCPInstallResult]
    public let output: String
    public let error: String?
}

public struct MCPInstallResult: Codable, Identifiable, Hashable, Sendable {
    public let provider: String
    public let command: [String]
    public let status: String
    public let error: String?

    public var id: String { provider }

    public var commandText: String {
        command.joined(separator: " ")
    }
}

public struct MCPCatalogSearchResponse: Codable, Hashable, Sendable {
    public let items: [MCPCatalogItem]
}

public struct MCPCatalogItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let description: String
    public let source: String
    public let packageType: String?
    public let installCommand: String?
    public let command: String?
    public let args: [String]?
    public let remoteUrl: String?
    public let requiresEnv: [String]?
    public let homepage: String?
    public let repository: String?
    public let verified: Bool
    public let lastUpdated: String?
}

public struct IntegrationGroup: Codable, Hashable, Sendable {
    public let title: String
    public let description: String
    public let commandHint: String
    public let providers: [ProviderIntegration]
}

public struct ProviderIntegration: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let available: Bool
    public let configured: Bool
    public let native: Bool
    public let command: String?
    public let status: String
}

public struct AgentRuntimeEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let runId: String
    public let agent: String
    public let kind: String
    public let title: String
    public let detail: String
    public let time: Date

    public init(id: String = UUID().uuidString, runId: String, agent: String, kind: String, title: String, detail: String = "", time: Date = Date()) {
        self.id = id
        self.runId = runId
        self.agent = agent
        self.kind = kind
        self.title = title
        self.detail = detail
        self.time = time
    }

    public var shortRunId: String {
        guard runId.count > 12 else { return runId }
        return "\(runId.prefix(8))...\(runId.suffix(4))"
    }
}

public struct PendingApprovalRequest: Identifiable, Hashable, Sendable {
    public let id: String
    public let runId: String
    public let title: String
    public let detail: String
    public let command: String
    public let path: String
    public let risk: String

    public init(id: String, runId: String, title: String, detail: String = "", command: String = "", path: String = "", risk: String = "medium") {
        self.id = id
        self.runId = runId
        self.title = title
        self.detail = detail
        self.command = command
        self.path = path
        self.risk = risk
    }
}

public struct ApprovalListResponse: Codable, Hashable, Sendable {
    public let approvals: [ApprovalRecord]
}

public struct ApprovalRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let runId: String
    public let projectId: String
    public let agent: String
    public let title: String
    public let detail: String?
    public let command: String?
    public let path: String?
    public let risk: String
    public let kind: String
    public let status: String
    public let decision: String?
    public let createdAt: String
    public let resolvedAt: String?
}

public struct ContextAttachment: Codable, Identifiable, Hashable, Sendable {
    public let type: String
    public let path: String
    public let startLine: Int?
    public let endLine: Int?
    public let content: String?

    public var id: String {
        [type, path, startLine.map(String.init) ?? "", endLine.map(String.init) ?? ""].joined(separator: ":")
    }

    public init(type: String = "file", path: String, startLine: Int? = nil, endLine: Int? = nil, content: String? = nil) {
        self.type = type
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.content = content
    }

    public static func file(path: String) -> ContextAttachment {
        ContextAttachment(type: "file", path: path)
    }

    public static func openFile(path: String, content: String) -> ContextAttachment {
        ContextAttachment(type: "openFile", path: path, content: content)
    }

    public static func selection(path: String, startLine: Int, endLine: Int, content: String) -> ContextAttachment {
        ContextAttachment(type: "selection", path: path, startLine: startLine, endLine: endLine, content: content)
    }

    public static func cursor(path: String, startLine: Int, endLine: Int, content: String) -> ContextAttachment {
        ContextAttachment(type: "cursor", path: path, startLine: startLine, endLine: endLine, content: content)
    }
}

public struct AgentAttachment: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let size: Int64
    public let kind: String
    public let path: String
    public let previewText: String?
    public let createdAt: String?

    public init(id: String, name: String, mimeType: String, size: Int64, kind: String, path: String, previewText: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.kind = kind
        self.path = path
        self.previewText = previewText
        self.createdAt = createdAt
    }
}

public struct EditorContextSnapshot: Equatable, Sendable {
    public let path: String
    public let selectedText: String
    public let selectionStartLine: Int?
    public let selectionEndLine: Int?
    public let cursorContext: String
    public let cursorStartLine: Int
    public let cursorEndLine: Int

    public var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var attachment: ContextAttachment? {
        if hasSelection, let start = selectionStartLine, let end = selectionEndLine {
            return .selection(path: path, startLine: start, endLine: end, content: selectedText)
        }
        guard !cursorContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .cursor(path: path, startLine: cursorStartLine, endLine: cursorEndLine, content: cursorContext)
    }

    public static func make(path: String, text: String, selection: NSRange, lineRadius: Int = 60, maxCharacters: Int = 20_000) -> EditorContextSnapshot {
        let boundedSelection = bounded(range: selection, in: text)
        let selectedRange = boundedSelection.length > 0 ? Range(boundedSelection, in: text) : nil
        let selectedText = selectedRange.map { truncate(String(text[$0]), maxCharacters: maxCharacters) } ?? ""
        let selectionStartLine = selectedRange.map { lineNumber(in: text, before: $0.lowerBound) }
        let selectionEndLine = selectedRange.map { lineNumber(in: text, before: $0.upperBound) }
        let cursorLocation = min(max(0, boundedSelection.location), text.utf16.count)
        let cursorRange = Range(NSRange(location: cursorLocation, length: 0), in: text)
        let cursorIndex = cursorRange?.lowerBound ?? text.endIndex
        let cursorLine = lineNumber(in: text, before: cursorIndex)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lineCount = max(lines.count, 1)
        let startLine = max(1, cursorLine - lineRadius)
        let endLine = min(lineCount, cursorLine + lineRadius)
        let startIndex = max(0, startLine - 1)
        let endIndex = min(lines.count, endLine)
        let context = endIndex > startIndex ? lines[startIndex..<endIndex].joined(separator: "\n") : text

        return EditorContextSnapshot(
            path: path,
            selectedText: selectedText,
            selectionStartLine: selectionStartLine,
            selectionEndLine: selectionEndLine,
            cursorContext: truncate(context, maxCharacters: maxCharacters),
            cursorStartLine: startLine,
            cursorEndLine: endLine
        )
    }

    private static func bounded(range: NSRange, in text: String) -> NSRange {
        let lower = min(max(0, range.location), text.utf16.count)
        let upper = min(max(lower, range.location + range.length), text.utf16.count)
        return NSRange(location: lower, length: upper - lower)
    }

    private static func lineNumber(in text: String, before index: String.Index) -> Int {
        var line = 1
        for character in text[..<index] where character == "\n" {
            line += 1
        }
        return line
    }

    private static func truncate(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters)) + "\n[truncated]"
    }
}

public struct ContextMentionSuggestion: Identifiable, Hashable, Sendable {
    public let path: String
    public let isOpen: Bool

    public var id: String { path }
}

public enum ContextMentionParser {
    public static func activeQuery(in text: String) -> String? {
        guard let range = activeMentionRange(in: text) else { return nil }
        return String(text[range].dropFirst())
    }

    public static func mentionedPaths(in text: String) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        for rawToken in text.split(whereSeparator: { $0.isWhitespace }) {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}\"'`"))
            guard token.hasPrefix("@"), token.count > 1 else { continue }
            let path = String(token.dropFirst())
            guard isLikelyRelativeFilePath(path), seen.insert(path).inserted else { continue }
            paths.append(path)
        }
        return paths
    }

    public static func replacingActiveMention(in text: String, with path: String) -> String {
        guard let range = activeMentionRange(in: text) else { return text }
        var value = text
        value.replaceSubrange(range, with: "@\(path) ")
        return value
    }

    private static func activeMentionRange(in text: String) -> Range<String.Index>? {
        guard !text.isEmpty else { return nil }
        let end = text.endIndex
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous].isWhitespace || text[previous] == "\n" {
                break
            }
            start = previous
        }
        guard start < end, text[start] == "@" else { return nil }
        let query = text[start..<end].dropFirst()
        guard !query.contains("/") || !query.contains("//") else { return nil }
        return start..<end
    }

    private static func isLikelyRelativeFilePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else { return false }
        return !path.contains("://")
    }
}

public struct AgentCapability: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let installed: Bool
    public let configured: Bool
    public let enabled: Bool
    public let command: String?
    public let installStatus: String?
    public let supportsSession: Bool
    public let supportsModel: Bool
    public let supportsPTYFallback: Bool
    public let installHint: String

    public var isSelectable: Bool {
        installed && configured && enabled
    }
}

public struct CreateTerminalRequest: Codable, Sendable {
    public let shell: String?
    public let cols: UInt16
    public let rows: UInt16
}

public struct TerminalSessionResponse: Codable, Identifiable, Hashable, Sendable {
    public let terminalId: String
    public let projectId: String
    public let shell: String

    public var id: String { terminalId }
}

public struct TerminalServerMessage: Codable, Sendable {
    public let type: String
    public let data: String?
    public let code: Int?
    public let message: String?
}

public enum TerminalFrame {
    public static let data: UInt8 = 0x01
    public static let resize: UInt8 = 0x02
    public static let close: UInt8 = 0x03
    public static let exit: UInt8 = 0x04
    public static let error: UInt8 = 0x05

    public static func dataFrame(_ payload: Data) -> Data {
        var frame = Data([data])
        frame.append(payload)
        return frame
    }

    public static func resizeFrame(cols: UInt16, rows: UInt16) -> Data {
        var frame = Data([resize])
        var colsBE = cols.bigEndian
        var rowsBE = rows.bigEndian
        withUnsafeBytes(of: &colsBE) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &rowsBE) { frame.append(contentsOf: $0) }
        return frame
    }

    public static var closeFrame: Data {
        Data([close])
    }
}

public struct OpenWorkspaceRequest: Codable, Sendable {
    public let rootId: String
    public let path: String
}

public struct CreateWorkspaceFolderRequest: Codable, Sendable {
    public let rootId: String
    public let parentPath: String
    public let name: String
}

public struct OpenRecentProjectRequest: Codable, Sendable {
    public let id: String
}

public enum AgentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case agent
    case plan
    case goal

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .agent: return "Agent"
        case .plan: return "Plan"
        case .goal: return "Goal"
        }
    }
    public var symbol: String {
        switch self {
        case .agent: return "wand.and.stars"
        case .plan: return "list.bullet.clipboard"
        case .goal: return "target"
        }
    }
}

public enum SlashCommandKind: String, CaseIterable, Identifiable, Sendable {
    case plan
    case goal
    case new
    case resume
    case ultrathink
    case effort
    case caveman
    case review
    case securityReview
    case run
    case verify
    case simplify
    case debug
    case initProject
    case diff
    case search
    case status
    case model
    case speed
    case providerNative
    case help

    public var id: String { rawValue }
}

public struct SlashCommandOption: Identifiable, Hashable, Sendable {
    public let kind: SlashCommandKind
    public let command: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let badge: String?
    public let supportedAgents: Set<String>?

    public var id: String { command }

    public init(kind: SlashCommandKind, command: String, title: String, detail: String, symbol: String, badge: String? = nil, supportedAgents: Set<String>? = nil) {
        self.kind = kind
        self.command = command
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.badge = badge
        self.supportedAgents = supportedAgents
    }

    public static let all: [SlashCommandOption] = [
        SlashCommandOption(kind: .plan, command: "/plan", title: "Plan", detail: "Forward provider-native plan mode with Air Code run metadata.", symbol: "list.bullet.clipboard"),
        SlashCommandOption(kind: .goal, command: "/goal", title: "Goal", detail: "Forward provider-native goal mode with Air Code run metadata.", symbol: "target", badge: "Codex/Claude/Hermes", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .new, command: "/new", title: "New Session", detail: "Forward provider-native new-session when supported; otherwise start a clean Air Code run.", symbol: "plus.message"),
        SlashCommandOption(kind: .resume, command: "/resume", title: "Resume Session", detail: "Forward provider-native resume when supported; otherwise continue the saved Air Code session.", symbol: "arrow.clockwise"),
        SlashCommandOption(kind: .model, command: "/model", title: "Model", detail: "Forward provider-native model picker when supported.", symbol: "cpu", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .speed, command: "/speed", title: "Codex Speed", detail: "Set Codex 1x or 1.5x mode.", symbol: "speedometer", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .effort, command: "/effort", title: "Effort", detail: "Forward provider-native effort when supported; otherwise set Air Code run effort.", symbol: "brain.head.profile", badge: "Claude/Codex"),
        SlashCommandOption(kind: .ultrathink, command: "/ultrathink", title: "Ultrathink", detail: "Use xhigh reasoning for this run.", symbol: "flame"),
        SlashCommandOption(kind: .caveman, command: "/caveman", title: "Caveman", detail: "Use terse, direct output for this run.", symbol: "bolt", badge: "Air Code"),
        SlashCommandOption(kind: .review, command: "/review", title: "Review", detail: "Forward provider-native review when supported.", symbol: "checkmark.seal", badge: "Adapter"),
        SlashCommandOption(kind: .review, command: "/code-review", title: "Code Review", detail: "Forward Claude Code correctness review.", symbol: "checkmark.seal", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .securityReview, command: "/security-review", title: "Security Review", detail: "Forward provider-native security review when supported.", symbol: "lock.shield", badge: "Adapter"),
        SlashCommandOption(kind: .run, command: "/run", title: "Run", detail: "Forward provider-native run/check command when supported.", symbol: "play.circle", badge: "Adapter"),
        SlashCommandOption(kind: .verify, command: "/verify", title: "Verify", detail: "Forward provider-native verification when supported.", symbol: "checkmark.circle", badge: "Adapter"),
        SlashCommandOption(kind: .simplify, command: "/simplify", title: "Simplify", detail: "Forward provider-native simplify command when supported.", symbol: "wand.and.stars", badge: "Adapter"),
        SlashCommandOption(kind: .debug, command: "/debug", title: "Debug", detail: "Forward provider-native debug command when supported.", symbol: "stethoscope", badge: "Adapter"),
        SlashCommandOption(kind: .initProject, command: "/init", title: "Init Memory", detail: "Forward provider-native project memory initialization.", symbol: "doc.badge.plus", badge: "Adapter"),
        SlashCommandOption(kind: .diff, command: "/diff", title: "Diff", detail: "Forward provider-native diff when supported; Changes still opens Air Code diff.", symbol: "rectangle.split.2x1"),
        SlashCommandOption(kind: .search, command: "/search", title: "Search", detail: "Search files in the opened project.", symbol: "magnifyingglass", badge: "Air Code"),
        SlashCommandOption(kind: .providerNative, command: "/mention", title: "Mention File", detail: "Attach a project file as agent context.", symbol: "at", badge: "Air Code"),
        SlashCommandOption(kind: .providerNative, command: "/auto-context", title: "Auto Context", detail: "Toggle current open file context.", symbol: "paperclip", badge: "Air Code"),
        SlashCommandOption(kind: .status, command: "/status", title: "Status", detail: "Forward provider status when supported; otherwise show Air Code settings.", symbol: "info.circle"),
        SlashCommandOption(kind: .help, command: "/help", title: "Command Help", detail: "Show supported slash commands.", symbol: "questionmark.circle"),
        SlashCommandOption(kind: .providerNative, command: "/rollback", title: "Rollback", detail: "Hermes checkpoint restore or preview.", symbol: "arrow.uturn.backward.circle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/provider", title: "Provider", detail: "Switch Hermes provider inside the active session.", symbol: "switch.2", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/personality", title: "Personality", detail: "Forward provider-native response style/personality control.", symbol: "person.crop.circle", badge: "Codex/Hermes", supportedAgents: ["codex", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/subgoal", title: "Subgoal", detail: "Add criteria to an active Hermes goal.", symbol: "target", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/history", title: "History", detail: "Show Hermes conversation history.", symbol: "clock", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/save", title: "Save", detail: "Save the current Hermes conversation.", symbol: "tray.and.arrow.down", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/retry", title: "Retry", detail: "Retry the last Hermes message.", symbol: "arrow.clockwise", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/undo", title: "Undo", detail: "Forward provider-native undo/checkpoint alias.", symbol: "arrow.uturn.left", badge: "Claude/Hermes", supportedAgents: ["claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/compress", title: "Compress", detail: "Compact Hermes context with an optional focus.", symbol: "arrow.down.right.and.arrow.up.left", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/sessions", title: "Sessions", detail: "Browse Hermes sessions.", symbol: "rectangle.stack", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/commands", title: "Commands", detail: "Browse Hermes commands and skills.", symbol: "command", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/tools", title: "Tools", detail: "Show Hermes tool status.", symbol: "hammer", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/toolsets", title: "Toolsets", detail: "Manage Hermes toolsets.", symbol: "shippingbox", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reasoning", title: "Reasoning", detail: "Change Hermes reasoning display or effort.", symbol: "brain.head.profile", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/queue", title: "Queue", detail: "Queue a Hermes prompt for the next turn.", symbol: "text.line.first.and.arrowtriangle.forward", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/thread", title: "Thread", detail: "Create or switch Hermes conversation thread.", symbol: "bubble.left.and.text.bubble.right", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/approve", title: "Approve", detail: "Approve a pending provider action.", symbol: "checkmark.shield", badge: "Codex/Hermes", supportedAgents: ["codex", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/deny", title: "Deny", detail: "Deny a pending Hermes action.", symbol: "xmark.shield", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/steer", title: "Steer", detail: "Inject a mid-run Hermes steering note.", symbol: "arrow.triangle.turn.up.right.diamond", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/footer", title: "Footer", detail: "Toggle Hermes runtime metadata footer.", symbol: "rectangle.bottomthird.inset.filled", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/yolo", title: "YOLO", detail: "Toggle Hermes dangerous-command approval bypass.", symbol: "exclamationmark.triangle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reload-mcp", title: "Reload MCP", detail: "Reload Hermes MCP servers.", symbol: "point.3.connected.trianglepath.dotted", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reload-skills", title: "Reload Skills", detail: "Reload Hermes skills.", symbol: "puzzlepiece.extension", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/restart", title: "Restart", detail: "Restart Hermes gateway/runtime where supported.", symbol: "arrow.clockwise.circle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/update", title: "Update", detail: "Update Hermes where supported.", symbol: "arrow.down.circle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .speed, command: "/fast", title: "Fast Mode", detail: "Set Codex 1.5x or provider-native fast mode.", symbol: "hare", badge: "Codex/Claude/Hermes", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/permissions", title: "Permissions", detail: "Show Air Code's server-side permission policy for the current project.", symbol: "hand.raised", badge: "Air Code", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/ide", title: "IDE Context", detail: "Provider IDE integration; Air Code sends project context directly.", symbol: "rectangle.connected.to.line.below", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/experimental", title: "Experimental", detail: "Codex experimental feature toggles.", symbol: "testtube.2", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/memories", title: "Memories", detail: "Codex memory configuration.", symbol: "books.vertical", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/apps", title: "Apps", detail: "Browse Codex apps/connectors.", symbol: "app.connected.to.app.below.fill", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/debug-config", title: "Debug Config", detail: "Print Codex config diagnostics.", symbol: "wrench.and.screwdriver", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/sandbox-add-read-dir", title: "Sandbox Read Dir", detail: "Grant Codex sandbox read access to an extra directory.", symbol: "folder.badge.gearshape", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/ps", title: "Processes", detail: "Show Codex background terminals.", symbol: "terminal", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/mcp", title: "MCP", detail: "Run the selected provider's MCP list command on the server.", symbol: "point.3.connected.trianglepath.dotted", badge: "Provider"),
        SlashCommandOption(kind: .providerNative, command: "/skills", title: "Skills", detail: "Show skills inventory or run Hermes skills list through the server adapter.", symbol: "puzzlepiece.extension", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/compact", title: "Compact", detail: "Provider-native context compaction.", symbol: "arrow.down.right.and.arrow.up.left", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/collab", title: "Collab", detail: "Codex collaboration mode switch.", symbol: "person.2.wave.2", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/agent", title: "Agent Thread", detail: "Codex active agent thread switch.", symbol: "person.crop.circle.badge.gearshape", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/side", title: "Side Chat", detail: "Codex ephemeral side conversation.", symbol: "sidebar.right", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/rename", title: "Rename", detail: "Provider-native session rename.", symbol: "text.cursor", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/fork", title: "Fork", detail: "Provider-native conversation branch.", symbol: "arrow.triangle.branch", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/copy", title: "Copy", detail: "Provider-native terminal clipboard action.", symbol: "doc.on.doc", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/theme", title: "Theme", detail: "Forward provider-native terminal theme command.", symbol: "paintpalette", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/logout", title: "Logout", detail: "Provider-native auth command; run on the server terminal.", symbol: "rectangle.portrait.and.arrow.right", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/memory", title: "Memory", detail: "Claude memory files and command skills.", symbol: "books.vertical", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/agents", title: "Agents", detail: "Claude subagent manager.", symbol: "person.2", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/batch", title: "Batch", detail: "Claude bundled skill for parallel work.", symbol: "square.stack.3d.up", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/branch", title: "Branch", detail: "Claude conversation branch.", symbol: "arrow.triangle.branch", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/btw", title: "BTW", detail: "Claude side question without bloating context.", symbol: "text.bubble", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/clear", title: "Clear", detail: "Forward provider-native transcript clear when supported.", symbol: "trash", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/allowed-tools", title: "Allowed Tools", detail: "Claude alias for the Air Code permissions panel.", symbol: "hand.raised", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/context", title: "Context", detail: "Show Air Code's current prompt context usage.", symbol: "chart.bar.xaxis", badge: "Air Code", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/cost", title: "Cost", detail: "Show current Air Code agent settings where provider usage is unavailable.", symbol: "creditcard", badge: "Air Code", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/stats", title: "Stats", detail: "Show current Air Code agent settings where provider stats are unavailable.", symbol: "chart.line.uptrend.xyaxis", badge: "Air Code", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/doctor", title: "Doctor", detail: "Run a safe provider doctor command where the CLI exposes one.", symbol: "cross.case", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/hooks", title: "Hooks", detail: "Show hooks inventory or run Hermes hooks list through the server adapter.", symbol: "link", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/keymap", title: "Keymap", detail: "Codex terminal keymap settings.", symbol: "keyboard", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/vim", title: "Vim Mode", detail: "Provider-native terminal editor mode.", symbol: "keyboard.chevron.compact.down", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/plugins", title: "Plugins", detail: "Show plugin inventory or run a safe provider plugin list command.", symbol: "shippingbox", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/raw", title: "Raw", detail: "Codex raw scrollback toggle.", symbol: "text.alignleft", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/title", title: "Title", detail: "Codex terminal title config.", symbol: "rectangle.and.pencil.and.ellipsis", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/statusline", title: "Status Line", detail: "Provider-native terminal status line config.", symbol: "rectangle.bottomthird.inset.filled", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/usage", title: "Usage", detail: "Provider usage and limits.", symbol: "chart.line.uptrend.xyaxis", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/rewind", title: "Rewind", detail: "Claude checkpoint undo.", symbol: "backward.end", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/checkpoint", title: "Checkpoint", detail: "Claude alias for rewind.", symbol: "backward.end", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/tasks", title: "Tasks", detail: "Claude background task list.", symbol: "checklist", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/bashes", title: "Bashes", detail: "Claude alias for background task list.", symbol: "terminal", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/ultraplan", title: "Ultraplan", detail: "Claude deep planning session.", symbol: "map", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/ultrareview", title: "Ultrareview", detail: "Claude deep cloud review.", symbol: "shield.lefthalf.filled", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/add-dir", title: "Add Directory", detail: "Claude additional directory access.", symbol: "folder.badge.plus", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/background", title: "Background", detail: "Provider background task control.", symbol: "rectangle.on.rectangle", badge: "Claude/Hermes", supportedAgents: ["claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/color", title: "Color", detail: "Claude terminal color mode.", symbol: "paintpalette", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/config", title: "Config", detail: "Claude configuration panel.", symbol: "gearshape", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/export", title: "Export", detail: "Claude conversation export.", symbol: "square.and.arrow.up", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/feedback", title: "Feedback", detail: "Send Claude Code feedback.", symbol: "bubble.left.and.bubble.right", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/focus", title: "Focus", detail: "Claude focus mode.", symbol: "scope", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/keybindings", title: "Keybindings", detail: "Claude keyboard shortcuts.", symbol: "keyboard", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/login", title: "Login", detail: "Claude authentication command.", symbol: "person.crop.circle.badge.checkmark", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/loop", title: "Loop", detail: "Claude iteration loop mode.", symbol: "repeat", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/recap", title: "Recap", detail: "Claude conversation recap.", symbol: "text.badge.checkmark", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/release-notes", title: "Release Notes", detail: "Claude Code release notes.", symbol: "newspaper", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/reload-plugins", title: "Reload Plugins", detail: "Reload Claude plugins.", symbol: "arrow.clockwise.circle", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/plugin", title: "Plugin", detail: "Manage Claude Code plugins.", symbol: "shippingbox", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/remote-control", title: "Remote Control", detail: "Expose the Claude session for remote control.", symbol: "antenna.radiowaves.left.and.right", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/rc", title: "Remote Control", detail: "Claude alias for remote-control.", symbol: "antenna.radiowaves.left.and.right", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/proactive", title: "Proactive Loop", detail: "Claude alias for loop.", symbol: "repeat", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/setup-bedrock", title: "Setup Bedrock", detail: "Configure Claude Code Bedrock provider.", symbol: "cloud", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/setup-vertex", title: "Setup Vertex", detail: "Configure Claude Code Vertex provider.", symbol: "cloud", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/stop", title: "Stop", detail: "Forward provider-native background stop.", symbol: "stop.circle", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/terminal-setup", title: "Terminal Setup", detail: "Install Claude terminal bindings.", symbol: "terminal", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/voice", title: "Voice", detail: "Provider voice controls.", symbol: "waveform", badge: "Claude/Hermes", supportedAgents: ["claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/web-setup", title: "Web Setup", detail: "Claude web integration setup.", symbol: "globe", badge: "Claude", supportedAgents: ["claude"])
    ]

    public static func matching(_ query: String, agent: String = "codex") -> [SlashCommandOption] {
        let normalized = query.lowercased()
        let agentID = agent.lowercased()
        let agentOptions = all.filter { option in
            option.supportedAgents?.contains(agentID) ?? true
        }
        guard !normalized.isEmpty else { return agentOptions }
        return agentOptions.filter { option in
            option.command.dropFirst().lowercased().hasPrefix(normalized)
                || option.title.lowercased().contains(normalized)
                || option.detail.lowercased().contains(normalized)
        }
    }
}

public enum CodexModelOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case gpt55 = "gpt-5.5"
    case gpt54 = "gpt-5.4"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt53Codex = "gpt-5.3-codex"
    case gpt53CodexSpark = "gpt-5.3-codex-spark"
    case gpt52 = "gpt-5.2"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .gpt55: return "GPT-5.5"
        case .gpt54: return "GPT-5.4"
        case .gpt54Mini: return "5.4 Mini"
        case .gpt53Codex: return "5.3 Codex"
        case .gpt53CodexSpark: return "5.3 Spark"
        case .gpt52: return "GPT-5.2"
        }
    }

    public var modelID: String {
        self == .auto ? "" : rawValue
    }
}

public enum ClaudeModelOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case sonnet
    case opus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        }
    }

    public var modelID: String {
        self == .auto ? "" : rawValue
    }
}

public enum ClaudeFastMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case fast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    public var symbol: String {
        switch self {
        case .normal: return "speedometer"
        case .fast: return "bolt.fill"
        }
    }

    public var speedMode: AgentSpeedMode {
        switch self {
        case .normal: return .auto
        case .fast: return .fast
        }
    }
}

public enum HermesProviderOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case nous
    case openAICodex = "openai-codex"
    case anthropic
    case openRouter = "openrouter"
    case xaiOAuth = "xai-oauth"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Provider"
        case .nous: return "Nous"
        case .openAICodex: return "OpenAI Codex"
        case .anthropic: return "Anthropic"
        case .openRouter: return "OpenRouter"
        case .xaiOAuth: return "xAI OAuth"
        }
    }

    public var menuTitle: String {
        switch self {
        case .auto: return "Default Hermes Provider"
        default: return title
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .nous: return "h.circle"
        case .openAICodex: return "terminal"
        case .anthropic: return "circle.hexagongrid"
        case .openRouter: return "point.3.connected.trianglepath.dotted"
        case .xaiOAuth: return "xmark.circle"
        }
    }

    public var providerID: String {
        self == .auto ? "" : rawValue
    }
}

public enum HermesModelOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case claudeSonnet46 = "anthropic/claude-sonnet-4.6"
    case claudeOpus46 = "anthropic/claude-opus-4.6"
    case gpt55 = "gpt-5.5"
    case gpt54 = "gpt-5.4"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt52 = "gpt-5.2"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Model"
        case .claudeSonnet46: return "Claude Sonnet 4.6"
        case .claudeOpus46: return "Claude Opus 4.6"
        case .gpt55: return "GPT-5.5"
        case .gpt54: return "GPT-5.4"
        case .gpt54Mini: return "5.4 Mini"
        case .gpt52: return "GPT-5.2"
        }
    }

    public var menuTitle: String {
        switch self {
        case .auto: return "Default Hermes Model"
        default: return title
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .claudeSonnet46, .claudeOpus46: return "circle.hexagongrid"
        case .gpt55, .gpt54, .gpt54Mini, .gpt52: return "cpu"
        }
    }

    public var modelID: String {
        self == .auto ? "" : rawValue
    }
}

public enum HermesFastMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case fast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    public var symbol: String {
        switch self {
        case .normal: return "speedometer"
        case .fast: return "bolt.fill"
        }
    }

    public var commandValue: String { rawValue }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case low
    case medium
    case high
    case xhigh
    case max

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Ultrathink"
        case .max: return "Max"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .low: return "speedometer"
        case .medium: return "brain"
        case .high: return "brain.head.profile"
        case .xhigh: return "flame"
        case .max: return "flame.fill"
        }
    }
}

public enum AgentSpeedMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case fast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Default"
        case .fast: return "Fast"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .fast: return "bolt.fill"
        }
    }

    public func title(for agentID: String) -> String {
        switch (self, agentID.lowercased()) {
        case (.auto, "codex"):
            return "1x"
        case (.fast, "codex"):
            return "1.5x"
        case (.fast, _):
            return "Fast"
        default:
            return title
        }
    }

    public func isSupported(by agentID: String) -> Bool {
        switch self {
        case .auto:
            return true
        case .fast:
            return agentID.lowercased() == "codex"
        }
    }

    public func requestValue(for agentID: String) -> String {
        if agentID.lowercased() == "claude" {
            return rawValue
        }
        guard isSupported(by: agentID) else { return AgentSpeedMode.auto.rawValue }
        return rawValue
    }
}

public enum CodexApprovalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case serverDefault = ""
    case ask = "on-request"
    case onFailure = "on-failure"
    case never = "never"

    public var id: String { rawValue.isEmpty ? "server-default" : rawValue }

    public var title: String {
        switch self {
        case .serverDefault: return "Server Default"
        case .ask: return "Ask"
        case .onFailure: return "On Failure"
        case .never: return "Never"
        }
    }

    public var symbol: String {
        switch self {
        case .serverDefault: return "server.rack"
        case .ask: return "hand.raised"
        case .onFailure: return "exclamationmark.triangle"
        case .never: return "checkmark.shield"
        }
    }

    public var isOverride: Bool { self != .serverDefault }
}

public enum CodexSandboxMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case serverDefault = ""
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case fullAccess = "danger-full-access"

    public var id: String { rawValue.isEmpty ? "server-default" : rawValue }

    public var title: String {
        switch self {
        case .serverDefault: return "Server Default"
        case .readOnly: return "Read Only"
        case .workspaceWrite: return "Workspace Write"
        case .fullAccess: return "Full Access"
        }
    }

    public var symbol: String {
        switch self {
        case .serverDefault: return "server.rack"
        case .readOnly: return "lock"
        case .workspaceWrite: return "folder.badge.gearshape"
        case .fullAccess: return "exclamationmark.shield"
        }
    }

    public var isOverride: Bool { self != .serverDefault }
}

public enum ClaudePermissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case serverDefault = ""
    case plan = "plan"
    case acceptEdits = "acceptEdits"
    case bypassPermissions = "bypassPermissions"

    public var id: String { rawValue.isEmpty ? "server-default" : rawValue }

    public var title: String {
        switch self {
        case .serverDefault: return "Server Default"
        case .plan: return "Plan First"
        case .acceptEdits: return "Accept Edits"
        case .bypassPermissions: return "Bypass"
        }
    }

    public var detail: String {
        switch self {
        case .serverDefault: return "Use the server configured Claude Code permission mode."
        case .plan: return "Ask Claude to plan before changing files."
        case .acceptEdits: return "Allow Claude Code edit operations with provider defaults for other tools."
        case .bypassPermissions: return "Skip Claude Code permission prompts. Use only in trusted sandboxes."
        }
    }

    public var symbol: String {
        switch self {
        case .serverDefault: return "server.rack"
        case .plan: return "list.bullet.clipboard"
        case .acceptEdits: return "square.and.pencil"
        case .bypassPermissions: return "exclamationmark.shield"
        }
    }

    public var isOverride: Bool { self != .serverDefault }
}

public enum HermesPermissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case serverDefault = ""
    case yolo = "yolo"

    public var id: String { rawValue.isEmpty ? "server-default" : rawValue }

    public var title: String {
        switch self {
        case .serverDefault: return "Provider Default"
        case .yolo: return "YOLO"
        }
    }

    public var detail: String {
        switch self {
        case .serverDefault: return "Use Hermes native approval behavior."
        case .yolo: return "Send Hermes native /yolo before the prompt. Use only in a trusted sandbox."
        }
    }

    public var symbol: String {
        switch self {
        case .serverDefault: return "server.rack"
        case .yolo: return "exclamationmark.triangle"
        }
    }

    public var isOverride: Bool { self != .serverDefault }
}

public struct StartAgentRequest: Codable, Sendable {
    public let agent: String
    public let prompt: String
    public let mode: String
    public let provider: String
    public let model: String
    public let reasoningEffort: String
    public let speedMode: String
    public let approvalMode: String
    public let sandboxMode: String
    public let resumeSession: Bool
    public let caveman: Bool
    public let context: [ContextAttachment]
    public let attachments: [AgentAttachment]

    public init(agent: String, prompt: String, mode: AgentMode = .agent, provider: String = "", model: String = "", reasoningEffort: ReasoningEffort = .auto, speedMode: AgentSpeedMode = .auto, approvalMode: String = "", sandboxMode: String = "", resumeSession: Bool = true, caveman: Bool = false, context: [ContextAttachment] = [], attachments: [AgentAttachment] = []) {
        self.agent = agent
        self.prompt = prompt
        self.mode = mode.rawValue
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort.rawValue
        self.speedMode = speedMode.requestValue(for: agent)
        self.approvalMode = approvalMode
        self.sandboxMode = sandboxMode
        self.resumeSession = resumeSession
        self.caveman = caveman
        self.context = context
        self.attachments = attachments
    }
}

public struct StartAgentResponse: Codable, Sendable {
    public let runId: String
    public let agent: String
    public let model: String?
    public let logPath: String?
    public let sessionId: String?
}

public struct SteerAgentRequest: Codable, Sendable {
    public let prompt: String
}

public struct SteerAgentResponse: Codable, Sendable {
    public let runId: String
    public let accepted: Bool
    public let message: String
}

public struct ApprovalDecisionRequest: Codable, Sendable {
    public let approvalId: String
    public let decision: String

    public init(approvalId: String, decision: String) {
        self.approvalId = approvalId
        self.decision = decision
    }
}

public struct ApprovalDecisionResponse: Codable, Sendable {
    public let runId: String
    public let accepted: Bool
    public let message: String
}

public struct AgentRunLogResponse: Codable, Sendable {
    public let runId: String
    public let path: String
    public let content: String
}

public struct AgentRunChangesResponse: Codable, Sendable {
    public let runId: String
    public let changes: [GitChange]
}

public struct AgentRunRevertResponse: Codable, Sendable {
    public let runId: String
    public let reverted: [String]
    public let conflicts: [AgentRunRevertConflict]
}

public struct AgentRunRevertConflict: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let reason: String

    public var id: String { path }
}

public struct ProviderStatusResponse: Codable, Hashable, Sendable {
    public let agent: String
    public let displayName: String
    public let installed: Bool
    public let configured: Bool
    public let enabled: Bool
    public let command: String?
    public let version: String?
    public let sessionId: String?
    public let updatedAt: String?
    public let model: String?
    public let provider: String?
    public let messageCount: Int
    public let transcriptChars: Int
    public let rawStatus: String?
    public let rawUsage: String?
    public let rawContext: String?
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case agent
        case displayName
        case installed
        case configured
        case enabled
        case command
        case version
        case sessionId
        case updatedAt
        case model
        case provider
        case messageCount
        case transcriptChars
        case rawStatus
        case rawUsage
        case rawContext
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decode(String.self, forKey: .agent)
        displayName = try container.decode(String.self, forKey: .displayName)
        installed = try container.decode(Bool.self, forKey: .installed)
        configured = try container.decode(Bool.self, forKey: .configured)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        transcriptChars = try container.decodeIfPresent(Int.self, forKey: .transcriptChars) ?? 0
        rawStatus = try container.decodeIfPresent(String.self, forKey: .rawStatus)
        rawUsage = try container.decodeIfPresent(String.self, forKey: .rawUsage)
        rawContext = try container.decodeIfPresent(String.self, forKey: .rawContext)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct AgentSessionInfo: Codable, Identifiable, Hashable, Sendable {
    public let agent: String
    public let sessionId: String
    public let updatedAt: String
    public let projectTag: String?
    public let lastRunId: String?
    public let lastMode: String?
    public let model: String?
    public let reasoningEffort: String?
    public let speedMode: String?

    public var id: String { agent }
}

public struct HermesNativeSessionInfo: Codable, Identifiable, Hashable, Sendable {
    public let sessionId: String
    public let preview: String
    public let source: String
    public let lastActive: String
    public let imported: Bool

    public var id: String { sessionId }
}

public struct ProviderNativeSessionInfo: Codable, Identifiable, Hashable, Sendable {
    public let agent: String
    public let sessionId: String
    public let preview: String
    public let source: String
    public let lastActive: String
    public let projectTag: String?
    public let projectTagSource: String?
    public let matchesProject: Bool
    public let cwd: String?
    public let path: String?
    public let imported: Bool

    public var id: String { "\(agent):\(sessionId)" }
}

public struct ImportHermesSessionRequest: Codable, Hashable, Sendable {
    public let sessionId: String
}

public struct ImportHermesSessionResponse: Codable, Hashable, Sendable {
    public let session: AgentSessionInfo
    public let conversation: AgentConversationResponse
}

public struct ImportNativeSessionRequest: Codable, Hashable, Sendable {
    public let sessionId: String
}

public struct ImportNativeSessionResponse: Codable, Hashable, Sendable {
    public let session: AgentSessionInfo
    public let conversation: AgentConversationResponse
}

public struct AgentConversationResponse: Codable, Hashable, Sendable {
    public let agent: String
    public let sessionId: String?
    public let updatedAt: String?
    public let messages: [AgentTranscriptMessage]
}

public struct AgentTranscriptMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let role: AgentMessage.Role
    public let text: String
    public let runId: String?
    public let createdAt: String
    public let changes: [GitChange]?

    public var agentMessage: AgentMessage {
        AgentMessage(id: id, role: role, text: text, runId: runId, changes: changes ?? [])
    }
}

public struct EventEnvelope: Codable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let projectId: String?
    public let time: Date?
    public let payload: JSONValue?
}

public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self {
            return object[key]
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct OpenFile: Identifiable, Hashable, Sendable {
    public let path: String
    public var content: String
    public var savedContent: String
    public var version: String
    public var conflictVersion: String?

    public var id: String { path }
    public var isDirty: Bool { content != savedContent }
}

public enum ConflictSavePath {
    public static func suggestedPath(for path: String) -> String {
        let nsPath = path as NSString
        let directory = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent
        let ext = (filename as NSString).pathExtension
        let stem = ext.isEmpty ? filename : (filename as NSString).deletingPathExtension
        let candidate = ext.isEmpty ? "\(stem).local" : "\(stem).local.\(ext)"
        if directory == "." || directory.isEmpty {
            return candidate
        }
        return "\(directory)/\(candidate)"
    }
}

public struct AgentMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case agent
        case status
        case error
        case changes
        case review
    }

    public let id: String
    public let role: Role
    public let text: String
    public let runId: String?
    public let changes: [GitChange]
    public let reviewFindings: [ReviewFinding]

    public init(id: String = UUID().uuidString, role: Role, text: String, runId: String? = nil, changes: [GitChange] = [], reviewFindings: [ReviewFinding] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.runId = runId
        self.changes = changes
        self.reviewFindings = reviewFindings
    }
}
