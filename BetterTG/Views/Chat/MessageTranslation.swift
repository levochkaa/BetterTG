// MessageTranslation.swift

import NaturalLanguage
import TDLibKit
import UIKit

// MARK: - MessageTranslation

/// Telegram's translation settings and canTranslateText (TranslateUI/Translate.swift): with Show Translate Button on,
/// the message menu offers Translate for text in a supported language the user doesn't read.
enum MessageTranslation {
    private static let showButtonKey = "BetterTG.showTranslateButton"

    /// Telegram's supportedTranslationLanguages.
    private static let supportedLanguages: Set = [
        "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "zh", "co", "hr", "cs", "da",
        "nl", "en", "eo", "et", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "hi", "hmn",
        "hu", "is", "ig", "id", "ga", "it", "ja", "jv", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "lv", "lt",
        "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ny", "or", "ps", "fa", "pl", "pt",
        "pt-BR", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv",
        "tl", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug", "uz", "vi", "cy", "xh", "yi", "yo", "zu",
    ]

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

    /// Telegram's effectiveIgnoredTranslationLanguages without a Do Not Translate list: the app language and the
    /// system's first languages.
    private static var ignoredLanguages: Set<String> {
        var systemLanguages = Locale.preferredLanguages.prefix(2).map { $0.components(separatedBy: "-").first ?? $0 }
        if systemLanguages.count == 2, systemLanguages != ["en", "ru"] {
            systemLanguages = Array(systemLanguages.prefix(1))
        }
        return Set(systemLanguages).union([appLanguageCode])
    }

    /// canTranslateText: the language of the text's first 64 characters when Translate should be offered for it.
    static func translatableLanguage(of text: String) -> String? {
        guard showsTranslateButton, !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(64)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses
            .filter({ supportedLanguages.contains(normalized($0.key.rawValue)) })
            .max(by: { $0.value < $1.value })
        else { return nil }
        let language = normalized(best.key.rawValue)
        return ignoredLanguages.contains(language) ? nil : language
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
    private let targetLanguage = MessageTranslation.appLanguageCode
    private var translation: FormattedText?
    private var failed = false

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(text: FormattedText, sourceLanguage: String?, canCopy: Bool, onCopied: @escaping () -> Void) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.canCopy = canCopy
        self.onCopied = onCopied
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
        if canCopy, let translation {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Translate.CopyTranslation"),
                style: .action(destructive: false),
            ) { [weak self] in self?.copyTranslation(translation) }]))
        }
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
        let client = client
        let text = text
        let targetLanguage = targetLanguage
        Task { [weak self] in
            let result = try? await client.send(TDNativeRequests.translateText(
                text: text,
                toLanguageCode: targetLanguage,
                tone: "",
            ))
            guard let self, contextIsCurrent else { return }
            if let result, !result.text.isEmpty {
                translation = result
            } else {
                failed = true
            }
            reload()
        }
    }

    private func copyTranslation(_ result: FormattedText) {
        UIPasteboard.setFormattedText(result)
        let onCopied = onCopied
        dismiss(animated: true) { onCopied() }
    }
}
