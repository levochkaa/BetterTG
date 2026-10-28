// TelegramPluralRules.swift

import Foundation

// MARK: - TelegramPluralCategory

enum TelegramPluralCategory: String {
    case zero
    case one
    case two
    case few
    case many
    case other
}

// MARK: - TelegramPluralRules

/// The plural form a count takes in a language, as Telegram's language packs number them.
enum TelegramPluralRules {
    static func category(languageCode: String, count: Int) -> TelegramPluralCategory {
        let code = languageCode.lowercased()
            .replacing("_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? languageCode
        let mod10 = count % 10
        let mod100 = count % 100

        switch code {
        case "ar":
            if count == 0 { return .zero }
            if count == 1 { return .one }
            if count == 2 { return .two }
            if (3...10).contains(mod100) { return .few }
            if (11...99).contains(mod100) { return .many }
            return .other
        case "be",
             "ru",
             "uk":
            if mod10 == 1, mod100 != 11 { return .one }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
            if mod10 == 0 || (5...9).contains(mod10) || (11...14).contains(mod100) { return .many }
            return .other
        case "bs",
             "hr",
             "sr":
            if mod10 == 1, mod100 != 11 { return .one }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
            return .other
        case "cs",
             "sk":
            if count == 1 { return .one }
            if (2...4).contains(count) { return .few }
            return .other
        case "cy":
            if count == 0 { return .zero }
            if count == 1 { return .one }
            if count == 2 { return .two }
            if count == 3 { return .few }
            if count == 6 { return .many }
            return .other
        case "fr",
             "hi",
             "pt":
            return count == 0 || count == 1 ? .one : .other
        case "ga":
            if count == 1 { return .one }
            if count == 2 { return .two }
            if (3...6).contains(count) { return .few }
            if (7...10).contains(count) { return .many }
            return .other
        case "lt":
            if mod10 == 1, !(11...19).contains(mod100) { return .one }
            if (2...9).contains(mod10), !(11...19).contains(mod100) { return .few }
            return .other
        case "lv":
            if mod10 == 0 || (11...19).contains(mod100) { return .zero }
            if mod10 == 1, mod100 != 11 { return .one }
            return .other
        case "pl":
            if count == 1 { return .one }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
            return .many
        case "ro":
            if count == 1 { return .one }
            if count == 0 || (1...19).contains(mod100) { return .few }
            return .other
        case "sl":
            if mod100 == 1 { return .one }
            if mod100 == 2 { return .two }
            if mod100 == 3 || mod100 == 4 { return .few }
            return .other
        case "ja",
             "ko",
             "th",
             "vi",
             "zh":
            return .other
        default:
            return count == 1 ? .one : .other
        }
    }
}
