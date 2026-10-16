// MessageTranslation.swift

import NaturalLanguage
import TDLibKit
import UIKit

// MARK: - MessageTranslation

/// Telegram's translation settings and canTranslateText (TranslateUI/Translate.swift): with Show Translate Button on,
/// the message menu offers Translate for text in a supported language the user doesn't read.
enum MessageTranslation {
    private static let showButtonKey = "BetterTG.showTranslateButton"
    private static let ignoredLanguagesKey = "BetterTG.doNotTranslateLanguages"

    /// Telegram's supportedTranslationLanguages, in its order.
    private static let supportedLanguageList = [
        "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "zh", "co", "hr", "cs", "da",
        "nl", "en", "eo", "et", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "hi", "hmn",
        "hu", "is", "ig", "id", "ga", "it", "ja", "jv", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "lv", "lt",
        "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ny", "or", "ps", "fa", "pl", "pt",
        "pt-BR", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv",
        "tl", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug", "uz", "vi", "cy", "xh", "yi", "yo", "zu",
    ]
    private static let supportedLanguages = Set(supportedLanguageList)
    /// Telegram's popularTranslationLanguages, listed first.
    private static let popularLanguages = ["en", "ar", "zh", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "es", "uk"]

    /// Settings > Language > Show Translate Button, off by default as in Telegram.
    static var showsTranslateButton: Bool {
        get { UserDefaults.standard.bool(forKey: showButtonKey) }
        set { UserDefaults.standard.set(newValue, forKey: showButtonKey) }
    }

    /// The app language's base code, which translations target (Telegram's strings.baseLanguageCode).
    static var appLanguageCode: String {
        let language = AppLocalization.shared.currentLanguage
        var code = (language.baseLanguagePackID.isEmpty ? language.id : language.baseLanguagePackID).lowercased()
        if code.hasSuffix("-raw") {
            code = String(code.dropLast(4))
        }
        return normalized(code)
    }

    /// The Do Not Translate list in order: the user's own once edited, else Telegram's default of the app language
    /// and the system's first languages (effectiveIgnoredTranslationLanguages).
    static var ignoredLanguageList: [String] {
        if let custom = UserDefaults.standard.stringArray(forKey: ignoredLanguagesKey) { return custom }
        return [appLanguageCode] + systemLanguageCodes.filter { $0 != appLanguageCode }
    }

    static var ignoredLanguages: Set<String> {
        Set(ignoredLanguageList)
    }

    /// translationSettingsController's languages: the popular ones with the app language on top, then the rest, each
    /// with its English name and its own name.
    static var languageList: [(code: String, title: String, subtitle: String)] {
        let english = Locale(identifier: "en")
        let appLanguage = appLanguageCode
        var result = [(code: String, title: String, subtitle: String)]()
        var added = Set<String>()
        for code in popularLanguages + supportedLanguageList where !added.contains(code) {
            guard let title = english.localizedString(forLanguageCode: code) else { continue }
            added.insert(code)
            let subtitle = Locale(identifier: code).localizedString(forLanguageCode: code) ?? title
            let entry = (code: code, title: title.capitalized, subtitle: subtitle.capitalized)
            if code == appLanguage {
                result.insert(entry, at: 0)
            } else {
                result.append(entry)
            }
        }
        return result
    }

    /// Telegram's systemLanguageCodes: the first preferred language, or the first two when they are English and
    /// Russian.
    private static var systemLanguageCodes: [String] {
        var languages = Locale.preferredLanguages.prefix(2).map { $0.components(separatedBy: "-").first ?? $0 }
        if languages.count == 2, languages != ["en", "ru"] {
            languages = Array(languages.prefix(1))
        }
        return languages
    }

    /// translationSettingsController's update: the first change starts from the default list.
    static func setIgnored(_ code: String, _ ignored: Bool) {
        var list = ignoredLanguageList
        if ignored {
            if !list.contains(code) { list.append(code) }
        } else {
            list.removeAll { $0 == code }
        }
        UserDefaults.standard.set(list, forKey: ignoredLanguagesKey)
    }

    /// The supported language of the text's first 64 characters, if recognised.
    static func detectedLanguage(of text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(64)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses
            .filter({ supportedLanguages.contains(normalized($0.key.rawValue)) })
            .max(by: { $0.value < $1.value })
        else { return nil }
        return normalized(best.key.rawValue)
    }

    /// canTranslateText: the text's language when the message menu should offer Translate for it.
    static func translatableLanguage(of text: String) -> String? {
        guard showsTranslateButton, let language = detectedLanguage(of: text) else { return nil }
        return ignoredLanguages.contains(language) ? nil : language
    }

