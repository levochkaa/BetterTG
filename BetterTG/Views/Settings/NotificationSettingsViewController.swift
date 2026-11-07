// NotificationSettingsViewController.swift

import Combine
import TDLibKit
import UIKit
import UserNotifications

// MARK: - NotificationSettingsViewController

/// Telegram's Notifications and Sounds (NotificationsAndSoundsController): private chats, groups and channels with
/// their state and exception counts, Stories, Reactions, In-App Notifications, the Badge Counter's Count Unread
/// Messages, New Contacts (`disable_contact_registered_notifications`), and Reset All Notifications. TDLib counts
/// unread chats without telling channels apart, so Include Channels has no counterpart. BetterTG adds the switch for
/// its push relay.
final class NotificationSettingsViewController: SettingsListViewController {
    /// The states NotificationsAndSoundsController warns about: never asked, refused, or allowed without alerts.
    private enum NotificationPermissionWarning {
        case notDetermined
        case denied
        case unreachable
    }

    /// ApplicationSpecificNotice's permission warning: the unreachable warning closed with Keep Disabled.
    private static let suppressedWarningKey = "BetterTG.notificationPermissionWarningSuppressed"

    private var settings = [NotificationScope: ScopeNotificationSettings]()
    private var exceptionCounts = [NotificationScope: Int]()
    /// Whether TDLib notifies about contacts who join Telegram; nil until read.
    private var contactJoinedEnabled: Bool?
    private var storyExceptionCount: Int?
    private var reactionCancellable: AnyCancellable?
    private var activeCancellable: AnyCancellable?
    /// DeviceAccess' notification status: nil while allowed (or unknown).
    private var permission: NotificationPermissionWarning?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.Title")
        reactionCancellable = ReactionNotificationSettingsStore.shared
            .changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
        activeCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.loadPermission() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
        loadPermission()
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
        if let privateChats = settings[.privateChats] {
            rows.append(storiesRow(privateChats))
        }
        if let reactions = ReactionNotificationSettingsStore.shared.settings(for: client) {
            rows.append(reactionsRow(reactions))
        }
        var sections = permissionSections() + [
            SettingsSection(header: L10n.telegram("Notifications.MessageNotifications"), rows: rows),
            inAppSection(),
            badgeSection(),
        ]
        if let contactJoinedEnabled {
            sections.append(SettingsSection(
                footer: L10n.telegram("NotificationSettings.ContactJoinedInfo"),
                rows: [SettingsRow(
                    title: L10n.telegram("NotificationSettings.ContactJoined"),
                    accessory: .toggle(isOn: contactJoinedEnabled) { [weak self] isOn in self?.setContactJoined(isOn) },
                )],
            ))
        }
        if PushRelayCoordinator.shared.isAvailable {
            sections.append(relaySection())
        }
        return sections + [
            SettingsSection(footer: L10n.telegram("Notifications.ResetAllNotificationsHelp"), rows: [SettingsRow(
                title: L10n.telegram("Notifications.ResetAllNotifications"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmReset() }]),
        ]
    }

