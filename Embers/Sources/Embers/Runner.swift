import AppKit

struct Session: Identifiable {
    let id: String
    let game: Game
    let exePath: String
    let startedAt: Date
    let process: Process
    /// Сколько держать игру запущенной (для таймера и очереди).
    let goal: TimeInterval
}

struct QueueItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let game: Game
    var minutes: Int = 15
}

/// Как Discord на macOS находит игру (проверено на клиенте 0.0.423):
/// модуль discord_utils берёт NSWorkspace.runningApplications, учитывает только
/// приложения с окном и сравнивает конец пути (bundleURL / executableURL)
/// с именем исполняемого файла из базы detectable. Windows-имена тоже
/// засчитываются, если путь совпадает: …/games/starrail.exe.
///
/// Поэтому кладём helper `fakegame` (Cocoa-приложение с невидимым окном 1×1)
/// ровно по такому пути и запускаем его напрямую.
@MainActor
final class Runner: ObservableObject {
    static let shared = Runner()

    @Published var sessions: [Session] = []
    @Published var error: String?

    // MARK: Очередь
    @Published var queue: [QueueItem] = [] { didSet { saveQueue() } }
    @Published private(set) var queueRunning = false
    @Published private(set) var queueCurrent: QueueItem?
    @Published private(set) var nextStartAt: Date?
    @Published private(set) var doneCount = 0
    private var queueTask: Task<Void, Never>?

    /// Пауза между играми очереди.
    static let gap: TimeInterval = 5
    /// Запас сверх времени квеста: Discord шлёт последний heartbeat ровно на финише,
    /// лишние 45 секунд гарантируют, что он успеет уйти.
    static let margin: TimeInterval = fast ? 2 : 45
    /// Для проверки: EMBERS_FAST_QUEUE=1 превращает минуты очереди в секунды.
    static let fast = ProcessInfo.processInfo.environment["EMBERS_FAST_QUEUE"] == "1"
    static let minute: TimeInterval = fast ? 1 : 60

