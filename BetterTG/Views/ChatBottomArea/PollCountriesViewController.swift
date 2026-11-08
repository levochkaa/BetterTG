// PollCountriesViewController.swift

import TDLibKit
import UIKit

// MARK: - PollCountriesViewController

/// CountriesMultiselectionScreen for a channel poll's Limit by Country: TDLib's countries with their flags and
/// Fragment's numbers beside France (`showFragment`), searchable, each checked or not, up to `poll_country_count_max`
/// with CountriesList.MaximumReached's toast past it. Done hands back the codes in the order they were chosen.
final class PollCountriesViewController: UITableViewController, UISearchResultsUpdating,
TelegramNavigationSearchProvider {
    private struct Country {
        let code: String
        let name: String

        var flag: String {
            guard code.count == 2, code != "FT" else { return "" }
            return code.uppercased()
                .unicodeScalars
                .compactMap { UnicodeScalar(127_397 + $0.value) }
                .map(String.init)
                .joined()
        }
    }

    private static let cellIdentifier = "PollCountryCell"

    let telegramNavigationSearch = UISearchController(searchResultsController: nil)

    private let client: TDLibClient
    private let onDone: ([String]) -> Void
    private var selected: [String]
    private var maximumCount = 12
    private var countries = [Country]()
    private var filtered = [Country]()
    private var query = ""
    private var loadTask: Task<Void, Never>?

    init(selected: [String], client: TDLibClient, onDone: @escaping ([String]) -> Void) {
        self.selected = selected
        self.client = client
        self.onDone = onDone
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("CountriesList.SelectCountries")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        navigationItem.rightBarButtonItem = UIBarButtonItem.telegramDone(target: self, action: #selector(donePressed))
        telegramNavigationSearch.obscuresBackgroundDuringPresentation = false
        telegramNavigationSearch.searchResultsUpdater = self
        telegramNavigationSearch.searchBar.placeholder = L10n.telegram("CountriesList.Search")
        definesPresentationContext = true
        load()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        filtered.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        L10n.telegramPlural("CountriesList.SelectUpTo", count: maximumCount)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let country = filtered[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = country.flag.isEmpty ? country.name : "\(country.flag)  \(country.name)"
        cell.contentConfiguration = content
        cell.accessoryType = selected.contains(country.code) ? .checkmark : .none
        cell.backgroundColor = .secondarySystemGroupedBackground
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let code = filtered[indexPath.row].code
        if let index = selected.firstIndex(of: code) {
            selected.remove(at: index)
        } else {
            guard selected.count < maximumCount else {
                let countries = L10n.telegramPlural("CountriesList.MaximumReached.Countries", count: maximumCount)
                TelegramUndoToast.show(
                    text: L10n.telegram("CountriesList.MaximumReached", countries),
                    in: view,
                    bottomInset: 8,
                    undo: nil,
                )
                return
            }
            selected.append(code)
        }
        tableView.cellForRow(at: indexPath)?.accessoryType = selected.contains(code) ? .checkmark : .none
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        applyFilter()
    }

    @objc private func donePressed() {
        onDone(selected)
        navigationController?.popViewController(animated: true)
    }

    private func load() {
        let client = client
        loadTask = Task { [weak self] in
            async let countriesRequest = client.getCountries()
            async let limitRequest = client.send(TDNativeRequests.getOption(name: "poll_country_count_max"))
            let result = await (try? countriesRequest)?.countries ?? []
            let limit = try? await limitRequest
            guard let self, !Task.isCancelled else { return }
            if case .optionValueInteger(let value)? = limit, value.value > 0 { maximumCount = Int(value.value) }
            var list = result
                .map { Country(code: $0.countryCode, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // CountriesMultiselectionScreen's Fragment entry, for anonymous numbers, stands before France unless TDLib
            // lists it already.
            if !list.contains(where: { $0.code == "FT" }), let index = list.firstIndex(where: { $0.code == "FR" }) {
                list.insert(Country(code: "FT", name: "Fragment"), at: index)
            }
            countries = list
            applyFilter()
        }
    }

    private func applyFilter() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = trimmed.isEmpty
            ? countries
            : countries.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) || $0.code.localizedCaseInsensitiveContains(trimmed)
            }
        tableView.reloadData()
    }
}
