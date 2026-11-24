import Foundation

/// Язык интерфейса: "en" (по умолчанию) или "ru". Хранится в UserDefaults.
enum Lang {
    static let key = "lang"
    static var current: String { UserDefaults.standard.string(forKey: key) ?? "en" }
    static var isRussian: Bool { current == "ru" }
}

/// t("English", "Русский") — возвращает строку на текущем языке.
func t(_ en: String, _ ru: String) -> String { Lang.isRussian ? ru : en }
