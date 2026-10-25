// StoryNotificationSettingsViewController.swift

import TDLibKit
import UIKit

// MARK: - StoryNotificationSettingsViewController

/// NotificationsPeerCategoryController's `.stories` on the private chats' scope: New Stories, and while it is off
/// Important Stories with "Always on for top 5 contacts."; then Show Sender's Name while stories notify; then the
/// chats whose stories notify their own way (getStoryNotificationSettingsExceptions), each removable. Sounds and adding
/// an exception are not offered, as for the chat categories.
final class StoryNotificationSettingsViewController: SettingsListViewController {
    private var settings: ScopeNotificationSettings
    private var exceptions = [(peer: SettingsPeer, settings: ChatNotificationSettings)]()
    private var isLoadingExceptions = true

    init(settings: ScopeNotificationSettings) {
        self.settings = settings
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Notifications.StoriesTitle")
        loadExceptions()
    }

    override func makeSections() -> [SettingsSection] {
        // StorySettings' mute: unmuted is all stories, default the important ones, muted none.
        let allEnabled = !settings.useDefaultMuteStories && !settings.muteStories
        let importantEnabled = settings.useDefaultMuteStories || !settings.muteStories
        var notifyRows = [SettingsRow(
            title: L10n.telegram("Notifications.Stories.GlobalSetting"),
            accessory: .toggle(isOn: allEnabled) { [weak self] isOn in
                // updateEnabled: on is unmuted, off returns to the important stories.
                self?.saveStories(useDefault: !isOn, mute: false)
            },
        )]
        var footer: String?
        if !allEnabled {
            notifyRows.append(SettingsRow(
                title: L10n.telegram("Notifications.Stories.Important"),
                accessory: .toggle(isOn: importantEnabled) { [weak self] isOn in
                    // updateEnabledImportant: on is the default, off is muted.
                    self?.saveStories(useDefault: isOn, mute: !isOn)
                },
            ))
            footer = L10n.telegram("NotificationSettings.Stories.ShowImportantFooter")
        }
        var sections = [SettingsSection(
            header: L10n.telegram("Notifications.Stories.SettingsHeader"),
            footer: footer,
            rows: notifyRows,
        )]
        // Telegram shows the options while private chats notify or exceptions exist.
        if settings.muteFor == 0 || !exceptions.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Notifications.Options").uppercased(),
                rows: [SettingsRow(
                    title: L10n.telegram("Notifications.Stories.DisplayName"),
                    accessory: .toggle(isOn: settings.showStoryPoster) { [weak self] isOn in
                        self?.saveShowsPoster(isOn)
                    },
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
                    handler: { [weak self] in self?.removeExceptions(chatIDs: [chatID]) },
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

    // MARK: Private

    /// An exception's line: Always On or Off, then a custom sound and a name shown or hidden.
    private static func exceptionText(_ settings: ChatNotificationSettings) -> String {
        let muted = !settings.useDefaultMuteStories && settings.muteStories
        var parts = [L10n.telegram(muted ? "Notification.Exceptions.AlwaysOff" : "Notification.Exceptions.AlwaysOn")]
        if !muted {
            if !settings.useDefaultStorySound {
                parts.append(L10n.telegram("Notification.Exceptions.SoundCustom"))
            }
            if !settings.useDefaultShowStoryPoster {
                parts.append(L10n.telegram(settings.showStoryPoster
                        ? "NotificationSettings.Stories.CompactShowName"
                        : "NotificationSettings.Stories.CompactHideName"))
            }
        }
        return parts.joined(separator: ", ")
    }

    private func saveStories(useDefault: Bool, mute: Bool) {
        save(settings.updatingStories(
            useDefaultMuteStories: useDefault,
            muteStories: mute,
            showStoryPoster: settings.showStoryPoster,
        ))
    }

    private func saveShowsPoster(_ shows: Bool) {
        save(settings.updatingStories(
            useDefaultMuteStories: settings.useDefaultMuteStories,
            muteStories: settings.muteStories,
            showStoryPoster: shows,
        ))
    }

    private func save(_ updated: ScopeNotificationSettings) {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let succeeded = await (try? client.send(TDNativeRequests.setScopeNotificationSettings(
                scope: .notificationSettingsScopePrivateChats, notificationSettings: updated,
            ))) != nil
            guard let self, contextIsCurrent else { return }
            if succeeded {
                settings = updated
            } else {
                presentChatListActionFailure()
            }
            reload()
        }
    }

    private func loadExceptions() {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            let chatIDs = await (try? client.send(TDNativeRequests.getStoryNotificationSettingsExceptions()))?
                .chatIds ?? []
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

    /// Removing an exception returns the chat's story mute, sound and name to the scope's defaults.
    private func removeExceptions(chatIDs: [Int64]) {
        let items = exceptions.filter { chatIDs.contains($0.peer.id) }
        perform { client in
            for item in items {
                _ = try await client.setChatNotificationSettings(
                    chatId: item.peer.id,
                    notificationSettings: item.settings.usingStoryDefaults,
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
        ) { [weak self] in self?.removeExceptions(chatIDs: chatIDs) }
    }
}

// MARK: - Helpers

private extension ScopeNotificationSettings {
    func updatingStories(
        useDefaultMuteStories: Bool,
        muteStories: Bool,
        showStoryPoster: Bool,
    ) -> ScopeNotificationSettings {
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
    var usingStoryDefaults: ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: useDefaultMuteFor,
            useDefaultMuteStories: true,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: true,
            useDefaultSound: useDefaultSound,
            useDefaultStorySound: true,
        )
    }
}
