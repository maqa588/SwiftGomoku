import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var game: GameStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var confirmsNewGame = false
    @State private var confirmsResign = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            configurationSidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
        } detail: {
            gameArea
        }
        .navigationTitle("Swift Gomoku")
        .toolbar { gameToolbar }
        .inspector(isPresented: $game.showsProtocolLog) {
            ProtocolLogView(engine: game.engine)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
        }
        .confirmationDialog(
            L10n.text("dialog.new_game.title"),
            isPresented: $confirmsNewGame,
            titleVisibility: .visible
        ) {
            Button(L10n.text("dialog.new_game.confirm"), role: .destructive, action: game.startNewGame)
        } message: {
            Text(L10n.text("dialog.new_game.message"))
        }
        .confirmationDialog(
            L10n.text("dialog.resign.title"),
            isPresented: $confirmsResign,
            titleVisibility: .visible
        ) {
            Button(L10n.text("toolbar.resign"), role: .destructive, action: game.resign)
        } message: {
            Text(L10n.text("dialog.resign.message"))
        }
        .frame(minWidth: 900, minHeight: 650)
        .onDisappear { game.shutdown() }
    }

    private var configurationSidebar: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.text("section.game")) {
                    Picker(L10n.text("label.mode"), selection: $game.mode) {
                        ForEach(MatchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if game.mode == .engine {
                        Picker(L10n.text("label.side"), selection: $game.humanColor) {
                            Text(Stone.black.title).tag(Stone.black)
                            Text(Stone.white.title).tag(Stone.white)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section(L10n.text("section.board")) {
                    Picker(L10n.text("label.size"), selection: $game.boardSize) {
                        Text("15 × 15").tag(15)
                        Text("19 × 19").tag(19)
                        Text("20 × 20").tag(20)
                    }

                    Picker(L10n.text("label.rule"), selection: $game.rule) {
                        ForEach(GameRule.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }

                }

                Section(L10n.text("section.current")) {
                    if game.mode == .engine {
                        LabeledContent(L10n.text("section.engine"), value: game.engineDisplayName)
                        LabeledContent(L10n.text("menu.search_threads"), value: "\(game.threadCount)")
                        LabeledContent(
                            L10n.text("menu.thinking_time"),
                            value: L10n.format("duration.seconds", game.timeoutSeconds)
                        )

                        if game.enginePath.isEmpty {
                            Label(L10n.text("engine.bundled.intel_notice"), systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    LabeledContent(L10n.text("section.sound"), value: soundSummary)
                }
            }
            .formStyle(.grouped)

            Divider()

            gameStatus
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }

    private var gameStatus: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusColor)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.statusTitle)
                    .font(.callout.weight(.medium))
                Text(game.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let notice = game.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            Text(L10n.format("moves.count", game.moves.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    @ToolbarContentBuilder
    private var gameToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: requestNewGame) {
                Label(L10n.text("toolbar.new_game"), systemImage: "play.fill")
            }
            .help(L10n.text("help.new_game"))

            Button(action: game.undo) {
                Label(L10n.text("toolbar.undo"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!game.canUndo)
            .help(L10n.text("help.undo"))

            Menu {
                gameSetupMenu
                boardSetupMenu

                if game.mode == .engine {
                    engineSetupMenu
                }

                soundSetupMenu

                Divider()

                Button(L10n.text("toolbar.resign"), role: .destructive) {
                    confirmsResign = true
                }
                .disabled(game.moves.isEmpty)
            } label: {
                Label(L10n.text("toolbar.more"), systemImage: "ellipsis.circle")
            }
            .help(L10n.text("help.more"))

            Button {
                game.showsProtocolLog.toggle()
            } label: {
                Label(L10n.text("toolbar.protocol_log"), systemImage: "terminal")
            }
            .help(L10n.text("help.protocol_log"))
        }
    }

    @ViewBuilder
    private var gameSetupMenu: some View {
        Menu(L10n.text("menu.game_settings"), systemImage: "person.2") {
            Picker(L10n.text("label.mode"), selection: $game.mode) {
                ForEach(MatchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
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
        }
    }

    private var boardSetupMenu: some View {
        Menu(L10n.text("menu.board_settings"), systemImage: "square.grid.3x3") {
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
    }

    private var engineSetupMenu: some View {
        Menu(L10n.text("menu.engine_settings"), systemImage: "cpu") {
            Button(game.engineDisplayName) { }
                .disabled(true)

            Button(L10n.text("button.import_engine"), systemImage: "square.and.arrow.down") {
                EngineSelectionPanel.present(for: game)
            }

            if game.bundledEngineAvailable && !game.isUsingBundledEngine {
                Button(L10n.text("button.use_bundled_engine"), systemImage: "cpu") {
                    game.useBundledEngine()
                }
            }

            Divider()

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
    }

    private var soundSetupMenu: some View {
        Menu(L10n.text("menu.sound_settings"), systemImage: "speaker.wave.2") {
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

    private var gameArea: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.statusTitle)
                        .font(.title2.weight(.semibold))
                    Text(L10n.format("board.summary", game.boardSize, game.boardSize, game.rule.title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let last = game.lastMove {
                    Text(L10n.format("board.last_move", coordinate(last.point)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            GomokuBoardView(
                boardSize: game.boardSize,
                moves: game.moves,
                isInteractive: boardIsInteractive,
                onPlay: game.play
            )
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var boardIsInteractive: Bool {
        if game.mode == .local, case .localTurn = game.phase { return true }
        if game.mode == .engine, case .humanTurn = game.phase { return true }
        return false
    }

    private var statusColor: Color {
        switch game.phase {
        case .error: .red
        case .engineThinking: .orange
        case .gameOver: .purple
        case .humanTurn, .localTurn: .green
        case .idle: .secondary
        }
    }

    private func requestNewGame() {
        if !game.moves.isEmpty {
            switch game.phase {
            case .humanTurn, .localTurn, .engineThinking:
                confirmsNewGame = true
                return
            default:
                break
            }
        }
        game.startNewGame()
    }

    private var soundSummary: String {
        guard game.soundEnabled else { return L10n.text("state.off") }
        return L10n.format(
            "sidebar.sound_summary",
            game.boardMaterial.title,
            Int((game.soundVolume * 100).rounded())
        )
    }

    private func coordinate(_ point: BoardPoint) -> String {
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        let column = point.x < letters.count ? String(letters[point.x]) : "X\(point.x)"
        return "\(column)\(point.y + 1)"
    }
}

private struct ProtocolLogView: View {
    @ObservedObject var engine: PiskvorkEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("log.title"))
                        .font(.headline)
                    Text(engine.state.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.text("button.clear"), action: engine.clearLogs)
                    .disabled(engine.logs.isEmpty)
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if engine.logs.isEmpty {
                            ContentUnavailableView(
                                L10n.text("log.empty.title"),
                                systemImage: "terminal",
                                description: Text(L10n.text("log.empty.description"))
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }

                        ForEach(engine.logs) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text(symbol(for: line.direction))
                                    .foregroundStyle(color(for: line.direction))
                                    .frame(width: 13)
                                Text(line.text)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: engine.logs.count) {
                    if let id = engine.logs.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func symbol(for direction: PiskvorkEngine.LogLine.Direction) -> String {
        switch direction {
        case .sent: "→"
        case .received: "←"
        case .diagnostic: "!"
        }
    }

    private func color(for direction: PiskvorkEngine.LogLine.Direction) -> Color {
        switch direction {
        case .sent: .blue
        case .received: .green
        case .diagnostic: .orange
        }
    }
}

#Preview {
    ContentView(game: GameStore())
}
