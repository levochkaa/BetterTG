// AppLocalization.swift

import Combine
import Foundation
import TDLibKit
import UIKit

// MARK: - AppLanguage

struct AppLanguage: Codable, Equatable, Identifiable {
    let baseLanguagePackID: String
    let id: String
    let isBeta: Bool
    let isOfficial: Bool
    let isRTL: Bool
    let name: String
    let nativeName: String
    let pluralCode: String
    let totalStringCount: Int
    let translatedStringCount: Int

    var translationProgress: Double {
        guard totalStringCount > 0 else { return 1 }
        return Double(translatedStringCount) / Double(totalStringCount)
    }
}

// MARK: - L10n

enum L10n {
    static func telegram(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.telegramString(key, arguments: arguments)
    }

    static func telegramPlural(_ key: String, count: Int) -> String {
        AppLocalization.shared.telegramPluralString(key, count: count)
    }

    static func telegramPlural(_ key: String, count: Int, formattedCount: String) -> String {
        AppLocalization.shared.telegramPluralString(key, count: count, formattedCount: formattedCount)
    }

    static func betterTG(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.betterTGString(key, arguments: arguments)
    }
}

extension TelegramAccount {
    var localizedTitle: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let phoneNumber, !phoneNumber.isEmpty {
            return "+\(phoneNumber)"
        }
        return L10n.betterTG("Accounts.New")
    }
}

// MARK: - AppLocalization

final class AppLocalization: @unchecked Sendable {
    // MARK: Private

    private enum StoredString: Codable, Equatable {
        case deleted
        case ordinary(String)
        case plural(PluralValues)
    }

    private enum PluralCategory: String {
        case zero
        case one
        case two
        case few
        case many
        case other
    }

    private struct PluralValues: Codable, Equatable {
        let few: String
        let many: String
        let one: String
        let other: String
        let two: String
        let zero: String

        func value(for category: PluralCategory) -> String {
            let candidate =
                switch category {
                case .zero: zero
                case .one: one
                case .two: two
                case .few: few
                case .many: many
                case .other: other
                }
            return candidate.isEmpty ? other : candidate
        }
    }

    private struct StoredLanguagePack: Codable, Equatable {
        let baseLanguagePackID: String
        let id: String
        let isRTL: Bool
        let pluralCode: String
        var strings: [String: StoredString]
    }

    // MARK: Internal

    static let shared = AppLocalization()

    private static let availableLanguagesFilename = "available-languages.json"
    private static let defaultsKey = "appLanguagePackID"
    private static let localizationTarget = "ios"

    private let lock = NSLock()
    private var availableLanguagesStorage: [AppLanguage]
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var packs = [String: StoredLanguagePack]()
    @MainActor private var applicationGeneration = UUID()
    private var selectedLanguagePackIDStorage: String

    var availableLanguages: [AppLanguage] {
        lock.withLock { availableLanguagesStorage }
    }

    var currentLanguage: AppLanguage {
        lock.withLock {
            availableLanguagesStorage.first(where: { $0.id == selectedLanguagePackIDStorage })
                ?? Self.fallbackLanguage(id: selectedLanguagePackIDStorage)
        }
    }

    var isRTL: Bool {
        lock.withLock {
            packs[selectedLanguagePackIDStorage]?.isRTL
                ?? availableLanguagesStorage.first(where: { $0.id == selectedLanguagePackIDStorage })?.isRTL
                ?? Self.isRTLLanguage(selectedLanguagePackIDStorage)
        }
    }

    var selectedLanguagePackID: String {
        lock.withLock { selectedLanguagePackIDStorage }
    }

    private init() {
        let selectedID = UserDefaults.standard.string(forKey: Self.defaultsKey)
            ?? Self.preferredLanguagePackID()
        self.selectedLanguagePackIDStorage = selectedID
        self.availableLanguagesStorage = Self.loadAvailableLanguages()
        if let selectedPack = Self.loadPack(id: selectedID) {
            packs[selectedID] = selectedPack
            if !selectedPack.baseLanguagePackID.isEmpty,
               let basePack = Self.loadPack(id: selectedPack.baseLanguagePackID)
            {
                packs[basePack.id] = basePack
            }
        }
    }

