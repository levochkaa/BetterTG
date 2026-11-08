// SettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - SettingsViewController

/// Telegram's Settings (PeerInfoScreen in settings mode): the account's profile, its accounts, the side menu bots,
/// Saved Messages, Devices and Chat Folders, then Notifications, Privacy, Data and Storage, Appearance and Language.
final class SettingsViewController: UITableViewController, TelegramConditionalNavigationSearchProvider,
UISearchResultsUpdating, UISearchControllerDelegate {
    private static let sectionGap: CGFloat = 20
    private static let blankIcon = UIGraphicsImageRenderer(size: CGSize(width: 25, height: 25)).image { _ in }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private var me: User?
    private var meAccountID: UUID?
    private var sessionCount: Int?

    private var loadTask: Task<Void, Never>?
    /// The Settings bots' launcher, for the account and client it was made for.
    private var appLauncher: (source: TdUpdateSource, launcher: WebAppLauncher)?
    /// The settings search, open from the bar's search button until its close button.
    private lazy var search: UISearchController = {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.delegate = self
        search.searchBar.placeholder = L10n.telegram("Common.Search")
        return search
    }()

    private var isSearching = false
    private var searchQuery = ""
    private var searchItems = [SettingsSearchItem]()
    /// The found items, or with an empty query the recent ones and the FAQ's questions.
    private var searchSections = [SettingsSearchSection]()
    /// The FAQ's questions, loaded once a search opens.
    private var faqItems = [SettingsSearchItem]()
    /// How far the list stood below its top when the search opened, to stand there again once it closes.
    private var listScroll: CGFloat?

    var shownTelegramNavigationSearch: UISearchController? {
        isSearching ? search : nil
    }

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.Title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 58, bottom: 0, right: 0)
        // Every gap between sections is one header: no padding above headers and no empty footers. Without estimates
        // the
        // delegate's heights are exact; self-sizing gave every header and footer the system's 17 pt instead.
        tableView.sectionHeaderTopPadding = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.register(SettingsProfileCell.self, forCellReuseIdentifier: SettingsProfileCell.reuseIdentifier)
        updateBarButtons()

        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.loadAccountState()
        }
        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            guard let self else { return }
            title = L10n.telegram("Settings.Title")
            // An open search finds the items in the new language.
            if isSearching {
                searchItems = SettingsSearch.items()
                updateSearchResults()
            } else {
                tableView.reloadData()
            }
        }
        SuggestedActionsStore.shared
            .changes
            .sink { [weak self] in self?.tableView.reloadData() }
            .store(in: &cancellables)
        AttachmentMenuBotStore.shared
            .changes
            .sink { [weak self] in self?.tableView.reloadData() }
            .store(in: &cancellables)
        ProxyStatusStore.shared
            .$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    /// UITableViewController scrolls a short list past its top as the keyboard comes up; the search results keep to
    /// the top unless a finger moves them.
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isSearching, !scrollView.isTracking, !scrollView.isDecelerating else { return }
        let top = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y < top { scrollView.contentOffset.y = top }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        loadAccountState()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        isSearching ? searchSections.count : Section.allCases.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        isSearching ? searchSections[safe: section]?.items.count ?? 0 : rows(in: section).count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        isSearching ? nil : Section(rawValue: section)?.title
    }

    /// ChatListSearchItemHeader over the recent items, Recent with Clear, and over the FAQ's questions.
    override func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard isSearching, let kind = searchSections[safe: section]?.kind else { return nil }
        switch kind {
        case .results:
            return nil
        case .recent:
            return SettingsSearchHeaderView(title: L10n.telegram("DialogList.SearchSectionRecent")) { [weak self] in
                SettingsSearch.clearRecents()
                self?.updateSearchResults()
            }
        case .faq:
            return SettingsSearchHeaderView(title: L10n.telegram("Settings.FrequentlyAskedQuestions"))
        }
    }

    /// The same gap above every section, a title's header taller by its line; an account without side menu bots
    /// shows no gap for their section.
    override func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if isSearching {
            return searchSections[safe: section]?.kind == .results ? Self.sectionGap : SettingsSearchHeaderView.height
        }
        if isEmptyAppsSection(section) { return .leastNormalMagnitude }
        return Section(rawValue: section)?.title == nil ? Self.sectionGap : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard !isSearching, !isEmptyAppsSection(section),
              self.tableView(tableView, titleForFooterInSection: section) != nil
        else {
            return .leastNormalMagnitude
        }
        return UITableView.automaticDimension
    }

    override func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching { return searchCell(at: indexPath) }
        if Section(rawValue: indexPath.section) == .profile {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsProfileCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? SettingsProfileCell)?.configure(
                user: meAccountID == TDLib.shared.activeAccountID ? me : nil,
                client: TDLib.shared.activeClient,
                accountID: TDLib.shared.activeAccountID,
            )
            (cell as? SettingsProfileCell)?.onLongPress = { [weak self, weak cell] in
                guard let cell else { return }
                self?.openProfileCopyMenu(from: cell)
            }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        guard let row = rows(in: indexPath.section)[safe: indexPath.row] else { return cell }

        var configuration = cell.defaultContentConfiguration()
        if row.showsValue {
            configuration = .valueCell()
        }
        configuration.text = row.title
        configuration.secondaryText = row == .devices ? Self.devicesLabel(sessionCount: sessionCount) : row.subtitle
        configuration.image = UIImage(systemName: row.symbolName)
        configuration.imageProperties.tintColor = row.tintColor
        configuration.imageProperties.maximumSize = CGSize(width: 25, height: 25)
        configuration.textProperties.color = row.isDestructive ? .systemRed : .label
        configuration.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = configuration
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityValue = nil
        cell.selectionStyle = row.isSelectable ? .default : .none

        switch row {
        case .account(let id):
            cell.accessoryType = id == TDLib.shared.activeAccountID ? .checkmark : .none
        case .addAccount,
             .addTestServerAccount,
             .setPhoto,
             .setUsername:
            // PeerInfoScreenActionItem: an accent action.
            configuration.textProperties.color = .systemBlue
            cell.contentConfiguration = configuration
        case .app(let botUserID):
            configureApp(cell, configuration: configuration, botUserID: botUserID)
        case .appearance,
             .chatFolders,
             .dataAndStorage,
             .devices,
             .faq,
             .language,
             .licenses,
             .myProfile,
             .notifications,
             .powerSaving,
             .privacy,
             .privacyPolicy,
             .proxy,
             .savedMessages,
             .support,
             .termsOfService,
             .tips:
            cell.accessoryType = .disclosureIndicator
        case .betterTG:
            cell.accessoryType = .disclosureIndicator
        case .suggestionInfo(let reminder):
            configuration = .subtitleCell()
            configuration.text = suggestionTitle(reminder)
            configuration.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
            configuration.secondaryText = Self.suggestionText(reminder)
            configuration.secondaryTextProperties.font = .systemFont(ofSize: 15)
            configuration.secondaryTextProperties.color = .secondaryLabel
            configuration.textToSecondaryTextVerticalPadding = 4
            cell.contentConfiguration = configuration
        case .suggestionAction,
             .suggestionKeep:
            if row == .suggestionKeep(.checkPhoneNumber) {
                configuration.text = L10n.telegram("Settings.KeepPhoneNumber", "+" + (me?.phoneNumber ?? ""))
            }
            configuration.textProperties.color = .tintColor
            cell.contentConfiguration = configuration
        case .logOut,
             .profile,
             .version:
            break
        }
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if isSearching {
            guard let item = searchSections[safe: indexPath.section]?.items[safe: indexPath.row] else { return }
            SettingsSearch.addRecent(item.id)
            open(item.target)
            // A setting inside a screen shows where it is there.
            if !item.breadcrumbs.isEmpty,
               let screen = navigationController?.topViewController as? SettingsListViewController
            {
                screen.focusedRowTitle = item.title
            }
            return
        }
        guard let row = rows(in: indexPath.section)[safe: indexPath.row] else { return }
        perform(row, from: indexPath)
    }

    /// A recent item leaves the list with Delete, as SettingsSearchRecentItem's revealed option does.
    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard isSearching, let section = searchSections[safe: indexPath.section], section.kind == .recent,
              let item = section.items[safe: indexPath.row] else { return nil }
        let delete = UIContextualAction(style: .destructive, title: L10n.telegram("Common.Delete")) {
            [weak self] _, _, completion in
            SettingsSearch.removeRecent(item.id)
            self?.updateSearchResults()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    /// PeerInfoSettingsItems' devicesLabel: the sessions with this one, or Add Device while it is the only one (QR
    /// login stays on in BetterTG's Devices).
    private static func devicesLabel(sessionCount: Int?) -> String? {
        guard let sessionCount else { return nil }
        return sessionCount <= 1 ? L10n.telegram("Settings.AddDevice") : String(sessionCount)
    }

    /// The text without its Markdown link brackets.
    private static func suggestionText(_ reminder: SuggestedActionsStore.Reminder) -> String {
        let key =
            switch reminder {
            case .checkPhoneNumber: "Settings.CheckPhoneNumberText"
            case .checkPassword: "Settings.CheckPasswordText"
            case .setPassword: "Settings.SuggestSetupPasswordText"
            }
        return L10n.telegram(key).replacingOccurrences(
            of: #"\[([^\]]*)\]\(\)"#,
            with: "$1",
            options: .regularExpression,
        )
    }

    func updateSearchResults(for search: UISearchController) {
        searchQuery = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateSearchResults()
    }

    /// The close button ends the search, and the bar's buttons come back.
    func didDismissSearchController(_: UISearchController) {
        guard isSearching else { return }
        isSearching = false
        searchQuery = ""
        searchSections = []
        updateBarButtons()
        tableView.reloadData()
        // The bar gives up the field's height on its next refresh; the list goes back after it.
        let listScroll = listScroll
        self.listScroll = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, !isSearching, let listScroll else { return }
            tableView.layoutIfNeeded()
            tableView.contentOffset.y = listScroll - tableView.adjustedContentInset.top
        }
    }

    /// What a Settings row opens; `indexPath` places Log Out's sheet beside its row.
    private func perform(_ row: Row, from _: IndexPath?) {
        switch row {
        case .account(let id):
            guard id != TDLib.shared.activeAccountID else { return }
            performAccountOperation { try TDLib.shared.switchToAccount(id) }
        case .addAccount:
            performAccountOperation { try TDLib.shared.addAccount() }
        case .addTestServerAccount:
            performAccountOperation { try TDLib.shared.addAccount(usesTestServer: true) }
        case .app(let botUserID):
            openBotApp(botUserID)
        case .appearance:
            navigationController?.pushViewController(AppearanceViewController(), animated: true)
        case .language:
            navigationController?.pushViewController(LanguageSelectionViewController(), animated: true)
        case .powerSaving:
            navigationController?.pushViewController(PowerSavingViewController(), animated: true)
        case .profile:
            navigationController?.pushViewController(EditProfileViewController(), animated: true)
        case .setPhoto:
            // openSettings(.avatar): the photo's choices, over the profile editor that sets it.
            let profile = EditProfileViewController()
            profile.opening = .photo
            navigationController?.pushViewController(profile, animated: true)
        case .setUsername:
            navigationController?.pushViewController(UsernameSetupViewController(), animated: true)
        case .myProfile:
            openMyProfile()
        case .proxy:
            navigationController?.pushViewController(ProxySettingsViewController(), animated: true)
        case .savedMessages:
            openSavedMessages()
        case .devices:
            navigationController?.pushViewController(ActiveSessionsViewController(), animated: true)
        case .chatFolders:
            navigationController?.pushViewController(ChatFoldersViewController(rootVM: .shared), animated: true)
        case .notifications:
            navigationController?.pushViewController(NotificationSettingsViewController(), animated: true)
        case .privacy:
            navigationController?.pushViewController(PrivacySettingsViewController(), animated: true)
        case .dataAndStorage:
            navigationController?.pushViewController(DataAndStorageViewController(), animated: true)
        case .support:
            confirmSupport()
        case .faq:
            TelegramSupport.openFaq(from: self)
        case .tips:
            // PeerInfoScreen's openTips: Telegram's features channel by its username.
            if let url = URL(string: "https://t.me/" + L10n.telegram("Settings.TipsUsername")) {
                TelegramLinkRouter.shared.open(url, from: self)
            }
        case .licenses:
            navigationController?.pushViewController(LicensesViewController(), animated: true)
        case .privacyPolicy:
            if let url = URL(string: "https://bettertg.su/privacy") { WebBrowser.open(url, from: self) }
        case .termsOfService:
            if let url = URL(string: "https://bettertg.su/terms") { WebBrowser.open(url, from: self) }
        case .logOut:
            // PeerInfoScreenSettingsActions' logout: the alternatives first (LogoutOptionsController).
            LogoutOptionsViewController.present(from: self) { [weak self] in
                self?.performAccountOperation { try TDLib.shared.logOutActiveAccount() }
            }
        case .suggestionInfo(let reminder):
            // The phone reminder's Learn more opens the FAQ's answer on a new number.
            guard reminder == .checkPhoneNumber,
                  let base = L10n.telegram("Settings.FAQ_URL").split(separator: "#").first,
                  let url = URL(string: base + "#" + L10n.telegram("Settings.CheckPhoneNumberFAQAnchor"))
            else { return }
            WebBrowser.open(url, from: self)
        case .suggestionKeep(let reminder):
            guard let source = TDLib.shared.activeUpdateSource else { return }
            SuggestedActionsStore.shared.dismiss(reminder, client: TDLib.shared.activeClient, source: source)
        case .suggestionAction:
            openTwoStepVerification()
        case .betterTG:
            navigationController?.pushViewController(BetterTGSettingsViewController(), animated: true)
        case .version:
            break
        }
    }

    /// peerInfoNavigationButtonSets' settings bar: QR Code on the left, then search and Edit on the right; an open
    /// search takes the row. Pushed, it keeps Back on the left.
    private func updateBarButtons() {
        guard !isSearching else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItems = nil
            return
        }
        let qrCode = UIBarButtonItem(
            image: UIImage(systemName: "qrcode"),
            primaryAction: UIAction { [weak self] _ in self?.openQRCode() },
        )
        qrCode.accessibilityLabel = L10n.telegram("PeerInfo.QRCode.Title")
        // Swiftgram's Settings pushed over Chats while its tab is hidden: Back takes the left, and QR Code stands
        // beside
        // the right items.
        let isPushed = !(parent is MainTabsViewController)
        navigationItem.leftBarButtonItem = isPushed ? nil : qrCode
        let edit = UIBarButtonItem.telegramEdit(primaryAction: UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(EditProfileViewController(), animated: true)
        })
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            primaryAction: UIAction { [weak self] _ in self?.openSearch() },
        )
        searchButton.accessibilityLabel = L10n.telegram("Common.Search")
        navigationItem.rightBarButtonItems = isPushed ? [edit, searchButton, qrCode] : [edit, searchButton]
    }

    /// The search button: the field takes the row with the keyboard up, and the list gives way to the recent items.
    private func openSearch() {
        guard !isSearching else { return }
        searchItems = SettingsSearch.items()
        listScroll = tableView.contentOffset.y + tableView.adjustedContentInset.top
        isSearching = true
        searchQuery = ""
        updateSearchResults()
        updateBarButtons()
        search.beginTelegramNavigationSearch()
        guard faqItems.isEmpty else { return }
        Task { [weak self] in
            let items = await SettingsSearch.faqItems()
            guard let self else { return }
            faqItems = items
            if isSearching { updateSearchResults() }
        }
    }

    private func updateSearchResults() {
        guard isSearching else { return }
        if searchQuery.isEmpty {
            let byID = Dictionary((searchItems + faqItems).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let recent = SettingsSearch.recentIDs.compactMap { byID[$0] }
            searchSections = [
                SettingsSearchSection(kind: .recent, items: recent),
                SettingsSearchSection(kind: .faq, items: faqItems),
            ].filter { !$0.items.isEmpty }
        } else {
            // The settings first, then the FAQ's questions, Delete My Account's first among them.
            var faq = SettingsSearch.search(faqItems, query: searchQuery)
            if let index = faq.firstIndex(where: { $0.id.contains("delete-my-account") }) {
                faq.insert(faq.remove(at: index), at: 0)
            }
            let results = SettingsSearch.search(searchItems, query: searchQuery) + faq
            searchSections = results.isEmpty ? [] : [SettingsSearchSection(kind: .results, items: results)]
        }
        tableView.reloadData()
        tableView.contentOffset.y = -tableView.adjustedContentInset.top
    }

    /// SettingsSearchResultItem: the section's icon on the first of a run of items from one section, the title, and
    /// the screens above it joined by arrows; a recent item has no icon.
    private func searchCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        guard let section = searchSections[safe: indexPath.section], let item = section.items[safe: indexPath.row]
        else { return cell }
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = item.title
        configuration.secondaryText = item.breadcrumbs.isEmpty ? nil : item.breadcrumbs.joined(separator: " → ")
        configuration.secondaryTextProperties.color = .secondaryLabel
        if section.kind == .results {
            let previous = indexPath.row > 0 ? section.items[safe: indexPath.row - 1] : nil
            // A clear image keeps the run's titles in line under the icon.
            configuration.image = previous?.icon == item.icon
                ? Self.blankIcon
                : UIImage(systemName: item.icon.symbolName)
            configuration.imageProperties.tintColor = item.icon.tintColor
            configuration.imageProperties.maximumSize = CGSize(width: 25, height: 25)
            configuration.imageProperties.reservedLayoutSize = CGSize(width: 25, height: 25)
        }
        cell.contentConfiguration = configuration
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityValue = nil
        cell.selectionStyle = .default
        return cell
    }

    private func open(_ target: SettingsSearchItem.Target) {
        switch target {
        case .row(let row):
            perform(row, from: nil)
        case .screen(let make):
            navigationController?.pushViewController(make(), animated: true)
        case .twoStepVerification:
            openTwoStepVerification()
        case .passcode:
            if let navigationController { PasscodeOptionsViewController.open(in: navigationController) }
        case .faq(let url):
            WebBrowser.open(url, from: self)
        case .language(let language):
            guard language.id != AppLocalization.shared.selectedLanguagePackID else { return }
            Task { [weak self] in
                do {
                    try await AppLocalization.shared.apply(language)
                } catch {
                    self?.showError(error.localizedDescription)
                }
            }
        case .deleteAccount:
            // deleteAccountOptionsController, which asks for the password when there is one.
            let client = TDLib.shared.activeClient
            Task { [weak self] in
                let password = try? await client.send(TDNativeRequests.getPasswordState())
                guard let self else { return }
                DeleteAccountOptionsViewController.present(hasPassword: password?.hasPassword ?? false, from: self)
            }
        }
    }

    /// The header's displayCopyContextMenu: a long press on the account offers Copy Phone Number (formatted) and Copy
    /// Username, each with its toast.
    private func openProfileCopyMenu(from cell: UIView) {
        guard let me, meAccountID == TDLib.shared.activeAccountID, presentedViewController == nil else { return }
        var actions = [TelegramContextMenuAction]()
        let client = TDLib.shared.activeClient
        if !me.phoneNumber.isEmpty {
            let phone = me.phoneNumber
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Settings.CopyPhoneNumber"), image: UIImage(systemName: "phone"),
            ) { [weak self] in
                Task { [weak self] in
                    UIPasteboard.general.string = await PhoneNumberFormat.international(phone, client: client)
                        ?? "+" + phone
                    self?.showCopyToast(L10n.telegram("Conversation.PhoneCopied"))
                }
            })
        }
        if let username = me.usernames?.editableUsername, !username.isEmpty {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Settings.CopyUsername"), image: UIImage(systemName: "at"),
            ) { [weak self] in
                UIPasteboard.general.string = "@\(username)"
                self?.showCopyToast(L10n.telegram("Conversation.UsernameCopied"))
            })
        }
        guard !actions.isEmpty else { return }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func showCopyToast(_ text: String) {
        guard let view = navigationController?.view ?? view else { return }
        // Above the root's tab bar, as the chat list's toasts stand.
        TelegramUndoToast.show(text: text, in: view, bottomInset: 66, undo: nil)
    }

    /// openQrCode from the settings bar: the account's own code, by its first active username or, with none, by the
    /// link TDLib gives.
    private func openQRCode() {
        guard let me else { return }
        var username = me.usernames?.activeUsernames.first
        #if DEBUG
            // `-ui-probe-qr-temporary` leaves the username out, so the code comes from getUserLink.
            if ProcessInfo.processInfo.arguments.contains("-ui-probe-qr-temporary") { username = nil }
        #endif
        let screen = PeerQRCodeViewController(
            username: username,
            peer: SettingsPeer(
                id: me.id,
                title: [me.firstName, me.lastName].filter { !$0.isEmpty }.joined(separator: " "),
                file: me.profilePhoto?.small,
                minithumbnail: me.profilePhoto?.minithumbnail,
                placeholder: me.telegramAvatarPlaceholder,
            ),
            client: TDLib.shared.activeClient,
            accountID: TDLib.shared.activeAccountID,
        )
        navigationController?.pushViewController(screen, animated: true)
    }

    /// Settings' rememberPassword and passwordSetup both reach the password's screen: entering it there proves it is
    /// remembered; without one it opens the setup.
    private func openTwoStepVerification() {
        let service = TDLibTwoStepVerificationService(client: TDLib.shared.activeClient)
        Task { [weak self] in
            let configuration = try? await service.configuration()
            guard let self else { return }
            navigationController?.pushViewController(
                TwoStepVerificationViewController.entry(for: configuration, service: service),
                animated: true,
            )
        }
    }

    private func suggestionTitle(_ reminder: SuggestedActionsStore.Reminder) -> String {
        switch reminder {
        case .checkPhoneNumber:
            L10n.telegram("Settings.CheckPhoneNumberTitle", "+" + (me?.phoneNumber ?? ""))
        case .checkPassword:
            L10n.telegram("Settings.CheckPasswordTitle")
        case .setPassword:
            L10n.telegram("Settings.SuggestSetupPasswordTitle")
        }
    }

    private func rows(in sectionIndex: Int) -> [Row] {
        guard let section = Section(rawValue: sectionIndex) else { return [] }
        switch section {
        case .profile:
            return TDLib.shared.activeAccountID == nil ? [] : [.profile]
        case .edit:
            guard TDLib.shared.activeAccountID != nil, let me, meAccountID == TDLib.shared.activeAccountID else {
                return []
            }
            let hasUsername = me.usernames?.activeUsernames.contains { !$0.isEmpty } == true
            return [.setPhoto(hasPhoto: me.profilePhoto != nil)] + (hasUsername ? [] : [.setUsername])
        case .suggestion:
            guard TDLib.shared.activeAccountID != nil,
                  let reminder = SuggestedActionsStore.shared.reminder(for: TDLib.shared.activeUpdateSource)
            else { return [] }
            // Change Number has no flow in BetterTG, so the phone reminder offers only Keep.
            return switch reminder {
            case .checkPhoneNumber: [.suggestionInfo(reminder), .suggestionKeep(reminder)]
            case .checkPassword: [.suggestionInfo(reminder), .suggestionKeep(reminder), .suggestionAction(reminder)]
            case .setPassword: [.suggestionInfo(reminder), .suggestionAction(reminder)]
            }
        case .accounts:
            let accountRows: [Row] = TDLib.shared.sortedAccounts.map { .account($0.id) }
            #if DEBUG
                // Telegram's debug accounts screen logs in on Production or Test.
                if ReadmeDemo.isActive { return accountRows + [.addAccount] }
                return accountRows + [.addAccount, .addTestServerAccount]
            #else
                return accountRows + [.addAccount]
            #endif
        case .myProfile:
            return TDLib.shared.activeAccountID == nil ? [] : [.myProfile]
        case .apps:
            return appEntries().map { .app($0.bot.botUserId) }
        case .proxy:
            // PeerInfoSettingsItems shows the proxy, after My Profile, once a server is saved.
            return TDLib.shared.activeAccountID != nil && ProxyStatusStore.shared.state.hasProxy ? [.proxy] : []
        case .shortcuts:
            return TDLib.shared.activeAccountID == nil ? [] : [.savedMessages, .devices, .chatFolders]
        case .appearance:
            let accountRows: [Row] = TDLib.shared.activeAccountID == nil
                ? []
                : [.notifications, .privacy, .dataAndStorage]
            return accountRows + [.appearance, .powerSaving, .language]
        case .support:
            return TDLib.shared.activeAccountID == nil ? [] : [.support, .faq, .tips]
        case .media:
            return [.betterTG]
        case .about:
            return [.version, .licenses, .privacyPolicy, .termsOfService]
        case .accountActions:
            return [.logOut]
        }
    }

    /// The profile header and the Devices count, read again whenever Settings shows.
    private func loadAccountState() {
        tableView.reloadData()
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            async let meRequest = client.getMe()
            async let sessionsRequest = client.send(TDNativeRequests.getActiveSessions())
            let me = try? await meRequest
            let sessions = try? await sessionsRequest
            guard let self, !Task.isCancelled, TDLib.shared.activeAccountID == accountID else { return }
            if let me {
                self.me = me
                meAccountID = accountID
            }
            sessionCount = sessions?.sessions.count
            tableView.reloadData()
        }
    }

    /// A section that shows only for some accounts, side menu bots or a saved proxy, leaves no gap when empty.
    private func isEmptyAppsSection(_ section: Int) -> Bool {
        [.apps, .proxy].contains(Section(rawValue: section)) && rows(in: section).isEmpty
    }

    /// PeerInfoData's settings bots: the account's attachment menu bots shown in the side menu (`.showInSettings`),
    /// in the list's order.
    private func appEntries() -> [AttachmentMenuBotStore.Entry] {
        guard TDLib.shared.activeAccountID != nil, let source = TDLib.shared.activeUpdateSource else { return [] }
        return AttachmentMenuBotStore.shared.entries(for: source).filter(\.bot.showInSideMenu)
    }

    /// PeerInfoSettingsItems' app row: the bot's short name and its side menu icon with 8 pt corners at Telegram's
    /// 30 pt (scaled to the other rows' icons), and a NEW title badge while the bot isn't added or its disclaimer
    /// stands.
    private func configureApp(
        _ cell: UITableViewCell,
        configuration: UIListContentConfiguration,
        botUserID: Int64,
    ) {
        var configuration = configuration
        cell.accessoryType = .disclosureIndicator
        guard let accountID = TDLib.shared.activeAccountID,
              let bot = appEntries().first(where: { $0.bot.botUserId == botUserID })
        else { return }
        let showsBadge = !bot.bot.isAdded
            || AttachmentMenuBotStore.shared.showsSideMenuDisclaimer(for: bot.bot, accountID: accountID)
        let badge = L10n.telegram("Settings.New")
        configuration.attributedText = appTitle(bot.bot.name, badge: showsBadge ? badge : nil)
        if let path = bot.imageIconPath, let icon = UIImage(contentsOfFile: path) {
            configuration.image = icon.withRenderingMode(.alwaysOriginal)
            configuration.imageProperties.cornerRadius = 25 * 8 / 30
        }
        cell.contentConfiguration = configuration
        cell.accessibilityValue = showsBadge ? badge : nil
    }

    /// PeerInfoScreenDisclosureItem's `.titleBadge`: the text in medium 11 white on the accent colour, 4 pt wider
    /// and 2 pt taller on each side, with 5 pt corners, 6 pt after the title.
    private func appTitle(_ title: String, badge: String?) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: UIColor.label],
        )
        guard let badge else { return result }
        let text = NSAttributedString(string: badge, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.white,
        ])
        let textSize = text.size()
        let badgeSize = CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height) + 4)
        let spacing: CGFloat = 6
        let fill = UIColor.systemBlue.resolvedColor(with: traitCollection)
        let canvas = CGSize(width: spacing + badgeSize.width, height: badgeSize.height)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            let rect = CGRect(origin: CGPoint(x: spacing, y: 0), size: badgeSize)
            fill.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
            text.draw(at: CGPoint(
                x: rect.minX + (badgeSize.width - textSize.width) / 2,
                y: (badgeSize.height - textSize.height) / 2,
            ))
        }
        let attachment = NSTextAttachment(image: image)
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: (font.capHeight - canvas.height) / 2), size: canvas)
        result.append(NSAttributedString(attachment: attachment))
        return result
    }

    /// PeerInfoScreen's `openBotApp`: the bot's terms or side menu disclaimer when due, then its Web App at full
    /// size for the account.
    private func openBotApp(_ botUserID: Int64) {
        guard let source = TDLib.shared.activeUpdateSource,
              let entry = AttachmentMenuBotStore.shared.entry(botUserID: botUserID, source: source),
              let client = TDLib.shared.authorizationClient(for: source)
        else { return }
        let launcher: WebAppLauncher
        if let appLauncher, appLauncher.source == source {
            launcher = appLauncher.launcher
        } else {
            launcher = WebAppLauncher(host: .init(
                accountID: source.accountID,
                client: client,
                presenter: { [weak self] in self },
                isCurrent: { [weak self] in self != nil && TDLib.shared.activeUpdateSource == source },
                actions: .init(
                    openTelegramLink: { [weak self] url in TelegramLinkRouter.shared.open(url, from: self) },
                    switchInline: { _, _ in },
                ),
            ))
            appLauncher = (source, launcher)
        }
        launcher.openSettingsWebApp(bot: entry.bot)
    }

    /// PeerInfoScreenSettingsActions' `.profile`: the account's own PeerInfoScreen with `isMyProfile`.
    private func openMyProfile() {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            guard let me = try? await client.getMe(),
                  let chat = try? await client.createPrivateChat(force: false, userId: me.id),
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  let self, TDLib.shared.activeAccountID == accountID
            else { return }
            let profile = PeerProfileViewController(
                customChat: customChat, topic: nil, client: client, accountID: accountID, isMyProfile: true,
            )
            navigationController?.pushViewController(profile, animated: true)
        }
    }

    /// Telegram's Saved Messages row opens the account's own chat.
    private func openSavedMessages() {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            guard let me = try? await client.getMe(),
                  let chat = try? await client.createPrivateChat(force: false, userId: me.id),
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  self != nil, TDLib.shared.activeAccountID == accountID
            else { return }
            NavigationStorage.shared.push(.customChat(customChat))
        }
    }

    /// PeerInfoScreen's `.support`: the note that volunteers answer, with FAQ, then OK opens the support chat.
    private func confirmSupport() {
        present(TelegramSupport.alert(
            openFaq: { [weak self] in self.map(TelegramSupport.openFaq) },
            openChat: { [weak self] in self.map(TelegramSupport.openChat) },
        ), animated: true)
    }

    private func performAccountOperation(_ operation: @escaping @MainActor () throws -> Void) {
        Task { @MainActor [weak self] in
            do {
                try operation()
            } catch {
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: L10n.betterTG("Accounts.ErrorTitle"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

extension SettingsViewController {
    fileprivate enum Section: Int, CaseIterable {
        case profile
        /// PeerInfoSettingsItems' `.edit` section: setting the photo, and a username while there is none.
        case edit
        /// PeerInfoSettingsItems' `.phone` section: the server's phone number or password reminder.
        case suggestion
        case accounts
        case myProfile
        case proxy
        case apps
        case shortcuts
        case appearance
        case support
        case media
        case about
        case accountActions

        // MARK: Internal

        var title: String? {
            switch self {
            case .accounts: L10n.betterTG("Accounts.Section")
            case .about: L10n.betterTG("Settings.AboutSection")
            case .accountActions,
                 .appearance,
                 .apps,
                 .edit,
                 .media,
                 .myProfile,
                 .profile,
                 .proxy,
                 .shortcuts,
                 .suggestion,
                 .support: nil
            }
        }
    }

    enum Row: Equatable {
        case profile
        /// Settings.ChangeProfilePhoto, or Settings.SetProfilePhotoOrVideo without a photo.
        case setPhoto(hasPhoto: Bool)
        case setUsername
        /// The reminder's title and text (PeerInfoScreenInfoItem).
        case suggestionInfo(SuggestedActionsStore.Reminder)
        /// Keep the number or the password, which dismisses the reminder.
        case suggestionKeep(SuggestedActionsStore.Reminder)
        /// Try the password, or set one up.
        case suggestionAction(SuggestedActionsStore.Reminder)
        case account(UUID)
        case addAccount
        /// Debug builds' sign-in on Telegram's test server.
        case addTestServerAccount
        /// A side menu bot by its user ID.
        case app(Int64)
        case myProfile
        case proxy
        case savedMessages
        case devices
        case chatFolders
        case notifications
        case privacy
        case dataAndStorage
        case appearance
        case powerSaving
        case language
        case support
        case faq
        case tips
        /// BetterTG's own options (Swiftgram's Swiftgram row).
        case betterTG
        case version
        case licenses
        case privacyPolicy
        case termsOfService
        case logOut

        // MARK: Internal

        var account: TelegramAccount? {
            guard case .account(let id) = self else { return nil }
            return TDLib.shared.accounts.first(where: { $0.id == id })
        }

        var title: String {
            switch self {
            case .suggestionInfo:
                ""
            case .suggestionKeep(let reminder):
                reminder == .checkPassword
                    ? L10n.telegram("Settings.KeepPassword")
                    : L10n.telegram("Settings.KeepPhoneNumber", "")
            case .suggestionAction(let reminder):
                reminder == .setPassword
                    ? L10n.telegram("Settings.SuggestSetupPasswordAction")
                    : L10n.telegram("Settings.TryEnterPassword")
            case .account:
                account?.localizedTitle ?? L10n.betterTG("Accounts.Account")
            case .addAccount:
                L10n.telegram("Settings.AddAccount")
            case .addTestServerAccount:
                L10n.betterTG("Accounts.AddTestServerAccount")
            case .app:
                ""
            case .profile:
                L10n.telegram("EditProfile.Title")
            case .setPhoto(let hasPhoto):
                L10n.telegram(hasPhoto ? "Settings.ChangeProfilePhoto" : "Settings.SetProfilePhotoOrVideo")
            case .setUsername:
                L10n.telegram("Settings.SetUsername")
            case .myProfile:
                L10n.telegram("Settings.MyProfile")
            case .proxy:
                L10n.telegram("Settings.Proxy")
            case .savedMessages:
                L10n.telegram("Settings.SavedMessages")
            case .devices:
                L10n.telegram("Settings.Devices")
            case .chatFolders:
                L10n.telegram("Settings.ChatFolders")
            case .notifications:
                L10n.telegram("Settings.NotificationsAndSounds")
            case .privacy:
                L10n.telegram("Settings.PrivacySettings")
            case .dataAndStorage:
                L10n.telegram("Settings.ChatSettings")
            case .appearance:
                L10n.telegram("Conversation.Theme")
            case .powerSaving:
                L10n.telegram("Settings.PowerSaving")
            case .language:
                L10n.telegram("Settings.AppLanguage")
            case .support:
                L10n.telegram("Settings.Support")
            case .faq:
                L10n.telegram("Settings.FAQ")
            case .tips:
                L10n.telegram("Settings.Tips")
            case .betterTG:
                "BetterTG"
            case .version:
                L10n.betterTG("Settings.Version")
            case .licenses:
                L10n.betterTG("Settings.Licenses")
            case .privacyPolicy:
                L10n.betterTG("Settings.PrivacyPolicy")
            case .termsOfService:
                L10n.betterTG("Settings.TermsOfService")
            case .logOut:
                L10n.telegram("Settings.Logout")
            }
        }

        @MainActor var subtitle: String? {
            switch self {
            case .suggestionAction,
                 .suggestionInfo,
                 .suggestionKeep:
                nil
            case .account(let id):
                accountSubtitle(isCurrent: id == TDLib.shared.activeAccountID)
            case .appearance:
                AppAppearance.current.title
            case .powerSaving:
                L10n.telegram(EnergyUsage.shared.isPowerSavingOn ? "Settings.PowerSavingOn" : "Settings.PowerSavingOff")
            case .language:
                AppLocalization.shared.currentLanguage.nativeName
            case .proxy:
                ProxyStatusStore.shared.state.enabledTypeTitle ?? L10n.telegram("Settings.ProxyDisabled")
            case .version:
                Utils.applicationVersion
            case .addAccount,
                 .addTestServerAccount,
                 .app,
                 .betterTG,
                 .chatFolders,
                 .dataAndStorage,
                 .devices,
                 .faq,
                 .licenses,
                 .logOut,
                 .myProfile,
                 .notifications,
                 .privacy,
                 .privacyPolicy,
                 .profile,
                 .savedMessages,
                 .setPhoto,
                 .setUsername,
                 .support,
                 .termsOfService,
                 .tips:
                nil
            }
        }

        /// Rows that show their value on the right, as Telegram's disclosure items do.
        var showsValue: Bool {
            switch self {
            case .appearance,
                 .devices,
                 .language,
                 .powerSaving,
                 .proxy: true
            default: false
            }
        }

        var symbolName: String {
            switch self {
            case .suggestionAction,
                 .suggestionInfo,
                 .suggestionKeep: ""
            case .profile: "person.crop.circle"
            case .setPhoto: "camera"
            case .setUsername: "at"
            case .account: "person.crop.circle.fill"
            case .addAccount: "plus.circle.fill"
            case .addTestServerAccount: "testtube.2"
            case .app: "square.grid.2x2.fill"
            case .proxy: "shield.fill"
            case .myProfile: "person.crop.circle.fill"
            case .savedMessages: "bookmark.fill"
            case .devices: "laptopcomputer.and.iphone"
            case .chatFolders: "folder.fill"
            case .notifications: "bell.badge.fill"
            case .privacy: "lock.fill"
            case .dataAndStorage: "externaldrive.fill"
            case .appearance: "paintpalette.fill"
            case .language: "globe"
            case .powerSaving: "battery.50percent"
            case .support: "bubble.left.and.text.bubble.right.fill"
            case .faq: "questionmark.circle.fill"
            case .tips: "lightbulb.fill"
            case .betterTG: "sparkles"
            case .version: "info.circle.fill"
            case .licenses: "text.book.closed.fill"
            case .privacyPolicy: "hand.raised.fill"
            case .termsOfService: "doc.text.fill"
            case .logOut: "rectangle.portrait.and.arrow.right"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .suggestionAction,
                 .suggestionInfo,
                 .suggestionKeep: .tintColor
            case .account: .systemTeal
            case .addAccount,
                 .addTestServerAccount,
                 .app,
                 .appearance,
                 .language,
                 .profile,
                 .savedMessages,
                 .setPhoto,
                 .setUsername,
                 .version: .systemBlue
            case .devices: .systemOrange
            case .chatFolders: .systemCyan
            case .notifications: .systemRed
            case .proxy: .systemBlue
            case .myProfile: .systemRed
            case .licenses,
                 .privacy,
                 .termsOfService: .systemGray
            case .privacyPolicy: .systemIndigo
            case .dataAndStorage: .systemGreen
            case .betterTG: .systemPurple
            case .logOut: .systemRed
            case .powerSaving,
                 .support: .systemOrange
            case .faq: .systemCyan
            case .tips: .systemYellow
            }
        }

        var isSelectable: Bool {
            switch self {
            case .version:
                false
            default:
                true
            }
        }

        var isDestructive: Bool { self == .logOut }

        /// Current Account or the phone number, then Test Server for a test server account.
        @MainActor private func accountSubtitle(isCurrent: Bool) -> String? {
            let parts = [
                isCurrent ? L10n.betterTG("Accounts.Current") : account?.phoneNumber.map { "+\($0)" },
                account?.usesTestServer == true ? L10n.betterTG("Accounts.TestServer") : nil,
            ].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

// MARK: - SettingsProfileCell

/// Telegram's settings header: the account's photo, name, phone number and username, opening Edit Profile.
private final class SettingsProfileCell: UITableViewCell {
    static let reuseIdentifier = "SettingsProfileCell"

    var onLongPress: (() -> Void)?

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        accessoryType = .disclosureIndicator
        let labels = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 3
        for subview in [avatarView, labels] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        avatarView.isUserInteractionEnabled = false
        nameLabel.font = .preferredFont(forTextStyle: .title3)
        nameLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            labels.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            labels.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(user: User?, client: TDLibClient, accountID: UUID?) {
        guard let user else {
            nameLabel.text = TDLib.shared.activeAccount?.localizedTitle
            detailLabel.text = nil
            return
        }
        nameLabel.text = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        var details = [String]()
        if !user.phoneNumber.isEmpty { details.append("+\(user.phoneNumber)") }
        if let username = user.usernames?.editableUsername, !username.isEmpty { details.append("@\(username)") }
        detailLabel.text = details.joined(separator: " • ")
        accessibilityLabel = [nameLabel.text, detailLabel.text].compactMap(\.self).joined(separator: ", ")
        // The account's own photo, never the Saved Messages icon.
        avatarView.configure(
            file: user.profilePhoto?.small,
            largeFile: user.profilePhoto?.big,
            minithumbnail: user.profilePhoto?.minithumbnail,
            placeholder: user.telegramAvatarPlaceholder,
            accountID: accountID,
            accountUserID: 0,
            client: client,
        )
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        setHighlighted(false, animated: true)
        onLongPress?()
    }
}
