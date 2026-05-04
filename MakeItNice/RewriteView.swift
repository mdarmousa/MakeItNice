//
//  RewriteView.swift
//  MakeItNice
//

import AppKit
import SwiftUI

struct RewriteView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://127.0.0.1:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "gemma4"

    @State private var input = ""
    @State private var output = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var connectionExpanded = false

    @State private var availableModels: [String] = []
    @State private var modelsLoadError: String?
    @State private var isLoadingModels = false

    /// Duration of the last successful rewrite; shown in the Results header.
    @State private var lastRewriteDuration: TimeInterval?

    private let service = OllamaService()

    /// Picker options: server list plus current selection so tags stay valid.
    private var pickerModelNames: [String] {
        var set = Set(availableModels)
        let m = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { set.insert(m) }
        return set.sorted()
    }

    private var resultsSectionTitle: String {
        if let d = lastRewriteDuration {
            return "Results (\(Self.formatRewriteDuration(d)))"
        }
        return "Results"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("Make It Nice")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            Form {
            Section {
                DisclosureGroup("Connection", isExpanded: $connectionExpanded) {
                    TextField("Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)

                    if pickerModelNames.isEmpty {
                        TextField("Model", text: $ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Model", selection: $ollamaModel) {
                            ForEach(pickerModelNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 8) {
                        Button("Refresh models") {
                            Task { await loadModels(forceNetwork: true) }
                        }
                        .disabled(isLoadingModels || !isBaseURLValid)

                        if isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer(minLength: 0)
                    }

                    if let modelsLoadError {
                        Text(modelsLoadError)
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Draft") {
                TextEditor(text: $input)
                    .font(.body)
                    .frame(minHeight: 120)
            }

            Section {
                HStack(spacing: 12) {
                    Button("Rewrite") {
                        Task { await runRewrite() }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(trimmedInput.isEmpty || isLoading)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                ScrollView {
                    Text(output.isEmpty ? " " : output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .font(.body)
                }
                .frame(minHeight: 140)

                HStack(spacing: 12) {
                    Button("Copy") {
                        copyOutput()
                    }
                    .disabled(trimmedOutput.isEmpty)

                    Button("Clear") {
                        input = ""
                        output = ""
                        errorMessage = nil
                        lastRewriteDuration = nil
                    }
                }
            } header: {
                Text(resultsSectionTitle)
            }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .task(id: ollamaBaseURL) {
            await loadModels(forceNetwork: false)
        }
    }

    private var isBaseURLValid: Bool {
        let key = OllamaService.normalizedBaseURL(ollamaBaseURL)
        return URL(string: key) != nil
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loads from cache when fresh; fetches when missing, stale past TTL, or `forceNetwork`.
    private func loadModels(forceNetwork: Bool) async {
        let key = OllamaService.normalizedBaseURL(ollamaBaseURL)
        guard URL(string: key) != nil else {
            modelsLoadError = OllamaServiceError.invalidBaseURL(ollamaBaseURL).errorDescription
            return
        }

        let cachedForKey: OllamaModelListCache? = {
            guard let c = OllamaModelListCache.load(),
                  OllamaService.normalizedBaseURL(c.baseURL) == key else { return nil }
            return c
        }()

        if let c = cachedForKey {
            availableModels = c.names
            modelsLoadError = nil
        } else if !forceNetwork {
            availableModels = []
        }

        let withinTTL = cachedForKey.map { Date().timeIntervalSince($0.fetchedAt) <= OllamaModelListCache.ttl } ?? false
        if !forceNetwork, withinTTL {
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let names = try await service.listModelNames(baseURL: ollamaBaseURL)
            availableModels = names
            OllamaModelListCache(baseURL: key, names: names, fetchedAt: Date()).save()
            modelsLoadError = nil
        } catch {
            modelsLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if cachedForKey == nil {
                availableModels = []
            }
        }
    }

    private func runRewrite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let started = Date()
        do {
            output = try await service.rewriteHumanized(
                userText: input,
                baseURL: ollamaBaseURL,
                model: ollamaModel
            )
            lastRewriteDuration = Date().timeIntervalSince(started)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Human-readable duration for the section title (e.g. `1 Second`, `2.4 Seconds`, `240 ms`).
    private static func formatRewriteDuration(_ seconds: TimeInterval) -> String {
        let s = max(seconds, 0)
        if s < 1 {
            let ms = max(1, Int((s * 1000).rounded(.toNearestOrAwayFromZero)))
            return "\(ms) ms"
        }
        let rounded = s.rounded(.toNearestOrAwayFromZero)
        if abs(s - rounded) < 0.05 {
            let n = Int(rounded)
            return n == 1 ? "1 Second" : "\(n) Seconds"
        }
        return String(format: "%.1f Seconds", s)
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}

#Preview {
    RewriteView()
        .frame(width: 380, height: 520)
}
