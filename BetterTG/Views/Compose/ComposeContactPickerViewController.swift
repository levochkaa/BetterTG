// ComposeContactPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - ComposeContactPickerViewController

/// Telegram's contact pickers in the compose flow, over the contacts by name and a search with Global Search people.
/// New Secret Chat (ContactSelectionController) starts a secret chat with the tapped person (createNewSecretChat)
/// and opens it in place of the compose screens. New Group (ContactMultiselectionController in `.groupCreation`)
/// checks people, shows them as chips above the list and goes on to the group's name with Next.
/// A new channel's subscribers (`.channelCreation`) join it with Next (addChatMembers), which also skips them.
final class ComposeContactPickerViewController: SettingsListViewController, UISearchResultsUpdating,
ComposeFlowScreen {
    enum Mode {
        /// One person, never a bot.
        case secretChat
        /// The members of a new basic group, which counts the account too.
        case newGroup
        /// People to add to a channel just created; the channel opens after them.
        case channelSubscribers(chatID: Int64)
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
    private let tokenView = ComposeTokenView()
    private var contacts = [ComposeContact]()
    private var contactSections = [ComposeContactSection]()
    private var isLoading = true
    private var query = ""
    private var foundContacts = [ComposeContact]()
    private var foundPeople = [ComposeContact]()
    private var isSearching = false
    /// The checked people, in the order they were checked.
    private var selected = [ComposeContact]()
    /// TDLib's basic_group_size_max: a basic group takes this many members with the account.
    private var basicGroupLimit = 200
    /// TDLib's supergroup_size_max, which Telegram's counter shows.
    private var supergroupLimit = 200_000
    private var tokenWidth: CGFloat = 0
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Who the mode lists: a secret chat is only with a person.
    private var allowsPerson: (ComposeContact) -> Bool {
        switch mode {
        case .channelSubscribers, .secretChat: { !$0.isBot }
        case .newGroup: { _ in true }
        }
    }

    private var isMultipleSelection: Bool {
        switch mode {
        case .secretChat: false
        case .channelSubscribers, .newGroup: true
        }
    }

    private var nextButton: UIBarButtonItem {
        UIBarButtonItem(
            title: L10n.telegram("Common.Next"), style: .prominent, target: self, action: #selector(nextPressed),
        )
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
        case .newGroup:
            title = L10n.telegram("Compose.NewGroupTitle")
            searchController.searchBar.placeholder = L10n.telegram("Compose.GroupTokenListPlaceholder")
            navigationItem.rightBarButtonItem = nextButton
            loadLimits()
        case .channelSubscribers:
            title = L10n.telegram("GroupInfo.AddParticipantTitle")
            searchController.searchBar.placeholder = L10n.telegram("Compose.GroupTokenListPlaceholder")
            navigationItem.rightBarButtonItem = nextButton
        }
        tokenView.onRemove = { [weak self] id in self?.deselect(id) }
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        updateCounter()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if tableView.bounds.width != tokenWidth { updateTokens() }
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

    private static func integerOption(_ name: String, client: TDLibClient) async -> Int? {
        guard case .optionValueInteger(let value) = try? await client.getOption(name: name) else { return nil }
        return Int(clamping: value.value)
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
        let isSelected = selected.contains { $0.userID == contact.userID }
        return contact.row(accessory: isSelected ? .checkmark : .none) { [weak self] in self?.select(contact) }
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

    private func loadLimits() {
        let client = client
        Task { [weak self] in
            let basic = await Self.integerOption("basic_group_size_max", client: client)
            let supergroup = await Self.integerOption("supergroup_size_max", client: client)
            guard let self, contextIsCurrent else { return }
            if let basic, basic > 1 { basicGroupLimit = basic }
            if let supergroup, supergroup > 0 { supergroupLimit = supergroup }
            updateCounter()
        }
    }

    private func select(_ contact: ComposeContact) {
        switch mode {
        case .secretChat:
            startSecretChat(with: contact)
        case .channelSubscribers, .newGroup:
            toggle(contact)
        }
    }

    // MARK: Multiple selection

    /// ContactMultiselectionController.openPeer: a checked person becomes a chip; a search result clears the search.
    private func toggle(_ contact: ComposeContact) {
        if let index = selected.firstIndex(where: { $0.userID == contact.userID }) {
            selected.remove(at: index)
        } else {
            // A basic group counts the account, so Telegram stops one short and explains the supergroup limit.
            if case .newGroup = mode, selected.count + 1 >= basicGroupLimit {
                presentAlert(title: nil, message: L10n.telegram("CreateGroup.SoftUserLimitAlert"))
                return
            }
            selected.append(contact)
        }
        if !trimmedQuery.isEmpty {
            searchController.searchBar.text = ""
            updateSearchResults(for: searchController)
        }
        selectionChanged()
    }

    private func deselect(_ userID: Int64) {
        selected.removeAll { $0.userID == userID }
        selectionChanged()
    }

    private func selectionChanged() {
        updateTokens()
        updateCounter()
        reload()
    }

    private func updateTokens() {
        guard isMultipleSelection, isViewLoaded else { return }
        tokenWidth = tableView.bounds.width
        tokenView.update(tokens: selected.map { ComposeTokenView.Token(id: $0.userID, title: $0.tokenTitle) })
        let height = tokenView.height(forWidth: tokenWidth)
        guard height > 0 else {
            tableView.tableHeaderView = nil
            return
        }
        tokenView.frame = CGRect(x: 0, y: 0, width: tokenWidth, height: height)
        tableView.tableHeaderView = tokenView
    }

    /// CounterControllerTitle: the number checked and the supergroup size.
    private func updateCounter() {
        guard case .newGroup = mode else { return }
        navigationItem.subtitle = "\(selected.count)/\(supergroupLimit)"
    }

    /// ContactMultiselectionController's Next: the checked people go on to the group's name.
    @objc private func nextPressed() {
        guard contextIsCurrent, actionTask == nil, navigationController?.topViewController === self else { return }
        switch mode {
        case .secretChat:
            return
        case .newGroup:
            navigationController?.pushViewController(CreateGroupViewController(members: selected), animated: true)
        case .channelSubscribers(let chatID):
            addSubscribers(to: chatID)
        }
    }

    // MARK: Channel subscribers

    /// ChannelVisibilityController's next in the initial setup: the checked people join (addChatMembers), then the
    /// channel opens in place of the compose screens, also when nobody is checked or adding fails, as in Telegram.
    private func addSubscribers(to chatID: Int64) {
        guard actionTask == nil, contextIsCurrent else { return }
        searchController.searchBar.resignFirstResponder()
        setBusy(true)
        let client = client
        let userIDs = selected.map(\.userID)
        actionTask = Task { [weak self] in
            if !userIDs.isEmpty {
                _ = try? await client.send(TDNativeRequests.addChatMembers(chatId: chatID, userIds: userIDs))
            }
            let opened = await ComposeContacts.open(chatID: chatID, client: client) {
                self?.contextIsCurrent == true
            }
            guard let self else { return }
            actionTask = nil
            setBusy(false)
            // The channel exists; without its chat this flow ends at the chat list.
            if !opened, contextIsCurrent { NavigationStorage.shared.popToRoot() }
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
            navigationItem.rightBarButtonItem = isMultipleSelection ? nextButton : nil
        }
    }
}
