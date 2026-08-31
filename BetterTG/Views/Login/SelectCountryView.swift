// SelectCountryView.swift

import TDLibKit
import UIKit

final class SelectCountryViewController: UITableViewController, UISearchResultsUpdating {
    // MARK: Private

    private let selectedCountry: PhoneNumberInfo
    private let onSelection: (PhoneNumberInfo) -> Void
    private let client: TDLibClient
    private let contextIsCurrent: () -> Bool
    private var loadTask: Task<Void, Never>?
    private var countries = [PhoneNumberInfo]()
    private var filteredCountries = [PhoneNumberInfo]()
    private var query = ""

    init(
        selectedCountry: PhoneNumberInfo,
        client: TDLibClient,
        contextIsCurrent: @escaping () -> Bool,
        onSelection: @escaping (PhoneNumberInfo) -> Void,
    ) {
        self.selectedCountry = selectedCountry
        self.onSelection = onSelection
        self.client = client
        self.contextIsCurrent = contextIsCurrent
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    deinit { loadTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Login.SelectCountry.Title")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CountryCell")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel),
        )

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = L10n.telegram("Common.Search")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        loadCountries()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        filteredCountries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let country = filteredCountries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "CountryCell", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = country.name
        configuration.secondaryText = "+\(country.phoneNumberPrefix)"
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.accessoryType = country == selectedCountry ? .checkmark : .none
        cell.backgroundColor = .secondarySystemBackground
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard contextIsCurrent() else { return }
        loadTask?.cancel()
        onSelection(filteredCountries[indexPath.row])
        dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        filterCountries()
    }

    @objc private func cancel() {
        loadTask?.cancel()
        dismiss(animated: true)
    }

    private func loadCountries() {
        let client = client
        loadTask = Task { [weak self] in
            guard self?.contextIsCurrent() == true,
                  let result = try? await client.getCountries().countries,
                  !Task.isCancelled, self?.contextIsCurrent() == true else { return }
            let detectedCountryCode = try? await client.getCountryCode().text
            let mapped = result.compactMap { country -> PhoneNumberInfo? in
                guard let callingCode = country.callingCodes.first else { return nil }
                return PhoneNumberInfo(
                    country: country.countryCode,
                    phoneNumberPrefix: callingCode,
                    name: country.name,
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !Task.isCancelled, let self, contextIsCurrent() else { return }
            countries = mapped
            if let detectedCountryCode,
               let detected = mapped.first(where: { $0.country == detectedCountryCode })
            {
                onSelection(detected)
            }
            filterCountries()
        }
    }

    private func filterCountries() {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredCountries = countries.filter {
            normalizedQuery.isEmpty
                || $0.name.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.phoneNumberPrefix.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.country.localizedCaseInsensitiveContains(normalizedQuery)
        }
        tableView.reloadData()
    }
}
