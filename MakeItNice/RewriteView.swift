//
//  RewriteView.swift
//  MakeItNice
//

import AppKit
import SwiftUI

struct RewriteView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://127.0.0.1:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "gemma4"
    /// Ollama Cloud: create at ollama.com/settings/keys — required only for `https://ollama.com` direct API.
    @AppStorage("ollamaAPIKey") private var ollamaAPIKey = ""

    @State private var input = ""
    @State private var output = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var connectionExpanded = false

    @State private var availableModels: [String] = []
    @State private var modelsLoadError: String?
    @State private var isLoadingModels = false

    @FocusState private var focusedField: FocusedField?

    /// Duration of the last successful rewrite; shown in the Results header.
    @State private var lastRewriteDuration: TimeInterval?

    /// Skips debounced rewrite when setting `input` from the ⌘F selection pipeline.
    @State private var suppressDebouncedRewrite = false
    @State private var inputDebounceTask: Task<Void, Never>?

    private let service = OllamaService()

    private enum FocusedField: Hashable {
        case draft
    }

    /// Picker options: server list plus current selection so tags stay valid.
    private var pickerModelNames: [String] {
        var set = Set(availableModels)
        let m = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { set.insert(m) }
        return set.sorted()
    }

    private var connectionTaskIdentity: String {
        let fp = OllamaService.apiKeyFingerprint(ollamaAPIKey)
        return "\(OllamaService.normalizedBaseURL(ollamaBaseURL))|\(fp)"
    }

    private var resultsSectionTitle: String {
        if let d = lastRewriteDuration {
            return "Results (\(Self.formatRewriteDuration(d)))"
        }
        return "Results"
    }

    /// Header / footer chrome: same SF Symbol and title as the menu bar app uses.
    private var brandChromeRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text("Make It Nice")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            brandChromeRow

            Form {
            Section {
                DisclosureGroup("Connection", isExpanded: $connectionExpanded) {
                    TextField("Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API key (Ollama Cloud only)", text: $ollamaAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Local Ollama: leave API key empty. Cloud: set Base URL to https://ollama.com and paste your key from ollama.com/settings/keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Use Ollama Cloud") {
                            ollamaBaseURL = "https://ollama.com"
                            connectionExpanded = true
                        }
                        Spacer(minLength: 0)
                    }

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
                    .focused($focusedField, equals: .draft)
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

            brandChromeRow
                .padding(.top, 4)
        }
        .formStyle(.grouped)
        .padding(8)
        .task(id: connectionTaskIdentity) {
            await loadModels(forceNetwork: false)
        }
        .onChange(of: input) { _, _ in
            guard !suppressDebouncedRewrite else { return }
            inputDebounceTask?.cancel()
            inputDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                await runDebouncedRewriteAfterInputChange()
            }
        }
        .onAppear {
            AppActionCenter.shared.registerSelectionPipeline { text in
                Task { await applySelectionFromHotKey(text) }
            }
        }
        .onDisappear {
            inputDebounceTask?.cancel()
            inputDebounceTask = nil
            AppActionCenter.shared.clearRegistration()
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
        let authPrint = OllamaService.apiKeyFingerprint(ollamaAPIKey)
        guard URL(string: key) != nil else {
            modelsLoadError = OllamaServiceError.invalidBaseURL(ollamaBaseURL).errorDescription
            return
        }

        let cachedForKey: OllamaModelListCache? = {
            guard let c = OllamaModelListCache.load(),
                  OllamaService.normalizedBaseURL(c.baseURL) == key,
                  c.apiKeyFingerprint == authPrint else { return nil }
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
            let names = try await service.listModelNames(baseURL: ollamaBaseURL, apiKey: ollamaAPIKey)
            availableModels = names
            OllamaModelListCache(
                baseURL: key,
                apiKeyFingerprint: authPrint,
                names: names,
                fetchedAt: Date()
            ).save()
            modelsLoadError = nil
        } catch {
            modelsLoadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if cachedForKey == nil {
                availableModels = []
            }
        }
    }

    private func applySelectionFromHotKey(_ text: String) async {
        suppressDebouncedRewrite = true
        input = text
        suppressDebouncedRewrite = false
        focusedField = .draft
        await runRewrite()
    }

    private func runDebouncedRewriteAfterInputChange() async {
        guard !trimmedInput.isEmpty else {
            output = ""
            errorMessage = nil
            lastRewriteDuration = nil
            return
        }
        await runRewrite()
    }

    private func runRewrite() async {
        guard !trimmedInput.isEmpty else {
            output = ""
            errorMessage = nil
            lastRewriteDuration = nil
            return
        }
        isLoading = true
        errorMessage = nil
        output = ""
        defer { isLoading = false }
        let started = Date()
        do {
            try await service.rewriteHumanizedStreaming(
                userText: input,
                baseURL: ollamaBaseURL,
                model: ollamaModel,
                apiKey: ollamaAPIKey
            ) { delta in
                await MainActor.run {
                    output += delta
                }
            }
            lastRewriteDuration = Date().timeIntervalSince(started)
            copyOutput()
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
        guard !trimmedOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}

#Preview {
    RewriteView()
        .frame(width: 380, height: 520)
}
