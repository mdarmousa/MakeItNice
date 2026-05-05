import AppKit
import Carbon.HIToolbox
import Foundation

/// Copies the frontmost app’s selection via synthetic ⌘C, then hands text to the main UI.
@MainActor
enum GlobalSelectionPipeline {
    static func run(openMainWindow: @escaping () -> Void) async {
        postCommandC()
        try? await Task.sleep(for: .milliseconds(150))
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        NSApp.activate(ignoringOtherApps: true)
        openMainWindow()
        try? await Task.sleep(for: .milliseconds(80))
        AppActionCenter.shared.deliverSelectionText(text)
    }

    private static func postCommandC() {
        let keyCode = CGKeyCode(kVK_ANSI_C)
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