    private static func storedStrings(_ strings: [LanguagePackString]) -> [String: StoredString] {
        Dictionary(uniqueKeysWithValues: strings.map { string in
            let value: StoredString =
                switch string.value {
                case .languagePackStringValueOrdinary(let ordinary): .ordinary(ordinary.value)
                case .languagePackStringValuePluralized(let plural):
                    .plural(.init(
                        few: plural.fewValue,
                        many: plural.manyValue,
                        one: plural.oneValue,
                        other: plural.otherValue,
                        two: plural.twoValue,
                        zero: plural.zeroValue,
                    ))
                case .languagePackStringValueDeleted, nil: .deleted
                }
            return (string.key, value)
        })
    }

    private static func language(from info: LanguagePackInfo) -> AppLanguage {
        AppLanguage(
            baseLanguagePackID: info.baseLanguagePackId,
            id: info.id,
            isBeta: info.isBeta,
            isOfficial: info.isOfficial,
            isRTL: info.isRtl,
            name: info.name,
            nativeName: info.nativeName,
            pluralCode: info.pluralCode,
            totalStringCount: info.totalStringCount,
            translatedStringCount: info.translatedStringCount,
        )
    }

    private static func fallbackLanguage(id: String) -> AppLanguage {
        AppLanguage(
            baseLanguagePackID: "",
            id: id,
            isBeta: false,
            isOfficial: true,
            isRTL: isRTLLanguage(id),
            name: id == "en" ? "English" : id,
            nativeName: id == "en" ? "English" : id,
            pluralCode: id,
            totalStringCount: 0,
            translatedStringCount: 0,
        )
    }

