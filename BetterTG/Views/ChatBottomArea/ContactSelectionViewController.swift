// ContactSelectionViewController.swift

import Contacts
import TDLibKit
import UIKit

// MARK: - ContactSelectionViewController

/// Telegram's attachment menu Contact (ContactSelectionController with `displayDeviceContacts`,
/// `multipleSelection: .always` and `requirePhoneNumbers`): the account's contacts that show a phone number, by name
/// under letters and with their presence, then the phonebook's other people with a number; ContactListNode's
/// permission rows while the phonebook is closed; ContactsSearchContainerNode's search over both; and checkmarks with
/// ContactSelectionCountPanelNode's Send and count. Send goes out as Telegram's attachment menu sends contacts: several
/// without vCards, one card that is only a name and a number at once, any other card through
/// DeviceContactInfoController's field selection.
final class ContactSelectionViewController: UIViewController, TelegramNavigationSearchProvider,
UISearchResultsUpdating, UITableViewDataSource, UITableViewDelegate {
    // MARK: Private

    private enum Pick {
        case user(ComposeContact)
        case device(DeviceContactEntry)

        var id: PickID {
            switch self {
            case .user(let contact): .user(contact.userID)
            case .device(let entry): .device(entry.identifier)
            }
        }
    }

    private enum PickID: Hashable {
        case user(Int64)
        case device(String)
    }

    private enum Row {
        case permissionInfo
        case permissionButton(String)
        case loading
        case noResults(String)
        case pick(Pick)
    }

    private struct Section {
        var header: String?
        var indexTitle: String?
        var rows: [Row]
    }

    private static let searchDelay = Duration.milliseconds(250)
    private static let searchLimit = 50
    private static let cellIdentifier = "ContactSelectionCell"

    // MARK: Internal

    let telegramNavigationSearch = UISearchController(searchResultsController: nil)
    /// Called once the picker has gone after Cancel or a send; a swipe down reaches the presenter's delegate.
    var onDismiss: (() -> Void)?

    private let client: TDLibClient
    private let accountID: UUID?
    private let send: ([InputMessageContent]) -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let countPanel = ContactSelectionCountPanel()
    private var authorization = CNContactStore.authorizationStatus(for: .contacts)
    private var contacts = [ComposeContact]()
    private var contactSections = [ComposeContactSection]()
    private var isLoading = true
    /// Every phonebook person with a number.
    private var phonebook = [DeviceContactEntry]()
    /// The phonebook people the Telegram contacts don't already show.
    private var deviceContacts = [DeviceContactEntry]()
    private var query = ""
    private var foundContacts = [ComposeContact]()
    private var foundDeviceContacts = [DeviceContactEntry]()
    private var isSearching = false
    /// The checked people, in the order they were checked.
    private var selected = [Pick]()
    private var sections = [Section]()
    private var countPanelShown = false
    private var didFinish = false
    private var loadTask: Task<Void, Never>?
    private var phonebookTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var phonebookIsOpen: Bool {
        authorization == .authorized || authorization == .limited
    }

    init(client: TDLibClient, accountID: UUID?, send: @escaping ([InputMessageContent]) -> Void) {
        self.client = client
        self.accountID = accountID
        self.send = send
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        phonebookTask?.cancel()
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Contacts.Title")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        let search = telegramNavigationSearch
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = L10n.telegram("Common.Search")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.register(SettingsPeerCell.self, forCellReuseIdentifier: SettingsPeerCell.reuseIdentifier)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        countPanel.onSend = { [weak self] in self?.sendPressed() }
        view.addSubview(countPanel)
        // Telegram follows the contacts permission; it can change in Settings while the picker is open.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authorizationChanged),
            name: UIApplication.didBecomeActiveNotification,
            object: nil,
        )
        reload()
        load()
        if phonebookIsOpen { loadPhonebook() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCountPanel()
    }

    /// One of several: a Telegram contact with its number and user ID, a phonebook person with the first number.
    private static func plainContent(for pick: Pick) -> InputMessageContent? {
        switch pick {
        case .user(let contact):
            guard !contact.phoneNumber.isEmpty else { return nil }
            return DeviceContactMessage.content(
                phoneNumber: contact.phoneNumber,
                firstName: contact.firstName,
                lastName: contact.lastName,
                organization: "",
                vcard: "",
                userID: contact.userID,
            )
        case .device(let entry):
            guard let phoneNumber = entry.phoneNumbers.first else { return nil }
            return DeviceContactMessage.content(
                phoneNumber: phoneNumber,
                firstName: entry.firstName,
                lastName: entry.lastName,
                organization: entry.organization,
                vcard: "",
                userID: 0,
            )
        }
    }

    /// ContactsSearchContainerNode's existingNormalizedPhoneNumbers and existingPeerIds: the phonebook people that
    /// none of the shown contacts already is, by number or by the card's Telegram reference.
    private static func phonebookEntries(
        _ entries: [DeviceContactEntry],
        notShownBy shown: [ComposeContact],
    ) -> [DeviceContactEntry] {
        let numbers = Set(shown.map { DeviceContactMessage.normalizedPhoneNumber($0.phoneNumber) })
        let userIDs = Set(shown.map(\.userID))
        return entries.filter { entry in
            if let userID = entry.telegramUserID, userIDs.contains(userID) { return false }
            return !entry.phoneNumbers.contains { numbers.contains(DeviceContactMessage.normalizedPhoneNumber($0)) }
        }
    }

    // MARK: Table

    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.rows.count ?? 0
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[safe: section]?.header
    }

    func sectionIndexTitles(for _: UITableView) -> [String]? {
        let titles = sections.compactMap(\.indexTitle)
        return titles.isEmpty ? nil : titles
    }

    func tableView(_: UITableView, sectionForSectionIndexTitle title: String, at _: Int) -> Int {
        sections.firstIndex { $0.indexTitle == title } ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = row(at: indexPath) else { return UITableViewCell() }
        if case .pick(let pick) = row {
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsPeerCell.reuseIdentifier, for: indexPath)
            let status: (text: String, isOnline: Bool)? =
                switch pick {
                case .user(let contact): contact.statusText
                case .device: nil
                }
            (cell as? SettingsPeerCell)?.configure(
                peer: peer(for: pick),
                detail: status?.text,
                detailColor: status?.isOnline == true ? .systemBlue : nil,
                client: client,
                accountID: accountID,
            )
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.selectionStyle = .default
            cell.accessoryType = isSelected(pick) ? .checkmark : .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .none
        var configuration = UIListContentConfiguration.cell()
        switch row {
        case .permissionInfo:
            configuration = .subtitleCell()
            configuration.text = L10n.telegram("Contacts.PermissionsTitle")
            configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
            configuration.secondaryText = L10n.telegram("Contacts.PermissionsText")
            configuration.secondaryTextProperties.color = .secondaryLabel
            configuration.secondaryTextProperties.numberOfLines = 0
            configuration.textToSecondaryTextVerticalPadding = 3
        case .permissionButton(let title):
            configuration.text = title
            configuration.textProperties.color = .tintColor
            cell.selectionStyle = .default
        case .loading:
            configuration.text = L10n.telegram("Channel.NotificationLoading")
            configuration.textProperties.color = .secondaryLabel
            configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            cell.accessoryView = indicator
        case .noResults(let query):
            configuration = .subtitleCell()
            configuration.text = L10n.telegram("Contacts.Search.NoResults")
            configuration.textProperties.alignment = .center
            configuration.secondaryText = L10n.telegram("Contacts.Search.NoResultsQueryDescription", query)
            configuration.secondaryTextProperties.alignment = .center
            configuration.secondaryTextProperties.color = .secondaryLabel
            configuration.secondaryTextProperties.numberOfLines = 0
            configuration.textToSecondaryTextVerticalPadding = 3
        case .pick:
            break
        }
        cell.contentConfiguration = configuration
        return cell
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch row(at: indexPath) {
        case .permissionButton,
             .pick: true
        case .loading,
             nil,
             .noResults,
             .permissionInfo: false
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch row(at: indexPath) {
        case .pick(let pick): toggle(pick)
        case .permissionButton: authorize()
        case .loading,
             nil,
             .noResults,
             .permissionInfo: break
        }
    }

    // MARK: Search

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        guard text != query else { return }
        query = text
        searchTask?.cancel()
        let trimmed = trimmedQuery
        foundContacts = []
        foundDeviceContacts = []
        guard !trimmed.isEmpty else {
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
            let me = try? await client.getMe()
            let ids = await (try? client.searchContacts(query: trimmed, limit: Self.searchLimit))?.userIds ?? []
            let found = await ComposeContacts.users(ids.filter { $0 != me?.id }, client: client)
            guard let self, !Task.isCancelled, trimmedQuery == trimmed else { return }
            showSearchResults(found, for: trimmed)
        }
    }

    /// ContactsSearchContainerNode with `.cloudContacts` and `.deviceContacts`: the matching contacts with a number,
    /// then the phonebook people whose first or last name starts with the query (DeviceContactDataManager.search),
    /// leaving out the numbers a found contact has and the cards that refer to a found contact.
    private func showSearchResults(_ found: [ComposeContact], for query: String) {
        foundContacts = found.filter { !$0.phoneNumber.isEmpty }
        let prefix = query.lowercased()
        foundDeviceContacts = Self.phonebookEntries(
            phonebook.filter { entry in
                entry.firstName.lowercased().hasPrefix(prefix) || entry.lastName.lowercased().hasPrefix(prefix)
            },
            notShownBy: foundContacts,
        )
        isSearching = false
        reload()
    }

    // MARK: Rows

    private func row(at indexPath: IndexPath) -> Row? {
        sections[safe: indexPath.section]?.rows[safe: indexPath.row]
    }

    private func reload() {
        sections = trimmedQuery.isEmpty ? listSections() : searchSections()
        guard isViewLoaded else { return }
        tableView.reloadData()
    }

    /// ContactListNode's `.natural` list: the permission rows while the phonebook is closed, the contacts under their
    /// letters, then the phonebook (ContactsSearchContainerNode's Phonebook section).
    private func listSections() -> [Section] {
        var result = [Section]()
        // Allow Access asks once; after a refusal the button opens Settings.
        if authorization == .notDetermined || authorization == .denied {
            let button = authorization == .notDetermined
                ? "Permissions.ContactsAllow.v0"
                : "Permissions.ContactsAllowInSettings.v0"
            result.append(Section(rows: [.permissionInfo, .permissionButton(L10n.telegram(button))]))
        }
        if isLoading, contacts.isEmpty {
            result.append(Section(rows: [.loading]))
        }
        result += contactSections.map { section in
            Section(
                header: section.title,
                indexTitle: section.indexTitle,
                rows: section.contacts.map { Row.pick(.user($0)) },
            )
        }
        if !deviceContacts.isEmpty {
            result.append(Section(
                header: L10n.telegram("Contacts.NotRegisteredSection"),
                rows: deviceContacts.map { Row.pick(.device($0)) },
            ))
        }
        return result
    }

    private func searchSections() -> [Section] {
        var result = [Section]()
        if !foundContacts.isEmpty {
            result.append(Section(
                header: L10n.telegram("Contacts.TopSection"),
                rows: foundContacts.map { Row.pick(.user($0)) },
            ))
        }
        if !foundDeviceContacts.isEmpty {
            result.append(Section(
                header: L10n.telegram("Contacts.NotRegisteredSection"),
                rows: foundDeviceContacts.map { Row.pick(.device($0)) },
            ))
        }
        if isSearching {
            result.append(Section(rows: [.loading]))
        } else if result.isEmpty {
            result.append(Section(rows: [.noResults(trimmedQuery)]))
        }
        return result
    }

    private func peer(for pick: Pick) -> SettingsPeer {
        switch pick {
        case .user(let contact):
            contact.peer
        case .device(let entry):
            SettingsPeer.deviceContact(
                identifier: entry.identifier,
                title: entry.title,
                firstName: entry.firstName,
                lastName: entry.lastName,
            )
        }
    }

    // MARK: Loading

    /// getContacts with ContactListFilter's `excludeSelf` and `excludeWithoutPhoneNumbers`.
    private func load() {
        let client = client
        loadTask = Task { [weak self] in
            let loaded = await ComposeContacts.load(client: client)
            guard let self, !Task.isCancelled else { return }
            isLoading = false
            contacts = (loaded ?? []).filter { !$0.phoneNumber.isEmpty }
            contactSections = ComposeContactSection.sections(contacts, sort: .name)
            updateDeviceContacts()
            reload()
        }
    }

    private func loadPhonebook() {
        phonebookTask?.cancel()
        phonebookTask = Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                DeviceContactMessage.phonebookContacts()
            }.value
            guard let self, !Task.isCancelled else { return }
            phonebook = entries
            updateDeviceContacts()
            reload()
        }
    }

    /// ContactListNode's rule for phonebook people: one whose number a Telegram contact has, or whose card refers to
    /// that contact, is that contact.
    private func updateDeviceContacts() {
        deviceContacts = Self.phonebookEntries(phonebook, notShownBy: contacts)
        let shown = Set(deviceContacts.map(\.identifier))
        let previousCount = selected.count
        selected.removeAll { pick in
            guard case .device(let entry) = pick else { return false }
            return !shown.contains(entry.identifier)
        }
        if selected.count != previousCount { updateCountPanel(animated: true) }
    }

    /// ContactListNode's authorize: Allow Access asks for the phonebook, Allow in Settings opens Settings.
    private func authorize() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            Task { [weak self] in
                _ = try? await CNContactStore().requestAccess(for: .contacts)
                self?.authorizationChanged()
            }
        case .denied,
             .restricted:
            guard let url = Foundation.URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .authorized,
             .limited:
            break
        @unknown default:
            break
        }
    }

    @objc private func authorizationChanged() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status != authorization else { return }
        authorization = status
        if phonebookIsOpen {
            loadPhonebook()
        } else {
            phonebookTask?.cancel()
            phonebook = []
            updateDeviceContacts()
        }
        reload()
    }

    // MARK: Selection

    private func isSelected(_ pick: Pick) -> Bool {
        let id = pick.id
        return selected.contains { $0.id == id }
    }

    /// ContactSelectionControllerNode's openPeer: a person is checked or unchecked; a search result also closes the
    /// search.
    private func toggle(_ pick: Pick) {
        let id = pick.id
        if let index = selected.firstIndex(where: { $0.id == id }) {
            selected.remove(at: index)
        } else {
            selected.append(pick)
        }
        if !query.isEmpty {
            telegramNavigationSearch.endTelegramNavigationSearch()
            updateSearchResults(for: telegramNavigationSearch)
        }
        reload()
        updateCountPanel(animated: true)
    }

    // MARK: Count panel

    private func updateCountPanel(animated: Bool) {
        // ContactSelectionCountPanelNode keeps its last number while it slides away.
        if !selected.isEmpty { countPanel.number = selected.count }
        let shown = !selected.isEmpty
        guard shown != countPanelShown else { return }
        countPanelShown = shown
        guard animated, isViewLoaded, view.window != nil else {
            if isViewLoaded { view.setNeedsLayout() }
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.layoutCountPanel()
        }
    }

    private func layoutCountPanel() {
        let bottomInset = view.safeAreaInsets.bottom
        let height = ContactSelectionCountPanel.height(bottomInset: bottomInset)
        countPanel.frame = CGRect(
            x: 0,
            y: view.bounds.height - (countPanelShown ? height : 0),
            width: view.bounds.width,
            height: height,
        )
        let inset = countPanelShown ? height - bottomInset : 0
        guard tableView.contentInset.bottom != inset else { return }
        tableView.contentInset.bottom = inset
        tableView.verticalScrollIndicatorInsets.bottom = inset
    }

    // MARK: Sending

    /// ChatControllerOpenAttachmentMenu's contact result: several people go out without vCards, one goes through its
    /// card.
    private func sendPressed() {
        guard !didFinish, let first = selected.first else { return }
        guard selected.count == 1 else {
            finish(sending: selected.compactMap { Self.plainContent(for: $0) })
            return
        }
        sendSingle(first)
    }

    /// A Telegram contact takes the phonebook card with its number, else its name and number labelled mobile. A card
    /// that is only a name and a number goes out at once; any other card opens its field selection in place of the
    /// picker, as Telegram pushes DeviceContactInfoController once the attachment menu has closed.
    private func sendSingle(_ pick: Pick) {
        let card: CNContact?
        var avatarID = ""
        var userID: Int64 = 0
        var peer: SettingsPeer?
        switch pick {
        case .user(let user):
            userID = user.userID
            peer = user.peer
            let number = DeviceContactMessage.normalizedPhoneNumber(user.phoneNumber)
            let match = number.isEmpty
                ? nil
                : phonebook.first(where: { entry in
                    entry.phoneNumbers.contains { DeviceContactMessage.normalizedPhoneNumber($0) == number }
                })
            avatarID = match?.identifier ?? ""
            card = match.flatMap { DeviceContactMessage.extendedContact(identifier: $0.identifier) }
                ?? DeviceContactMessage.basicContact(
                    firstName: user.firstName,
                    lastName: user.lastName,
                    phoneNumber: user.phoneNumber,
                )
        case .device(let entry):
            avatarID = entry.identifier
            card = DeviceContactMessage.extendedContact(identifier: entry.identifier)
        }
        guard let contact = card, !contact.phoneNumbers.isEmpty else {
            finish(sending: [])
            return
        }
        guard !DeviceContactMessage.isPrimitive(contact) else {
            let content = DeviceContactMessage.content(for: contact, userID: userID, includesVCard: false)
            finish(sending: content.map { [$0] } ?? [])
            return
        }
        guard let navigationController else { return }
        didFinish = true
        let send = send
        let fields = DeviceContactFieldsViewController(
            contact: contact,
            avatarID: avatarID,
            peer: peer,
            userID: userID,
        ) { content in
            send([content])
        }
        fields.onDismiss = onDismiss
        navigationController.setViewControllers([fields], animated: true)
    }

    private func finish(sending contents: [InputMessageContent]) {
        guard !didFinish else { return }
        didFinish = true
        let send = send
        let onDismiss = onDismiss
        dismiss(animated: true) {
            onDismiss?()
            guard !contents.isEmpty else { return }
            send(contents)
        }
    }

    @objc private func cancelPressed() {
        guard !didFinish else { return }
        didFinish = true
        let onDismiss = onDismiss
        dismiss(animated: true) { onDismiss?() }
    }
}

