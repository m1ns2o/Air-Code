import Foundation

public enum AirCodeAPIError: LocalizedError {
    case invalidURL
    case missingConnection
    case badStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .missingConnection:
            return "Server URL or token is missing."
        case .badStatus(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}

public final class AirCodeAPI: Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func checkAuth() async throws {
        let _: [String: Bool] = try await send(path: "/v1/auth/check", method: "GET")
    }

    public func projects() async throws -> [ProjectSummary] {
        try await send(path: "/v1/projects", method: "GET")
    }

    public func workspaceRoots() async throws -> [WorkspaceRootSummary] {
        try await send(path: "/v1/workspace-roots", method: "GET")
    }

    public func workspaceTree(rootId: String, path: String) async throws -> [TreeEntry] {
        try await send(path: "/v1/workspace-roots/\(rootId)/tree?path=\(path.urlQueryEscaped)", method: "GET")
    }

    public func openWorkspace(rootId: String, path: String) async throws -> ProjectSummary {
        try await send(path: "/v1/workspace/open", method: "POST", body: OpenWorkspaceRequest(rootId: rootId, path: path))
    }

    public func tree(projectId: String, path: String) async throws -> [TreeEntry] {
        try await send(path: "/v1/projects/\(projectId)/tree?path=\(path.urlQueryEscaped)", method: "GET")
    }

    public func readFile(projectId: String, path: String) async throws -> FileResponse {
        try await send(path: "/v1/projects/\(projectId)/files?path=\(path.urlQueryEscaped)", method: "GET")
    }

    public func saveFile(projectId: String, path: String, content: String, baseVersion: String) async throws -> FileResponse {
        try await send(path: "/v1/projects/\(projectId)/files", method: "PUT", body: SaveFileRequest(path: path, content: content, baseVersion: baseVersion))
    }

    public func gitStatus(projectId: String) async throws -> [GitChange] {
        try await send(path: "/v1/projects/\(projectId)/git/status", method: "GET")
    }

    public func diff(projectId: String, path: String) async throws -> DiffResponse {
        try await send(path: "/v1/projects/\(projectId)/git/diff?path=\(path.urlQueryEscaped)", method: "GET")
    }

    public func revert(projectId: String, path: String) async throws {
        let _: [String: Bool] = try await send(path: "/v1/projects/\(projectId)/git/revert", method: "POST", body: ["path": path])
    }

    public func runCommand(projectId: String, command: String, args: [String]) async throws -> CommandResponse {
        try await send(path: "/v1/projects/\(projectId)/command", method: "POST", body: CommandRequest(command: command, args: args))
    }

    public func startAgent(projectId: String, agent: String, prompt: String, mode: AgentMode, ultrathink: Bool, caveman: Bool) async throws -> StartAgentResponse {
        try await send(path: "/v1/projects/\(projectId)/agents/runs", method: "POST", body: StartAgentRequest(agent: agent, prompt: prompt, mode: mode, ultrathink: ultrathink, caveman: caveman))
    }

    public func stopAgent(projectId: String, runId: String) async throws {
        let _: [String: Bool] = try await send(path: "/v1/projects/\(projectId)/agents/runs/\(runId)/stop", method: "POST")
    }

    public func eventStream() -> AsyncThrowingStream<EventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            guard var components = URLComponents(url: baseURL.appendingPathComponent("/v1/events"), resolvingAgainstBaseURL: false) else {
                continuation.finish(throwing: AirCodeAPIError.invalidURL)
                return
            }
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            guard let url = components.url else {
                continuation.finish(throwing: AirCodeAPIError.invalidURL)
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let task = session.webSocketTask(with: request)
            task.resume()

            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data
                        switch message {
                        case .data(let payload): data = payload
                        case .string(let text): data = Data(text.utf8)
                        @unknown default: continue
                        }
                        let event = try JSONDecoder.airCode.decode(EventEnvelope.self, from: data)
                        continuation.yield(event)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                receiveTask.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func send<T: Decodable, B: Encodable>(path: String, method: String, body: B? = Optional<Data>.none) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AirCodeAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder.airCode.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AirCodeAPIError.badStatus(-1, "Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AirCodeAPIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == [String: Bool].self, data.isEmpty {
            return ["ok": true] as! T
        }
        return try JSONDecoder.airCode.decode(T.self, from: data)
    }
}

private extension String {
    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
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
