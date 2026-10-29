// TelegramPushText.swift

import Foundation

// MARK: - TelegramPushText

/// The text Telegram for iOS shows for a push. Telegram's server builds it from the `PUSH_<loc_key>` string of the
/// iOS language pack, `"<title>|<body>"` (`"%1$@|🎤 voice message"`), filled with the push's `loc_args`. The relay's
/// alert is Telegram Web's text instead, the Web Push `title` and `description`, worded for the web client.
struct TelegramPushText: Equatable {
    // MARK: Private

    /// Older packs name albums (`loc_key` `MESSAGES`) `ALBUM`, and files sent to a user `FILES`.
    private static let keyAliases = [
        "MESSAGES": "ALBUM",
        "CHAT_MESSAGES": "CHAT_ALBUM",
        "CHANNEL_MESSAGES": "CHANNEL_ALBUM",
        "MESSAGE_DOCS": "MESSAGE_FILES",
    ]

    /// Keys whose last argument is a count.
    private static let countedSuffixes = ["_PHOTOS", "_VIDEOS", "_DOCS", "_FILES", "_FWDS", "_PLAYLIST"]

    // MARK: Internal

    /// Nil when the string has no title part.
    let title: String?
    let body: String

    /// `payload` is Telegram's Web Push payload as the relay keeps it: `{"data": {"loc_key": …, "loc_args": […]}}`.
    init?(payload: String, strings: TelegramPushStrings) {
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let push = root["data"] as? [String: Any],
              let locKey = push["loc_key"] as? String
        else { return nil }
        let arguments = (push["loc_args"] as? [Any])?.compactMap { $0 as? String } ?? []
        self.init(locKey: locKey, arguments: arguments, strings: strings)
    }

    /// Counted keys (`MESSAGE_PHOTOS`, `MESSAGES`, …) are plurals in the language pack, in the form of the count they
    /// print (`%2$d`). Older packs name albums `PUSH_ALBUM` and have counted keys only as a plural body,
    /// `PUSH_<loc_key>_TEXT`, titled by the conversation. Nil when the strings have nothing for the key.
    init?(locKey: String, arguments: [String], strings: TelegramPushStrings) {
        switch strings.entry("PUSH_\(locKey)") {
        case .template(let template):
            self.init(template: template, arguments: arguments)
            return
        case .plural(let plural):
            self.init(template: plural.template(count: plural.count(arguments: arguments)), arguments: arguments)
            return
        case nil:
            break
        }

        let key = Self.keyAliases[locKey] ?? locKey
        if key != locKey, case .template(let template) = strings.entry("PUSH_\(key)") {
            self.init(template: template, arguments: arguments)
            return
        }
        guard Self.countedSuffixes.contains(where: { key.hasSuffix($0) }),
              let count = arguments.last.flatMap({ Int($0) }),
              case .plural(let plural) = strings.entry("PUSH_\(key)_TEXT")
        else { return nil }
        let author = arguments.first ?? ""
        self.init(
            title: key.hasPrefix("CHAT_") && arguments.count > 2 ? arguments[1] : author,
            body: Self.format(plural.template(count: count), arguments: [String(count)])
                .replacing("{author}", with: author),
        )
    }

    private init(title: String?, body: String) {
        self.title = title
        self.body = body
    }

    /// Splits before formatting: a name may contain "|".
    private init(template: String, arguments: [String]) {
        if let separator = template.firstIndex(of: "|") {
            self.init(
                title: Self.format(String(template[..<separator]), arguments: arguments),
                body: Self.format(String(template[template.index(after: separator)...]), arguments: arguments),
            )
        } else {
            self.init(title: nil, body: Self.format(template, arguments: arguments))
        }
    }

