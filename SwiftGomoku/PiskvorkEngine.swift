import Combine
import Foundation

@MainActor
final class PiskvorkEngine: ObservableObject {
    enum State: Equatable {
        case stopped, launching, waitingForReady, ready, thinking
        case failed(String)
        var title: String {
            switch self {
            case .stopped: L10n.text("engine.state.stopped")
            case .launching: L10n.text("engine.state.launching")
            case .waitingForReady: L10n.text("engine.state.initializing")
            case .ready: L10n.text("engine.state.ready")
            case .thinking: L10n.text("engine.state.thinking")
            case .failed: L10n.text("engine.state.failed")
            }
        }
    }

    struct LogLine: Identifiable {
        enum Direction { case sent, received, diagnostic }
        let id = UUID()
        let direction: Direction
        let text: String
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var logs: [LogLine] = []
    @Published private(set) var engineName = L10n.text("engine.default_name")

    var onReady: (() -> Void)?
    var onMove: ((BoardPoint) -> Void)?
    var onFailure: ((String) -> Void)?
    var onMessage: ((String) -> Void)?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var waitingForStart = false
    private var stopping = false

    func launch(executableURL: URL, boardSize: Int) throws {
        stop()
        logs.removeAll(keepingCapacity: true)
        state = .launching
        stopping = false

        let task = Process(), input = Pipe(), output = Pipe(), error = Pipe()
        task.executableURL = executableURL
        task.currentDirectoryURL = executableURL.deletingLastPathComponent()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = error
        task.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self] in self?.log(.diagnostic, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        task.terminationHandler = { [weak self] task in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // An older process can finish after a new game has already launched.
                // Never let that stale callback tear down the new process's pipes.
                guard self.process === task else { return }
                self.cleanup()
                self.process = nil
                if !self.stopping && task.terminationStatus != 0 {
                    self.fail(L10n.format("error.engine.exited", task.terminationStatus))
                } else { self.state = .stopped }
            }
        }

        do { try task.run() } catch { state = .failed(error.localizedDescription); throw error }
        process = task; inputPipe = input; outputPipe = output; errorPipe = error
        state = .waitingForReady
        waitingForStart = true
        send("START \(boardSize)")
    }

    func configure(timeoutSeconds: Int, rule: GameRule, threadCount: Int) {
        send("INFO timeout_turn \(timeoutSeconds * 1_000)")
        send("INFO timeout_match 0")
        send("INFO time_left 2147483647")
        send("INFO max_memory 0")
        send("INFO game_type 0")
        send("INFO rule \(rule.protocolValue)")
        send("INFO thread_num \(max(threadCount, 1))")
    }

    func requestOpeningMove() { state = .thinking; send("BEGIN") }
    func requestMove(after point: BoardPoint) { state = .thinking; send("TURN \(point.x),\(point.y)") }

    func requestMove(from moves: [Move], engineColor: Stone) {
        state = .thinking
        send("BOARD")
        for move in moves {
            send("\(move.point.x),\(move.point.y),\(move.stone == engineColor ? 1 : 2)")
        }
        send("DONE")
    }

    func send(_ line: String) {
        guard let data = "\(line)\r\n".data(using: .utf8), let handle = inputPipe?.fileHandleForWriting else { return }
        do { try handle.write(contentsOf: data); log(.sent, line) }
        catch { fail(L10n.format("error.engine.write", error.localizedDescription)) }
    }

    func clearLogs() { logs.removeAll(keepingCapacity: true) }

    func stop() {
        guard let process else { state = .stopped; return }
        stopping = true
        if process.isRunning { send("END"); process.terminate() }
        cleanup()
        self.process = nil
        state = .stopped
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let separator = outputBuffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let data = outputBuffer[..<separator]
            outputBuffer.removeSubrange(...separator)
            while outputBuffer.first == 10 || outputBuffer.first == 13 { outputBuffer.removeFirst() }
            if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                handle(line)
            }
        }
    }

    private func handle(_ line: String) {
        log(.received, line)
        let upper = line.uppercased()
        if upper.hasPrefix("MESSAGE ") || upper.hasPrefix("DEBUG ") {
            onMessage?(String(line.drop(while: { $0 != " " }).dropFirst())); return
        }
        if upper.hasPrefix("ERROR") { fail(line); return }
        if waitingForStart {
            if upper.hasPrefix("OK") { waitingForStart = false; state = .ready; onReady?() }
            else if upper.hasPrefix("UNKNOWN") { fail(L10n.format("error.engine.start_unsupported", line)) }
            return
        }
        let coordinate = upper.hasPrefix("SUGGEST ") ? String(line.dropFirst("SUGGEST ".count)) : line
        if let point = parseCoordinate(coordinate) { state = .ready; onMove?(point) }
        if upper.contains("NAME=") { engineName = parseName(line) ?? engineName }
    }

    private func parseCoordinate(_ text: String) -> BoardPoint? {
        let token = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? text
        let values = token.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count >= 2, let x = Int(values[0].trimmingCharacters(in: .whitespaces)),
              let y = Int(values[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return BoardPoint(x: x, y: y)
    }

    private func parseName(_ line: String) -> String? {
        guard let range = line.range(of: #"name\s*=\s*\"([^\"]+)\""#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(line[range]).split(separator: "\"").dropFirst().first.map(String.init)
    }

    private func log(_ direction: LogLine.Direction, _ text: String) {
        guard !text.isEmpty else { return }
        logs.append(LogLine(direction: direction, text: text))
        if logs.count > 600 { logs.removeFirst(logs.count - 600) }
    }

    private func fail(_ message: String) { state = .failed(message); onFailure?(message) }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe = nil; outputPipe = nil; errorPipe = nil
        outputBuffer.removeAll(keepingCapacity: true)
    }
}
