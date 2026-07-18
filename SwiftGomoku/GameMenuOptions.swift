#if os(macOS)
import AppKit
#endif

enum GameMenuOptions {
    static let boardSizes = [15, 19, 20]
    static let timeoutSeconds = [1, 3, 5, 10, 15, 30, 60, 120]
    static let soundVolumes = [0.25, 0.5, 0.75, 1.0]
}

@MainActor
enum EngineSelectionPanel {
    static func present(for game: GameStore) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = L10n.text("engine.panel.title")
        panel.message = L10n.text("engine.panel.message")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("button.select")

        if panel.runModal() == .OK, let url = panel.url {
            game.setEngineURL(url)
        }
        #elseif os(iOS)
        // No-op since external engines are not supported on iOS
        #endif
    }
}