    private let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Embers/fake", isDirectory: true)
    }()

    private init() {
        killStrays()
        loadQueue()
    }

    func isRunning(_ g: Game) -> Bool { sessions.contains { $0.id == g.id } }

    func start(_ game: Game, goal: TimeInterval = 15 * 60) {
        guard !isRunning(game), let exe = game.chosenExe else { return }
        do {
            let target = try makeBinary(for: game, exe: exe)
            let p = Process()
            p.executableURL = target
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            let gid = game.id
            p.terminationHandler = { _ in
                Task { @MainActor in Runner.shared.sessions.removeAll { $0.id == gid } }
            }
            try p.run()
            // Пустышка при старте забирает фокус — возвращаем его Embers.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
            }
            sessions.append(Session(id: game.id, game: game, exePath: target.path, startedAt: Date(), process: p, goal: goal))
        } catch {
            self.error = t("Couldn't start “\(game.name)”: \(error.localizedDescription)", "Не удалось запустить «\(game.name)»: \(error.localizedDescription)")
        }
    }

    func stop(_ game: Game) {
        sessions.first { $0.id == game.id }?.process.terminate()
    }

    func stopAll() {
        stopQueue()
        for s in sessions { s.process.terminate() }
        sessions.removeAll()
    }

    // MARK: - Очередь

    func isQueued(_ g: Game) -> Bool { queue.contains { $0.game.id == g.id } }

    func enqueue(_ g: Game) {
        guard !isQueued(g) else { return }
        queue.append(QueueItem(game: g))
    }

    func dequeue(_ item: QueueItem) {
        if queueCurrent?.id == item.id { skipCurrent(); return }
        queue.removeAll { $0.id == item.id }
    }

    func move(_ item: QueueItem, by delta: Int) {
        guard let i = queue.firstIndex(of: item) else { return }
        let j = i + delta
        guard queue.indices.contains(j), queue[j].id != queueCurrent?.id, item.id != queueCurrent?.id else { return }
        queue.swapAt(i, j)
    }

    func setMinutes(_ m: Int, for item: QueueItem) {
        guard let i = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[i].minutes = m
    }

    func clearQueue() {
        stopQueue()
        queue.removeAll()
        doneCount = 0
    }

    /// Игры очереди идут по одной: игра → её время + запас → 5 секунд паузы → следующая.
    func startQueue() {
        guard !queueRunning, !queue.isEmpty else { return }
        // Вручную запущенные игры гасим, чтобы не мешали.
        for s in sessions { s.process.terminate() }
        queueRunning = true
        doneCount = 0
        queueTask = Task { [weak self] in await self?.runQueue() }
    }

    func stopQueue() {
        queueTask?.cancel()
        queueTask = nil
        if let cur = queueCurrent { stop(cur.game) }
        queueCurrent = nil
        nextStartAt = nil
        queueRunning = false
    }

    /// Остановить текущую игру очереди и перейти к следующей.
    func skipCurrent() {
        if let cur = queueCurrent { stop(cur.game) }
    }

    private func runQueue() async {
        while !Task.isCancelled, let item = queue.first {
            queueCurrent = item
            let goal = TimeInterval(item.minutes) * Self.minute + Self.margin
            start(item.game, goal: goal)
            guard isRunning(item.game) else { break }   // не запустилась — ошибка уже показана
            let end = Date().addingTimeInterval(goal)
            // Ждём конца или ручной остановки (тогда это «пропустить»).
            while !Task.isCancelled, Date() < end, isRunning(item.game) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if Task.isCancelled { break }
            stop(item.game)
            queue.removeAll { $0.id == item.id }
            doneCount += 1
            queueCurrent = nil
            if queue.isEmpty { break }
            nextStartAt = Date().addingTimeInterval(Self.gap)
            try? await Task.sleep(nanoseconds: UInt64(Self.gap * 1_000_000_000))
            nextStartAt = nil
        }
        queueCurrent = nil
        nextStartAt = nil
        queueRunning = false
        queueTask = nil
    }

    // Очередь переживает перезапуск приложения.
    private static let queueKey = "embers.queue"
    private func saveQueue() {
        if let d = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(d, forKey: Self.queueKey) }
    }
    private func loadQueue() {
        if let d = UserDefaults.standard.data(forKey: Self.queueKey),
           let q = try? JSONDecoder().decode([QueueItem].self, from: d) { queue = q }
    }

    /// Пустышки, оставшиеся после аварийного выхода, закрываем при старте.
    private func killStrays() {
        let marker = root.path + "/"
        for app in NSWorkspace.shared.runningApplications
        where (app.executableURL?.path ?? "").hasPrefix(marker) {
            app.forceTerminate()
        }
    }

    private func makeBinary(for game: Game, exe: Exe) throws -> URL {
        let parts = exe.n.split(separator: "/").map(String.init)
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        guard !parts.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let fm = FileManager.default
        let gameDir = root.appendingPathComponent(game.id, isDirectory: true)
        try? fm.removeItem(at: gameDir)

        var dir = gameDir
        let target: URL

        if let appIdx = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            // macOS-имя: …/Name.app/Contents/MacOS/<bin> плюс Info.plist, чтобы это был бандл.
            for p in parts[...appIdx] { dir.appendPathComponent(p, isDirectory: true) }
            let rest = Array(parts[(appIdx + 1)...])
            let binName: String
            if rest.isEmpty {
                binName = String(parts[appIdx].dropLast(4))
                target = dir.appendingPathComponent("Contents/MacOS/\(binName)")
            } else {
                binName = rest.last!
                var t = dir
                for p in rest { t.appendPathComponent(p) }
                target = t
            }
            try fm.createDirectory(at: dir.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleExecutable": binName,
                "CFBundleIdentifier": "app.embers.fake.\(game.id)",
                "CFBundleName": game.name,
                "CFBundlePackageType": "APPL",
                "LSUIElement": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: dir.appendingPathComponent("Contents/Info.plist"))
        } else {
            // Windows-имя или голый бинарник: путь должен заканчиваться ровно на имя из базы.
            for p in parts.dropLast() { dir.appendPathComponent(p, isDirectory: true) }
            target = dir.appendingPathComponent(parts.last!)
        }

        guard let helper = Bundle.main.url(forResource: "fakegame", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: helper, to: target)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target
    }
}
