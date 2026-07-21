import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published var mode: MatchMode = .engine
    @Published var rule: GameRule = .freestyle
    @Published var humanColor: Stone = .black
    @Published var boardSize = 15
    @Published var timeoutSeconds: Int {
        didSet { UserDefaults.standard.set(timeoutSeconds, forKey: Self.timeoutSecondsKey) }
    }
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
    private static let timeoutSecondsKey = "PiskvorkTimeoutSeconds"
    private var rebuildWhenReady = false
 
    init() {
        let defaults = UserDefaults.standard
        let savedTimeout = defaults.integer(forKey: Self.timeoutSecondsKey)
        timeoutSeconds = savedTimeout > 0 ? savedTimeout : 5
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

    var enginePath: String { customEnginePath ?? "" }
    var isUsingBundledEngine: Bool {
        return customEnginePath == nil
    }
    var bundledEngineAvailable: Bool {
        return true
    }
    var engineDisplayName: String {
        if isUsingBundledEngine { return L10n.text("engine.bundled.name") }
        guard !enginePath.isEmpty else { return L10n.text("engine.none") }
        return URL(fileURLWithPath: enginePath).lastPathComponent
    }
    static let maximumThreadCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
    static let recommendedThreadCount = max(maximumThreadCount - 1, 1)
    var nextStone: Stone { moves.count.isMultiple(of: 2) ? .black : .white }
    var lastMove: Move? { moves.last }
    var engineColor: Stone {
        switch mode {
        case .engine: humanColor.opponent
        case .selfPlay: nextStone
        case .local: humanColor.opponent
        }
    }
    var canUndo: Bool {
        switch mode {
        case .local, .selfPlay: !moves.isEmpty
        case .engine: moves.contains { $0.stone == humanColor }
        }
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
        case .idle: mode == .local ? L10n.text("status.idle.local") : L10n.text("status.idle.engine")
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
        if mode == .selfPlay {
            phase = .engineThinking
            launchEngine(rebuild: false)
        } else {
            if engineColor == .black { phase = .engineThinking; launchEngine(rebuild: false) }
            else { phase = .humanTurn }
        }
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
        case .selfPlay:
            break
        }
    }

    func undo() {
        guard canUndo else { return }
        notice = nil
        if mode == .local { moves.removeLast(); phase = .localTurn; return }
        engine.stop()
        if mode == .selfPlay {
            moves.removeLast()
            phase = .engineThinking
            if engine.state == .ready {
                if moves.isEmpty {
                    engine.requestOpeningMove()
                } else {
                    engine.requestMove(from: moves, engineColor: nextStone)
                }
            } else {
                launchEngine(rebuild: true)
            }
            return
        }
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
        let winnerName = (mode == .local || mode == .selfPlay) ? nextStone.opponent.title : engineColor.title
        phase = .gameOver(L10n.format("result.winner", winnerName))
    }

    func stone(at point: BoardPoint) -> Stone? { moves.last { $0.point == point }?.stone }
    func shutdown() { engine.stop(); stoneSound.stop() }

    private func validateEngine() -> Bool {
        if isUsingBundledEngine { return true }
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
        do {
            try engine.launch(
                executableURL: URL(fileURLWithPath: enginePath),
                boardSize: boardSize,
                inMemory: isUsingBundledEngine
            )
        }
        catch { phase = .error(L10n.format("error.engine.launch", error.localizedDescription)) }
    }

    private func engineReady() {
        engine.configure(timeoutSeconds: timeoutSeconds, rule: rule, threadCount: threadCount)
        if rebuildWhenReady || !moves.isEmpty {
            engine.requestMove(from: moves, engineColor: engineColor)
        } else {
            if mode == .selfPlay || engineColor == .black {
                engine.requestOpeningMove()
            } else {
                phase = .humanTurn
            }
        }
    }

    private func receiveEngineMove(_ point: BoardPoint) {
        guard case .engineThinking = phase else { return }
        guard onBoard(point), stone(at: point) == nil else {
            phase = .error(L10n.format("error.engine.invalid_move", point.x, point.y)); return
        }
        let currentStone = engineColor
        place(point, stone: currentStone)
        if !finishIfNeeded(moves.last!) {
            if mode == .selfPlay {
                phase = .engineThinking
                if engine.state == .ready {
                    engine.requestMove(from: moves, engineColor: nextStone)
                } else {
                    launchEngine(rebuild: true)
                }
            } else {
                phase = .humanTurn
            }
        }
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
        if rule == .renju && mode == .local && move.stone == .black && isForbidden(move.point) {
            engine.stop()
            phase = .gameOver(L10n.format("result.forbidden_loss", Stone.white.title))
            return true
        }
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

    // MARK: - Renju Forbidden Move Detection
    //
    // Implements the standard Renju forbidden-move rules for Black:
    //   1. Overline (长连禁手): a line of 6 or more Black stones.
    //   2. Double-Four (四四禁手): placing the stone creates two or more "fours" across all directions.
    //      A "four" in this context means: a window of 5 consecutive points contains exactly 4 Black
    //      stones and 1 empty point (the empty point is where Black could make a five), AND filling
    //      that empty point would not extend the line beyond 5 (i.e., no overline would result).
    //   3. Double-Three (三三禁手): placing the stone creates two or more "open threes" across all
    //      directions. An open three is a three where adding one more Black stone (at the open point)
    //      would form a live four (活四, two open ends), AND that open point is not itself a forbidden
    //      point (which would mean the three can never legally become four).
    //
    // Rule: Black wins if exactly five are formed even if a forbidden pattern co-exists.
    // (The isWinning check runs first in finishIfNeeded.)

    private func isForbidden(_ point: BoardPoint) -> Bool {
        // Overline: ≥ 6 consecutive Black stones in any direction
        if hasOverline(at: point) { return true }

        // Double-Four: ≥ 2 fours across all four directions
        if countAllFours(at: point) >= 2 { return true }

        // Double-Three: ≥ 2 genuine open-threes across all four directions
        if countAllOpenThrees(at: point) >= 2 { return true }

        return false
    }

    // MARK: Overline

    private func hasOverline(at point: BoardPoint) -> Bool {
        let dirs = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for (dx, dy) in dirs {
            let total = 1
                + count(from: point, stone: .black, dx:  dx, dy:  dy)
                + count(from: point, stone: .black, dx: -dx, dy: -dy)
            if total >= 6 { return true }
        }
        return false
    }

    // MARK: Double-Four

    /// Total number of "fours" that `point` (a Black stone) participates in.
    /// A four in a direction (dx,dy) is any window of 5 consecutive cells that
    ///   • contains exactly 4 Black stones (including `point`) and 1 empty cell, AND
    ///   • filling the empty cell would produce exactly 5 (not 6+) Black stones in that line.
    private func countAllFours(at point: BoardPoint) -> Int {
        let dirs = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var total = 0
        for (dx, dy) in dirs {
            total += countFoursInDirection(at: point, dx: dx, dy: dy)
        }
        return total
    }

    private func countFoursInDirection(at point: BoardPoint, dx: Int, dy: Int) -> Int {
        var fourCount = 0
        // Slide a window of 5 over every position that includes `point`.
        // offset = position of `point` within the window (0..4)
        for offset in 0 ..< 5 {
            let start = BoardPoint(x: point.x - offset * dx, y: point.y - offset * dy)
            var blacks = 0
            var emptyPos: BoardPoint? = nil
            var valid = true

            for i in 0 ..< 5 {
                let p = BoardPoint(x: start.x + i * dx, y: start.y + i * dy)
                guard onBoard(p) else { valid = false; break }
                switch stone(at: p) {
                case .black: blacks += 1
                case .white: valid = false; break
                case .none:
                    if emptyPos != nil { valid = false; break } // two empties → not a four
                    emptyPos = p
                }
                if !valid { break }
            }

            guard valid, blacks == 4, let ep = emptyPos else { continue }

            // Confirm filling `ep` does NOT create an overline (would exceed 5).
            // Count continuations from ep in both directions of the same axis.
            let ext = 1
                + count(from: ep, stone: .black, dx:  dx, dy:  dy)
                + count(from: ep, stone: .black, dx: -dx, dy: -dy)
            if ext == 5 {
                fourCount += 1
            }
        }
        return fourCount
    }

    // MARK: Double-Three

    /// Total number of genuine "open threes" that `point` (a Black stone) participates in.
    private func countAllOpenThrees(at point: BoardPoint) -> Int {
        let dirs = [(1, 0), (0, 1), (1, 1), (1, -1)]
        var total = 0
        for (dx, dy) in dirs {
            if hasOpenThreeInDirection(at: point, dx: dx, dy: dy) { total += 1 }
        }
        return total
    }

    /// Returns true if placing at `point` creates an open-three in the given direction.
    ///
    /// An open-three is defined as: a 3-stone pattern that, by adding one more Black stone
    /// at a specific point `q`, would form a live-four (活四) — meaning `q` has at least
    /// one open end on each side of the resulting 4-stone line — AND `q` itself is not a
    /// forbidden point (so the three can legally promote to four).
    ///
    /// We enumerate candidate "four-extension" points `q` adjacent to or within the cluster,
    /// then verify each one would form an open four.
    private func hasOpenThreeInDirection(at point: BoardPoint, dx: Int, dy: Int) -> Bool {
        // Collect the run of Black stones that include `point` in this direction,
        // plus the immediate empty cells flanking each end.
        let fwdBlacks = count(from: point, stone: .black, dx:  dx, dy:  dy)
        let bwdBlacks = count(from: point, stone: .black, dx: -dx, dy: -dy)
        let runLen = 1 + fwdBlacks + bwdBlacks  // total connected Black stones including `point`

        // For an open-three we need exactly 3 Black in a connected run (possibly with one gap).
        // We handle both: solid run of 3 (○○○) and split run with one gap (○○_○ / ○_○○).

        // Strategy: find candidate "fourth stone" positions `q` that could be added to
        // extend this group to a four, then test whether doing so creates an open four.
        var candidateQs: [BoardPoint] = []

        if runLen == 3 {
            // Solid three: look at both ends for a place to extend to four
            let fwdEnd = BoardPoint(x: point.x + (fwdBlacks + 1) * dx,
                                   y: point.y + (fwdBlacks + 1) * dy)
            let bwdEnd = BoardPoint(x: point.x - (bwdBlacks + 1) * dx,
                                   y: point.y - (bwdBlacks + 1) * dy)
            if onBoard(fwdEnd) && stone(at: fwdEnd) == nil { candidateQs.append(fwdEnd) }
            if onBoard(bwdEnd) && stone(at: bwdEnd) == nil { candidateQs.append(bwdEnd) }
        } else if runLen == 2 {
            // Might be a split three: look one beyond each end and also one "inside" gap
            // Forward: _○○_ → the gap is one step beyond fwdEnd
            let fwdEnd = BoardPoint(x: point.x + (fwdBlacks + 1) * dx,
                                   y: point.y + (fwdBlacks + 1) * dy)
            let bwdEnd = BoardPoint(x: point.x - (bwdBlacks + 1) * dx,
                                   y: point.y - (bwdBlacks + 1) * dy)
            // Check if there is a black stone one further beyond the gap (○_○ pattern)
            let fwdBeyond = BoardPoint(x: fwdEnd.x + dx, y: fwdEnd.y + dy)
            let bwdBeyond = BoardPoint(x: bwdEnd.x - dx, y: bwdEnd.y - dy)
            if onBoard(fwdEnd) && stone(at: fwdEnd) == nil {
                if onBoard(fwdBeyond) && stone(at: fwdBeyond) == .black {
                    // Split pattern: run of 2 + gap + 1 black → "q" fills the gap
                    candidateQs.append(fwdEnd)
                } else {
                    // Extending the solid run of 2 to make 3: not our job here
                    // (we want three→four candidates, not two→three)
                    _ = fwdEnd
                }
            }
            if onBoard(bwdEnd) && stone(at: bwdEnd) == nil {
                if onBoard(bwdBeyond) && stone(at: bwdBeyond) == .black {
                    candidateQs.append(bwdEnd)
                }
            }
        } else if runLen == 1 {
            // Single stone at `point`; look for ○_○ split patterns in each direction
            let fwdGap  = BoardPoint(x: point.x + dx,       y: point.y + dy)
            let fwdBlk  = BoardPoint(x: point.x + 2 * dx,   y: point.y + 2 * dy)
            let bwdGap  = BoardPoint(x: point.x - dx,       y: point.y - dy)
            let bwdBlk  = BoardPoint(x: point.x - 2 * dx,   y: point.y - 2 * dy)
            if onBoard(fwdGap) && stone(at: fwdGap) == nil &&
               onBoard(fwdBlk) && stone(at: fwdBlk) == .black {
                candidateQs.append(fwdGap)
            }
            if onBoard(bwdGap) && stone(at: bwdGap) == nil &&
               onBoard(bwdBlk) && stone(at: bwdBlk) == .black {
                candidateQs.append(bwdGap)
            }
        }

        // For each candidate "q", test whether adding a Black stone at q would form an open four
        // in the (dx,dy) direction AND q is not itself a forbidden point.
        for q in candidateQs {
            if wouldFormOpenFour(at: q, dx: dx, dy: dy) && !isForbiddenIfPlaced(at: q) {
                return true
            }
        }
        return false
    }

    /// Would placing a Black stone at `q` create an open-four (活四) in the given direction?
    /// An open-four has 4 Black stones in a row with both ends free (and the run is exactly 4).
    private func wouldFormOpenFour(at q: BoardPoint, dx: Int, dy: Int) -> Bool {
        guard stone(at: q) == nil else { return false }
        // Simulate placing at q
        let fwd = count(from: q, stone: .black, dx:  dx, dy:  dy)
        let bwd = count(from: q, stone: .black, dx: -dx, dy: -dy)
        let run = 1 + fwd + bwd
        guard run == 4 else { return false }
        // Both ends must be empty (open four)
        let fwdEnd = BoardPoint(x: q.x + (fwd + 1) * dx, y: q.y + (fwd + 1) * dy)
        let bwdEnd = BoardPoint(x: q.x - (bwd + 1) * dx, y: q.y - (bwd + 1) * dy)
        let fwdOpen = onBoard(fwdEnd) && stone(at: fwdEnd) == nil
        let bwdOpen = onBoard(bwdEnd) && stone(at: bwdEnd) == nil
        return fwdOpen && bwdOpen
    }

    /// Check if placing a Black stone at `q` (which is currently empty) would make it a
    /// forbidden point, but WITHOUT actually mutating `moves`. We temporarily append and pop.
    private func isForbiddenIfPlaced(at q: BoardPoint) -> Bool {
        moves.append(Move(point: q, stone: .black))
        let result = isForbidden(q)
        moves.removeLast()
        return result
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
