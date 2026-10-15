// ComposeContactPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - ComposeContactPickerViewController

/// Telegram's contact pickers in the compose flow, over the contacts by name and a search with Global Search people.
/// New Secret Chat (ContactSelectionController) starts a secret chat with the tapped person (createNewSecretChat)
/// and opens it in place of the compose screens.
final class ComposeContactPickerViewController: SettingsListViewController, UISearchResultsUpdating,
ComposeFlowScreen {
    enum Mode {
        /// One person, never a bot.
        case secretChat
    }

    private static let searchDelay = Duration.milliseconds(250)

    private static var loadingRow: SettingsRow {
        SettingsRow(
            title: L10n.telegram("Channel.NotificationLoading"),
            style: .status(.secondaryLabel),
            accessory: .activity,
        )
    }

    private let mode: Mode
    private let searchController = UISearchController(searchResultsController: nil)
    private var contacts = [ComposeContact]()
    private var contactSections = [ComposeContactSection]()
    private var isLoading = true
    private var query = ""
    private var foundContacts = [ComposeContact]()
    private var foundPeople = [ComposeContact]()
    private var isSearching = false
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Who the mode lists: a secret chat is only with a person.
    private var allowsPerson: (ComposeContact) -> Bool {
        switch mode {
        case .secretChat: { !$0.isBot }
        }
    }

    init(mode: Mode) {
        self.mode = mode
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        actionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .secretChat:
            title = L10n.telegram("Compose.NewEncryptedChatTitle")
            searchController.searchBar.placeholder = L10n.telegram("Common.Search")
        }
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard trimmedQuery.isEmpty else { return searchSections() }
        if isLoading, contacts.isEmpty {
            return [SettingsSection(rows: [Self.loadingRow])]
        }
        return contactSections.map { section in
            SettingsSection(header: section.title, rows: section.contacts.map { self.row(for: $0) })
        }
    }

    override func sectionIndexTitles(for _: UITableView) -> [String]? {
        guard trimmedQuery.isEmpty else { return nil }
        let titles = contactSections.compactMap(\.indexTitle)
        return titles.isEmpty ? nil : titles
    }

    override func tableView(_: UITableView, sectionForSectionIndexTitle _: String, at index: Int) -> Int {
        index
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != query else { return }
        query = text
        searchTask?.cancel()
        let trimmed = trimmedQuery
        foundContacts = []
        foundPeople = []
        guard !trimmed.isEmpty, contextIsCurrent else {
            isSearching = false
            reload()
            return
        }
        isSearching = true
        reload()
        let client = client
        let allows = allowsPerson
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            let results = await ComposeContacts.search(trimmed, usersOnly: true, client: client)
            guard let self, !Task.isCancelled, contextIsCurrent, trimmedQuery == trimmed else { return }
            foundContacts = results.contacts.filter(allows)
            foundPeople = results.global.compactMap(\.user).filter(allows)
            isSearching = false
            reload()
        }
    }

    private func row(for contact: ComposeContact) -> SettingsRow {
        contact.row { [weak self] in self?.select(contact) }
    }

    private func searchSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if !foundContacts.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Contacts.TopSection"),
                rows: foundContacts.map { self.row(for: $0) },
            ))
        }
        if !foundPeople.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("DialogList.SearchSectionGlobal"),
                rows: foundPeople.map { self.row(for: $0) },
            ))
        }
        if isSearching {
            sections.append(SettingsSection(rows: [Self.loadingRow]))
        } else if sections.isEmpty {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Contacts.Search.NoResults"),
                style: .status(.secondaryLabel),
            )]))
        }
        return sections
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        let allows = allowsPerson
        loadTask = Task { [weak self] in
            let contacts = await ComposeContacts.load(client: client)
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            isLoading = false
            self.contacts = (contacts ?? []).filter(allows)
            contactSections = ComposeContactSection.sections(self.contacts, sort: .name)
            reload()
        }
    }

    private func select(_ contact: ComposeContact) {
        switch mode {
        case .secretChat:
            startSecretChat(with: contact)
        }
    }

    // MARK: Secret chat

    /// ComposeController.openCreateNewSecretChat: createSecretChat, then the chat replaces the compose screens.
    private func startSecretChat(with contact: ComposeContact) {
        guard actionTask == nil, contextIsCurrent else { return }
        searchController.searchBar.resignFirstResponder()
        setBusy(true)
        let client = client
        let userID = contact.userID
        actionTask = Task { [weak self] in
            do {
                let chat = try await client.send(TDNativeRequests.createNewSecretChat(userId: userID))
                let opened = await ComposeContacts.open(chatID: chat.id, client: client) {
                    self?.contextIsCurrent == true
                }
                guard let self else { return }
                actionTask = nil
                setBusy(false)
                if !opened, contextIsCurrent { presentChatListActionFailure() }
            } catch {
                guard let self else { return }
                actionTask = nil
                setBusy(false)
                guard contextIsCurrent else { return }
                let message = (error as? TDLibError)?.message ?? ""
                presentAlert(title: nil, message: L10n.telegram(
                    message.contains("FLOOD") ? "TwoStepAuth.FloodError" : "Login.UnknownError",
                ))
            }
        }
    }

    /// Telegram's displayNavigationActivity while a request runs.
    private func setBusy(_ busy: Bool) {
        tableView.isUserInteractionEnabled = !busy
        if busy {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }
}
