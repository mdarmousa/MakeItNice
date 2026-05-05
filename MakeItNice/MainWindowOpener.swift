import SwiftUI

/// Captures `openWindow` from the SwiftUI environment and registers it on `AppActionCenter`.
struct MainWindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                AppActionCenter.shared.registerOpenMainWindow {
                    openWindow(id: "main")
                }
            }
    }
}
