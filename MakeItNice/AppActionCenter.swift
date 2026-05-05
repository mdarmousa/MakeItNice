import Foundation

@MainActor
final class AppActionCenter {
    static let shared = AppActionCenter()

    private init() {}

    private var selectionPipelineHandler: ((String) -> Void)?
    private var openMainWindowHandler: (() -> Void)?
    private var pendingSelectionText: String?

    func registerOpenMainWindow(_ handler: @escaping () -> Void) {
        openMainWindowHandler = handler
    }

    func registerSelectionPipeline(_ handler: @escaping (String) -> Void) {
        selectionPipelineHandler = handler
        if let text = pendingSelectionText {
            pendingSelectionText = nil
            handler(text)
        }
    }

    func clearRegistration() {
        selectionPipelineHandler = nil
    }

    /// Text captured from the clipboard after synthetic ⌘C (may be empty if nothing was selected).
    func deliverSelectionText(_ text: String) {
        if let selectionPipelineHandler {
            selectionPipelineHandler(text)
        } else {
            pendingSelectionText = text
        }
    }

    func requestOpenMainWindow() {
        openMainWindowHandler?()
    }
}
