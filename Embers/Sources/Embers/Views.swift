import SwiftUI

// MARK: - Тема
// Тёплый тёмный фон, один фирменный оранжевый, плоские поверхности.
// Без градиентов, свечения и теней на неподвижных элементах: глубину дают
// шаги тона и обложки игр.
enum Theme {
    static let ground  = Color(hex: 0x12100E)
    static let surface = Color(hex: 0x1C1916)
    static let raised  = Color(hex: 0x26221E)
    static let line    = Color(hex: 0x2F2A25)
    static let text    = Color(hex: 0xF5EFE8)
    static let muted   = Color(hex: 0xB0A69B)
    static let faint   = Color(hex: 0x8E8479)
    static let orange  = Color(hex: 0xFF7A1A)
    static let orangeInk = Color(hex: 0x1F0F02)   // тёмный текст на оранжевом
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

func clock(_ t: TimeInterval) -> String {
    let s = Int(max(0, t))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Экран

struct ContentView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var runner: Runner
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @AppStorage(Lang.key) private var lang = "en"

    private var results: [Game] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.games }
        // Сначала те, что начинаются с запроса, потом остальные совпадения.
        let hits = store.games.filter { $0.n.lowercased().contains(q) }
        return hits.filter { $0.n.lowercased().hasPrefix(q) } + hits.filter { !$0.n.lowercased().hasPrefix(q) }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        NowPlayingPanel()
                        if !runner.queue.isEmpty { QueuePanel() }
                        searchField
                        if query.isEmpty { featuredSection }
                        librarySection
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.never)
            }
            .ignoresSafeArea(edges: .top)
            .id(lang)   // смена языка перерисовывает весь интерфейс
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.orange)
        .alert(t("Something went wrong", "Не получилось"), isPresented: Binding(get: { runner.error != nil }, set: { if !$0 { runner.error = nil } })) {
            Button("OK") { runner.error = nil }
        } message: { Text(runner.error ?? "") }
        .background(
            // ⌘F — к поиску
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        )
    }

    // Шапка в строке со «светофором» окна
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.orange)
            Text("Embers").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                lang = (lang == "en") ? "ru" : "en"
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe").font(.system(size: 12, weight: .semibold))
                    Text(lang == "en" ? "EN" : "RU").font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(Theme.surface, in: Capsule())
                .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help(t("Switch language", "Сменить язык"))
            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.refreshing { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)) }
                }
                .frame(width: 28, height: 28)
                .background(Theme.surface, in: Circle())
                .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help(t("Refresh the game list from Discord", "Обновить базу игр из Discord"))
            .disabled(store.refreshing)
        }
        .padding(.leading, 64)   // место под кнопки окна
        .frame(height: 28)
    }

    private func sectionTitle(_ title: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(note).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer()
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(t("Often in quests", "Часто бывают в квестах"), t("one click and Discord sees the game", "одно нажатие — и Discord видит игру"))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(store.featured) { GameTile(game: $0).frame(width: 168) }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(query.isEmpty ? t("All games", "Все игры") : t("Results", "Результаты"),
                         query.isEmpty ? t("\(store.games.count.formatted()) games from Discord's database", "\(store.games.count.formatted()) игр из базы Discord")
                                       : t("\(results.count.formatted()) for “\(query)”", "\(results.count.formatted()) по запросу «\(query)»"))
            if results.isEmpty {
                Text(t("This game isn't in Discord's database. Check the name in the quest card.", "Такой игры нет в базе Discord. Проверьте название в карточке квеста."))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18, alignment: .top)],
                          alignment: .leading, spacing: 22) {
                    ForEach(results) { GameTile(game: $0) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(searchFocused ? Theme.orange : Theme.faint)
            TextField("", text: $query, prompt: Text(t("Find a quest game, e.g. Rust", "Найти игру из квеста — например, Rust")).foregroundColor(Theme.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                }.buttonStyle(.plain)
            } else {
                Text("⌘F").font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(searchFocused ? Theme.orange.opacity(0.7) : Theme.line, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }
}

// MARK: - Обложка

struct Cover: View {
    let game: Game
    var radius: CGFloat = 14

    var body: some View {
        Group {
            if game.v != nil {
                // Есть обложка — на всю плитку.
                AsyncImage(url: game.coverURL, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if case .success(let img) = phase {
                        img.resizable().interpolation(.high).scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                // Только маленькая иконка — не растягиваем, ставим по центру.
                GeometryReader { geo in
                    ZStack {
                        Theme.raised
                        AsyncImage(url: game.iconURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().interpolation(.high).scaledToFit()
                            } else {
                                letter
                            }
                        }
                        .frame(width: geo.size.width * 0.42, height: geo.size.width * 0.42)
                        .clipShape(RoundedRectangle(cornerRadius: geo.size.width * 0.09, style: .continuous))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var placeholder: some View { ZStack { Theme.raised; letter } }

    private var letter: some View {
        Text(String(game.n.prefix(1)).uppercased())
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Theme.faint)
    }
}

// MARK: - Плитка игры

struct GameTile: View {
    @EnvironmentObject var runner: Runner
    let game: Game
    @State private var hover = false

    var body: some View {
        let running = runner.isRunning(game)
        let queued = runner.isQueued(game)
        Button {
            running ? runner.stop(game) : runner.start(game)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Cover(game: game)
                        .scaleEffect(hover ? 1.04 : 1)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Затемнение под кнопкой при наведении — единственная «подложка».
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(hover ? 0.45 : 0))

                    if hover {
                        Image(systemName: running ? "stop.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.orangeInk)
                            .frame(width: 52, height: 52)
                            .background(Theme.orange, in: Circle())
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    if hover && !running {
                        VStack {
                            HStack {
                                Spacer()
                                Button { queued ? () : runner.enqueue(game) } label: {
                                    Image(systemName: queued ? "checkmark" : "plus")
                                        .font(.system(size: 12, weight: .bold))
                                        .frame(width: 30, height: 30)
                                        .background(Theme.raised, in: Circle())
                                        .foregroundStyle(queued ? Theme.orange : Theme.text)
                                }
                                .buttonStyle(.plain)
                                .help(queued ? t("Already in queue", "Уже в очереди") : t("Add to queue", "Добавить в очередь"))
                            }
                            Spacer()
                        }
                        .padding(10)
                    }

                    if queued && !running && !hover {
                        VStack {
                            Spacer()
                            HStack {
                                Text(t("In queue", "В очереди"))
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Theme.raised, in: Capsule())
                                    .foregroundStyle(Theme.text)
                                Spacer()
                            }
                        }
                        .padding(10)
                    }

                    if running {
                        VStack {
                            Spacer()
                            HStack {
                                PlayingBadge(startedAt: runner.sessions.first { $0.id == game.id }?.startedAt ?? .now)
                                Spacer()
                            }
                        }
                        .padding(10)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(running ? Theme.orange : Color.white.opacity(0.06), lineWidth: running ? 2 : 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.n)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(running ? Theme.orange : Theme.text)
                    Text(running ? t("Click to stop", "Нажмите, чтобы остановить") : (game.hasMac ? "macOS" : t("Windows · runs on Mac", "Windows · работает на Mac")))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .help(running ? t("Stop \(game.n)", "Остановить \(game.n)") : t("Start \(game.n)", "Запустить \(game.n)"))
        .contextMenu {
            Button(running ? t("Stop", "Остановить") : t("Start now", "Запустить сейчас")) { running ? runner.stop(game) : runner.start(game) }
            if queued {
                Button(t("Remove from queue", "Убрать из очереди")) { runner.queue.removeAll { $0.game.id == game.id } }
            } else {
                Button(t("Add to queue", "Добавить в очередь")) { runner.enqueue(game) }
            }
        }
    }
}

struct PlayingBadge: View {
    let startedAt: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 5) {
                Circle().fill(Theme.orangeInk).frame(width: 6, height: 6)
                Text(t("Playing \(clock(ctx.date.timeIntervalSince(startedAt)))", "Играет \(clock(ctx.date.timeIntervalSince(startedAt)))"))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.orangeInk)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.orange, in: Capsule())
        }
    }
}

// MARK: - Панель «Сейчас играет»

struct NowPlayingPanel: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        Group {
            if let s = runner.sessions.last {
                playing(s)
            } else if let next = runner.nextStartAt, let item = runner.queue.first {
                between(next, item)
            } else {
                idle
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: runner.sessions.map(\.id))
    }

    private var idle: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.orange)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Nothing running", "Сейчас ничего не запущено"))
                    .font(.system(size: 26, weight: .bold))
                Text(t("Click a cover to start a game right away, or “+” to build a queue. Discord sees the game within 5–10 seconds, no need to install it. Video (ad) quests are not supported.", "Нажмите на обложку, чтобы запустить игру сразу, или на «+», чтобы собрать очередь. Discord увидит игру через 5–10 секунд, саму игру устанавливать не нужно. Квесты с просмотром рекламы не поддерживаются."))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    /// Пауза между играми очереди.
    private func between(_ next: Date, _ item: QueueItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let secs = Int(max(0, next.timeIntervalSince(ctx.date)).rounded(.up))
            HStack(spacing: 22) {
                Cover(game: item.game, radius: 16).frame(width: 104, height: 104).opacity(0.6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Next in \(secs) s", "Следующая через \(secs) с"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                    Text(item.game.n).font(.system(size: 26, weight: .bold)).lineLimit(1)
                    Text(t("Done in this queue: \(runner.doneCount)", "Готово в этой очереди: \(runner.doneCount)"))
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                stopQueueButton
            }
        }
    }

    private var stopQueueButton: some View {
        Button { runner.stopQueue() } label: {
            Label(t("Stop queue", "Остановить очередь"), systemImage: "stop.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).frame(height: 36)
                .background(Theme.raised, in: Capsule())
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
    }

    private func playing(_ s: Session) -> some View {
        let fromQueue = runner.queueCurrent?.game.id == s.game.id
        let questMinutes = fromQueue ? (runner.queueCurrent?.minutes ?? 15) : 15
        let questLength = TimeInterval(questMinutes * 60)
        return TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(s.startedAt)
            let done = elapsed >= questLength
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    Cover(game: s.game, radius: 16)
                        .frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.orange).frame(width: 7, height: 7)
                            Text(status(done: done, fromQueue: fromQueue, minutes: questMinutes))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.orange)
                        }
                        Text(s.game.n)
                            .font(.system(size: 28, weight: .bold))
                            .lineLimit(1)
                        Text(s.game.chosenExe?.n ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(clock(elapsed))
                                .font(.system(size: 34, weight: .bold))
                                .monospacedDigit()
                            Text(t("of \(clock(questLength))", "из \(clock(questLength))"))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 132, alignment: .topLeading)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        if fromQueue {
                            Button { runner.skipCurrent() } label: {
                                Label(t("Skip", "Пропустить"), systemImage: "forward.end.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 16).frame(height: 36)
                                    .background(Theme.raised, in: Capsule())
                                    .foregroundStyle(Theme.text)
                            }
                            .buttonStyle(.plain)
                            stopQueueButton
                        } else {
                            Button { runner.stop(s.game) } label: {
                                Label(t("Stop", "Остановить"), systemImage: "stop.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 16).frame(height: 36)
                                    .background(Theme.raised, in: Capsule())
                                    .foregroundStyle(Theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ProgressTrack(value: min(1, elapsed / questLength))
                if runner.sessions.count > 1 {
                    others(excluding: s)
                }
            }
        }
    }

    private func status(done: Bool, fromQueue: Bool, minutes: Int) -> String {
        if done { return fromQueue ? t("Time's up, next game in a moment", "Время вышло, через минуту — следующая игра") : t("\(minutes) minutes done, the quest should count", "\(minutes) минут прошло, квест должен засчитаться") }
        if fromQueue {
            let left = runner.queue.count - 1
            return left > 0 ? t("Queue · \(left) more after this", "Очередь · после неё ещё \(left)") : t("Queue · last game", "Очередь · последняя игра")
        }
        return t("Discord sees the game", "Discord видит игру")
    }

    private func others(excluding s: Session) -> some View {
        HStack(spacing: 8) {
            Text(t("Also running:", "Тоже запущены:")).font(.system(size: 12)).foregroundStyle(Theme.faint)
            ForEach(runner.sessions.filter { $0.id != s.id }) { o in
                Button { runner.stop(o.game) } label: {
                    HStack(spacing: 6) {
                        Text(o.game.n).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Theme.raised, in: Capsule())
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(t("quests count for every running game", "квесты идут по всем запущенным играм"))
                .font(.system(size: 12)).foregroundStyle(Theme.faint)
        }
    }
}

// MARK: - Очередь

struct QueuePanel: View {
    @EnvironmentObject var runner: Runner
    private let durations = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t("Queue", "Очередь")).font(.system(size: 22, weight: .bold))
                Text(summary).font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                if !runner.queueRunning {
                    Button(t("Clear", "Очистить")) { runner.clearQueue() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.trailing, 6)
                    Button { runner.startQueue() } label: {
                        Label(t("Start queue", "Запустить очередь"), systemImage: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(Theme.orange, in: Capsule())
                            .foregroundStyle(Theme.orangeInk)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(runner.queue.enumerated()), id: \.element.id) { idx, item in
                    row(item, isFirst: idx == 0, isLast: idx == runner.queue.count - 1)
                    if idx < runner.queue.count - 1 {
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 74)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var summary: String {
        let total = runner.queue.reduce(0) { $0 + $1.minutes }
        let games = runner.queue.count
        return t("\(games) \(games == 1 ? "game" : "games") · about \(total) min · 5 s between games", "\(games) \(plural(games, "игра", "игры", "игр")) · около \(total) мин · между играми 5 секунд")
    }

    private func row(_ item: QueueItem, isFirst: Bool, isLast: Bool) -> some View {
        let current = runner.queueCurrent?.id == item.id
        return HStack(spacing: 14) {
            Cover(game: item.game, radius: 10).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.game.n).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(current ? Theme.orange : Theme.text)
                Text(current ? t("Running now", "Сейчас запущена") : t("Waiting for its turn", "Ждёт своей очереди"))
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            Spacer()
            Menu {
                ForEach(durations, id: \.self) { m in
                    Button(t("\(m) min", "\(m) мин")) { runner.setMinutes(m, for: item) }
                }
            } label: {
                Text(t("\(item.minutes) min", "\(item.minutes) мин")).font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(current)
            .help(t("Minutes the quest needs", "Сколько минут требует квест"))

            HStack(spacing: 2) {
                iconButton("chevron.up", t("Up", "Выше")) { runner.move(item, by: -1) }.disabled(isFirst || current)
                iconButton("chevron.down", t("Down", "Ниже")) { runner.move(item, by: 1) }.disabled(isLast || current)
                iconButton("xmark", current ? t("Skip", "Пропустить") : t("Remove", "Убрать")) { runner.dequeue(item) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func iconButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Theme.raised, in: Circle())
                .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return one }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
    return many
}

struct ProgressTrack: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(Theme.orange)
                    .frame(width: max(8, geo.size.width * value))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 1), value: value)
    }
}
