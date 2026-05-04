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

    private let service = OllamaService()

    var body: some View {
        Form {
            Section {
                DisclosureGroup("Connection", isExpanded: $connectionExpanded) {
                    TextField("Base URL", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $ollamaModel)
                        .textFieldStyle(.roundedBorder)
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

            Section("Result") {
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
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runRewrite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            output = try await service.rewriteHumanized(
                userText: input,
                baseURL: ollamaBaseURL,
                model: ollamaModel
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