    private static func preferredLanguagePackID() -> String {
        guard let preferred = Locale.preferredLanguages.first?.lowercased().replacingOccurrences(of: "_", with: "-")
        else { return "en" }
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return "zh-hant"
        }
        if preferred.hasPrefix("zh") {
            return "zh-hans"
        }
        if preferred.hasPrefix("pt-br") {
            return "pt-br"
        }
        return preferred.split(separator: "-").first.map(String.init) ?? "en"
    }

    private static func bundleLanguageCandidates(_ languageID: String) -> [String] {
        let normalized = languageID.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = normalized.split(separator: "-").first.map(String.init)
        return [normalized, base].compactMap(\.self).uniqued()
    }

    private static func isRTLLanguage(_ languageID: String) -> Bool {
        let code = languageID.lowercased().split(separator: "-").first.map(String.init) ?? languageID
        return ["ar", "ckb", "fa", "he", "ps", "sd", "ug", "ur"].contains(code)
    }

    private static func format(_ value: String, localeID: String, arguments: [CVarArg]) -> String {
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: Locale(identifier: localeID), arguments: arguments)
    }

    private static func telegramPluralSuffix(_ category: PluralCategory) -> String {
        switch category {
        case .zero: "_0"
        case .one: "_1"
        case .two: "_2"
        case .few: "_3_10"
        case .many: "_many"
        case .other: "_any"
        }
    }

    private static func pluralCategory(languageCode: String, count: Int) -> PluralCategory {
        let code = languageCode.lowercased()
            .replacingOccurrences(of: "_", with: "-")
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
        case "be", "ru", "uk":
            if mod10 == 1, mod100 != 11 { return .one }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
            if mod10 == 0 || (5...9).contains(mod10) || (11...14).contains(mod100) { return .many }
            return .other
        case "bs", "hr", "sr":
            if mod10 == 1, mod100 != 11 { return .one }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return .few }
            return .other
        case "cs", "sk":
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
        case "fr", "hi", "pt":
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
        case "ja", "ko", "th", "vi", "zh":
            return .other
        default:
            return count == 1 ? .one : .other
        }
    }

    private static func cacheDirectory() -> URL? {
        guard let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        let directory = applicationSupport.appendingPathComponent("BetterTG/Localization", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func packURL(id: String) -> URL? {
        cacheDirectory()?.appendingPathComponent("\(id).json")
    }

    private static func save(_ pack: StoredLanguagePack) {
        guard let url = packURL(id: pack.id), let data = try? JSONEncoder().encode(pack) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadPack(id: String) -> StoredLanguagePack? {
        guard let url = packURL(id: id),
              let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(StoredLanguagePack.self, from: data)
        else { return nil }
        return pack
    }

    private static func saveAvailableLanguages(_ languages: [AppLanguage]) {
        guard let directory = cacheDirectory(), let data = try? JSONEncoder().encode(languages) else { return }
        try? data.write(
            to: directory.appendingPathComponent(availableLanguagesFilename),
            options: .atomic,
        )
    }

    private static func loadAvailableLanguages() -> [AppLanguage] {
        guard let directory = cacheDirectory(),
              let data = try? Data(contentsOf: directory.appendingPathComponent(availableLanguagesFilename)),
              let languages = try? JSONDecoder().decode([AppLanguage].self, from: data),
              !languages.isEmpty
        else { return [fallbackLanguage(id: "en")] }
        return languages
    }

    private static func applyLayoutDirection(isRTL: Bool) {
        Task { @MainActor in
            let semanticContentAttribute: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
            UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .forEach { $0.semanticContentAttribute = semanticContentAttribute }
        }
    }

    func start() {
        lock.lock()
        guard !isStarted else {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        nc.publisher(&cancellables, for: .updateLanguagePackStrings) { [weak self] update in
            self?.process(update)
        }
    }

    func configureTDLibClient(_ client: TDLibClient, databaseDirectory: URL) async throws {
        let databasePath = databaseDirectory.appendingPathComponent("language-packs.sqlite").path
        try await enqueueTDLibOption(
            name: "language_pack_database_path",
            value: .optionValueString(OptionValueString(value: databasePath)),
            client: client,
        )
        try await enqueueTDLibOption(
            name: "localization_target",
            value: .optionValueString(OptionValueString(value: Self.localizationTarget)),
            client: client,
        )
        try await enqueueTDLibOption(
            name: "language_pack_id",
            value: .optionValueString(OptionValueString(value: selectedLanguagePackID)),
            client: client,
        )
    }

    func clientDidConfigure(_ client: TDLibClient) {
        Task { [weak self] in
            await self?.refreshAvailableLanguages(using: client)
            await self?.refreshCurrentLanguagePack(using: client)
        }
    }

    func refreshAvailableLanguages() async {
        await refreshAvailableLanguages(using: TDLib.shared.activeClient)
    }

    @MainActor func languagePack(id: String) async throws -> AppLanguage {
        let client = TDLib.shared.activeClient
        let accountID = TDLib.shared.activeAccountID
        let info = try await client.getLanguagePackInfo(languagePackId: id)
        guard client.id == TDLib.shared.activeClient.id, accountID == TDLib.shared.activeAccountID else {
            throw CancellationError()
        }
        return Self.language(from: info)
    }

    @MainActor func apply(_ language: AppLanguage) async throws {
        let generation = UUID()
        applicationGeneration = generation
        let client = TDLib.shared.activeClient
        let accountID = TDLib.shared.activeAccountID
        let downloadedPack: StoredLanguagePack?
        let downloadedBasePack: StoredLanguagePack?

        downloadedPack =
            if language.id == "en" {
                try? await downloadPack(language, using: client)
            } else {
                try await downloadPack(language, using: client)
            }

        if !language.baseLanguagePackID.isEmpty {
            let baseInfo = try await client.getLanguagePackInfo(languagePackId: language.baseLanguagePackID)
            downloadedBasePack = try await downloadPack(Self.language(from: baseInfo), using: client)
        } else {
            downloadedBasePack = nil
        }

        try Task.checkCancellation()
        guard applicationGeneration == generation, client.id == TDLib.shared.activeClient.id,
              accountID == TDLib.shared.activeAccountID else { throw CancellationError() }
        _ = try await client.setOption(
            name: "language_pack_id",
            value: .optionValueString(OptionValueString(value: language.id)),
        )

        guard applicationGeneration == generation, client.id == TDLib.shared.activeClient.id,
              accountID == TDLib.shared.activeAccountID else { throw CancellationError() }
        let languages = lock.withLock {
            availableLanguagesStorage.removeAll { $0.id == language.id }
            availableLanguagesStorage.insert(language, at: 0)
            selectedLanguagePackIDStorage = language.id
            if let downloadedPack {
                packs[downloadedPack.id] = downloadedPack
            }
            if let downloadedBasePack {
                packs[downloadedBasePack.id] = downloadedBasePack
            }
            return availableLanguagesStorage
        }
        Self.saveAvailableLanguages(languages)
        nc.post(name: .availableAppLanguagesChanged)
        UserDefaults.standard.set(language.id, forKey: Self.defaultsKey)
        Self.applyLayoutDirection(isRTL: language.isRTL)
        nc.post(name: .appLanguageChanged)
    }

    func telegramString(_ key: String, arguments: [CVarArg] = []) -> String {
        let result: (String, String) = lock.withLock {
            let selectedID = selectedLanguagePackIDStorage
            if let value = ordinaryString(key, in: selectedID) {
                return (value, packs[selectedID]?.pluralCode ?? selectedID)
            }
            return (bundledTelegramString(key), "en")
        }
        return Self.format(result.0, localeID: result.1, arguments: arguments)
    }

    func telegramPluralString(_ key: String, count: Int, formattedCount: String? = nil) -> String {
        let result: (String, String) = lock.withLock {
            let selectedID = selectedLanguagePackIDStorage
            if let resolved = pluralString(key, count: count, in: selectedID) {
                return resolved
            }

            let category = Self.pluralCategory(languageCode: "en", count: count)
            let suffix = Self.telegramPluralSuffix(category)
            let localized = bundledTelegramString(key + suffix)
            if localized != key + suffix {
                return (localized, "en")
            }
            return (bundledTelegramString(key + "_any"), "en")
        }
        return Self.format(result.0, localeID: result.1, arguments: [(formattedCount ?? String(count)) as NSString])
    }

    func betterTGString(_ key: String, arguments: [CVarArg] = []) -> String {
        let result: (String, String) = lock.withLock {
            let selectedID = selectedLanguagePackIDStorage
            if let value = bundledString(key, table: "BetterTG", languageID: selectedID) {
                return (value, selectedID)
            }
            return (bundledString(key, table: "BetterTG", languageID: "en") ?? key, "en")
        }
        return Self.format(result.0, localeID: result.1, arguments: arguments)
    }

    private func enqueueTDLibOption(name: String, value: OptionValue, client: TDLibClient) async throws {
        _ = try await client.setOption(name: name, value: value)
    }

    // MARK: Private

    private func refreshAvailableLanguages(using client: TDLibClient) async {
        do {
            let info = try await client.getLocalizationTargetInfo(onlyLocal: false)
            var languages = info.languagePacks.map(Self.language(from:))
            if !languages.contains(where: { $0.id == "en" }) {
                languages.append(Self.fallbackLanguage(id: "en"))
            }
            languages.sort {
                if $0.id == $1.id { return false }
                if $0.id == selectedLanguagePackID { return true }
                if $1.id == selectedLanguagePackID { return false }
                return $0.nativeName.localizedCaseInsensitiveCompare($1.nativeName) == .orderedAscending
            }
            languages = lock.withLock {
                let downloadedCustom = availableLanguagesStorage.filter { installed in
                    !installed.isOfficial && !languages.contains(where: { $0.id == installed.id })
                }
                let merged = languages + downloadedCustom
                availableLanguagesStorage = merged
                return merged
            }
            Self.saveAvailableLanguages(languages)
            nc.post(name: .availableAppLanguagesChanged)
        } catch {
            log("Unable to refresh Telegram language packs: \(error.localizedDescription)")
        }
    }

    private func refreshCurrentLanguagePack(using client: TDLibClient) async {
        do {
            let info = try await client.getLanguagePackInfo(languagePackId: selectedLanguagePackID)
            let language = Self.language(from: info)
            let pack = try await downloadPack(language, using: client)
            var basePack: StoredLanguagePack?
            if !language.baseLanguagePackID.isEmpty {
                let baseInfo = try await client.getLanguagePackInfo(languagePackId: language.baseLanguagePackID)
                basePack = try await downloadPack(Self.language(from: baseInfo), using: client)
            }
            // Every new client (launch, foreground ownership restore) refreshes the pack. Only changed strings are a
            // language change: the root rebuilds its navigation stack on that notification.
            let changed = lock.withLock {
                let changed = packs[pack.id] != pack || basePack.map { packs[$0.id] != $0 } == true
                packs[pack.id] = pack
                if let basePack {
                    packs[basePack.id] = basePack
                }
                return changed
            }
            if changed { nc.post(name: .appLanguageChanged) }
        } catch {
            log("Unable to refresh Telegram language pack \(selectedLanguagePackID): \(error.localizedDescription)")
        }
    }

    private func downloadPack(_ language: AppLanguage, using client: TDLibClient) async throws -> StoredLanguagePack {
        _ = try? await client.synchronizeLanguagePack(languagePackId: language.id)
        let response = try await client.getLanguagePackStrings(keys: [], languagePackId: language.id)
        let pack = StoredLanguagePack(
            baseLanguagePackID: language.baseLanguagePackID,
            id: language.id,
            isRTL: language.isRTL,
            pluralCode: language.pluralCode,
            strings: Self.storedStrings(response.strings),
        )
        Self.save(pack)
        return pack
    }

    private func process(_ update: UpdateLanguagePackStrings) {
        guard update.localizationTarget == Self.localizationTarget else { return }
        let relevant = lock.withLock {
            update.languagePackId == selectedLanguagePackIDStorage
                || packs[selectedLanguagePackIDStorage]?.baseLanguagePackID == update.languagePackId
        }
        guard relevant else { return }

        guard !update.strings.isEmpty else {
            Task { [weak self] in
                await self?.refreshCurrentLanguagePack(using: TDLib.shared.activeClient)
            }
            return
        }

        var updatedPack: StoredLanguagePack?
        lock.withLock {
            guard var pack = packs[update.languagePackId] else { return }
            pack.strings.merge(Self.storedStrings(update.strings), uniquingKeysWith: { _, updated in updated })
            packs[pack.id] = pack
            updatedPack = pack
        }
        if let updatedPack {
            Self.save(updatedPack)
            nc.post(name: .appLanguageChanged)
        }
    }

    private func ordinaryString(_ key: String, in languageID: String) -> String? {
        if let pack = packs[languageID],
           case .ordinary(let value) = pack.strings[key],
           !value.isEmpty
        {
            return value
        }
        guard let baseID = packs[languageID]?.baseLanguagePackID, !baseID.isEmpty else { return nil }
        if let basePack = packs[baseID],
           case .ordinary(let value) = basePack.strings[key],
           !value.isEmpty
        {
            return value
        }
        return nil
    }

    private func pluralString(_ key: String, count: Int, in languageID: String) -> (String, String)? {
        if let pack = packs[languageID], case .plural(let values) = pack.strings[key] {
            let category = Self.pluralCategory(languageCode: pack.pluralCode, count: count)
            return (values.value(for: category), languageID)
        }
        guard let baseID = packs[languageID]?.baseLanguagePackID,
              !baseID.isEmpty,
              let basePack = packs[baseID],
              case .plural(let values) = basePack.strings[key]
        else { return nil }
        let category = Self.pluralCategory(languageCode: basePack.pluralCode, count: count)
        return (values.value(for: category), baseID)
    }

    private func bundledTelegramString(_ key: String) -> String {
        bundledString(key, table: "Telegram", languageID: "en") ?? key
    }

    private func bundledString(_ key: String, table: String, languageID: String) -> String? {
        let candidates = Self.bundleLanguageCandidates(languageID)
        for candidate in candidates {
            guard let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else { continue }
            let value = bundle.localizedString(forKey: key, value: nil, table: table)
            if value != key {
                return value
            }
        }
        return nil
    }
}

private extension NSLock {
    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try operation()
    }
}
