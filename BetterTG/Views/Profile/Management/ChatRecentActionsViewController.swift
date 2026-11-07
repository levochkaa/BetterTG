// ChatRecentActionsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatEventText

/// The sentences Telegram's ChatRecentActionsController shows for an admin log event, with the actor's name where
/// the string names them and before the ones that start with the action. Events Telegram draws as colors, emoji
/// status, wallpapers and call settings are left out.
@MainActor enum ChatEventText {
    /// Whose names an event's sentence needs besides the actor.
    static func peers(in action: ChatEventAction) -> [PeerProfileMemberID] {
        switch action {
        case .chatEventMemberInvited(let value): [.user(value.userId)]
        case .chatEventMemberPromoted(let value): [.user(value.userId)]
        case .chatEventMemberRestricted(let value): [PeerProfileMemberID(value.memberId)]
        case .chatEventMemberTagChanged(let value): [.user(value.userId)]
        case .chatEventMemberJoinedByRequest(let value): [.user(value.approverUserId)]
        case .chatEventLinkedChatChanged(let value):
            [value.oldLinkedChatId, value.newLinkedChatId].filter { $0 != 0 }.map { .chat($0) }
        default: []
        }
    }

    static func text(
        _ action: ChatEventAction,
        actor: String,
        isChannel: Bool,
        name: (PeerProfileMemberID) -> String,
    ) -> String? {
        func string(_ key: String, _ arguments: CVarArg...) -> String {
            AppLocalization.shared.telegramString(key, arguments: arguments)
        }
        func led(_ key: String, _ arguments: CVarArg...) -> String {
            actor + " " + AppLocalization.shared.telegramString(key, arguments: arguments)
        }
        func toggle(_ isOn: Bool, _ on: String, _ off: String) -> String {
            string(isOn ? on : off, actor)
        }
        func link(_ link: ChatInviteLink) -> String {
            ChatInviteLinkText.address(link.inviteLink)
        }
        func quoted(_ header: String, _ message: Message) -> String {
            let summary = MessageTextSpoilerPresentation.summary(for: message)
            return summary.isEmpty ? header : header + "\n" + summary
        }
        func topic(_ info: ForumTopicInfo?) -> String {
            info?.name ?? ""
        }
        switch action {
        case .chatEventMessageEdited(let value):
            return quoted(string("Channel.AdminLog.MessageEdited", actor), value.newMessage)
        case .chatEventMessageDeleted(let value):
            return quoted(string("Channel.AdminLog.MessageDeleted", actor), value.message)
        case .chatEventMessagePinned(let value):
            return quoted(string("Channel.AdminLog.MessagePinned", actor), value.message)
        case .chatEventMessageUnpinned(let value):
            return quoted(string("Channel.AdminLog.MessageUnpinnedExtended", actor), value.message)
        case .chatEventPollStopped:
            return string("Channel.AdminLog.PollStopped", actor)
        case .chatEventMemberJoined:
            return string(isChannel ? "Notification.JoinedChannel" : "Notification.JoinedChat", actor)
        case .chatEventMemberJoinedByInviteLink(let value):
            return string(
                value.viaChatFolderInviteLink
                    ? "Channel.AdminLog.JoinedViaFolderInviteLink"
                    : "Channel.AdminLog.JoinedViaInviteLink",
                actor,
                link(value.inviteLink),
            )
        case .chatEventMemberJoinedByRequest(let value):
            let approver = name(.user(value.approverUserId))
            if let inviteLink = value.inviteLink {
                return string("Channel.AdminLog.JoinedViaRequest", actor, link(inviteLink), approver)
            }
            return string("Channel.AdminLog.JoinedViaPublicRequest", actor, approver)
        case .chatEventMemberInvited(let value):
            return string("Notification.Invited", actor, name(.user(value.userId)))
        case .chatEventMemberLeft:
            return string(isChannel ? "Notification.LeftChannel" : "Notification.LeftChat", actor)
        case .chatEventMemberPromoted(let value):
            let member = name(.user(value.userId))
            let wasAdmin = isAdministrator(value.oldStatus)
            let isAdmin = isAdministrator(value.newStatus)
            if case .chatMemberStatusCreator = value.newStatus {
                return led("Channel.AdminLog.MessageTransferedName", member)
            }
            if !wasAdmin, isAdmin { return led("Channel.AdminLog.MessageAddedAdminName", member) }
            if wasAdmin, !isAdmin { return led("Channel.AdminLog.MessageRemovedAdminName", member) }
            return led("Channel.AdminLog.MessagePromotedName", member)
        case .chatEventMemberRestricted(let value):
            let member = name(PeerProfileMemberID(value.memberId))
            if case .chatMemberStatusBanned = value.newStatus {
                return led("Channel.AdminLog.MessageKickedName", member)
            }
            if case .chatMemberStatusBanned = value.oldStatus {
                return led("Channel.AdminLog.MessageUnkickedName", member)
            }
            return led("Channel.AdminLog.MessageRestrictedName", member)
        case .chatEventMemberTagChanged(let value):
            return led("Channel.AdminLog.MessageRankNameNew", name(.user(value.userId)), value.newTag)
        case .chatEventDescriptionChanged(let value):
            let header = string(
                isChannel ? "Channel.AdminLog.MessageChangedChannelAbout" : "Channel.AdminLog.MessageChangedGroupAbout",
                actor,
            )
            return value.newDescription.isEmpty ? header : header + "\n" + value.newDescription
        case .chatEventLinkedChatChanged(let value):
            if value.newLinkedChatId != 0 {
                return string(
                    isChannel
                        ? "Channel.AdminLog.MessageChangedLinkedGroup"
                        : "Channel.AdminLog.MessageChangedLinkedChannel",
                    actor,
                    name(.chat(value.newLinkedChatId)),
                )
            }
            return string(
                isChannel
                    ? "Channel.AdminLog.MessageChangedUnlinkedGroup"
                    : "Channel.AdminLog.MessageChangedUnlinkedChannel",
                actor,
                name(.chat(value.oldLinkedChatId)),
            )
        case .chatEventMessageAutoDeleteTimeChanged(let value):
            return value.newMessageAutoDeleteTime > 0
                ? string(
                    "Channel.AdminLog.MessageChangedAutoremoveTimeoutSet",
                    actor,
                    SettingsFormatting.timeInterval(seconds: value.newMessageAutoDeleteTime),
                )
                : string("Channel.AdminLog.MessageChangedAutoremoveTimeoutRemove", actor)
        case .chatEventPermissionsChanged:
            return led("Channel.AdminLog.DefaultRestrictionsUpdated")
        case .chatEventPhotoChanged(let value):
            if isChannel {
                return string(value.newPhoto == nil ? "Channel.MessagePhotoRemoved" : "Channel.MessagePhotoUpdated")
            }
            return string(
                value.newPhoto == nil ? "Notification.RemovedGroupPhoto" : "Notification.ChangedGroupPhoto",
                actor,
            )
        case .chatEventSlowModeDelayChanged(let value):
            return value.newSlowModeDelay > 0
                ? string(
                    "Channel.AdminLog.SetSlowmode",
                    actor,
                    SettingsFormatting.timeInterval(seconds: value.newSlowModeDelay),
                )
                : string("Channel.AdminLog.DisabledSlowmode", actor)
        case .chatEventStickerSetChanged(let value):
            return string(
                value.newStickerSetId == 0
                    ? "Channel.AdminLog.MessageRemovedGroupStickerPack"
                    : "Channel.AdminLog.MessageChangedGroupStickerPack",
                actor,
            )
        case .chatEventTitleChanged(let value):
            return isChannel
                ? string("Channel.MessageTitleUpdated", value.newTitle).trimmingCharacters(in: .whitespaces)
                : string("Notification.ChangedGroupName", actor, value.newTitle).trimmingCharacters(in: .whitespaces)
        case .chatEventUsernameChanged(let value):
            if value.newUsername.isEmpty {
                return string(
                    isChannel
                        ? "Channel.AdminLog.MessageRemovedChannelUsername"
                        : "Channel.AdminLog.MessageRemovedGroupUsername",
                    actor,
                )
            }
            return string(
                isChannel
                    ? "Channel.AdminLog.MessageChangedChannelUsername"
                    : "Channel.AdminLog.MessageChangedGroupUsername",
                actor,
            ) + "\nt.me/" + value.newUsername
        case .chatEventActiveUsernamesChanged(let value):
            return string(
                isChannel
                    ? "Channel.AdminLog.MessageChangedChannelUsernames"
                    : "Channel.AdminLog.MessageChangedGroupUsernames",
                actor,
            ) + value.newUsernames.map { "\nt.me/" + $0 }.joined()
        case .chatEventHasProtectedContentToggled(let value):
            return toggle(
                value.hasProtectedContent,
                "Channel.AdminLog.MessageToggleNoForwardsOn",
                "Channel.AdminLog.MessageToggleNoForwardsOff",
            )
        case .chatEventInvitesToggled(let value):
            return toggle(
                value.canInviteUsers,
                "Channel.AdminLog.MessageToggleInvitesOn",
                "Channel.AdminLog.MessageToggleInvitesOff",
            )
        case .chatEventIsAllHistoryAvailableToggled(let value):
            return toggle(
                value.isAllHistoryAvailable,
                "Channel.AdminLog.MessageGroupPreHistoryVisible",
                "Channel.AdminLog.MessageGroupPreHistoryHidden",
            )
        case .chatEventHasAggressiveAntiSpamEnabledToggled(let value):
            return toggle(
                value.hasAggressiveAntiSpamEnabled,
                "Channel.AdminLog.AntiSpamEnabled",
                "Channel.AdminLog.AntiSpamDisabled",
            )
        case .chatEventSignMessagesToggled(let value):
            return toggle(
                value.signMessages,
                "Channel.AdminLog.MessageToggleSignaturesOn",
                "Channel.AdminLog.MessageToggleSignaturesOff",
            )
        case .chatEventShowMessageSenderToggled(let value):
            return toggle(
                value.showMessageSender,
                "Channel.AdminLog.MessageToggleProfileSignaturesOn",
                "Channel.AdminLog.MessageToggleProfileSignaturesOff",
            )
        case .chatEventAutomaticTranslationToggled(let value):
            return toggle(
                value.hasAutomaticTranslation,
                "Channel.AdminLog.MessageToggleAutoTranslateOn",
                "Channel.AdminLog.MessageToggleAutoTranslateOff",
            )
        case .chatEventInviteLinkEdited(let value):
            return string("Channel.AdminLog.EditedInviteLink", actor, link(value.newInviteLink))
        case .chatEventInviteLinkRevoked(let value):
            return string("Channel.AdminLog.RevokedInviteLink", actor, link(value.inviteLink))
        case .chatEventInviteLinkDeleted(let value):
            return string("Channel.AdminLog.DeletedInviteLink", actor, link(value.inviteLink))
        case .chatEventVideoChatCreated:
            return string(isChannel ? "Channel.AdminLog.StartedLiveStream" : "Channel.AdminLog.StartedVoiceChat", actor)
        case .chatEventVideoChatEnded:
            return string(isChannel ? "Channel.AdminLog.EndedLiveStream" : "Channel.AdminLog.EndedVoiceChat", actor)
        case .chatEventIsForumToggled(let value):
            return toggle(value.isForum, "Channel.AdminLog.TopicsEnabled", "Channel.AdminLog.TopicsDisabled")
        case .chatEventForumTopicCreated(let value):
            return string("Channel.AdminLog.TopicCreated", actor, topic(value.topicInfo))
        case .chatEventForumTopicEdited(let value):
            return string(
                "Channel.AdminLog.TopicRenamed", actor, topic(value.oldTopicInfo), topic(value.newTopicInfo),
            )
        case .chatEventForumTopicToggleIsClosed(let value):
            return string(
                value.topicInfo.isClosed ? "Channel.AdminLog.TopicClosed" : "Channel.AdminLog.TopicReopened",
                actor,
                topic(value.topicInfo),
            )
        case .chatEventForumTopicToggleIsHidden(let value):
            return string(
                value.topicInfo.isHidden ? "Channel.AdminLog.TopicHidden" : "Channel.AdminLog.TopicUnhidden",
                actor,
                topic(value.topicInfo),
            )
        case .chatEventForumTopicDeleted(let value):
            return string("Channel.AdminLog.TopicDeleted", actor, topic(value.topicInfo))
        case .chatEventForumTopicPinned(let value):
            return value.newTopicInfo != nil
                ? string("Channel.AdminLog.TopicPinned", actor, topic(value.newTopicInfo))
                : string("Channel.AdminLog.TopicUnpinned", actor, topic(value.oldTopicInfo))
        default:
            return nil
        }
    }