    /// DeviceAccess.authorizationStatus: refused, never asked, or allowed with neither alerts nor the lock screen.
    private func loadPermission() {
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            var warning: NotificationPermissionWarning? =
                switch settings.authorizationStatus {
                case .denied: .denied
                case .notDetermined: .notDetermined
                default:
                    settings.alertSetting != .enabled && settings.lockScreenSetting != .enabled
                        && settings.notificationCenterSetting != .enabled ? .unreachable : nil
                }
            #if DEBUG
                // `-ui-probe-notification-permission denied|unreachable|not-determined` shows a warning.
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-ui-probe-notification-permission") {
                    warning =
 switch arguments[safe: index + 1] {
                    case "unreachable": .unreachable
                    case "not-determined": .notDetermined
                    default: .denied
                    }
                }
            #endif
            guard let self else { return }
            if warning == .unreachable, UserDefaults.standard.bool(forKey: Self.suppressedWarningKey) {
                warning = nil
            }
            guard warning != permission else { return }
            permission = warning
            reload()
        }
    }

    /// The warning's section: Turn ON Notifications (Check Notification Settings when alerts are off) with its text,
    /// and Turn Notifications ON, Turn ON in Settings or Open Settings; the unreachable warning can be closed.
    private func permissionSections() -> [SettingsSection] {
        guard let permission else { return [] }
        let unreachable = permission == .unreachable
        var info = SettingsRow(
            title: L10n.telegram(unreachable
                ? "Notifications.PermissionsUnreachableTitle"
                : "Notifications.PermissionsTitle"),
            detail: L10n.telegram(unreachable
                ? "Notifications.PermissionsUnreachableText"
                : "Notifications.PermissionsText"),
            style: .subtitle,
        )
        if unreachable {
            info.trailingView = SettingsTrailingView { [weak self] in
                let close = UIButton(type: .system)
                close.setImage(UIImage(systemName: "xmark"), for: .normal)
                close.tintColor = .tertiaryLabel
                close.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
                close.accessibilityLabel = L10n.telegram("Common.Close")
                close.addAction(UIAction { [weak self] _ in self?.suppressPermissionWarning() }, for: .touchUpInside)
                return close
            }
        }
        let actionKey =
            switch permission {
            case .notDetermined: "Notifications.PermissionsAllow"
            case .denied: "Notifications.PermissionsAllowInSettings"
            case .unreachable: "Notifications.PermissionsOpenSettings"
            }
        let action = SettingsRow(
            title: L10n.telegram(actionKey),
            style: .action(destructive: false),
        ) { [weak self] in self?.authorizeNotifications() }
        return [SettingsSection(rows: [info, action])]
    }

    /// authorizeNotifications: the system's question when it hasn't been asked, otherwise the app's settings.
    private func authorizeNotifications() {
        if permission == .notDetermined {
            Task { [weak self] in
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
                    .alert,
                    .badge,
                    .sound,
                ])
                UIApplication.shared.registerForRemoteNotifications()
                self?.loadPermission()
            }
            return
        }
        if permission == .unreachable { UserDefaults.standard.set(true, forKey: Self.suppressedWarningKey) }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// suppressWarning: Keep notifications disabled? with Keep Disabled and Enable.
    private func suppressPermissionWarning() {
        let alert = UIAlertController(
            title: L10n.telegram("Notifications.PermissionsSuppressWarningTitle"),
            message: L10n.telegram("Notifications.PermissionsSuppressWarningText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Notifications.PermissionsKeepDisabled"), style: .default) {
            [weak self] _ in
            UserDefaults.standard.set(true, forKey: Self.suppressedWarningKey)
            self?.permission = nil
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Notifications.PermissionsEnable"), style: .cancel) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
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
            let storyExceptions = try? await client.send(TDNativeRequests.getStoryNotificationSettingsExceptions())
            guard let self, contextIsCurrent else { return }
            self.settings = settings
            exceptionCounts = counts
            contactJoinedEnabled = contactJoined
            storyExceptionCount = storyExceptions?.chatIds.count
            reload()
        }
    }

    /// NotificationsAndSoundsController's `.stories`: Top 5 by default, else On or Off, with the exception count.
    private func storiesRow(_ settings: ScopeNotificationSettings) -> SettingsRow {
        var detail = L10n.telegram(settings.useDefaultMuteStories
            ? "Notifications.TopChats"
            : settings.muteStories ? "Notifications.Off" : "Notifications.On")
        if let count = storyExceptionCount, count > 0 {
            detail += ", " + L10n.telegramPlural("Notifications.CategoryExceptions", count: count)
        }
        return SettingsRow(
            title: L10n.telegram("Notifications.Stories"),
            detail: detail,
            style: .subtitle,
            symbol: "circle.dashed",
            symbolTint: .systemPurple,
            accessory: .disclosure,
        ) { [weak self] in
            guard let self, let current = self.settings[.privateChats] else { return }
            navigationController?.pushViewController(
                StoryNotificationSettingsViewController(settings: current),
                animated: true,
            )
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

    /// In-App Sounds, In-App Vibrate and In-App Preview, for messages that arrive while BetterTG is open.
    private func inAppSection() -> SettingsSection {
        SettingsSection(header: L10n.telegram("Notifications.InAppNotifications"), rows: [
            SettingsRow(
                title: L10n.telegram("Notifications.InAppNotificationsSounds"),
                accessory: .toggle(isOn: InAppNotificationSettings.playSounds) { isOn in
                    InAppNotificationSettings.playSounds = isOn
                },
            ),
            SettingsRow(
                title: L10n.telegram("Notifications.InAppNotificationsVibrate"),
                accessory: .toggle(isOn: InAppNotificationSettings.vibrate) { isOn in
                    InAppNotificationSettings.vibrate = isOn
                },
            ),
            SettingsRow(
                title: L10n.telegram("Notifications.InAppNotificationsPreview"),
                accessory: .toggle(isOn: InAppNotificationSettings.displayPreviews) { isOn in
                    InAppNotificationSettings.displayPreviews = isOn
                },
            ),
        ])
    }

    /// The Badge Counter's Count Unread Messages, with the note on what switching it does.
    private func badgeSection() -> SettingsSection {
        let countsMessages = InAppNotificationSettings.badgeCountsMessages
        return SettingsSection(
            header: L10n.telegram("Notifications.Badge"),
            footer: L10n.telegram(countsMessages
                ? "Notifications.Badge.CountUnreadMessages.InfoOn"
                : "Notifications.Badge.CountUnreadMessages.InfoOff"),
            rows: [SettingsRow(
                title: L10n.telegram("Notifications.Badge.CountUnreadMessages"),
                accessory: .toggle(isOn: countsMessages) { [weak self] isOn in
                    InAppNotificationSettings.badgeCountsMessages = isOn
                    self?.reload()
                },
            )],
        )
    }

    /// Notifications via BetterTG Server: off, after a confirmation, deletes the device's data from the relay.
    private func relaySection() -> SettingsSection {
        SettingsSection(footer: L10n.betterTG("Notifications.RelayInfo"), rows: [SettingsRow(
            title: L10n.betterTG("Notifications.Relay"),
            accessory: .toggle(isOn: PushRelayCoordinator.shared.isEnabled) { [weak self] isOn in
                guard !isOn else {
                    PushRelayCoordinator.shared.setEnabled(true)
                    return
                }
                self?.confirm(
                    message: L10n.betterTG("Notifications.RelayOffConfirmation"),
                    actionTitle: L10n.betterTG("Notifications.RelayOff"),
                    cancel: { [weak self] in self?.reload() },
                ) {
                    PushRelayCoordinator.shared.setEnabled(false)
                }
            },
        )])
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