    /// TextProcessingTranslateContentComponent: the app language, unless the text is already in it; then English,
    /// or for English text another language the user reads.
    static func targetLanguage(from source: String?) -> String {
        let appLanguage = appLanguageCode
        guard let source, source == appLanguage else { return appLanguage }
        guard source == "en" else { return "en" }
        if let other = ignoredLanguageList.first(where: { $0 != "en" }) { return other }
        let preferred = Locale.preferredLanguages.first { !$0.hasPrefix("en") }
        return preferred.map { normalized($0) } ?? "en"
    }

    /// The language's name in the app language, capitalised as a header.
    static func languageName(_ code: String) -> String? {
        guard let name = Locale(identifier: appLanguageCode).localizedString(forLanguageCode: code), !name.isEmpty
        else { return nil }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// normalizeTranslationLanguage.
    private static func normalized(_ code: String) -> String {
        let base = code.components(separatedBy: "-").first ?? code
        return base == "nb" ? "no" : base
    }
}

// MARK: - MessageTranslationViewController

/// Telegram's translate screen for a message: the original text under its language, TDLib's translation into the app
/// language under that language, and Copy Translation unless the chat protects its content.
final class MessageTranslationViewController: SettingsListViewController {
    private let text: FormattedText
    private let sourceLanguage: String?
    private let canCopy: Bool
    private let onCopied: () -> Void
    private var targetLanguage: String
    private var translation: FormattedText?
    private var failed = false
    private var requestGeneration = 0

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(text: FormattedText, sourceLanguage: String?, canCopy: Bool, onCopied: @escaping () -> Void) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.canCopy = canCopy
        self.onCopied = onCopied
        self.targetLanguage = MessageTranslation.targetLanguage(from: sourceLanguage)
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Translate.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        loadTranslation()
    }

    override func makeSections() -> [SettingsSection] {
        let translationRow =
            if let translation {
                SettingsRow(title: translation.text, style: .subtitle)
            } else if failed {
                SettingsRow(title: L10n.telegram("Login.UnknownError"), style: .status(.secondaryLabel))
            } else {
                SettingsRow(title: " ", accessory: .activity)
            }
        var sections = [
            SettingsSection(
                header: sourceLanguage.flatMap(MessageTranslation.languageName)
                    ?? L10n.telegram("Translate.Languages.Original"),
                rows: [SettingsRow(title: text.text, style: .subtitle)],
            ),
            SettingsSection(
                header: MessageTranslation.languageName(targetLanguage)
                    ?? L10n.telegram("Translate.Languages.Translation"),
                rows: [translationRow],
            ),
        ]
        var actions = [SettingsRow]()
        if canCopy, let translation {
            actions.append(SettingsRow(
                title: L10n.telegram("Translate.CopyTranslation"),
                style: .action(destructive: false),
            ) { [weak self] in self?.copyTranslation(translation) })
        }
        actions.append(SettingsRow(
            title: L10n.telegram("Translate.ChangeLanguage"),
            style: .action(destructive: false),
        ) { [weak self] in self?.changeLanguage() })
        sections.append(SettingsSection(rows: actions))
        return sections
    }

    static func present(
        text: FormattedText,
        sourceLanguage: String?,
        canCopy: Bool,
        from presenter: UIViewController,
        onCopied: @escaping () -> Void,
    ) {
        let navigation = TelegramNavigationController(rootViewController: MessageTranslationViewController(
            text: text,
            sourceLanguage: sourceLanguage,
            canCopy: canCopy,
            onCopied: onCopied,
        ))
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    private func loadTranslation() {
        guard contextIsCurrent else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let client = client
        let text = text
        let targetLanguage = targetLanguage
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.translateText(
                text: text,
                toLanguageCode: targetLanguage,
                tone: "",
            ))
            guard let self, contextIsCurrent, requestGeneration == generation else { return }
            if let result, !result.text.isEmpty {
                translation = result
            } else {
                failed = true
            }
            reload()
        }
    }

    /// Telegram's language choice for the translation: the result switches to the picked language.
    private func changeLanguage() {
        let picker = TranslationLanguagesViewController(mode: .target(selected: targetLanguage) { [weak self] code in
            guard let self else { return }
            navigationController?.popViewController(animated: true)
            guard code != targetLanguage else { return }
            targetLanguage = code
            translation = nil
            failed = false
            reload()
            loadTranslation()
        })
        navigationController?.pushViewController(picker, animated: true)
    }

    private func copyTranslation(_ result: FormattedText) {
        UIPasteboard.setFormattedText(result)
        let onCopied = onCopied
        dismiss(animated: true) { onCopied() }
    }
}
