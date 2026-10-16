// LanguageSelectionViewController.swift

import Combine
import UIKit

final class LanguageSelectionViewController: UITableViewController, UISearchResultsUpdating,
TelegramNavigationSearchProvider {
    // MARK: Private

    /// LocalizationListControllerNode's Do Not Translate value: the codes of several languages, or one language's
    /// English name.
    private static var doNotTranslateValue: String {
        let languages = MessageTranslation.ignoredLanguageList
        if languages.count > 1 { return languages.joined(separator: ", ") }
        return languages.first.flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0) } ?? ""
    }

    let telegramNavigationSearch = UISearchController(searchResultsController: nil)

    // MARK: Private

    private var applyingLanguageID: String?
    private var cancellables = Set<AnyCancellable>()
    private var languages = [AppLanguage]()
    private var query = ""

    private var visibleLanguages: [AppLanguage] {
        guard !query.isEmpty else { return languages }
        return languages.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.nativeName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    /// Telegram's Translate Messages section sits above the languages and hides while searching.
    private var showsTranslateSection: Bool {
        query.isEmpty
    }

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLocalizedContent()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LanguageCell")

        nc.publisher(&cancellables, for: .availableAppLanguagesChanged) { [weak self] _ in
            self?.reloadLanguages()
        }
        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            self?.configureLocalizedContent()
            self?.reloadLanguages()
        }

        reloadLanguages()
        Task { await AppLocalization.shared.refreshAvailableLanguages() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Do Not Translate's value follows the list the user just edited.
        if showsTranslateSection, MessageTranslation.showsTranslateButton {
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
    }

    override func numberOfSections(in _: UITableView) -> Int { showsTranslateSection ? 2 : 1 }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard isTranslateSection(section) else { return visibleLanguages.count }
        return MessageTranslation.showsTranslateButton ? 2 : 1
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        L10n.telegram(isTranslateSection(section) ? "Localization.TranslateMessages" : "Localization.InterfaceLanguage")
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        guard isTranslateSection(section) else { return L10n.betterTG("Localization.LanguagePacksInfo") }
        guard MessageTranslation.showsTranslateButton else {
            return L10n.telegram("Localization.ShowTranslateInfoExtended")
        }
        return L10n.telegram(MessageTranslation.ignoredLanguageList.count > 1
            ? "Localization.DoNotTranslateManyInfo"
            : "Localization.DoNotTranslateInfo")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LanguageCell", for: indexPath)
        if isTranslateSection(indexPath.section), indexPath.row == 1 {
            var configuration = UIListContentConfiguration.valueCell()
            configuration.text = L10n.telegram("Localization.DoNotTranslate")
            configuration.secondaryText = Self.doNotTranslateValue
            cell.contentConfiguration = configuration
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return cell
        }
        if isTranslateSection(indexPath.section) {
            var configuration = cell.defaultContentConfiguration()
            configuration.text = L10n.telegram("Localization.ShowTranslate")
            cell.contentConfiguration = configuration
            cell.accessoryType = .none
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = MessageTranslation.showsTranslateButton
            toggle.addTarget(self, action: #selector(showTranslateChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            return cell
        }
        guard let language = visibleLanguages[safe: indexPath.row] else { return cell }

        var configuration = cell.defaultContentConfiguration()
        configuration.text = language.nativeName
        var details = [String]()
        if language.name.caseInsensitiveCompare(language.nativeName) != .orderedSame {
            details.append(language.name)
        }
        if language.totalStringCount > 0, language.translationProgress < 0.999 {
            details.append(NumberFormatter.localizedString(
                from: NSNumber(value: language.translationProgress),
                number: .percent,
            ))
        }
        configuration.secondaryText = details.isEmpty ? nil : details.joined(separator: " • ")
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.selectionStyle = .default
        cell.accessoryView = nil
        cell.accessoryType = language.id == AppLocalization.shared.selectedLanguagePackID ? .checkmark : .none

        if language.id == applyingLanguageID {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
            cell.selectionStyle = .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isTranslateSection(indexPath.section), indexPath.row == 1 {
            navigationController?.pushViewController(
                TranslationLanguagesViewController(mode: .doNotTranslate),
                animated: true,
            )
            return
        }
        guard !isTranslateSection(indexPath.section),
              applyingLanguageID == nil,
              let language = visibleLanguages[safe: indexPath.row],
              language.id != AppLocalization.shared.selectedLanguagePackID
        else { return }

        applyingLanguageID = language.id
        tableView.reloadData()
        Task { @MainActor [weak self] in
            do {
                try await AppLocalization.shared.apply(language)
            } catch {
                self?.showDownloadError()
            }
            self?.applyingLanguageID = nil
            self?.tableView.reloadData()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
    }

    private func isTranslateSection(_ section: Int) -> Bool {
        showsTranslateSection && section == 0
    }

    @objc private func showTranslateChanged(_ sender: UISwitch) {
        MessageTranslation.showsTranslateButton = sender.isOn
        tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
    }

    private func configureLocalizedContent() {
        title = L10n.telegram("Settings.AppLanguage")
        navigationItem.largeTitleDisplayMode = .never
        let searchController = telegramNavigationSearch
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = L10n.telegram("Common.Search")
    }

    private func reloadLanguages() {
        languages = AppLocalization.shared.availableLanguages
        tableView.reloadData()
    }

    private func showDownloadError() {
        let alert = UIAlertController(
            title: L10n.telegram("Settings.AppLanguage"),
            message: L10n.betterTG("Localization.DownloadError"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}
