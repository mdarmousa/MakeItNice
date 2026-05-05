//
//  MakeItNiceApp.swift
//  MakeItNice
//
//  Created by Mohammad Darmousa on 05/05/2026.
//

import SwiftUI

@main
struct MakeItNiceApp: App {
    @Environment(\.openWindow) private var openWindow

    private let hotKeyManager = HotKeyManager()

    init() {
        hotKeyManager.start()
    }

    var body: some Scene {
        Window("Make It Nice", id: "main") {
            RewriteView()
                .frame(minWidth: 360, minHeight: 460)
                .background(MainWindowOpener())
        }

        MenuBarExtra("Make It Nice", systemImage: "bolt.fill") {
            Button("Open") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button("Grab selection & rewrite (⌘F)") {
                Task { @MainActor in
                    await GlobalSelectionPipeline.run {
                        AppActionCenter.shared.requestOpenMainWindow()
                    }
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
