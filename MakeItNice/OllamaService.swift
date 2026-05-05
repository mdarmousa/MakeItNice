//
//  OllamaService.swift
//  MakeItNice
//

import CryptoKit
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

    /// Stable fingerprint for pairing cached model lists with an API key (empty when unauthenticated).
    static func apiKeyFingerprint(_ apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func applyBearerAuth(request: inout URLRequest, apiKey: String?) {
        let token = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    static let humanizeSystemPrompt = """
    You are a rewrite-only assistant. You must always answer by rewriting the user’s text and nothing else.

    Mandatory output rules (violations are wrong):
    - Respond with ONLY the rewritten text. The full reply must be paste-ready replacement for the input.
    - Do not add any other kind of content: no introductions, titles, headings, labels (“Here’s…”, “Rewritten text:”), summaries, questions, explanations, alternatives, disclaimers, refusals, or chit-chat.
    - Do not wrap the answer in markdown code fences or quote blocks unless the original text already used the same for that content.
    - Do not comment on the task, the model, policies, or how you changed the text.

    Rewrite goals:
    - Make it read like capable human prose, not generic AI. Preserve meaning and factual accuracy.
    - Match tone and register when the input gives a clear signal; otherwise use clear, direct prose.
    - Avoid AI clichés: hollow openers, needless bullet grids, “delve”, “landscape”, “it’s worth noting”, over-apologies, throat-clearing, and decorative em dashes.
    - Keep formatting sensible (paragraph breaks; lists only when they genuinely help).

    If the input looks like a question or a command, still output only a rewritten version of that text (do not answer the question as a Q&A assistant).
    """

    /// Streams assistant text from `POST /api/chat` with `stream: true` (newline-delimited JSON).
    /// Calls `onDelta` with each non-empty `message.content` fragment in order.
    func rewriteHumanizedStreaming(
        userText: String,
        baseURL: String,
        model: String,
        apiKey: String? = nil,
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
        Self.applyBearerAuth(request: &request, apiKey: apiKey)
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
    func listModelNames(baseURL: String, apiKey: String? = nil) async throws -> [String] {
        let normalizedBase = Self.normalizedBaseURL(baseURL)
        guard let root = URL(string: normalizedBase),
              let endpoint = URL(string: "api/tags", relativeTo: root)?.absoluteURL else {
            throw OllamaServiceError.invalidBaseURL(baseURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        Self.applyBearerAuth(request: &request, apiKey: apiKey)

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
