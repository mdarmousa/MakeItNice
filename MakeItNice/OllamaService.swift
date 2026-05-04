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

    static let humanizeSystemPrompt = """
    You rewrite text so it reads like a thoughtful human wrote it, not an AI.
    Preserve meaning and factual accuracy. Match the user’s approximate tone and register (casual vs formal) unless they gave almost no signal—then default to clear, direct prose.
    Avoid AI clichés: stock openers, symmetrical bullet patterns for no reason, “delve”, “landscape”, “it’s important to note”, over-apologies, filler throat-clearing, and heavy em dash habits.
    Keep formatting reasonable (paragraphs, lists only when they help). Do not add a preamble or meta commentary.
    Output only the rewritten text.
    """

    func rewriteHumanized(userText: String, baseURL: String, model: String) async throws -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalizedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let root = URL(string: normalizedBase),
              let endpoint = URL(string: "api/chat", relativeTo: root)?.absoluteURL else {
            throw OllamaServiceError.invalidBaseURL(baseURL)
        }

        let payload = ChatRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            stream: false,
            messages: [
                .init(role: "system", content: Self.humanizeSystemPrompt),
                .init(role: "user", content: trimmed),
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

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

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw OllamaServiceError.serverMessage(err)
        }
        guard let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw OllamaServiceError.emptyResponse
        }
        return content
    }
}

// MARK: - Wire format

private struct ChatRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [ChatMessage]
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let message: AssistantMessage?
    let error: String?

    struct AssistantMessage: Decodable {
        let role: String?
        let content: String?
    }
}

private struct OllamaErrorEnvelope: Decodable {
    let error: String?
}
