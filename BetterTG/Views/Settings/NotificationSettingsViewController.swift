// NotificationSettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - NotificationSettingsViewController

/// Telegram's Notifications and Sounds (NotificationsAndSoundsController): private chats, groups and channels with
/// their state and exception counts, and Reset All Notifications. BetterTG has no in-app sound or badge settings to
/// show here.
final class NotificationSettingsViewController: SettingsListViewController {
    private var settings = [NotificationScope: ScopeNotificationSettings]()
    private var exceptionCounts = [NotificationScope: Int]()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.Title")
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
        return [
            SettingsSection(header: L10n.telegram("Notifications.MessageNotifications"), rows: categories),
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
            guard let self, contextIsCurrent else { return }
            self.settings = settings
            exceptionCounts = counts
            reload()
        }
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
