import Foundation

public enum LSPWebSocketTransportError: LocalizedError {
    case missingResult
    case server(String)
    case mismatchedResponse(expected: String, actual: String?)

    public var errorDescription: String? {
        switch self {
        case .missingResult:
            return "LSP WebSocket response is missing a result."
        case .server(let message):
            return message
        case .mismatchedResponse(let expected, let actual):
            return "LSP WebSocket response id mismatch. expected=\(expected) actual=\(actual ?? "nil")"
        }
    }
}

public actor LSPWebSocketTransport {
    private let task: URLSessionWebSocketTask
    private var didResume = false

    public init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func request<Result: Decodable & Sendable, Params: Encodable & Sendable>(_ method: String, params: Params) async throws -> Result {
        if !didResume {
            task.resume()
            didResume = true
        }

        let id = UUID().uuidString
        let payload = LSPWebSocketRequest(id: id, method: method, params: params)
        let data = try JSONEncoder.airCode.encode(payload)
        try await task.send(.data(data))

        while !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let text):
                data = Data(text.utf8)
            @unknown default:
                continue
            }
            let response = try JSONDecoder.airCode.decode(LSPWebSocketResponse<Result>.self, from: data)
            guard response.id == id else {
                throw LSPWebSocketTransportError.mismatchedResponse(expected: id, actual: response.id)
            }
            guard response.ok else {
                throw LSPWebSocketTransportError.server(response.error ?? "LSP WebSocket request failed.")
            }
            guard let result = response.result else {
                throw LSPWebSocketTransportError.missingResult
            }
            return result
        }
        throw CancellationError()
    }

    public func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

private struct LSPWebSocketRequest<Params: Encodable>: Encodable {
    let id: String
    let method: String
    let params: Params
}

private struct LSPWebSocketResponse<Result: Decodable>: Decodable {
    let id: String?
    let ok: Bool
    let result: Result?
    let error: String?
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
