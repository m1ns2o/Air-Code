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

public struct GitChange: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let status: String

    public var id: String { "\(status):\(path)" }
}

public struct DiffResponse: Codable, Sendable {
    public let diff: String
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
    case caveman
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

    public var id: String { command }

    public static let all: [SlashCommandOption] = [
        SlashCommandOption(kind: .plan, command: "/plan", title: "Plan", detail: "Ask the agent for an implementation plan first.", symbol: "list.bullet.clipboard", badge: nil),
        SlashCommandOption(kind: .goal, command: "/goal", title: "Goal", detail: "Run Codex goal mode for a longer objective.", symbol: "target", badge: "Experimental"),
        SlashCommandOption(kind: .new, command: "/new", title: "New Session", detail: "Start from a clean Air Code transcript.", symbol: "plus.message", badge: nil),
        SlashCommandOption(kind: .resume, command: "/resume", title: "Resume Session", detail: "Continue the saved provider session.", symbol: "arrow.clockwise", badge: nil),
        SlashCommandOption(kind: .ultrathink, command: "/ultrathink", title: "Ultrathink", detail: "Use the highest reasoning effort for this run.", symbol: "flame", badge: nil),
        SlashCommandOption(kind: .caveman, command: "/caveman", title: "Caveman", detail: "Use terse, direct output for this run.", symbol: "bolt", badge: nil),
        SlashCommandOption(kind: .help, command: "/help", title: "Command Help", detail: "Show the supported slash commands.", symbol: "questionmark.circle", badge: nil)
    ]

    public static func matching(_ query: String) -> [SlashCommandOption] {
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return all }
        return all.filter { option in
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

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case low
    case medium
    case high
    case xhigh

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Ultrathink"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .low: return "speedometer"
        case .medium: return "brain"
        case .high: return "brain.head.profile"
        case .xhigh: return "flame"
        }
    }
}

public struct StartAgentRequest: Codable, Sendable {
    public let agent: String
    public let prompt: String
    public let mode: String
    public let provider: String
    public let model: String
    public let reasoningEffort: String
    public let resumeSession: Bool
    public let caveman: Bool

    public init(agent: String, prompt: String, mode: AgentMode = .agent, provider: String = "", model: String = "", reasoningEffort: ReasoningEffort = .auto, resumeSession: Bool = true, caveman: Bool = false) {
        self.agent = agent
        self.prompt = prompt
        self.mode = mode.rawValue
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort.rawValue
        self.resumeSession = resumeSession
        self.caveman = caveman
    }
}

public struct StartAgentResponse: Codable, Sendable {
    public let runId: String
    public let agent: String
    public let model: String?
    public let logPath: String?
    public let sessionId: String?
}

public struct AgentRunLogResponse: Codable, Sendable {
    public let runId: String
    public let path: String
    public let content: String
}

public struct AgentSessionInfo: Codable, Identifiable, Hashable, Sendable {
    public let agent: String
    public let sessionId: String
    public let updatedAt: String
    public let lastRunId: String?
    public let lastMode: String?
    public let model: String?
    public let reasoningEffort: String?

    public var id: String { agent }
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
        AgentMessage(id: id, role: role, text: text, changes: changes ?? [])
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

public struct AgentMessage: Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case agent
        case status
        case error
        case changes
    }

    public let id: String
    public let role: Role
    public let text: String
    public let changes: [GitChange]

    public init(id: String = UUID().uuidString, role: Role, text: String, changes: [GitChange] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.changes = changes
    }
}
