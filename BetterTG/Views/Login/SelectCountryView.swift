// SelectCountryView.swift

import TDLibKit
import UIKit

final class SelectCountryViewController: UITableViewController, UISearchResultsUpdating {
    init(selectedCountry: PhoneNumberInfo, onSelection: @escaping (PhoneNumberInfo) -> Void) {
        self.selectedCountry = selectedCountry
        self.onSelection = onSelection
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Country"
        tableView.backgroundColor = .black
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CountryCell")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel),
        )

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
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
        configuration.textProperties.color = .white
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.accessoryType = country == selectedCountry ? .checkmark : .none
        cell.backgroundColor = .secondarySystemBackground
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelection(filteredCountries[indexPath.row])
        dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        filterCountries()
    }

    private let selectedCountry: PhoneNumberInfo
    private let onSelection: (PhoneNumberInfo) -> Void
    private var countries = [PhoneNumberInfo]()
    private var filteredCountries = [PhoneNumberInfo]()
    private var query = ""

    @objc private func cancel() {
        dismiss(animated: true)
    }

    private func loadCountries() {
        Task { [weak self] in
            guard let self, let result = try? await td.getCountries().countries else { return }
            let detectedCountryCode = try? await td.getCountryCode().text
            let mapped = result.compactMap { country -> PhoneNumberInfo? in
                guard let callingCode = country.callingCodes.first else { return nil }
                return PhoneNumberInfo(
                    country: country.countryCode,
                    phoneNumberPrefix: callingCode,
                    name: country.englishName,
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run {
                self.countries = mapped
                if let detectedCountryCode,
                   let detected = mapped.first(where: { $0.country == detectedCountryCode })
                {
                    self.onSelection(detected)
                }
                self.filterCountries()
            }
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