    /// Fills `%@`, `%1$@` and `%1$d` with the arguments; a missing argument becomes empty instead of crashing like
    /// `String(format:)`.
    static func format(_ template: String, arguments: [String]) -> String {
        let characters = Array(template)
        var result = ""
        var nextSequentialArgument = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "%", index + 1 < characters.count else {
                result.append(character)
                index += 1
                continue
            }
            if characters[index + 1] == "%" {
                result.append("%")
                index += 2
                continue
            }
            if characters[index + 1] == "@" || characters[index + 1] == "d" {
                result += nextSequentialArgument < arguments.count ? arguments[nextSequentialArgument] : ""
                nextSequentialArgument += 1
                index += 2
                continue
            }
            var digitsEnd = index + 1
            while digitsEnd < characters.count, characters[digitsEnd].isASCII, characters[digitsEnd].isNumber {
                digitsEnd += 1
            }
            if digitsEnd > index + 1, digitsEnd + 1 < characters.count, characters[digitsEnd] == "$",
               characters[digitsEnd + 1] == "@" || characters[digitsEnd + 1] == "d",
               let position = Int(String(characters[(index + 1)..<digitsEnd]))
            {
                result += position >= 1 && position <= arguments.count ? arguments[position - 1] : ""
                index = digitsEnd + 2
                continue
            }
            result.append(character)
            index += 1
        }
        return result
    }
}

// MARK: - TelegramPushStrings

/// The `PUSH_*` strings of the selected Telegram language pack over the English ones the app bundles. The app keeps
/// the language pack's in the app group for the notification service.
struct TelegramPushStrings: Codable, Equatable {
    // MARK: Internal

    enum Value: Codable, Equatable {
        case ordinary(String)
        case plural(zero: String, one: String, two: String, few: String, many: String, other: String)
    }

    /// A `PUSH_*` string: one template, or the forms of a plural.
    enum Entry {
        case template(String)
        case plural(Plural)
    }

    struct Plural {
        let forms: [TelegramPluralCategory: String]
        let other: String
        let pluralCode: String

        func template(count: Int) -> String {
            forms[TelegramPluralRules.category(languageCode: pluralCode, count: count)] ?? other
        }

        /// The argument a plural counts is the one its forms print as a number (`%2$d`); 1 when they print none.
        func count(arguments: [String]) -> Int {
            for form in [other] + forms.values {
                guard let match = form.firstMatch(of: /%(\d+)\$d/), let position = Int(match.1),
                      position >= 1, position <= arguments.count, let count = Int(arguments[position - 1])
                else { continue }
                return count
            }
            return 1
        }
    }

    let pluralCode: String
    let values: [String: Value]

    /// The language pack's strings, falling back to the bundled English `PUSH_*` strings, whose plurals are kept as
    /// `<key>_1` and `<key>_any`.
    static func load() -> TelegramPushStrings {
        let stored = storedURL()
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(TelegramPushStrings.self, from: $0) }
        return TelegramPushStrings(
            pluralCode: stored?.pluralCode ?? "en",
            values: bundledEnglish().merging(stored?.values ?? [:]) { _, stored in stored },
        )
    }

    static func store(_ strings: TelegramPushStrings) {
        guard let url = storedURL(), let data = try? JSONEncoder().encode(strings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Private

    private static func storedURL() -> URL? {
        BetterTGAppGroup.containerURL()?.appendingPathComponent("TelegramPushStrings.json")
    }

    private static func bundledEnglish() -> [String: Value] {
        // The notification service lives in <App>.app/PlugIns/<Extension>.appex.
        var appURL = Bundle.main.bundleURL
        if appURL.pathExtension == "appex" {
            appURL = appURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        guard let path = Bundle(url: appURL)?.path(
            forResource: "Telegram",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: "en",
        ),
              let strings = NSDictionary(contentsOfFile: path) as? [String: String]
        else { return [:] }
        return strings.filter { $0.key.hasPrefix("PUSH_") }.mapValues { .ordinary($0) }
    }

    func entry(_ key: String) -> Entry? {
        switch values[key] {
        case .ordinary(let value) where !value.isEmpty:
            return .template(value)
        case .plural(let zero, let one, let two, let few, let many, let other):
            let forms: [TelegramPluralCategory: String] = [
                .zero: zero, .one: one, .two: two, .few: few, .many: many, .other: other,
            ].filter { !$0.value.isEmpty }
            return .plural(Plural(forms: forms, other: other, pluralCode: pluralCode))
        case nil,
             .ordinary:
            break
        }
        guard case .ordinary(let other) = values["\(key)_any"] else { return nil }
        var forms = [TelegramPluralCategory.other: other]
        if case .ordinary(let one) = values["\(key)_1"] {
            forms[.one] = one
        }
        return .plural(Plural(forms: forms, other: other, pluralCode: "en"))
    }
}
