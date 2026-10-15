// NotificationCategoryViewController.swift

import TDLibKit
import UIKit

// MARK: - NotificationCategoryViewController

/// Telegram's NotificationsPeerCategoryController for private chats, groups or channels: Alert and Message Preview
/// for the scope (setScopeNotificationSettings), then the chats with their own settings, each removable, and Delete
/// All Exceptions. Sounds and adding an exception are not offered.
final class NotificationCategoryViewController: SettingsListViewController {
    private let scope: NotificationScope
    private var settings: ScopeNotificationSettings
    private var exceptions = [(peer: SettingsPeer, settings: ChatNotificationSettings)]()
    private var isLoadingExceptions = true

    init(scope: NotificationScope, settings: ScopeNotificationSettings) {
        self.scope = scope
        self.settings = settings
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = scope.screenTitle
        loadExceptions()
    }

    override func makeSections() -> [SettingsSection] {
        let enabled = settings.muteFor == 0
        var sections = [SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("Notifications.MessageNotificationsAlert"),
            accessory: .toggle(isOn: enabled, onChange: { [weak self] isOn in self?.setEnabled(isOn) }),
        )])]
        if enabled {
            sections.append(SettingsSection(
                header: L10n.telegram("Notifications.Options").uppercased(),
                rows: [SettingsRow(
                    title: L10n.telegram("Notifications.MessageNotificationsPreview"),
                    accessory: .toggle(isOn: settings.showPreview, onChange: { [weak self] isOn in
                        self?.setShowsPreview(isOn)
                    }),
                )],
            ))
        }
        var exceptionRows = exceptions.map { item in
            let chatID = item.peer.id
            return SettingsRow(
                title: item.peer.title,
                detail: Self.exceptionText(item.settings),
                style: .peer(item.peer),
                swipeAction: (
                    title: L10n.telegram("Common.Delete"),
                    handler: { [weak self] in self?.removeException(chatIDs: [chatID]) },
                ),
            )
        }
        if isLoadingExceptions {
            exceptionRows.append(SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            ))
        } else if exceptions.count > 1 {
            exceptionRows.append(SettingsRow(
                title: L10n.telegram("Notifications.DeleteAllExceptions"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmRemoveAll() })
        }
        if !exceptionRows.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Notifications.MessageNotificationsExceptions").uppercased(),
                rows: exceptionRows,
            ))
        }
        return sections
    }

    /// Telegram's exception subtitle: Always On, Always Off or Muted until, with the preview and sound overrides.
    private static func exceptionText(_ settings: ChatNotificationSettings) -> String {
        var parts = [String]()
        if !settings.useDefaultMuteFor {
            if settings.muteFor == 0 {
                parts.append(L10n.telegram("Notification.Exceptions.AlwaysOn"))
            } else if settings.muteFor >= 365 * 24 * 60 * 60 {
                parts.append(L10n.telegram("Notification.Exceptions.AlwaysOff"))
            } else {
                let until = Date().addingTimeInterval(TimeInterval(settings.muteFor))
                parts.append(L10n.telegram(
                    "Notification.Exceptions.MutedUntil",
                    until.formatted(date: .abbreviated, time: .shortened),
                ))
            }
        }
        if !settings.useDefaultShowPreview {
            parts.append(L10n.telegram(
                settings.showPreview
                    ? "Notification.Exceptions.PreviewAlwaysOn"
                    : "Notification.Exceptions.PreviewAlwaysOff",
            ))
        }
        if !settings.useDefaultSound {
            parts.append(L10n.telegram("Notification.Exceptions.SoundCustom"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Scope

    private func setEnabled(_ enabled: Bool) {
        save(settings.updating(muteFor: enabled ? 0 : Int(Int32.max), showPreview: settings.showPreview))
    }

    private func setShowsPreview(_ showsPreview: Bool) {
        save(settings.updating(muteFor: settings.muteFor, showPreview: showsPreview))
    }

    private func save(_ updated: ScopeNotificationSettings) {
        guard contextIsCurrent else { return }
        let client = client
        let tdScope = scope.tdScope
        Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.setScopeNotificationSettings(
                scope: tdScope, notificationSettings: updated,
            ))) != nil
            guard let self, contextIsCurrent else { return }
            if succeeded {
                settings = updated
            } else {
                presentChatListActionFailure()
            }
            // A failed change returns the switch to the saved value.
            reload()
        }
    }

    // MARK: Exceptions

    private func loadExceptions() {
        guard contextIsCurrent else { return }
        let client = client
        let tdScope = scope.tdScope
        Task { [weak self] in
            let chatIDs = await (try? client.send(TDNativeRequests.getChatNotificationSettingsExceptions(
                scope: tdScope, compareSound: false,
            )))?.chatIds ?? []
            var loaded = [(peer: SettingsPeer, settings: ChatNotificationSettings)]()
            for id in chatIDs {
                guard let chat = try? await client.getChat(chatId: id) else { continue }
                loaded.append((peer: SettingsPeer(chat: chat), settings: chat.notificationSettings))
            }
            guard let self, contextIsCurrent else { return }
            exceptions = loaded
            isLoadingExceptions = false
            reload()
        }
    }

    /// Telegram removes an exception by returning the chat's mute, sound and preview to the scope's defaults.
    private func removeException(chatIDs: [Int64]) {
        let items = exceptions.filter { chatIDs.contains($0.peer.id) }
        perform { client in
            for item in items {
                _ = try await client.setChatNotificationSettings(
                    chatId: item.peer.id,
                    notificationSettings: item.settings.usingScopeDefaults,
                )
            }
        } completion: { [weak self] in
            self?.exceptions.removeAll { chatIDs.contains($0.peer.id) }
            self?.reload()
        }
    }

    private func confirmRemoveAll() {
        let chatIDs = exceptions.map(\.peer.id)
        confirm(
            message: L10n.telegram("Notification.Exceptions.DeleteAllConfirmation"),
            actionTitle: L10n.telegram("Notification.Exceptions.DeleteAll"),
        ) { [weak self] in self?.removeException(chatIDs: chatIDs) }
    }
}

// MARK: - Helpers

private extension ScopeNotificationSettings {
    func updating(muteFor: Int, showPreview: Bool) -> ScopeNotificationSettings {
        ScopeNotificationSettings(
            muteFor: muteFor,
            soundId: soundId,
            showPreview: showPreview,
            useDefaultMuteStories: useDefaultMuteStories,
            muteStories: muteStories,
            storySoundId: storySoundId,
            showStoryPoster: showStoryPoster,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            disableMentionNotifications: disableMentionNotifications,
        )
    }
}

private extension ChatNotificationSettings {
    var usingScopeDefaults: ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: 0,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: true,
            useDefaultMuteStories: useDefaultMuteStories,
            useDefaultShowPreview: true,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: true,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}
