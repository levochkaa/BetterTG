// NotificationSettingsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - NotificationSettingsViewController

/// Telegram's Notifications and Sounds (NotificationsAndSoundsController): private chats, groups and channels with
/// their state and exception counts, Reactions, New Contacts (`disable_contact_registered_notifications`), and Reset
/// All Notifications. BetterTG has no in-app sound or badge settings to show here.
final class NotificationSettingsViewController: SettingsListViewController {
    private var settings = [NotificationScope: ScopeNotificationSettings]()
    private var exceptionCounts = [NotificationScope: Int]()
    /// Whether TDLib notifies about contacts who join Telegram; nil until read.
    private var contactJoinedEnabled: Bool?
    private var reactionCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.Title")
        reactionCancellable = ReactionNotificationSettingsStore.shared
            .changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        let categories = NotificationScope.allCases.map { scope in
            var detail = settings[scope].map {
                L10n.telegram($0.muteFor == 0 ? "Notifications.On" : "Notifications.Off")
            } ?? L10n.telegram("Channel.NotificationLoading")
            if let count = exceptionCounts[scope], count > 0 {
                detail += ", " + L10n.telegramPlural("Notifications.CategoryExceptions", count: count)
            }
            return SettingsRow(
                title: scope.title,
                detail: detail,
                style: .subtitle,
                symbol: scope.symbol,
                symbolTint: scope.tint,
                accessory: .disclosure,
                isEnabled: settings[scope] != nil,
            ) { [weak self] in self?.openCategory(scope) }
        }
        var rows = categories
        if let reactions = ReactionNotificationSettingsStore.shared.settings(for: client) {
            rows.append(reactionsRow(reactions))
        }
        var sections = [SettingsSection(header: L10n.telegram("Notifications.MessageNotifications"), rows: rows)]
        if let contactJoinedEnabled {
            sections.append(SettingsSection(
                footer: L10n.telegram("NotificationSettings.ContactJoinedInfo"),
                rows: [SettingsRow(
                    title: L10n.telegram("NotificationSettings.ContactJoined"),
                    accessory: .toggle(isOn: contactJoinedEnabled) { [weak self] isOn in self?.setContactJoined(isOn) },
                )],
            ))
        }
        return sections + [
            SettingsSection(footer: L10n.telegram("Notifications.ResetAllNotificationsHelp"), rows: [SettingsRow(
                title: L10n.telegram("Notifications.ResetAllNotifications"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmReset() }]),
        ]
    }

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            var settings = [NotificationScope: ScopeNotificationSettings]()
            var counts = [NotificationScope: Int]()
            for scope in NotificationScope.allCases {
                settings[scope] = try? await client
                    .send(TDNativeRequests.getScopeNotificationSettings(scope: scope.tdScope))
                counts[scope] = try? await client.send(TDNativeRequests.getChatNotificationSettingsExceptions(
                    scope: scope.tdScope, compareSound: false,
                ))
                .chatIds
                .count
            }
            let contactJoined =
                if case .optionValueBoolean(let disabled) = try? await client.getOption(
                    name: "disable_contact_registered_notifications",
                ) {
                    !disabled.value
                } else {
                    true
                }
            guard let self, contextIsCurrent else { return }
            self.settings = settings
            exceptionCounts = counts
            contactJoinedEnabled = contactJoined
            reload()
        }
    }

    /// NotificationsAndSoundsController's `.reactions`: Messages and Stories while they notify, else Off.
    private func reactionsRow(_ settings: TDNativeReactionNotificationSettings) -> SettingsRow {
        var parts = [String]()
        if settings.messageReactionSource != .reactionNotificationSourceNone {
            parts.append(L10n.telegram("Notifications.Reactions.SubtitleMessages"))
        }
        if settings.storyReactionSource != .reactionNotificationSourceNone {
            parts.append(L10n.telegram("Notifications.Reactions.SubtitleStories"))
        }
        return SettingsRow(
            title: L10n.telegram("Notifications.Reactions"),
            detail: parts.isEmpty ? L10n.telegram("Notifications.Off") : parts.joined(separator: ", "),
            style: .subtitle,
            symbol: "heart.fill",
            symbolTint: .systemRed,
            accessory: .disclosure,
        ) { [weak self] in
            self?.navigationController?.pushViewController(ReactionNotificationSettingsViewController(), animated: true)
        }
    }

    private func setContactJoined(_ isOn: Bool) {
        contactJoinedEnabled = isOn
        perform { client in
            _ = try await client.setOption(
                name: "disable_contact_registered_notifications",
                value: .optionValueBoolean(TDNativeOptionValueBoolean(value: !isOn)),
            )
        } completion: {}
    }

    private func openCategory(_ scope: NotificationScope) {
        guard let current = settings[scope] else { return }
        let controller = NotificationCategoryViewController(scope: scope, settings: current)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func confirmReset() {
        confirm(
            message: L10n.telegram("Notifications.ResetAllNotificationsText"),
            actionTitle: L10n.telegram("Notifications.Reset"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.resetAllNotificationSettings())
            } completion: { [weak self] in
                self?.load()
            }
        }
    }
}

// MARK: - NotificationScope

enum NotificationScope: CaseIterable {
    case privateChats
    case groupChats
    case channels

    var tdScope: NotificationSettingsScope {
        switch self {
        case .privateChats: .notificationSettingsScopePrivateChats
        case .groupChats: .notificationSettingsScopeGroupChats
        case .channels: .notificationSettingsScopeChannelChats
        }
    }

    var title: String {
        switch self {
        case .privateChats: L10n.telegram("Notifications.PrivateChats")
        case .groupChats: L10n.telegram("Notifications.GroupChats")
        case .channels: L10n.telegram("Notifications.Channels")
        }
    }

    var screenTitle: String {
        switch self {
        case .privateChats: L10n.telegram("Notifications.PrivateChatsTitle")
        case .groupChats: L10n.telegram("Notifications.GroupChatsTitle")
        case .channels: L10n.telegram("Notifications.ChannelsTitle")
        }
    }

    var symbol: String {
        switch self {
        case .privateChats: "person.fill"
        case .groupChats: "person.2.fill"
        case .channels: "megaphone.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .privateChats: .systemBlue
        case .groupChats: .systemGreen
        case .channels: .systemOrange
        }
    }
}
