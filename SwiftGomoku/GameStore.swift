import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published var mode: MatchMode = .engine
    @Published var rule: GameRule = .freestyle
    @Published var humanColor: Stone = .black
    @Published var boardSize = 15
    @Published var timeoutSeconds = 5
    @Published var showsProtocolLog = false
    @Published var threadCount: Int {
        didSet { UserDefaults.standard.set(threadCount, forKey: Self.threadCountKey) }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundEnabledKey) }
    }
    @Published var boardMaterial: BoardMaterial {
        didSet { UserDefaults.standard.set(boardMaterial.rawValue, forKey: Self.boardMaterialKey) }
    }
    @Published var soundVolume: Double {
        didSet { UserDefaults.standard.set(soundVolume, forKey: Self.soundVolumeKey) }
    }
    @Published private(set) var moves: [Move] = []
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var notice: String?
    @Published private(set) var customEnginePath: String?

    let engine = PiskvorkEngine()
    private let stoneSound = StoneSoundEngine()
    private static let enginePathKey = "PiskvorkEnginePath"
    private static let threadCountKey = "PiskvorkThreadCount"
    private static let soundEnabledKey = "StoneSoundEnabled"
    private static let boardMaterialKey = "StoneSoundBoardMaterial"
    private static let soundVolumeKey = "StoneSoundVolume"
    private var rebuildWhenReady = false

    init() {
        let defaults = UserDefaults.standard
        customEnginePath = defaults.string(forKey: Self.enginePathKey).flatMap { $0.isEmpty ? nil : $0 }
        let savedThreads = defaults.integer(forKey: Self.threadCountKey)
        threadCount = savedThreads > 0 ? min(savedThreads, Self.maximumThreadCount) : Self.recommendedThreadCount
        soundEnabled = defaults.object(forKey: Self.soundEnabledKey) as? Bool ?? true
        boardMaterial = BoardMaterial(
            rawValue: defaults.string(forKey: Self.boardMaterialKey) ?? ""
        ) ?? .kaya
        soundVolume = defaults.object(forKey: Self.soundVolumeKey) as? Double ?? 0.72
        engine.onReady = { [weak self] in self?.engineReady() }
        engine.onMove = { [weak self] in self?.receiveEngineMove($0) }
        engine.onFailure = { [weak self] in self?.phase = .error($0) }
        engine.onMessage = { [weak self] in self?.notice = $0 }
    }

    var engineColor: Stone { humanColor.opponent }
    var enginePath: String { customEnginePath ?? Self.bundledEngineURL?.path ?? "" }
    var isUsingBundledEngine: Bool { customEnginePath == nil && Self.bundledEngineURL != nil }
    var bundledEngineAvailable: Bool { Self.bundledEngineURL != nil }
    var engineDisplayName: String {
        if isUsingBundledEngine { return L10n.text("engine.bundled.name") }
        guard !enginePath.isEmpty else { return L10n.text("engine.none") }
        return URL(fileURLWithPath: enginePath).lastPathComponent
    }
    static let maximumThreadCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
    static let recommendedThreadCount = max(maximumThreadCount - 1, 1)
    var nextStone: Stone { moves.count.isMultiple(of: 2) ? .black : .white }
    var lastMove: Move? { moves.last }
    var canUndo: Bool {
        mode == .local ? !moves.isEmpty : moves.contains { $0.stone == humanColor }
    }
    var statusTitle: String {
        switch phase {
        case .idle: L10n.text("status.ready")
        case .humanTurn: L10n.format("status.human_turn", humanColor.title)
        case .localTurn: L10n.format("status.local_turn", nextStone.title)
        case .engineThinking: L10n.format("status.engine_thinking", engine.engineName)
        case .gameOver(let result): result
        case .error: L10n.text("status.engine_error")
        }
    }
    var statusDetail: String {
        switch phase {
        case .idle: mode == .engine ? L10n.text("status.idle.engine") : L10n.text("status.idle.local")
        case .humanTurn: L10n.text("status.place_stone")
        case .localTurn: rule.detail
        case .engineThinking: L10n.format("status.thinking.detail", timeoutSeconds)
        case .gameOver: L10n.format("status.game_over.detail", moves.count)
        case .error(let message): message
        }
    }

    func setEngineURL(_ url: URL) {
        customEnginePath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.enginePathKey)
        notice = nil
    }

    func useBundledEngine() {
        customEnginePath = nil
        UserDefaults.standard.removeObject(forKey: Self.enginePathKey)
        notice = nil
    }

    func startNewGame() {
        engine.stop(); moves.removeAll(keepingCapacity: true); notice = nil; rebuildWhenReady = false
        if mode == .local { phase = .localTurn; return }
        guard validateEngine() else { return }
        if engineColor == .black { phase = .engineThinking; launchEngine(rebuild: false) }
        else { phase = .humanTurn }
    }

    func play(at point: BoardPoint) {
        guard onBoard(point), stone(at: point) == nil else { return }
        switch mode {
        case .local:
            guard case .localTurn = phase else { return }
            place(point, stone: nextStone)
            if !finishIfNeeded(moves.last!) { phase = .localTurn }
        case .engine:
            guard case .humanTurn = phase, nextStone == humanColor else { return }
            place(point, stone: humanColor)
            guard !finishIfNeeded(moves.last!) else { return }
            phase = .engineThinking
            if engine.state == .ready { engine.requestMove(after: point) }
            else { launchEngine(rebuild: true) }
        }
    }

    func undo() {
        guard canUndo else { return }
        notice = nil
        if mode == .local { moves.removeLast(); phase = .localTurn; return }
        engine.stop()
        var removedHuman = false
        while !moves.isEmpty {
            if moves.removeLast().stone == humanColor { removedHuman = true }
            if removedHuman && nextStone == humanColor { break }
        }
        phase = .humanTurn
    }

    func resign() {
        guard !moves.isEmpty else { return }
        engine.stop()
        phase = .gameOver(L10n.format("result.winner", mode == .engine ? engineColor.title : nextStone.opponent.title))
    }

    func stone(at point: BoardPoint) -> Stone? { moves.last { $0.point == point }?.stone }
    func shutdown() { engine.stop(); stoneSound.stop() }

    private func validateEngine() -> Bool {
        guard !enginePath.isEmpty else { phase = .error(L10n.text("error.engine.not_selected")); return false }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: enginePath, isDirectory: &directory), !directory.boolValue else {
            phase = .error(L10n.text("error.engine.not_found")); return false
        }
        guard FileManager.default.isExecutableFile(atPath: enginePath) else {
            phase = .error(L10n.text("error.engine.not_executable")); return false
        }
        return true
    }

    private func launchEngine(rebuild: Bool) {
        guard validateEngine() else { return }
        rebuildWhenReady = rebuild
        do { try engine.launch(executableURL: URL(fileURLWithPath: enginePath), boardSize: boardSize) }
        catch { phase = .error(L10n.format("error.engine.launch", error.localizedDescription)) }
    }

    private func engineReady() {
        engine.configure(timeoutSeconds: timeoutSeconds, rule: rule, threadCount: threadCount)
        if rebuildWhenReady || !moves.isEmpty { engine.requestMove(from: moves, engineColor: engineColor) }
        else { engine.requestOpeningMove() }
    }

    private func receiveEngineMove(_ point: BoardPoint) {
        guard case .engineThinking = phase else { return }
        guard onBoard(point), stone(at: point) == nil else {
            phase = .error(L10n.format("error.engine.invalid_move", point.x, point.y)); return
        }
        place(point, stone: engineColor)
        if !finishIfNeeded(moves.last!) { phase = .humanTurn }
    }

    private func place(_ point: BoardPoint, stone: Stone) {
        moves.append(Move(point: point, stone: stone))
        if soundEnabled {
            stoneSound.play(
                stone: stone,
                at: point,
                boardSize: boardSize,
                material: boardMaterial,
                volume: soundVolume
            )
        }
    }

    private func finishIfNeeded(_ move: Move) -> Bool {
        if isWinning(move) { engine.stop(); phase = .gameOver(L10n.format("result.winner", move.stone.title)); return true }
        if moves.count == boardSize * boardSize { engine.stop(); phase = .gameOver(L10n.text("result.draw")); return true }
        return false
    }

    private func isWinning(_ move: Move) -> Bool {
        [(1, 0), (0, 1), (1, 1), (1, -1)].contains { dx, dy in
            let count = 1 + count(from: move.point, stone: move.stone, dx: dx, dy: dy)
                + count(from: move.point, stone: move.stone, dx: -dx, dy: -dy)
            switch rule {
            case .freestyle: return count >= 5
            case .exactFive: return count == 5
            case .renju: return move.stone == .black ? count == 5 : count >= 5
            }
        }
    }

    private func count(from point: BoardPoint, stone: Stone, dx: Int, dy: Int) -> Int {
        var total = 0, cursor = BoardPoint(x: point.x + dx, y: point.y + dy)
        while onBoard(cursor), self.stone(at: cursor) == stone {
            total += 1; cursor = BoardPoint(x: cursor.x + dx, y: cursor.y + dy)
        }
        return total
    }

    private func onBoard(_ point: BoardPoint) -> Bool {
        (0..<boardSize).contains(point.x) && (0..<boardSize).contains(point.y)
    }

    private static var bundledEngineURL: URL? {
#if arch(arm64)
        return [
            Bundle.main.url(forResource: "pbrain-rapfi", withExtension: nil, subdirectory: "Engines"),
            Bundle.main.url(forResource: "pbrain-rapfi", withExtension: nil, subdirectory: "Resources/Engines"),
            Bundle.main.url(forResource: "pbrain-rapfi", withExtension: nil)
        ].compactMap { $0 }.first
#else
        return nil
#endif
    }
}
