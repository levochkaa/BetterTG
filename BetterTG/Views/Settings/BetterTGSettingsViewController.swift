// BetterTGSettingsViewController.swift

import UIKit

// MARK: - BetterTGSettingsViewController

/// BetterTG's own options in one place, as Swiftgram's SGSettingsController keeps its: the tabs, and the chat list's
/// search and folder tabs. Each change applies at once; the switch keeps its own animation, and only rows whose
/// availability changes redraw. The bar's search button filters the rows as Swiftgram's search field does.
final class BetterTGSettingsViewController: SettingsListViewController, TelegramConditionalNavigationSearchProvider,
UISearchResultsUpdating, UISearchControllerDelegate {
    private lazy var search: UISearchController = {
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.placeholder = L10n.telegram("Common.Search")
        return search
    }()

    private var isSearching = false
    private var query = ""

    var shownTelegramNavigationSearch: UISearchController? {
        isSearching ? search : nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "BetterTG"
        updateBarButtons()
    }

    override func makeSections() -> [SettingsSection] {
        Self.filter(allSections(), by: query)
    }

    /// filterSGItemListUIEntrires: a section whose header or footer matches keeps every row; otherwise it keeps the
    /// rows whose title matches, and a section with none goes.
    private static func filter(_ sections: [SettingsSection], by query: String) -> [SettingsSection] {
        guard !query.isEmpty else { return sections }
        func matches(_ text: String?) -> Bool {
            text?.localizedCaseInsensitiveContains(query) == true
        }
        return sections.compactMap { section in
            if matches(section.header) || matches(section.footer) { return section }
            var section = section
            section.rows = section.rows.filter { matches($0.title) }
            return section.rows.isEmpty ? nil : section
        }
    }

    // MARK: Search

    func updateSearchResults(for search: UISearchController) {
        let text = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text != query else { return }
        query = text
        reload()
    }

    func didDismissSearchController(_: UISearchController) {
        guard isSearching else { return }
        isSearching = false
        query = ""
        updateBarButtons()
        reload()
    }

    private func openSearch() {
        guard !isSearching else { return }
        isSearching = true
        query = ""
        updateBarButtons()
        search.beginTelegramNavigationSearch()
    }

    /// The search button on the right; an open search takes the row.
    private func updateBarButtons() {
        guard !isSearching else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let button = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            primaryAction: UIAction { [weak self] _ in self?.openSearch() },
        )
        button.accessibilityLabel = L10n.telegram("Common.Search")
        navigationItem.rightBarButtonItem = button
    }

    // MARK: Rows

    private func allSections() -> [SettingsSection] {
        let settings = BetterTGSettings.shared
        let tabsShown = !settings.hidesTabBar
        return [
            SettingsSection(
                header: L10n.betterTG("BetterTGSettings.Tabs"),
                footer: L10n.betterTG("BetterTGSettings.WideTabBarInfo"),
                rows: [
                    toggle("BetterTGSettings.HideTabBar", isOn: settings.hidesTabBar) { settings.hidesTabBar = $0 },
                    toggle("BetterTGSettings.ArchiveTab", isOn: settings.showsArchiveTab, isEnabled: tabsShown) {
                        settings.showsArchiveTab = $0
                    },
                    toggle("BetterTGSettings.SettingsTab", isOn: settings.showsSettingsTab, isEnabled: tabsShown) {
                        settings.showsSettingsTab = $0
                    },
                    toggle("BetterTGSettings.TabNames", isOn: settings.showsTabNames, isEnabled: tabsShown) {
                        settings.showsTabNames = $0
                    },
                    toggle("BetterTGSettings.WideTabBar", isOn: settings.wideTabBar, isEnabled: tabsShown) {
                        settings.wideTabBar = $0
                    },
                ],
            ),
            SettingsSection(
                header: L10n.betterTG("BetterTGSettings.ChatList"),
                footer: L10n.betterTG("BetterTGSettings.SearchBarAtTopInfo"),
                rows: [
                    toggle("BetterTGSettings.SearchBarAtTop", isOn: settings.searchBarAtTop) {
                        settings.searchBarAtTop = $0
                    },
                ],
            ),
            SettingsSection(
                header: L10n.telegram("Settings.ChatFolders"),
                footer: L10n.betterTG("Folders.TabsAtBottomFooter"),
                rows: [
                    toggle("Folders.TabsAtBottom", isOn: FolderTabAppearance.shared.tabsAtBottom) {
                        FolderTabAppearance.shared.tabsAtBottom = $0
                    },
                ],
            ),
        ]
    }

    private func toggle(
        _ key: String,
        isOn: Bool,
        isEnabled: Bool = true,
        onChange: @escaping (Bool) -> Void,
    ) -> SettingsRow {
        var row = SettingsRow(title: L10n.betterTG(key), accessory: .toggle(isOn: isOn) { [weak self] value in
            onChange(value)
            self?.refreshAvailability()
        })
        row.isEnabled = isEnabled
        return row
    }

    /// Hide Tab Bar turns the tab rows off and on: those rows redraw, and the switch that changed keeps animating.
    private func refreshAvailability() {
        let previous = sections
        rebuildSections()
        guard isViewLoaded, previous.count == sections.count else { return reload() }
        var changed = [IndexPath]()
        for (sectionIndex, section) in sections.enumerated() {
            guard previous[sectionIndex].rows.count == section.rows.count else { return reload() }
            for (rowIndex, row) in section.rows.enumerated()
                where previous[sectionIndex].rows[rowIndex].isEnabled != row.isEnabled
            {
                changed.append(IndexPath(row: rowIndex, section: sectionIndex))
            }
        }
        guard !changed.isEmpty else { return }
        tableView.reconfigureRows(at: changed)
    }
}
