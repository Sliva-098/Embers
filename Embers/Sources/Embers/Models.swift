import Foundation

struct Exe: Codable, Hashable {
    let n: String   // имя исполняемого файла, как в базе Discord
    let o: String   // "darwin" | "win32"
}

struct Game: Codable, Identifiable, Hashable {
    let i: String
    let n: String
    let c: String?
    let e: [Exe]
    var v: String? = nil   // обложка (cover_image_hash)

    var id: String { i }
    var name: String { n }
    var hasMac: Bool { e.contains { $0.o == "darwin" } }

    /// Предпочитаем macOS-файл: именно его настоящий Discord на Mac ищет среди процессов.
    var chosenExe: Exe? { e.first { $0.o == "darwin" } ?? e.first }

    var iconURL: URL? {
        guard let c else { return nil }
        return URL(string: "https://cdn.discordapp.com/app-icons/\(i)/\(c).png?size=128")
    }

    /// Квадратный арт игры из CDN Discord; если его нет — иконка.
    var coverURL: URL? {
        guard let v else { return iconURL }
        return URL(string: "https://cdn.discordapp.com/app-icons/\(i)/\(v).png?size=512")
    }
}

@MainActor
final class GameStore: ObservableObject {
    @Published var games: [Game] = []
    @Published var refreshing = false
    @Published var lastError: String?

    static let cacheURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Embers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("games.json")
    }()

    init() {
        load()
        // Раз в сутки тихо подтягиваем свежую базу: новые игры для квестов
        // Discord добавляет в тот же список detectable, что использует сам клиент.
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path)[.modificationDate]) as? Date
        if modified == nil || Date().timeIntervalSince(modified!) > 24 * 3600 {
            Task { await refresh() }
        }
    }

    private func load() {
        // Кэш после «Обновить базу» — если он уже с обложками; иначе встроенная база.
        if let d = try? Data(contentsOf: Self.cacheURL),
           let list = try? JSONDecoder().decode([Game].self, from: d),
           list.contains(where: { $0.v != nil }) {
            games = Self.sorted(list)
            return
        }
        if let u = Bundle.main.url(forResource: "games", withExtension: "json"),
           let d = try? Data(contentsOf: u),
           let list = try? JSONDecoder().decode([Game].self, from: d) {
            games = Self.sorted(list)
        }
    }

    /// Названия на буквы — сначала, «.hack//» и «1/8192» — в конце.
    static func sorted(_ list: [Game]) -> [Game] {
        list.sorted {
            let a = $0.n.first?.isLetter ?? false, b = $1.n.first?.isLetter ?? false
            if a != b { return a }
            return $0.n.localizedCaseInsensitiveCompare($1.n) == .orderedAscending
        }
    }

    /// Игры, которые часто встречаются в квестах Discord (порядок — как показываем).
    static let questRegulars = [
        "EVE Online", "Honkai: Star Rail", "Genshin Impact", "Zenless Zone Zero", "Wuthering Waves",
        "Marvel Rivals", "ARKNIGHTS: ENDFIELD", "Dune: Awakening", "Delta Force", "THE FINALS",
        "Once Human", "Throne and Liberty", "NARAKA: BLADEPOINT", "Warframe", "Destiny 2",
        "VALORANT", "Fortnite", "Apex Legends", "Rocket League", "Palworld",
    ]

    var featured: [Game] {
        let byName = Dictionary(games.map { ($0.n.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return Self.questRegulars.compactMap { byName[$0.lowercased()] }
    }

    /// Обновить базу из публичного эндпоинта Discord (авторизация не нужна).
    func refresh() async {
        refreshing = true; lastError = nil
        defer { refreshing = false }
        do {
            let url = URL(string: "https://discord.com/api/v9/applications/detectable")!
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var out: [Game] = []
            for g in raw {
                guard let id = g["id"] as? String, let name = g["name"] as? String else { continue }
                let exes = (g["executables"] as? [[String: Any]] ?? []).compactMap { e -> Exe? in
                    guard let n = e["name"] as? String, let o = e["os"] as? String,
                          o == "darwin" || o == "win32", (e["is_launcher"] as? Bool) != true else { return nil }
                    return Exe(n: String(n.drop(while: { $0 == ">" })), o: o)
                }
                if exes.isEmpty { continue }
                out.append(Game(i: id, n: name, c: g["icon_hash"] as? String, e: exes, v: g["cover_image_hash"] as? String))
            }
            try JSONEncoder().encode(out).write(to: Self.cacheURL)
            games = Self.sorted(out)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