// MARK: - SettingsPeer + device contacts

extension SettingsPeer {
    /// A phonebook card's avatar: Telegram's custom letters, the first name's and the last name's initials, over a
    /// colour kept stable by the card's identifier.
    static func deviceContact(identifier: String, title: String, firstName: String, lastName: String) -> SettingsPeer {
        // FNV-1a, so the colour doesn't change between launches as String's hash does.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        // Negative, so the avatar is never taken for the account's own Saved Messages.
        let id = -Int64(hash >> 2) - 1
        return SettingsPeer(
            id: id,
            title: title,
            file: nil,
            minithumbnail: nil,
            placeholder: TelegramAvatarPlaceholder(
                peerID: id,
                accentColorID: Int(hash % 7),
                upgradedGiftColors: nil,
                letters: [firstName, lastName].compactMap(\.telegramAvatarFirstLetter),
                isDeleted: false,
            ),
        )
    }
}

// MARK: - ContactSelectionCountPanel

/// ContactSelectionCountPanelNode: Send with the number of checked people in an accent badge after it, on the bar
/// material under a separator.
private final class ContactSelectionCountPanel: UIView {
    private final class Button: UIButton {
        override var isHighlighted: Bool {
            didSet { onHighlight?(isHighlighted) }
        }

        var onHighlight: ((Bool) -> Void)?
    }

