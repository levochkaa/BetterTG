// ChatbotSetupViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatbotSetupViewController

/// ChatbotSetupScreen: a bot found by its username or t.me link is added with ADD (if it can connect to Business) and
/// removed with its cross; the added bot then gets CHATS ACCESSIBLE FOR THE BOT (All 1-to-1 Chats Except… or Only
/// Selected Chats, with chat categories and people) and BOT PERMISSIONS. Leaving the screen saves what changed
/// (setBusinessConnectedBot, or deleteBusinessConnectedBot for a removed bot).
final class ChatbotSetupViewController: SettingsListViewController {
    enum Category: CaseIterable {
        case existingChats, newChats, contacts, nonContacts

        var title: String {
            switch self {
            case .existingChats: L10n.telegram("BusinessMessageSetup.Recipients.CategoryExistingChats")
            case .newChats: L10n.telegram("BusinessMessageSetup.Recipients.CategoryNewChats")
            case .contacts: L10n.telegram("BusinessMessageSetup.Recipients.CategoryContacts")
            case .nonContacts: L10n.telegram("BusinessMessageSetup.Recipients.CategoryNonContacts")
            }
        }

        var symbol: String {
            switch self {
            case .existingChats: "bubble.left.and.bubble.right.fill"
            case .newChats: "bubble.left.fill"
            case .contacts: "person.crop.circle.fill"
            case .nonContacts: "person.crop.circle.badge.questionmark.fill"
            }
        }
    }

    /// TelegramBusinessBotRights, in BusinessBotRights' order.
    enum Right: Int, CaseIterable {
        case reply, readMessages, deleteSentMessages, deleteAllMessages, editName, editBio, editProfilePhoto,
             editUsername, viewGiftsAndStars, sellGifts, changeGiftSettings, transferAndUpgradeGifts, transferStars,
             manageStories

        var title: String {
            switch self {
            case .reply: L10n.telegram("ChatbotSetup.Rights.ReplyToMessages")
            case .readMessages: L10n.telegram("ChatbotSetup.Rights.MarkAsRead")
            case .deleteSentMessages: L10n.telegram("ChatbotSetup.Rights.DeleteSentMessages")
            case .deleteAllMessages: L10n.telegram("ChatbotSetup.Rights.DeleteReceivedMessages")
            case .editName: L10n.telegram("ChatbotSetup.Rights.EditName")
            case .editBio: L10n.telegram("ChatbotSetup.Rights.EditBio")
            case .editProfilePhoto: L10n.telegram("ChatbotSetup.Rights.EditProfilePhoto")
            case .editUsername: L10n.telegram("ChatbotSetup.Rights.EditUsername")
            case .viewGiftsAndStars: L10n.telegram("ChatbotSetup.Rights.ViewGifts")
            case .sellGifts: L10n.telegram("ChatbotSetup.Rights.SellGifts")
            case .changeGiftSettings: L10n.telegram("ChatbotSetup.Rights.ChangeGiftSettings")
            case .transferAndUpgradeGifts: L10n.telegram("ChatbotSetup.Rights.TransferAndUpgradeGifts")
            case .transferStars: L10n.telegram("ChatbotSetup.Rights.TransferStars")
            case .manageStories: L10n.telegram("ChatbotSetup.Rights.ManageStories")
            }
        }
    }

    /// What the screen saves, compared with what it loaded so a visit alone changes nothing.
    private struct Setup: Equatable {
        var botID: Int64?
        var excludesSelected = true
        var categories = Set<Category>()
        var chatIDs = [Int64]()
        var excludedChatIDs = [Int64]()
        var rights: Set<Right> = [.reply, .readMessages, .deleteSentMessages, .deleteAllMessages]
    }

    private enum Search {
        case searching
        case notFound
        case found(User)
    }

    private static let groups: [(title: String, rights: [Right])] = [
        (
            "ChatbotSetup.Rights.ManageMessages",
            [.reply, .readMessages, .deleteSentMessages, .deleteAllMessages],
        ),
        ("ChatbotSetup.Rights.ManageProfile", [.editName, .editBio, .editProfilePhoto, .editUsername]),
        (
            "ChatbotSetup.Rights.ManageGiftsAndStars",
            [.viewGiftsAndStars, .sellGifts, .changeGiftSettings, .transferAndUpgradeGifts, .transferStars],
        ),
        ("ChatbotSetup.Rights.ManageStories", [.manageStories]),
    ]

