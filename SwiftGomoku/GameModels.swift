import Foundation

struct BoardPoint: Hashable, Identifiable {
    let x: Int
    let y: Int
    var id: String { "\(x),\(y)" }
}

enum Stone: Int, CaseIterable, Identifiable {
    case black = 1, white = 2
    var id: Int { rawValue }
    var opponent: Stone { self == .black ? .white : .black }
    var title: String { L10n.text(self == .black ? "stone.black" : "stone.white") }
}

enum BoardMaterial: String, CaseIterable, Identifiable {
    case kaya, katsura, shinKaya
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kaya: L10n.text("sound.material.kaya")
        case .katsura: L10n.text("sound.material.katsura")
        case .shinKaya: L10n.text("sound.material.shin_kaya")
        }
    }
}

struct Move: Identifiable, Hashable {
    let id = UUID()
    let point: BoardPoint
    let stone: Stone
}

enum MatchMode: String, CaseIterable, Identifiable {
    case engine, local, selfPlay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .engine: L10n.text("mode.engine")
        case .local: L10n.text("mode.local")
        case .selfPlay: L10n.text("mode.self_play")
        }
    }

    static var selectableCases: [MatchMode] {
        return [.engine, .local, .selfPlay]
    }
}

enum GameRule: String, CaseIterable, Identifiable {
    case freestyle, exactFive, renju
    var id: String { rawValue }
    var title: String {
        switch self {
        case .freestyle: L10n.text("rule.freestyle")
        case .exactFive: L10n.text("rule.exact_five")
        case .renju: L10n.text("rule.renju")
        }
    }
    var protocolValue: Int {
        switch self { case .freestyle: 0; case .exactFive: 1; case .renju: 4 }
    }
    var detail: String {
        switch self {
        case .freestyle: L10n.text("rule.freestyle.detail")
        case .exactFive: L10n.text("rule.exact_five.detail")
        case .renju: L10n.text("rule.renju.detail")
        }
    }
}

enum GamePhase: Equatable {
    case idle, humanTurn, localTurn, engineThinking
    case gameOver(String), error(String)
}
