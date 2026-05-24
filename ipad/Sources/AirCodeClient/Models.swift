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

public struct RecentProjectSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rootId: String
    public let path: String
    public let projectId: String
    public let openedAt: String
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
        SlashCommandOption(kind: .plan, command: "/plan", title: "Plan", detail: "Plan first, then wait for approval.", symbol: "list.bullet.clipboard"),
        SlashCommandOption(kind: .goal, command: "/goal", title: "Goal", detail: "Keep working toward a stated condition.", symbol: "target", badge: "Codex/Claude/Hermes", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .new, command: "/new", title: "New Session", detail: "Start from a clean Air Code transcript.", symbol: "plus.message"),
        SlashCommandOption(kind: .resume, command: "/resume", title: "Resume Session", detail: "Continue the saved provider session.", symbol: "arrow.clockwise"),
        SlashCommandOption(kind: .model, command: "/model", title: "Model", detail: "Use the model selector in the chat header.", symbol: "cpu"),
        SlashCommandOption(kind: .speed, command: "/speed", title: "Speed", detail: "Set provider default or Codex fast mode.", symbol: "speedometer", badge: "Codex"),
        SlashCommandOption(kind: .effort, command: "/effort", title: "Effort", detail: "Set low, medium, high, xhigh, or max reasoning.", symbol: "brain.head.profile", badge: "Claude/Codex"),
        SlashCommandOption(kind: .ultrathink, command: "/ultrathink", title: "Ultrathink", detail: "Use xhigh reasoning for this run.", symbol: "flame"),
        SlashCommandOption(kind: .caveman, command: "/caveman", title: "Caveman", detail: "Use terse, direct output for this run.", symbol: "bolt", badge: "Air Code"),
        SlashCommandOption(kind: .review, command: "/review", title: "Review", detail: "Review current changes for bugs and regressions.", symbol: "checkmark.seal", badge: "Task"),
        SlashCommandOption(kind: .securityReview, command: "/security-review", title: "Security Review", detail: "Inspect changes for security risks.", symbol: "lock.shield", badge: "Task"),
        SlashCommandOption(kind: .run, command: "/run", title: "Run", detail: "Ask the agent to launch or exercise the app.", symbol: "play.circle", badge: "Task"),
        SlashCommandOption(kind: .verify, command: "/verify", title: "Verify", detail: "Ask the agent to build, test, and validate behavior.", symbol: "checkmark.circle", badge: "Task"),
        SlashCommandOption(kind: .simplify, command: "/simplify", title: "Simplify", detail: "Improve recent edits for quality and reuse.", symbol: "wand.and.stars", badge: "Task"),
        SlashCommandOption(kind: .debug, command: "/debug", title: "Debug", detail: "Investigate a failing behavior or log.", symbol: "stethoscope", badge: "Task"),
        SlashCommandOption(kind: .initProject, command: "/init", title: "Init Memory", detail: "Create agent project guidance files.", symbol: "doc.badge.plus", badge: "Task"),
        SlashCommandOption(kind: .diff, command: "/diff", title: "Diff", detail: "Open Air Code's side-by-side diff view.", symbol: "rectangle.split.2x1"),
        SlashCommandOption(kind: .status, command: "/status", title: "Status", detail: "Show current agent, model, mode, and session.", symbol: "info.circle"),
        SlashCommandOption(kind: .help, command: "/help", title: "Command Help", detail: "Show supported slash commands.", symbol: "questionmark.circle"),
        SlashCommandOption(kind: .providerNative, command: "/rollback", title: "Rollback", detail: "Hermes checkpoint restore or preview.", symbol: "arrow.uturn.backward.circle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/subgoal", title: "Subgoal", detail: "Add criteria to an active Hermes goal.", symbol: "target", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/history", title: "History", detail: "Show Hermes conversation history.", symbol: "clock", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/save", title: "Save", detail: "Save the current Hermes conversation.", symbol: "tray.and.arrow.down", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/retry", title: "Retry", detail: "Retry the last Hermes message.", symbol: "arrow.clockwise", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/undo", title: "Undo", detail: "Remove the last Hermes exchange.", symbol: "arrow.uturn.left", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/compress", title: "Compress", detail: "Compact Hermes context with an optional focus.", symbol: "arrow.down.right.and.arrow.up.left", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/sessions", title: "Sessions", detail: "Browse Hermes sessions.", symbol: "rectangle.stack", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/commands", title: "Commands", detail: "Browse Hermes commands and skills.", symbol: "command", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/tools", title: "Tools", detail: "Show Hermes tool status.", symbol: "hammer", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/toolsets", title: "Toolsets", detail: "Manage Hermes toolsets.", symbol: "shippingbox", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reasoning", title: "Reasoning", detail: "Change Hermes reasoning display or effort.", symbol: "brain.head.profile", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/queue", title: "Queue", detail: "Queue a Hermes prompt for the next turn.", symbol: "text.line.first.and.arrowtriangle.forward", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/steer", title: "Steer", detail: "Inject a mid-run Hermes steering note.", symbol: "arrow.triangle.turn.up.right.diamond", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/footer", title: "Footer", detail: "Toggle Hermes runtime metadata footer.", symbol: "rectangle.bottomthird.inset.filled", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/yolo", title: "YOLO", detail: "Toggle Hermes dangerous-command approval bypass.", symbol: "exclamationmark.triangle", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reload-mcp", title: "Reload MCP", detail: "Reload Hermes MCP servers.", symbol: "point.3.connected.trianglepath.dotted", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/reload-skills", title: "Reload Skills", detail: "Reload Hermes skills.", symbol: "puzzlepiece.extension", badge: "Hermes", supportedAgents: ["hermes"]),
        SlashCommandOption(kind: .speed, command: "/fast", title: "Fast Mode", detail: "Turn Codex fast mode on, off, or show status.", symbol: "hare", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/permissions", title: "Permissions", detail: "Provider-native approval rules; configure on the server.", symbol: "hand.raised", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/ide", title: "IDE Context", detail: "Provider IDE integration; Air Code sends project context directly.", symbol: "rectangle.connected.to.line.below", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/experimental", title: "Experimental", detail: "Codex experimental feature toggles.", symbol: "testtube.2", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/approve", title: "Approve", detail: "Codex approval retry command.", symbol: "checkmark.shield", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/memories", title: "Memories", detail: "Codex memory configuration.", symbol: "books.vertical", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/mcp", title: "MCP", detail: "Provider-native MCP management.", symbol: "point.3.connected.trianglepath.dotted", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/skills", title: "Skills", detail: "Provider-native skills command.", symbol: "puzzlepiece.extension", badge: "Provider", supportedAgents: ["codex", "claude", "hermes"]),
        SlashCommandOption(kind: .providerNative, command: "/compact", title: "Compact", detail: "Provider-native context compaction.", symbol: "arrow.down.right.and.arrow.up.left", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/collab", title: "Collab", detail: "Codex collaboration mode switch.", symbol: "person.2.wave.2", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/agent", title: "Agent Thread", detail: "Codex active agent thread switch.", symbol: "person.crop.circle.badge.gearshape", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/side", title: "Side Chat", detail: "Codex ephemeral side conversation.", symbol: "sidebar.right", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/rename", title: "Rename", detail: "Provider-native session rename.", symbol: "text.cursor", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/fork", title: "Fork", detail: "Provider-native conversation branch.", symbol: "arrow.triangle.branch", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/copy", title: "Copy", detail: "Provider-native terminal clipboard action.", symbol: "doc.on.doc", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/theme", title: "Theme", detail: "Use Air Code's theme menu instead.", symbol: "paintpalette", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/logout", title: "Logout", detail: "Provider-native auth command; run on the server terminal.", symbol: "rectangle.portrait.and.arrow.right", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/memory", title: "Memory", detail: "Claude memory files and command skills.", symbol: "books.vertical", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/agents", title: "Agents", detail: "Claude subagent manager.", symbol: "person.2", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/batch", title: "Batch", detail: "Claude bundled skill for parallel work.", symbol: "square.stack.3d.up", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/branch", title: "Branch", detail: "Claude conversation branch.", symbol: "arrow.triangle.branch", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/btw", title: "BTW", detail: "Claude side question without bloating context.", symbol: "text.bubble", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/clear", title: "Clear", detail: "Start a new local Air Code session.", symbol: "trash", badge: "Claude alias"),
        SlashCommandOption(kind: .providerNative, command: "/context", title: "Context", detail: "Claude context usage viewer.", symbol: "chart.bar.xaxis", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/cost", title: "Cost", detail: "Claude usage alias.", symbol: "creditcard", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/doctor", title: "Doctor", detail: "Provider installation diagnostics.", symbol: "cross.case", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/hooks", title: "Hooks", detail: "Provider-native lifecycle hooks.", symbol: "link", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/keymap", title: "Keymap", detail: "Codex terminal keymap settings.", symbol: "keyboard", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/vim", title: "Vim Mode", detail: "Provider-native terminal editor mode.", symbol: "keyboard.chevron.compact.down", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/plugins", title: "Plugins", detail: "Provider-native plugin browser.", symbol: "shippingbox", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/raw", title: "Raw", detail: "Codex raw scrollback toggle.", symbol: "text.alignleft", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/mention", title: "Mention File", detail: "Codex terminal file mention helper.", symbol: "at", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/title", title: "Title", detail: "Codex terminal title config.", symbol: "rectangle.and.pencil.and.ellipsis", badge: "Codex", supportedAgents: ["codex"]),
        SlashCommandOption(kind: .providerNative, command: "/statusline", title: "Status Line", detail: "Provider-native terminal status line config.", symbol: "rectangle.bottomthird.inset.filled", badge: "Codex/Claude", supportedAgents: ["codex", "claude"]),
        SlashCommandOption(kind: .providerNative, command: "/usage", title: "Usage", detail: "Claude usage and limits.", symbol: "chart.line.uptrend.xyaxis", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/rewind", title: "Rewind", detail: "Claude checkpoint undo.", symbol: "backward.end", badge: "Claude", supportedAgents: ["claude"]),
        SlashCommandOption(kind: .providerNative, command: "/tasks", title: "Tasks", detail: "Claude background task list.", symbol: "checklist", badge: "Claude", supportedAgents: ["claude"]),
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
        SlashCommandOption(kind: .providerNative, command: "/stop", title: "Stop", detail: "Stop Claude background work.", symbol: "stop.circle", badge: "Claude", supportedAgents: ["claude"]),
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
        case (.fast, "codex"):
            return "Fast 1.5x"
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
        guard isSupported(by: agentID) else { return AgentSpeedMode.auto.rawValue }
        return rawValue
    }
}

public struct StartAgentRequest: Codable, Sendable {
    public let agent: String
    public let prompt: String
    public let mode: String
    public let provider: String
    public let model: String
    public let reasoningEffort: String
    public let speedMode: String
    public let resumeSession: Bool
    public let caveman: Bool

    public init(agent: String, prompt: String, mode: AgentMode = .agent, provider: String = "", model: String = "", reasoningEffort: ReasoningEffort = .auto, speedMode: AgentSpeedMode = .auto, resumeSession: Bool = true, caveman: Bool = false) {
        self.agent = agent
        self.prompt = prompt
        self.mode = mode.rawValue
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort.rawValue
        self.speedMode = speedMode.requestValue(for: agent)
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

public struct AgentSessionInfo: Codable, Identifiable, Hashable, Sendable {
    public let agent: String
    public let sessionId: String
    public let updatedAt: String
    public let lastRunId: String?
    public let lastMode: String?
    public let model: String?
    public let reasoningEffort: String?
    public let speedMode: String?

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
    public let runId: String?
    public let changes: [GitChange]

    public init(id: String = UUID().uuidString, role: Role, text: String, runId: String? = nil, changes: [GitChange] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.runId = runId
        self.changes = changes
    }
}
