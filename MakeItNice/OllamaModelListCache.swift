//
//  OllamaModelListCache.swift
//  MakeItNice
//

import Foundation

/// Persisted snapshot of `GET /api/tags` for a single Ollama base URL.
struct OllamaModelListCache: Codable, Sendable {
    /// Stored normalized base URL (matches `OllamaService.normalizedBaseURL`).
    var baseURL: String
    var names: [String]
    var fetchedAt: Date

    /// Time after which a background refresh is allowed (cache may still be shown while stale).
    static let ttl: TimeInterval = 24 * 60 * 60

    private static let userDefaultsKey = "ollamaModelListCache.v1"

    static func load() -> OllamaModelListCache? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(OllamaModelListCache.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