    private var loaded: Setup?
    private var setup = Setup()
    private var bot: User?
    private var query = ""
    private var search: Search?
    private var searchTask: Task<Void, Never>?
    private var peers = [Int64: SettingsPeer]()

    /// ChatbotSearchResultItemComponent: searching, Chatbot not found, or the bot with ADD or its cross.
    private var searchRows: [SettingsRow] {
        switch search {
        case nil:
            return []
        case .searching:
            return [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )]
        case .notFound:
            return [SettingsRow(
                title: L10n.telegram("ChatbotSetup.BotNotFoundStatus"),
                style: .status(.secondaryLabel),
            )]
        case .found(let user):
            let isInstalled = setup.botID == user.id
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            let peer = peers[user.id] ?? SettingsPeer(
                id: user.id,
                title: name,
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            )
            return [SettingsRow(
                title: name,
                detail: L10n.telegram("Bot.GenericBotStatus"),
                style: .peer(peer),
                trailingView: SettingsTrailingView { [weak self] in
                    let button = UIButton(configuration: isInstalled ? .plain() : .filled())
                    if isInstalled {
                        button.configuration?.image = UIImage(systemName: "xmark.circle.fill")
                        button.configuration?.baseForegroundColor = .tertiaryLabel
                    } else {
                        var title = AttributedString(L10n.telegram("ChatbotSetup.BotAddAction"))
                        title.font = .systemFont(ofSize: 15, weight: .semibold)
                        button.configuration?.attributedTitle = title
                        button.configuration?.cornerStyle = .capsule
                        button.configuration?.contentInsets = NSDirectionalEdgeInsets(
                            top: 4, leading: 14, bottom: 4, trailing: 14,
                        )
                    }
                    button.addAction(UIAction { _ in
                        if isInstalled {
                            self?.removeBot()
                        } else {
                            self?.install(user)
                        }
                    }, for: .touchUpInside)
                    return button
                },
            )]
        }
    }

    /// With Only Selected Chats, the people the bot never reaches although a category includes them.
    private var excludedChatsSection: SettingsSection {
        var rows = [SettingsRow(
            title: L10n.telegram("BusinessMessageSetup.Recipients.AddExclude"),
            style: .action(destructive: false),
            symbol: "minus",
        ) { [weak self] in self?.pickPeople(excluding: true) }]
        rows += peerRows(setup.excludedChatIDs) { [weak self] id in
            self?.setup.excludedChatIDs.removeAll { $0 == id }
        }
        return SettingsSection(
            header: L10n.telegram("BusinessMessageSetup.Recipients.ExcludedSectionHeader"),
            footer: L10n.telegram("ChatbotSetup.Recipients.ExcludedSectionFooter").withoutTelegramMarkup,
            rows: rows,
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChatbotSetup.TitleItem")
        load()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isLeavingNavigation else { return }
        save()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [
            SettingsSection(
                header: L10n.telegram("ChatbotSetup.Text")
                    .withoutTelegramLinks
                    .withoutTelegramMarkup
                    .replacing(" >", with: ""),
                rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: query,
                    placeholder: L10n.telegram("ChatbotSetup.BotSearchPlaceholder"),
                    maxLength: 64,
                ) { [weak self] text in self?.updateQuery(text) }))],
            ),
            SettingsSection(footer: L10n.telegram("ChatbotSetup.BotSectionFooter"), rows: searchRows),
        ]
        guard setup.botID != nil else { return sections }
        sections.append(SettingsSection(
            header: L10n.telegram("ChatbotSetup.RecipientsSectionHeader"),
            rows: [
                modeRow("BusinessMessageSetup.RecipientsOptionAllExcept", excludes: true),
                modeRow("BusinessMessageSetup.RecipientsOptionOnly", excludes: false),
            ],
        ))
        sections.append(chatsSection(isExcluded: setup.excludesSelected))
        if !setup.excludesSelected {
            sections.append(excludedChatsSection)
        }
        for (index, group) in Self.groups.enumerated() {
            sections.append(SettingsSection(
                header: index == 0 ? L10n.telegram("ChatbotSetup.PermissionsSectionHeader") : nil,
                footer: index == Self.groups.count - 1 ? L10n.telegram("ChatbotSetup.PermissionsSectionFooter") : nil,
                rows: rightRows(title: L10n.telegram(group.title), rights: group.rights),
            ))
        }
        return sections
    }

    private func load() {
        let client = client
        Task { [weak self] in
            let info = try? await client.send(TDNativeRequests.getBusinessConnectedBot())
            var setup = Setup()
            var bot: User?
            if let connected = info?.bot {
                bot = try? await client.getUser(userId: connected.botUserId)
                let recipients = connected.recipients
                setup.botID = connected.botUserId
                setup.excludesSelected = recipients.excludeSelected
                setup.chatIDs = recipients.chatIds
                setup.excludedChatIDs = recipients.excludedChatIds
                if recipients.selectExistingChats { setup.categories.insert(.existingChats) }
                if recipients.selectNewChats { setup.categories.insert(.newChats) }
                if recipients.selectContacts { setup.categories.insert(.contacts) }
                if recipients.selectNonContacts { setup.categories.insert(.nonContacts) }
                let rights = connected.rights
                let values: [Right: Bool] = [
                    .reply: rights.canReply, .readMessages: rights.canReadMessages,
                    .deleteSentMessages: rights.canDeleteSentMessages,
                    .deleteAllMessages: rights.canDeleteAllMessages, .editName: rights.canEditName,
                    .editBio: rights.canEditBio, .editProfilePhoto: rights.canEditProfilePhoto,
                    .editUsername: rights.canEditUsername, .viewGiftsAndStars: rights.canViewGiftsAndStars,
                    .sellGifts: rights.canSellGifts, .changeGiftSettings: rights.canChangeGiftSettings,
                    .transferAndUpgradeGifts: rights.canTransferAndUpgradeGifts,
                    .transferStars: rights.canTransferStars, .manageStories: rights.canManageStories,
                ]
                setup.rights = Set(values.filter(\.value).keys)
            }
            guard let self, contextIsCurrent else { return }
            loaded = setup
            self.setup = setup
            self.bot = bot
            if let bot {
                query = bot.usernames?.activeUsernames.first ?? ""
                search = .found(bot)
            }
            reload()
            resolvePeers()
        }
    }

    private func modeRow(_ key: String, excludes: Bool) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram(key),
            accessory: setup.excludesSelected == excludes ? .checkmark : .none,
        ) { [weak self] in
            guard let self, setup.excludesSelected != excludes else { return }
            setup.excludesSelected = excludes
            // The chosen chats change meaning with the mode, as Telegram resets them.
            setup.categories = []
            setup.chatIDs = []
            setup.excludedChatIDs = []
            reload()
        }
    }

    /// The included chats (Only Selected Chats) or the excluded ones (All 1-to-1 Chats Except…): Include Chats… or
    /// Exclude Chats…, then the categories and the people, each removed by swiping.
    private func chatsSection(isExcluded: Bool) -> SettingsSection {
        var rows = [SettingsRow(
            title: L10n.telegram(isExcluded
                ? "BusinessMessageSetup.Recipients.AddExclude"
                : "BusinessMessageSetup.Recipients.AddInclude"),
            style: .action(destructive: false),
            symbol: "plus",
        ) { [weak self] in self?.addChats() }]
        for category in Category.allCases where setup.categories.contains(category) {
            rows.append(SettingsRow(
                title: category.title,
                symbol: category.symbol,
                symbolTint: .systemBlue,
                swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in
                    self?.setup.categories.remove(category)
                    self?.reload()
                }),
            ))
        }
        rows += peerRows(setup.chatIDs) { [weak self] id in self?.setup.chatIDs.removeAll { $0 == id } }
        return SettingsSection(
            header: L10n.telegram(isExcluded
                ? "BusinessMessageSetup.Recipients.ExcludedSectionHeader"
                : "BusinessMessageSetup.Recipients.IncludedSectionHeader"),
            footer: L10n.telegram(isExcluded
                ? "ChatbotSetup.Recipients.ExcludedSectionFooter"
                : "ChatbotSetup.Recipients.IncludedSectionFooter")
                .withoutTelegramMarkup,
            rows: rows,
        )
    }

    private func peerRows(_ ids: [Int64], remove: @escaping (Int64) -> Void) -> [SettingsRow] {
        ids.compactMap { id in
            guard let peer = peers[id] else { return nil }
            return SettingsRow(
                title: peer.title,
                style: .peer(peer),
                swipeAction: (L10n.telegram("Common.Delete"), { [weak self] in
                    remove(id)
                    self?.reload()
                }),
            )
        }
    }

    /// A group's switch (on while all its rights are) and its rights; Read Messages stays on.
    private func rightRows(title: String, rights: [Right]) -> [SettingsRow] {
        var rows = [SettingsRow]()
        if rights.count > 1 {
            rows.append(SettingsRow(
                title: title,
                accessory: .toggle(isOn: rights.allSatisfy(setup.rights.contains)) { [weak self] isOn in
                    self?.setRights(Set(rights), isOn: isOn)
                },
            ))
        }
        if rights.first == .reply {
            rows.append(SettingsRow(
                title: L10n.telegram("ChatbotSetup.Rights.ReadMessages"),
                accessory: .toggle(isOn: true) { _ in },
                isEnabled: false,
            ))
        }
        for right in rights {
            rows.append(SettingsRow(
                title: rights.count > 1 ? right.title : title,
                accessory: .toggle(isOn: setup.rights.contains(right)) { [weak self] isOn in
                    self?.setRights([right], isOn: isOn)
                },
            ))
        }
        return rows
    }

    /// updateBotQuery: a username or a t.me link, resolved after a pause.
    private func updateQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        if name.hasPrefix("t.me/") { name = String(name.dropFirst(5)) }
        name = name.components(separatedBy: CharacterSet(charactersIn: "/?")).first ?? name
        if name.hasPrefix("@") { name.removeFirst() }
        guard !name.isEmpty else {
            search = nil
            reload(sections: [1])
            return
        }
        if case .found = search {} else {
            search = .searching
            reload(sections: [1])
        }
        let client = client
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            var bot: User?
            if let chat = try? await client.send(TDNativeRequests.searchPublicChat(username: name)),
               case .chatTypePrivate(let privateChat) = chat.type,
               let user = try? await client.getUser(userId: privateChat.userId),
               case .userTypeBot = user.type
            {
                bot = user
            }
            guard !Task.isCancelled, let self, contextIsCurrent else { return }
            search = bot.map { .found($0) } ?? .notFound
            reload(sections: [1])
        }
    }

    /// installAction: a bot that can connect to Business gets the default rights and the toast; another one the
    /// error.
    private func install(_ user: User) {
        view.endEditing(true)
        guard case .userTypeBot(let info) = user.type, info.canConnectToBusiness else {
            let alert = UIAlertController(
                title: nil,
                message: L10n.telegram("ChatbotSetup.ErrorBotNotBusinessCapable"),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
            return
        }
        bot = user
        setup.botID = user.id
        setup.rights = [.reply, .readMessages, .deleteSentMessages, .deleteAllMessages]
        reload()
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        TelegramUndoToast.show(
            text: L10n.telegram("ChatbotSetup.BotInstalled", name),
            in: view,
            bottomInset: 12,
            undo: nil,
        )
    }

    private func removeBot() {
        searchTask?.cancel()
        setup.botID = nil
        bot = nil
        search = nil
        query = ""
        reload()
    }

    /// The categories not chosen yet, then the people.
    private func addChats() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for category in Category.allCases where !setup.categories.contains(category) {
            sheet.addAction(UIAlertAction(title: category.title, style: .default) { [weak self] _ in
                self?.setup.categories.insert(category)
                self?.reload()
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("ChatbotSetup.Recipients.AddUsers"), style: .default) {
            [weak self] _ in self?.pickPeople(excluding: false)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView =
            tableView.cellForRow(at: IndexPath(row: 0, section: 3)) ?? view
        present(sheet, animated: true)
    }

    /// People only: a business bot reaches private chats.
    private func pickPeople(excluding: Bool) {
        guard presentedViewController == nil else { return }
        let chosen = Set(setup.chatIDs + setup.excludedChatIDs)
        let picker = SettingsPeerPickerViewController(excludedUserIDs: chosen, excludedChatIDs: [])
        picker.listsOnlyPeople = true
        picker.pickerTitle = L10n.telegram(excluding || setup.excludesSelected
            ? "BusinessMessageSetup.Recipients.ExcludeSearchTitle"
            : "BusinessMessageSetup.Recipients.IncludeSearchTitle")
        picker.onDone = { [weak self] users, _ in
            guard let self else { return }
            if excluding {
                setup.excludedChatIDs += users
            } else {
                setup.chatIDs += users
            }
            resolvePeers()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    /// presentStarGiftsWarningIfNeeded: rights that give away gifts, stars or the username ask first.
    private func setRights(_ rights: Set<Right>, isOn: Bool) {
        let risky = rights.intersection([.transferAndUpgradeGifts, .transferStars, .editUsername])
            .subtracting(setup.rights)
        guard isOn, !risky.isEmpty else {
            apply(rights, isOn: isOn)
            return
        }
        let username = "@" + (bot?.usernames?.activeUsernames.first ?? "")
        let key =
            if risky.contains(.editUsername) {
                "ChatbotSetup.Gift.Warning.UsernameText"
            } else if risky == [.transferAndUpgradeGifts] {
                "ChatbotSetup.Gift.Warning.GiftsText"
            } else if risky == [.transferStars] {
                "ChatbotSetup.Gift.Warning.StarsText"
            } else {
                "ChatbotSetup.Gift.Warning.CombinedText"
            }
        let alert = UIAlertController(
            title: L10n.telegram("ChatbotSetup.Gift.Warning.Title"),
            message: L10n.telegram(key, username).withoutTelegramMarkup,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("ChatbotSetup.Gift.Warning.Proceed"), style: .default) {
            [weak self] _ in self?.apply(rights, isOn: true)
        })
        present(alert, animated: true)
    }

    private func apply(_ rights: Set<Right>, isOn: Bool) {
        if isOn { setup.rights.formUnion(rights) } else { setup.rights.subtract(rights) }
        refreshRowsInPlace()
    }

    private func resolvePeers() {
        let client = client
        let missing = (setup.chatIDs + setup.excludedChatIDs).filter { peers[$0] == nil }
        Task { [weak self] in
            var resolved = [Int64: SettingsPeer]()
            for id in missing {
                if let peer = await SettingsPeer.user(id, client: client) { resolved[id] = peer }
            }
            guard let self, contextIsCurrent else { return }
            peers.merge(resolved) { $1 }
            reload()
        }
    }

    // MARK: Saving

    private func save() {
        guard let loaded, setup != loaded else { return }
        let setup = setup
        let client = client
        Task {
            guard let botID = setup.botID else {
                if let previous = loaded.botID {
                    _ = try? await client.send(TDNativeRequests.deleteBusinessConnectedBot(botUserId: previous))
                }
                return
            }
            // The chats must be known to TDLib before they can be named.
            for id in setup.chatIDs + setup.excludedChatIDs {
                _ = try? await client.createPrivateChat(force: false, userId: id)
            }
            let rights = setup.rights
            let connected = TDNativeBusinessConnectedBot(
                botUserId: botID,
                recipients: TDNativeBusinessRecipients(
                    chatIds: setup.chatIDs,
                    excludedChatIds: setup.excludesSelected ? [] : setup.excludedChatIDs,
                    selectExistingChats: setup.categories.contains(.existingChats),
                    selectNewChats: setup.categories.contains(.newChats),
                    selectContacts: setup.categories.contains(.contacts),
                    selectNonContacts: setup.categories.contains(.nonContacts),
                    excludeSelected: setup.excludesSelected,
                ),
                rights: TDNativeBusinessBotRights(
                    canReply: rights.contains(.reply),
                    canReadMessages: rights.contains(.readMessages),
                    canDeleteSentMessages: rights.contains(.deleteSentMessages),
                    canDeleteAllMessages: rights.contains(.deleteAllMessages),
                    canEditName: rights.contains(.editName),
                    canEditBio: rights.contains(.editBio),
                    canEditProfilePhoto: rights.contains(.editProfilePhoto),
                    canEditUsername: rights.contains(.editUsername),
                    canViewGiftsAndStars: rights.contains(.viewGiftsAndStars),
                    canSellGifts: rights.contains(.sellGifts),
                    canChangeGiftSettings: rights.contains(.changeGiftSettings),
                    canTransferAndUpgradeGifts: rights.contains(.transferAndUpgradeGifts),
                    canTransferStars: rights.contains(.transferStars),
                    canManageStories: rights.contains(.manageStories),
                ),
            )
            _ = try? await client.send(TDNativeRequests.setBusinessConnectedBot(bot: connected))
        }
    }
}
