//
//  OllamaService.swift
//  MakeItNice
//

import Foundation

enum OllamaServiceError: LocalizedError {
    case invalidBaseURL(String)
    case emptyResponse
    case serverMessage(String)
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let s):
            return "Invalid Ollama base URL: \(s)"
        case .emptyResponse:
            return "Ollama returned an empty reply."
        case .serverMessage(let s):
            return s
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "HTTP \(code): \(body)"
            }
            return "HTTP \(code)"
        }
    }
}

struct OllamaService: Sendable {

    /// Normalized host root for cache keys and API paths (trim whitespace, no trailing slash).
    static func normalizedBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static let humanizeSystemPrompt = """
    You rewrite text so it reads like a thoughtful human wrote it, not an AI.
    Preserve meaning and factual accuracy. Match the user’s approximate tone and register (casual vs formal) unless they gave almost no signal—then default to clear, direct prose.
    Avoid AI clichés: stock openers, symmetrical bullet patterns for no reason, “delve”, “landscape”, “it’s important to note”, over-apologies, filler throat-clearing, and heavy em dash habits.
    Keep formatting reasonable (paragraphs, lists only when they help). Do not add a preamble or meta commentary.
    Output only the rewritten text.
    """

    /// Streams assistant text from `POST /api/chat` with `stream: true` (newline-delimited JSON).
    /// Calls `onDelta` with each non-empty `message.content` fragment in order.
    func rewriteHumanizedStreaming(
        userText: String,
        baseURL: String,
        model: String,
        onDelta: @Sendable @escaping (String) async -> Void
    ) async throws {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalizedBase = Self.normalizedBaseURL(baseURL)
        guard let root = URL(string: normalizedBase),
              let endpoint = URL(string: "api/chat", relativeTo: root)?.absoluteURL else {
            throw OllamaServiceError.invalidBaseURL(baseURL)
        }

        let payload = ChatRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            stream: true,
            messages: [
                .init(role: "system", content: Self.humanizeSystemPrompt),
                .init(role: "user", content: trimmed),
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaServiceError.httpStatus(-1, nil)
        }

        if http.statusCode != 200 {
            var acc = Data()
            acc.reserveCapacity(4096)
            for try await b in bytes {
                acc.append(b)
                if acc.count > 65_536 { break }
            }
            let snippet = String(data: acc, encoding: .utf8)
            if let errBody = try? JSONDecoder().decode(OllamaErrorEnvelope.self, from: acc),
               let msg = errBody.error, !msg.isEmpty {
                throw OllamaServiceError.serverMessage(msg)
            }
            throw OllamaServiceError.httpStatus(http.statusCode, snippet)
        }

        var lineBuffer = Data()
        var sawAnyContent = false

        func flushLine() async throws {
            defer { lineBuffer.removeAll(keepingCapacity: true) }
            guard !lineBuffer.isEmpty,
                  let line = String(data: lineBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { return }

            guard let lineData = line.data(using: .utf8) else { return }
            let chunk = try JSONDecoder().decode(ChatStreamChunk.self, from: lineData)
            if let err = chunk.error, !err.isEmpty {
                throw OllamaServiceError.serverMessage(err)
            }
            if let piece = chunk.message?.content, !piece.isEmpty {
                await onDelta(piece)
                sawAnyContent = true
            }
        }

        for try await byte in bytes {
            if byte == 13 { continue }
            if byte == 10 {
                try await flushLine()
            } else {
                lineBuffer.append(byte)
            }
        }
        try await flushLine()

        if !sawAnyContent {
            throw OllamaServiceError.emptyResponse
        }
    }

    /// Lists installed model names from `GET /api/tags`.
    func listModelNames(baseURL: String) async throws -> [String] {
        let normalizedBase = Self.normalizedBaseURL(baseURL)
        guard let root = URL(string: normalizedBase),
              let endpoint = URL(string: "api/tags", relativeTo: root)?.absoluteURL else {
            throw OllamaServiceError.invalidBaseURL(baseURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaServiceError.httpStatus(-1, nil)
        }

        if http.statusCode != 200 {
            let snippet = String(data: data, encoding: .utf8)
            if let errBody = try? JSONDecoder().decode(OllamaErrorEnvelope.self, from: data),
               let msg = errBody.error, !msg.isEmpty {
                throw OllamaServiceError.serverMessage(msg)
            }
            throw OllamaServiceError.httpStatus(http.statusCode, snippet)
        }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw OllamaServiceError.serverMessage(err)
        }
        return (decoded.models ?? []).map(\.name).sorted()
    }
}

// MARK: - Wire format

private struct TagsResponse: Decodable {
    let models: [TagModel]?
    let error: String?

    struct TagModel: Decodable {
        let name: String
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [ChatMessage]
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatStreamChunk: Decodable {
    let message: StreamAssistantMessage?
    let error: String?

    struct StreamAssistantMessage: Decodable {
        let content: String?
    }
}

private struct OllamaErrorEnvelope: Decodable {
    let error: String?
}
