import SwiftUI

@main
@MainActor
struct SwiftGomokuApp: App {
    @StateObject private var game = GameStore()

    var body: some Scene {
        #if os(macOS)
        WindowGroup { ContentView(game: game) }
            .defaultSize(width: 1120, height: 760)
            .commands { SwiftGomokuCommands(game: game) }

        Window(L10n.text("about.title"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup { ContentView(game: game) }
        #endif
    }
}

private struct SwiftGomokuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var game: GameStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.text("about.menu")) { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) { }

        CommandMenu(L10n.text("menu.game")) {
            Button(L10n.text("toolbar.new_game"), systemImage: "play.fill") {
                game.startNewGame()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.text("toolbar.undo"), systemImage: "arrow.uturn.backward") {
                game.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!game.canUndo)

            Button(L10n.text("toolbar.resign")) {
                game.resign()
            }
            .disabled(game.moves.isEmpty)

            Divider()

            Picker(L10n.text("label.mode"), selection: $game.mode) {
                ForEach(MatchMode.selectableCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Menu(L10n.text("menu.board_settings")) {
                Picker(L10n.text("label.size"), selection: $game.boardSize) {
                    ForEach(GameMenuOptions.boardSizes, id: \.self) { size in
                        Text("\(size) × \(size)").tag(size)
                    }
                }

                Picker(L10n.text("label.rule"), selection: $game.rule) {
                    ForEach(GameRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            }

            if game.mode == .engine {
                Picker(L10n.text("label.side"), selection: $game.humanColor) {
                    ForEach(Stone.allCases) { stone in
                        Text(stone.title).tag(stone)
                    }
                }

                Picker(L10n.text("menu.thinking_time"), selection: $game.timeoutSeconds) {
                    ForEach(GameMenuOptions.timeoutSeconds, id: \.self) { seconds in
                        Text(L10n.format("duration.seconds", seconds)).tag(seconds)
                    }
                }
            }

            Divider()

            Menu(L10n.text("menu.sound_settings")) {
                Toggle(L10n.text("label.placement_sound"), isOn: $game.soundEnabled)

                Picker(L10n.text("label.board_material"), selection: $game.boardMaterial) {
                    ForEach(BoardMaterial.allCases) { material in
                        Text(material.title).tag(material)
                    }
                }
                .disabled(!game.soundEnabled)

                Menu(L10n.format("menu.volume_current", Int((game.soundVolume * 100).rounded()))) {
                    ForEach(GameMenuOptions.soundVolumes, id: \.self) { volume in
                        Toggle(
                            "\(Int(volume * 100))%",
                            isOn: Binding(
                                get: { abs(game.soundVolume - volume) < 0.01 },
                                set: { if $0 { game.soundVolume = volume } }
                            )
                        )
                    }
                }
                .disabled(!game.soundEnabled)
            }
        }

        CommandMenu(L10n.text("menu.engine")) {
            Button(game.engineDisplayName) { }
                .disabled(true)

            #if os(macOS)
            Button(L10n.text("button.import_engine"), systemImage: "square.and.arrow.down") {
                EngineSelectionPanel.present(for: game)
            }

            if game.bundledEngineAvailable && !game.isUsingBundledEngine {
                Button(L10n.text("button.use_bundled_engine"), systemImage: "cpu") {
                    game.useBundledEngine()
                }
            }

            Divider()
            #endif

            Menu(L10n.format("label.threads", game.threadCount)) {
                Button(L10n.text("menu.decrease_threads"), systemImage: "minus") {
                    game.threadCount = max(game.threadCount - 1, 1)
                }
                .disabled(game.threadCount <= 1)

                Button(L10n.text("menu.increase_threads"), systemImage: "plus") {
                    game.threadCount = min(game.threadCount + 1, GameStore.maximumThreadCount)
                }
                .disabled(game.threadCount >= GameStore.maximumThreadCount)

                Divider()

                Button(L10n.format("menu.recommended_threads", GameStore.recommendedThreadCount)) {
                    game.threadCount = GameStore.recommendedThreadCount
                }
            }
        }

        CommandGroup(after: .sidebar) {
            Toggle(L10n.text("toolbar.protocol_log"), isOn: $game.showsProtocolLog)
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
