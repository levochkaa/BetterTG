// LanguageSelectionViewController.swift

import Combine
import UIKit

final class LanguageSelectionViewController: UITableViewController, UISearchResultsUpdating,
TelegramNavigationSearchProvider {
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

    override func numberOfSections(in _: UITableView) -> Int { 1 }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        visibleLanguages.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        L10n.telegram("Localization.InterfaceLanguage")
    }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        L10n.betterTG("Localization.LanguagePacksInfo")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LanguageCell", for: indexPath)
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
        guard applyingLanguageID == nil,
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

    // MARK: Private

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