    private static func isAdministrator(_ status: ChatMemberStatus) -> Bool {
        switch status {
        case .chatMemberStatusAdministrator,
             .chatMemberStatusCreator: true
        default: false
        }
    }
}

// MARK: - ChatRecentActionsViewController

/// Telegram's ChatRecentActionsController: the admin log of the last 48 hours (getChatEventLog), newest first and
/// grouped by day, each event with who did it, Telegram's sentence and the time. Older events load while scrolling.
/// A message Aggressive Anti-Spam deleted offers Report False Positive.
final class ChatRecentActionsViewController: SettingsListViewController, TelegramConditionalNavigationSearchProvider,
UISearchResultsUpdating, UISearchControllerDelegate {
    private struct Event {
        let id: Int64
        let date: Int
        let actor: String
        let text: String
        /// The message to report when TDLib allows reporting its deletion as a false positive.
        let falsePositiveMessageID: Int64?
    }

    private static let pageLimit = 100

    private let target: ChatManagementTarget
    private var events = [Event]()
    private var names = [PeerProfileMemberID: String]()
    private var oldestEventID: Int64 = 0
    private var hasMore = true
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?
    private var reportedMessageIDs = Set<Int64>()
    private var eventIndexPaths = [Int64: IndexPath]()
    private var filter = ChatEventLogFilter()
    /// The page loads belong to one filter; a new one drops what an older one still brings.
    private var loadGeneration = 0
    private var filterTask: Task<Void, Never>?
    /// ChatRecentActionsControllerNode's panel: Settings (the filter) and the "?" that explains the log.
    private let panel = ChatListSelectionToolbar()
    /// ChatRecentActionsController's search: the bar's button opens a field whose text getChatEventLog looks for.
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
    private var queryTask: Task<Void, Never>?

    var shownTelegramNavigationSearch: UISearchController? {
        isSearching ? search : nil
    }

    init(target: ChatManagementTarget) {
        self.target = target
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        filterTask?.cancel()
        queryTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Group.Info.AdminLog")
        panel.update(
            left: L10n.telegram("Channel.AdminLog.Settings"),
            leftEnabled: true,
            right: "?",
            rightEnabled: true,
        )
        panel.onLeft = { [weak self] in self?.openFilter() }
        panel.onRight = { [weak self] in self?.showInfo() }
        updateBarButtons()
        panel.layer.zPosition = 999
        tableView.addSubview(panel)
        additionalSafeAreaInsets.bottom += ChatListSelectionToolbar.contentHeight
        loadMore()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPanel()
    }

    override func scrollViewDidScroll(_: UIScrollView) {
        layoutPanel()
    }

    override func makeSections() -> [SettingsSection] {
        guard isLoaded else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        let info = L10n.telegram(
            target.isChannel ? "Channel.AdminLog.InfoPanelChannelAlertText" : "Channel.AdminLog.InfoPanelAlertText",
        )
        guard !events.isEmpty else {
            // ChatRecentActionsControllerNode's empty node names the filter when one is set.
            let filtered = !filter.isDefault(isChannel: target.isChannel) || !query.isEmpty
            // ChatRecentActionsControllerNode: EmptyFilterQueryText for a search, else Group_AdminLog_EmptyText or
            // Broadcast_AdminLog_EmptyText.
            let text =
                if !query.isEmpty {
                    L10n.telegram("Channel.AdminLog.EmptyFilterQueryText", query)
                } else {
                    L10n.telegram(target.isChannel ? "Broadcast.AdminLog.EmptyText" : "Group.AdminLog.EmptyText")
                }
            return [SettingsSection(footer: info, rows: [SettingsRow(
                title: L10n.telegram(filtered ? "Channel.AdminLog.EmptyFilterTitle" : "Channel.AdminLog.EmptyTitle"),
                detail: text,
                style: .subtitle,
            )])]
        }
        var sections = [SettingsSection]()
        eventIndexPaths = [:]
        for event in events {
            let date = Foundation.Date(timeIntervalSince1970: TimeInterval(event.date))
            let header = date.formatted(date: .long, time: .omitted)
            var row = SettingsRow(
                title: event.actor,
                detail: event.text + "\n" + date.formatted(date: .omitted, time: .shortened),
                style: .subtitle,
            )
            if let messageID = event.falsePositiveMessageID, !reportedMessageIDs.contains(messageID) {
                let eventID = event.id
                row.action = { [weak self] in self?.offerFalsePositiveReport(eventID: eventID, messageID: messageID) }
            }
            if sections.last?.header == header {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append(SettingsSection(header: header, rows: [row]))
            }
            eventIndexPaths[event.id] = IndexPath(
                row: sections[sections.count - 1].rows.count - 1,
                section: sections.count - 1,
            )
        }
        sections[sections.count - 1].footer = hasMore ? nil : info
        if hasMore { sections[sections.count - 1].rows.append(ChatManagementRows.loading) }
        return sections
    }

    override func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard hasMore, isLoaded, indexPath.section == sections.count - 1,
              indexPath.row >= (sections.last?.rows.count ?? 0) - 1 else { return }
        loadMore()
    }

    // MARK: Search

    func updateSearchResults(for search: UISearchController) {
        let text = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text != query else { return }
        // The log is searched on the server; typing waits a moment before asking again.
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            queryTask = nil
            query = text
            restartLog()
        }
    }

    func didDismissSearchController(_: UISearchController) {
        guard isSearching else { return }
        isSearching = false
        queryTask?.cancel()
        queryTask = nil
        updateBarButtons()
        if !query.isEmpty {
            query = ""
            restartLog()
        }
    }

    /// The root is the scrolling table: the panel stays at the viewport's bottom, over the home indicator.
    private func layoutPanel() {
        let bottom = max(0, tableView.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        let height = ChatListSelectionToolbar.contentHeight + bottom
        panel.frame = CGRect(
            x: tableView.bounds.minX,
            y: tableView.bounds.maxY - height,
            width: tableView.bounds.width,
            height: height,
        )
        tableView.bringSubviewToFront(panel)
    }

    private func loadMore() {
        guard contextIsCurrent, loadTask == nil, hasMore else { return }
        let client = client
        let chatID = target.chatID
        let fromEventID = oldestEventID
        let isChannel = target.isChannel
        let knownNames = names
        let filters = filter.native(isChannel: isChannel)
        let userIDs = filter.adminUserIDs.map { Array($0).sorted() } ?? []
        let generation = loadGeneration
        let query = query
        loadTask = Task { [weak self] in
            var names = knownNames
            let page = await (try? client.send(TDNativeRequests.getChatEventLog(
                chatId: chatID,
                query: query,
                fromEventId: fromEventID,
                limit: Self.pageLimit,
                filters: filters,
                userIds: userIDs,
            )))?.events
            var resolved = [Event]()
            for event in page ?? [] {
                guard !Task.isCancelled else { return }
                for id in [PeerProfileMemberID(event.memberId)] + ChatEventText.peers(in: event.action)
                    where names[id] == nil
                {
                    names[id] = await SettingsPeer.resolve(id.sender, client: client)?.title ?? ""
                }
                let actor = names[PeerProfileMemberID(event.memberId)] ?? ""
                guard let text = ChatEventText.text(
                    event.action, actor: actor, isChannel: isChannel, name: { names[$0] ?? "" },
                ) else { continue }
                var falsePositiveMessageID: Int64?
                if case .chatEventMessageDeleted(let deleted) = event.action, deleted.canReportAntiSpamFalsePositive {
                    falsePositiveMessageID = deleted.message.id
                }
                resolved.append(Event(
                    id: event.id,
                    date: event.date,
                    actor: actor,
                    text: text,
                    falsePositiveMessageID: falsePositiveMessageID,
                ))
            }
            guard let self, !Task.isCancelled, generation == loadGeneration else { return }
            loadTask = nil
            guard contextIsCurrent else { return }
            self.names = names
            events += resolved
            oldestEventID = page?.last?.id ?? oldestEventID
            hasMore = (page?.count ?? 0) >= Self.pageLimit
            isLoaded = true
            reload()
        }
    }

    // MARK: Filter

    /// openFilterSetup: the admins load first, then the filter opens as a sheet.
    private func openFilter() {
        guard contextIsCurrent, filterTask == nil, presentedViewController == nil else { return }
        let client = client
        let group = target.group
        let chatID = target.chatID
        filterTask = Task { [weak self] in
            let found: [ChatMember] =
                switch group {
                case .supergroup(let id):
                    await (try? client.send(TDNativeRequests.getSupergroupMembers(
                        supergroupId: id, filter: .supergroupMembersFilterAdministrators, offset: 0, limit: 200,
                    )))?.members ?? []
                case .basic:
                    await (ChatManagementTarget.load(chatID: chatID, client: client)?.basicGroupInfo?.members ?? [])
                        .filter {
                            switch $0.status {
                            case .chatMemberStatusAdministrator,
                                 .chatMemberStatusCreator: true
                            default: false
                            }
                        }
                }
            let admins = await ChatManagementMember.resolve(found, client: client).filter { $0.userID != nil }
            guard let self else { return }
            filterTask = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            let screen = ChatRecentActionsFilterViewController(
                filter: filter,
                isChannel: target.isChannel,
                admins: admins,
            ) { [weak self] filter in self?.apply(filter) }
            present(TelegramNavigationController(rootViewController: screen), animated: true)
        }
    }

    /// A new filter reads the log again from its newest event.
    private func apply(_ newFilter: ChatEventLogFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        restartLog()
    }

    private func restartLog() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        events = []
        oldestEventID = 0
        hasMore = true
        isLoaded = false
        reload()
        loadMore()
    }

    /// infoButtonPressed: what the event log is.
    private func showInfo() {
        presentAlert(
            title: L10n.telegram("Channel.AdminLog.InfoPanelAlertTitle"),
            message: L10n.telegram(
                target.isChannel
                    ? "Channel.AdminLog.InfoPanelChannelAlertText"
                    : "Channel.AdminLog.InfoPanelAlertText",
            ),
        )
    }

    private func openSearch() {
        guard !isSearching else { return }
        isSearching = true
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

    // MARK: Anti-spam false positives

    /// ChatRecentActionsControllerNode's message menu for the anti-spam bot's deletion: Report False Positive.
    private func offerFalsePositiveReport(eventID: Int64, messageID: Int64) {
        guard contextIsCurrent, let indexPath = eventIndexPaths[eventID],
              let cell = tableView.cellForRow(at: indexPath)
        else { return }
        presentTelegramContextMenu(
            sourceView: cell,
            actions: [TelegramContextMenuAction(
                title: L10n.telegram("Conversation.ContextMenuReportFalsePositive"),
                image: UIImage(systemName: "checkmark.shield"),
            ) { [weak self] in self?.reportFalsePositive(messageID: messageID) }],
            presentationStyle: .menuOnly,
        )
    }

    /// reportSupergroupAntiSpamFalsePositive, then Telegram's AntiSpamFalsePositiveReportedText toast.
    private func reportFalsePositive(messageID: Int64) {
        guard let supergroupID = target.supergroupID, contextIsCurrent,
              reportedMessageIDs.insert(messageID).inserted
        else { return }
        reload()
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.reportSupergroupAntiSpamFalsePositive(
                    supergroupId: supergroupID, messageId: messageID,
                ))
                guard let self, contextIsCurrent else { return }
                showToast(L10n.telegram("Group.AdminLog.AntiSpamFalsePositiveReportedText"))
            } catch {
                guard let self else { return }
                reportedMessageIDs.remove(messageID)
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }
}