    private static let buttonHeight: CGFloat = 44
    private static let badgeHeight: CGFloat = 22

    var onSend: (() -> Void)?

    var number = 0 {
        didSet {
            guard number != oldValue else { return }
            badgeLabel.text = String(number)
            button.accessibilityValue = String(number)
            setNeedsLayout()
        }
    }

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let separator = UIView()
    private let button = Button(type: .system)
    private let badgeLabel = UILabel()
    private let titleFont = UIFont.systemFont(ofSize: 17, weight: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        separator.backgroundColor = .separator
        addSubview(separator)
        button.setTitle(L10n.telegram("ShareMenu.Send"), for: .normal)
        button.titleLabel?.font = titleFont
        button.accessibilityLabel = L10n.telegram("ShareMenu.Send")
        button.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        button.onHighlight = { [weak self] highlighted in
            self?.badgeLabel.alpha = highlighted ? 0.4 : 1
        }
        addSubview(button)
        badgeLabel.font = .systemFont(ofSize: 14)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = tintColor
        badgeLabel.layer.cornerRadius = Self.badgeHeight / 2
        badgeLabel.clipsToBounds = true
        badgeLabel.isUserInteractionEnabled = false
        badgeLabel.isAccessibilityElement = false
        addSubview(badgeLabel)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        let pixel = 1 / traitCollection.displayScale
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: pixel)
        let buttonFrame = CGRect(
            x: safeAreaInsets.left,
            y: 0,
            width: max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right),
            height: Self.buttonHeight,
        )
        button.frame = buttonFrame
        let title = (button.title(for: .normal) ?? "") as NSString
        let titleWidth = ceil(title.size(withAttributes: [.font: titleFont]).width)
        let textWidth = ceil(badgeLabel.sizeThatFits(CGSize(width: 100, height: Self.badgeHeight)).width)
        badgeLabel.frame = CGRect(
            x: buttonFrame.midX + titleWidth / 2 + 6,
            y: buttonFrame.maxY - 33,
            width: max(Self.badgeHeight, textWidth + 11),
            height: Self.badgeHeight,
        )
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        badgeLabel.backgroundColor = tintColor
    }

    /// ContactSelectionCountPanelNode's height: the button, then 9 pt below it, 4 of them inside the home indicator's
    /// inset.
    static func height(bottomInset: CGFloat) -> CGFloat {
        buttonHeight + bottomInset + (bottomInset > 0 ? 5 : 9)
    }

    @objc private func sendPressed() {
        onSend?()
    }
}
