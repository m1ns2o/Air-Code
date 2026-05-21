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

    public var id: String { rawValue }
    public var title: String { self == .agent ? "Agent" : "Plan" }
    public var symbol: String { self == .agent ? "wand.and.stars" : "list.bullet.clipboard" }
}

public struct StartAgentRequest: Codable, Sendable {
    public let agent: String
    public let prompt: String
    public let mode: String
    public let ultrathink: Bool
    public let caveman: Bool

    public init(agent: String, prompt: String, mode: AgentMode = .agent, ultrathink: Bool = false, caveman: Bool = false) {
        self.agent = agent
        self.prompt = prompt
        self.mode = mode.rawValue
        self.ultrathink = ultrathink
        self.caveman = caveman
    }
}

public struct StartAgentResponse: Codable, Sendable {
    public let runId: String
    public let agent: String
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

    public let id: UUID
    public let role: Role
    public let text: String
    public let changes: [GitChange]

    public init(id: UUID = UUID(), role: Role, text: String, changes: [GitChange] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.changes = changes
    }
}
