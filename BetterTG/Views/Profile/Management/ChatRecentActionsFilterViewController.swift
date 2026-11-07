// ChatRecentActionsFilterViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatEventLogFilter

/// What Recent Actions shows: ChatRecentActionsFilterController's event groups (AdminLogEventsFlags) and admins.
struct ChatEventLogFilter: Equatable {
    /// The groups in the filter's order; a channel has no restrictions.
    enum Category: CaseIterable {
        case restrictions
        case admins
        case newMembers
        case info
        case inviteLinks
        case deletedMessages
        case editedMessages
        case pinnedMessages
        case leaving
        case calls

        static func all(isChannel: Bool) -> [Category] {
            isChannel ? allCases.filter { $0 != .restrictions } : allCases
        }

        func title(isChannel: Bool) -> String {
            switch self {
            case .restrictions: L10n.telegram("Channel.AdminLogFilter.EventsRestrictions")
            case .admins: L10n.telegram("Channel.AdminLogFilter.EventsAdmins")
            case .newMembers: L10n.telegram("Channel.AdminLogFilter.EventsNewMembers")
            case .info: L10n.telegram(isChannel
                    ? "Channel.AdminLogFilter.ChannelEventsInfo"
                    : "Channel.AdminLogFilter.EventsInfo")
            case .inviteLinks: L10n.telegram("Channel.AdminLogFilter.EventsInviteLinks")
            case .deletedMessages: L10n.telegram("Channel.AdminLogFilter.EventsDeletedMessages")
            case .editedMessages: L10n.telegram("Channel.AdminLogFilter.EventsEditedMessages")
            case .pinnedMessages: L10n.telegram("Channel.AdminLogFilter.EventsPinned")
            case .leaving: L10n.telegram("Channel.AdminLogFilter.EventsLeaving")
            case .calls: L10n.telegram(isChannel
                    ? "Channel.AdminLogFilter.EventsLiveStreams"
                    : "Channel.AdminLogFilter.EventsCalls")
            }
        }
    }

    var categories = Set(Category.allCases)
    /// The admins whose actions show; nil shows everyone's.
    var adminUserIDs: Set<Int64>?

    func isDefault(isChannel: Bool) -> Bool {
        Set(Category.all(isChannel: isChannel)).isSubset(of: categories) && adminUserIDs == nil
    }

    /// getChatEventLog's filters: nil while every group is on. TDLib's finer kinds go with the group Telegram shows
    /// them under: tags with admins, subscriptions with new members, topics with the info.
    func native(isChannel: Bool) -> ChatEventLogFilters? {
        guard !Set(Category.all(isChannel: isChannel)).isSubset(of: categories) else { return nil }
        return TDNativeChatEventLogFilters(
            messageEdits: categories.contains(.editedMessages),
            messageDeletions: categories.contains(.deletedMessages),
            messagePins: categories.contains(.pinnedMessages),
            memberJoins: categories.contains(.newMembers),
            memberLeaves: categories.contains(.leaving),
            memberInvites: categories.contains(.newMembers),
            memberPromotions: categories.contains(.admins),
            memberRestrictions: categories.contains(.restrictions),
            memberTagChanges: categories.contains(.admins),
            infoChanges: categories.contains(.info),
            settingChanges: categories.contains(.info),
            inviteLinkChanges: categories.contains(.inviteLinks),
            videoChatChanges: categories.contains(.calls),
            forumChanges: categories.contains(.info),
            subscriptionExtensions: categories.contains(.newMembers),
        )
    }
}

// MARK: - ChatRecentActionsFilterViewController

/// Telegram's ChatRecentActionsFilterController: All Actions and each group of events with a check, then All Admins
/// and each admin with a check. Done applies it while at least one group and one admin stay chosen.
final class ChatRecentActionsFilterViewController: SettingsListViewController {
    private let isChannel: Bool
    private let admins: [ChatManagementMember]
    private let onApply: (ChatEventLogFilter) -> Void
    private var filter: ChatEventLogFilter

    private var categories: [ChatEventLogFilter.Category] {
        ChatEventLogFilter.Category.all(isChannel: isChannel)
    }

    private var allAdminIDs: Set<Int64> {
        Set(admins.compactMap(\.userID))
    }

    init(
        filter: ChatEventLogFilter,
        isChannel: Bool,
        admins: [ChatManagementMember],
        onApply: @escaping (ChatEventLogFilter) -> Void,
    ) {
        self.filter = filter
        self.isChannel = isChannel
        self.admins = admins
        self.onApply = onApply
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("ChatAdmins.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closePressed),
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = L10n.telegram("Common.Close")
        navigationItem.rightBarButtonItem = UIBarButtonItem.telegramDone(target: self, action: #selector(donePressed))
        updateDone()
    }

    override func makeSections() -> [SettingsSection] {
        let allActions = Set(categories).isSubset(of: filter.categories)
        var actionRows = [SettingsRow(
            title: L10n.telegram("Channel.AdminLogFilter.EventsAll"),
            accessory: .toggle(isOn: allActions, onChange: { [weak self] isOn in
                guard let self else { return }
                filter.categories = isOn ? Set(categories) : []
                changed()
            }),
        )]
        for category in categories {
            actionRows.append(SettingsRow(
                title: category.title(isChannel: isChannel),
                accessory: filter.categories.contains(category) ? .checkmark : .none,
            ) { [weak self] in
                guard let self else { return }
                if filter.categories.remove(category) == nil { filter.categories.insert(category) }
                changed()
            })
        }
        var sections = [SettingsSection(
            header: L10n.telegram("Channel.AdminLogFilter.EventsTitle"),
            rows: actionRows,
        )]
        guard !admins.isEmpty else { return sections }
        let chosen = filter.adminUserIDs ?? allAdminIDs
        var adminRows = [SettingsRow(
            title: L10n.telegram("Channel.AdminLogFilter.AdminsAll"),
            accessory: .toggle(isOn: allAdminIDs.isSubset(of: chosen), onChange: { [weak self] isOn in
                guard let self else { return }
                filter.adminUserIDs = isOn ? nil : []
                changed()
            }),
        )]
        for admin in admins {
            guard let userID = admin.userID else { continue }
            let isOwner =
                if case .chatMemberStatusCreator = admin.status {
                    true
                } else {
                    false
                }
            adminRows.append(SettingsRow(
                title: admin.peer.title,
                detail: L10n.telegram(isOwner ? "Channel.Management.LabelOwner" : "ChatAdmins.AdminLabel")
                    .lowercased(),
                style: .peer(admin.peer),
                accessory: chosen.contains(userID) ? .checkmark : .none,
            ) { [weak self] in self?.toggleAdmin(userID) })
        }
        sections.append(SettingsSection(
            header: L10n.telegram("Channel.AdminLogFilter.AdminsTitle"),
            rows: adminRows,
        ))
        return sections
    }

    private func toggleAdmin(_ userID: Int64) {
        var chosen = filter.adminUserIDs ?? allAdminIDs
        if chosen.remove(userID) == nil { chosen.insert(userID) }
        filter.adminUserIDs = chosen == allAdminIDs ? nil : chosen
        changed()
    }

    private func changed() {
        refreshRowsInPlace()
        updateDone()
    }

    /// doneEnabled: a group of events and an admin to show.
    private func updateDone() {
        navigationItem.rightBarButtonItem?.isEnabled = !filter.categories.isDisjoint(with: categories)
            && filter.adminUserIDs?.isEmpty != true
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        onApply(filter)
        dismiss(animated: true)
    }
}
