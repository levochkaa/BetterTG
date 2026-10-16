// TranslationLanguagesViewController.swift

import UIKit

// MARK: - TranslationLanguagesViewController

/// Telegram's translation language lists: Do Not Translate (translationSettingsController), where a checked language
/// is never offered for translation, and the translate screen's choice of the language to translate into.
final class TranslationLanguagesViewController: SettingsListViewController {
    enum Mode {
        case doNotTranslate
        case target(selected: String, onSelect: (String) -> Void)
    }

    private let mode: Mode
    private let languages = MessageTranslation.languageList
    /// Do Not Translate lists the languages checked when it opened first.
    private let initiallyIgnored = MessageTranslation.ignoredLanguages

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title =
            switch mode {
            case .doNotTranslate: L10n.telegram("DoNotTranslate.Title")
            case .target: L10n.telegram("Translate.Languages.Title")
            }
    }

    override func makeSections() -> [SettingsSection] {
        switch mode {
        case .doNotTranslate:
            let ignored = MessageTranslation.ignoredLanguages
            let ordered = languages.filter { initiallyIgnored.contains($0.code) }
                + languages.filter { !initiallyIgnored.contains($0.code) }
            return [SettingsSection(rows: ordered.map { language in
                SettingsRow(
                    title: language.title,
                    detail: language.subtitle,
                    style: .subtitle,
                    accessory: ignored.contains(language.code) ? .checkmark : .none,
                ) { [weak self] in
                    MessageTranslation.setIgnored(
                        language.code,
                        !MessageTranslation.ignoredLanguages.contains(language.code),
                    )
                    self?.reload()
                }
            })]
        case .target(let selected, let onSelect):
            return [SettingsSection(rows: languages.map { language in
                SettingsRow(
                    title: language.title,
                    detail: language.subtitle,
                    style: .subtitle,
                    accessory: language.code == selected ? .checkmark : .none,
                ) { onSelect(language.code) }
            })]
        }
    }
}
