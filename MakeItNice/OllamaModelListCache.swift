//
//  OllamaModelListCache.swift
//  MakeItNice
//

import Foundation

/// Persisted snapshot of `GET /api/tags` for a single Ollama base URL (+ optional API key identity).
struct OllamaModelListCache: Codable, Sendable {
    /// Stored normalized base URL (matches `OllamaService.normalizedBaseURL`).
    var baseURL: String
    /// Matches `OllamaService.apiKeyFingerprint` for the key used; empty when unauthenticated.
    var apiKeyFingerprint: String
    var names: [String]
    var fetchedAt: Date

    /// Time after which a background refresh is allowed (cache may still be shown while stale).
    static let ttl: TimeInterval = 24 * 60 * 60

    private static let userDefaultsKey = "ollamaModelListCache.v1"

    enum CodingKeys: String, CodingKey {
        case baseURL
        case apiKeyFingerprint
        case names
        case fetchedAt
    }

    init(baseURL: String, apiKeyFingerprint: String, names: [String], fetchedAt: Date) {
        self.baseURL = baseURL
        self.apiKeyFingerprint = apiKeyFingerprint
        self.names = names
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        apiKeyFingerprint = try c.decodeIfPresent(String.self, forKey: .apiKeyFingerprint) ?? ""
        names = try c.decode([String].self, forKey: .names)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
    }

    static func load() -> OllamaModelListCache? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(OllamaModelListCache.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}
