// NewMessageViewController.swift

import TDLibKit
import UIKit

// MARK: - NewMessageViewController

/// Telegram's New Message (ComposeController with ContactListNode's `.natural` presentation): the create actions, then
/// the contacts with their presence, by name under letters or by last seen (ContactsController's Sort menu). The
/// search lists matching contacts and Global Search results (ContactsSearchContainerNode). A contact or result
/// opens its chat in place of this screen.
final class NewMessageViewController: SettingsListViewController, UISearchResultsUpdating, ComposeFlowScreen {
    private static let searchDelay = Duration.milliseconds(250)

    private static var loadingRow: SettingsRow {
        SettingsRow(
            title: L10n.telegram("Channel.NotificationLoading"),
            style: .status(.secondaryLabel),
            accessory: .activity,
        )
    }

    private let searchController = UISearchController(searchResultsController: nil)
    private lazy var sortItem = UIBarButtonItem(
        title: L10n.telegram("Contacts.Sort"),
        style: .plain,
        target: self,
        action: #selector(sortPressed),
    )
    private var contacts = [ComposeContact]()
    private var contactSections = [ComposeContactSection]()
    private var isLoading = true
    private var sort = ComposeContactSort.saved
    private var query = ""
    private var foundContacts = [ComposeContact]()
    private var foundChats = [ComposeFoundChat]()
    private var isSearching = false
    /// Sections above the contacts: the create actions.
    private var contactSectionOffset = 0
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        openTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Compose.NewMessage")
        navigationItem.rightBarButtonItem = sortItem
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("Common.Search")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The presences change while another screen is on top.
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard trimmedQuery.isEmpty else { return searchSections() }
        var sections = [SettingsSection]()
        let options = optionRows()
        if !options.isEmpty { sections.append(SettingsSection(rows: options)) }
        contactSectionOffset = sections.count
        if isLoading, contacts.isEmpty {
            sections.append(SettingsSection(rows: [Self.loadingRow]))
            return sections
        }
        for section in contactSections {
            sections.append(SettingsSection(
                header: section.title,
                rows: section.contacts.map { contact in
                    contact.row { [weak self] in self?.openUser(contact.userID) }
                },
            ))
        }
        return sections
    }

    override func sectionIndexTitles(for _: UITableView) -> [String]? {
        guard trimmedQuery.isEmpty, sort == .name else { return nil }
        let titles = contactSections.compactMap(\.indexTitle)
        return titles.isEmpty ? nil : titles
    }

    override func tableView(_: UITableView, sectionForSectionIndexTitle _: String, at index: Int) -> Int {
        contactSectionOffset + index
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != query else { return }
        query = text
        searchTask?.cancel()
        let trimmed = trimmedQuery
        foundContacts = []
        foundChats = []
        guard !trimmed.isEmpty, contextIsCurrent else {
            isSearching = false
            reload()
            return
        }
        isSearching = true
        reload()
        let client = client
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            let results = await ComposeContacts.search(trimmed, usersOnly: false, client: client)
            guard let self, !Task.isCancelled, contextIsCurrent, trimmedQuery == trimmed else { return }
            foundContacts = results.contacts
            foundChats = results.global
            isSearching = false
            reload()
        }
    }

    /// ComposeControllerNode's options above the contacts.
    private func optionRows() -> [SettingsRow] {
        [
            optionRow("Compose.NewGroup", symbol: "person.2") { [weak self] in
                self?.push(ComposeContactPickerViewController(mode: .newGroup))
            },
            optionRow("Compose.NewEncryptedChat", symbol: "lock") { [weak self] in
                self?.push(ComposeContactPickerViewController(mode: .secretChat))
            },
            optionRow("NewContact.Title", symbol: "person.crop.circle.badge.plus") { [weak self] in
                self?.push(NewContactViewController())
            },
            optionRow("Compose.NewChannel", symbol: "megaphone") { [weak self] in
                self?.push(ChannelIntroViewController())
            },
        ]
    }

    /// ContactListActionItem: an accent title with its icon.
    private func optionRow(_ key: String, symbol: String, action: @escaping () -> Void) -> SettingsRow {
        SettingsRow(title: L10n.telegram(key), style: .action(destructive: false), symbol: symbol, action: action)
    }

    private func push(_ controller: UIViewController) {
        guard contextIsCurrent, navigationController?.topViewController === self else { return }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func searchSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if !foundContacts.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Contacts.TopSection"),
                rows: foundContacts.map { contact in
                    contact.row { [weak self] in self?.openUser(contact.userID) }
                },
            ))
        }
        if !foundChats.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("DialogList.SearchSectionGlobal"),
                rows: foundChats.map { found in
                    SettingsRow(
                        title: found.peer.title,
                        detail: found.detail,
                        style: .peer(found.peer),
                    ) { [weak self] in
                        self?.openChat(found.chatID)
                    }
                },
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
        guard contextIsCurrent, loadTask == nil else { return }
        let client = client
        loadTask = Task { [weak self] in
            let contacts = await ComposeContacts.load(client: client)
            guard let self else { return }
            loadTask = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            isLoading = false
            if let contacts { self.contacts = contacts }
            contactSections = ComposeContactSection.sections(self.contacts, sort: sort)
            reload()
        }
    }

    /// ContactsController's Sort menu, by Last Seen or by Name, growing out of the Sort pill.
    @objc private func sortPressed() {
        guard contextIsCurrent, let source = sortItem.telegramChromeView else { return }
        let current = sort
        let actions = [ComposeContactSort.presence, .name].map { option in
            TelegramContextMenuAction(
                title: L10n.telegram(option == .presence ? "Contacts.Sort.ByLastSeen" : "Contacts.Sort.ByName"),
                image: option == current ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in self?.setSort(option) }
        }
        presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .sourceMorph)
    }

    private func setSort(_ value: ComposeContactSort) {
        guard value != sort else { return }
        sort = value
        ComposeContactSort.saved = value
        contactSections = ComposeContactSection.sections(contacts, sort: value)
        reload()
    }

    // MARK: Opening

    private func openUser(_ userID: Int64) {
        guard openTask == nil, contextIsCurrent else { return }
        let client = client
        openTask = Task { [weak self] in
            let opened = await ComposeContacts.openPrivateChat(userID: userID, client: client) {
                self?.contextIsCurrent == true
            }
            self?.finishOpening(opened)
        }
    }

    private func openChat(_ chatID: Int64) {
        guard openTask == nil, contextIsCurrent else { return }
        let client = client
        openTask = Task { [weak self] in
            let opened = await ComposeContacts.open(chatID: chatID, client: client) {
                self?.contextIsCurrent == true
            }
            self?.finishOpening(opened)
        }
    }

    private func finishOpening(_ opened: Bool) {
        openTask = nil
        if !opened, contextIsCurrent { presentChatListActionFailure() }
    }
}
