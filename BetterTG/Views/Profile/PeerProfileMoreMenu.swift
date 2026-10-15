// PeerProfileMoreMenu.swift

import TDLibKit
import UIKit

// MARK: - PeerProfileMoreMenu

/// The chat actions of Telegram's profile header (PeerInfoScreenPerformButtonAction: the Mute button's menu and the
/// More menu's Auto-Delete, Clear Messages and Leave items), read from the chat's current state. BetterTG keeps them in
/// one More menu. Every request runs on the profile's client and is dropped once it is no longer current.
@MainActor struct PeerProfileMoreMenu {
    let customChat: CustomChat
    /// The chat as TDLib has it now, for its notification settings and auto-delete timer.
    let chat: Chat
    let client: TDLibClient
    let canChangeInfo: Bool
    let scope: ChatListActionScope
    weak var host: UIViewController?

    // MARK: Mute

    private var isMuted: Bool {
        let settings = chat.notificationSettings
        if settings.useDefaultMuteFor,
           let scopeSettings = RootVM.shared.scopeNotificationSettings[customChat.notificationSettingsScope]
        {
            return scopeSettings.muteFor > 0
        }
        return settings.muteFor > 0
    }

    // MARK: Auto-Delete

    /// Telegram's canSetupAutoremoveTimeout: a person (not a bot), or a group or channel whose info this account
    /// can change.
    private var canSetAutoDelete: Bool {
        switch customChat.type {
        case .user: !customChat.isSavedMessages
        case .bot: false
        case .group, .supergroup: canChangeInfo
        }
    }

    /// Telegram's `muteForIntervalString` / `mutedForTimeIntervalString`: hours below a day, days above.
    private static func intervalText(_ prefix: String, seconds: Int) -> String {
        let (key, count) = seconds < 24 * 60 * 60
            ? ("\(prefix).Hours", max(1, seconds / (60 * 60)))
            : ("\(prefix).Days", max(1, seconds / (24 * 60 * 60)))
        return L10n.telegramPlural(key, count: count, formattedCount: count.formatted(.number))
    }

    /// Telegram's timeIntervalString for the auto-delete presets: days, weeks or months.
    private static func timeInterval(_ seconds: Int) -> String {
        let day = 24 * 60 * 60
        let (key, count): (String, Int) =
            if seconds < day * 7 {
                ("MessageTimer.Days", seconds / day)
            } else if seconds < day * 30 {
                ("MessageTimer.Weeks", seconds / (day * 7))
            } else {
                ("MessageTimer.Months", seconds / (day * 30))
            }
        return L10n.telegramPlural(key, count: max(1, count))
    }

    func actions() -> [TelegramContextMenuAction] {
        var actions = [muteAction()]
        if canSetAutoDelete {
            actions.append(autoDeleteAction())
        }
        if let clear = clearMessagesAction() {
            actions.append(clear)
        }
        actions.append(removalAction())
        return actions
    }

    /// Muted: Unmute. Otherwise Telegram's Mute menu: Mute for… presets, the sound toggle and Mute Forever.
    private func muteAction() -> TelegramContextMenuAction {
        let settings = chat.notificationSettings
        guard !isMuted else {
            return TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.ButtonUnmute"),
                image: UIImage(systemName: "speaker.wave.2.fill"),
            ) { updateNotifications(settings.settingMuteFor(0), toast: L10n.telegram("PeerInfo.TooltipUnmuted")) }
        }
        let presets = [60 * 60, 8 * 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60]
        let soundEnabled = settings.useDefaultSound || settings.soundId != 0
        return TelegramContextMenuAction(
            title: L10n.telegram("PeerInfo.ButtonMute"),
            image: UIImage(systemName: "speaker.slash.fill"),
            children: [
                TelegramContextMenuAction(
                    title: L10n.telegram("PeerInfo.MuteFor"),
                    image: UIImage(systemName: "clock"),
                    children: presets.map { seconds in
                        TelegramContextMenuAction(title: Self.intervalText("MuteFor", seconds: seconds)) {
                            updateNotifications(
                                settings.settingMuteFor(seconds),
                                toast: L10n.telegram(
                                    "PeerInfo.TooltipMutedFor",
                                    Self.intervalText("MutedForTime", seconds: seconds),
                                ),
                            )
                        }
                    },
                ),
                TelegramContextMenuAction(
                    title: L10n.telegram(soundEnabled ? "PeerInfo.DisableSound" : "PeerInfo.EnableSound"),
                    image: UIImage(systemName: soundEnabled ? "bell.slash" : "bell"),
                    startsNewSection: true,
                ) {
                    updateNotifications(
                        settings.settingSound(enabled: !soundEnabled),
                        toast: L10n.telegram(
                            soundEnabled ? "PeerInfo.TooltipSoundDisabled" : "PeerInfo.TooltipSoundEnabled",
                        ),
                    )
                },
                TelegramContextMenuAction(
                    title: L10n.telegram("PeerInfo.MuteForever"),
                    image: UIImage(systemName: "speaker.slash.fill"),
                    isDestructive: true,
                ) {
                    updateNotifications(
                        settings.settingMuteFor(Int(Int32.max)),
                        toast: L10n.telegram("PeerInfo.TooltipMutedForever"),
                    )
                },
            ],
        )
    }

    private func updateNotifications(_ settings: ChatNotificationSettings, toast: String) {
        let chatID = chat.id
        perform(toast: toast) { client in
            _ = try await client.setChatNotificationSettings(chatId: chatID, notificationSettings: settings)
        }
    }

    private func autoDeleteAction() -> TelegramContextMenuAction {
        let current = chat.messageAutoDeleteTime
        let day = 24 * 60 * 60
        var children = [day, 7 * day, 31 * day].map { seconds in
            TelegramContextMenuAction(title: Self.timeInterval(seconds)) {
                setAutoDelete(seconds)
            }
        }
        if current > 0 {
            children.append(TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.AutoDeleteDisable"),
                isDestructive: true,
            ) { setAutoDelete(0) })
        }
        return TelegramContextMenuAction(
            title: L10n.telegram(current == 0 ? "PeerInfo.EnableAutoDelete" : "PeerInfo.AdjustAutoDelete"),
            image: UIImage(systemName: "timer"),
            children: children,
        )
    }

    /// PeerInfoScreen.setAutoremove, with its "Messages will be auto-deleted" or "Auto-delete is off" toast.
    private func setAutoDelete(_ seconds: Int) {
        let chatID = chat.id
        let toast = seconds > 0
            ? L10n.telegram("Conversation.AutoremoveChanged", Self.timeInterval(seconds))
            : L10n.telegram("Conversation.AutoremoveOff")
        perform(toast: toast) { client in
            _ = try await client.send(TDNativeRequests.setChatMessageAutoDeleteTime(
                chatId: chatID, messageAutoDeleteTime: seconds,
            ))
        }
    }

    // MARK: Clear Messages

    /// Telegram's ClearPeerHistory on TDLib's flags: a person's chat for both sides when TDLib allows it, otherwise
    /// for this account where TDLib can clear it.
    private func clearMessagesAction() -> TelegramContextMenuAction? {
        var children = [TelegramContextMenuAction]()
        switch customChat.type {
        case .user where !customChat.isSavedMessages:
            if chat.canBeDeletedForAllUsers {
                let firstName = customChat.user?.firstName ?? ""
                let name = firstName.isEmpty ? customChat.displayTitle : firstName
                children.append(TelegramContextMenuAction(
                    title: L10n.telegram("Conversation.DeleteMessagesFor", name),
                    isDestructive: true,
                ) { clearHistory(revoke: true) })
            }
            children.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.DeleteMessagesForMe"),
                isDestructive: true,
            ) { clearHistory(revoke: false) })
        case .bot, .group:
            children.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.DeleteMessagesForMe"),
                isDestructive: true,
            ) { clearHistory(revoke: false) })
        case .supergroup(let group):
            let isPublic = group.usernames?.activeUsernames.isEmpty == false
            guard !group.isChannel, !group.isDirectMessagesGroup, !isPublic, chat.canBeDeletedOnlyForSelf else {
                return nil
            }
            children.append(TelegramContextMenuAction(
                title: L10n.telegram("Conversation.DeleteMessagesForMe"),
                isDestructive: true,
            ) { clearHistory(revoke: false) })
        case .user:
            return nil
        }
        return TelegramContextMenuAction(
            title: L10n.telegram("PeerInfo.ClearMessages"),
            image: UIImage(systemName: "eraser"),
            children: children,
        )
    }

    private func clearHistory(revoke: Bool) {
        let chatID = chat.id
        perform(toast: L10n.telegram("Undo.ChatCleared")) { client in
            _ = try await client.deleteChatHistory(chatId: chatID, removeFromChatList: false, revoke: revoke)
        }
    }

    // MARK: Leave and Delete

    /// Telegram's Leave Group, Leave Channel and Delete Group; a person's or bot's chat gets the chat list's Delete
    /// Chat. The chat list's removal sheet decides between leaving, deleting for everyone and clearing.
    private func removalAction() -> TelegramContextMenuAction {
        let title: String =
            switch customChat.type {
            case .bot, .user:
                L10n.telegram("ChatList.DeleteChat")
            case .group(let group):
                L10n.telegram(group.status.isOwner ? "Group.DeleteGroup" : "Group.LeaveGroup")
            case .supergroup(let group):
                group.isChannel
                    ? L10n.telegram("Channel.LeaveChannel")
                    : L10n.telegram(group.status.isOwner ? "Group.DeleteGroup" : "Group.LeaveGroup")
            }
        let customChat = customChat
        let client = client
        let scope = scope
        return TelegramContextMenuAction(
            title: title,
            image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak host] in
            guard let host, scope.isCurrent else { return }
            ChatListChatRemoval(chat: customChat, client: client, scope: scope, host: host) { [weak host] status in
                guard let navigation = host?.navigationController else { return }
                // Clearing keeps the chat; leaving or deleting returns to the chat list, as Telegram does.
                if status != L10n.telegram("Undo.ChatCleared") {
                    navigation.popToRootViewController(animated: true)
                }
                if let root = navigation.viewControllers.first?.view {
                    TelegramUndoToast.show(text: status, in: root, bottomInset: 12, undo: nil)
                }
            }.start()
        }
    }

    // MARK: Helpers

    private func perform(toast: String, _ request: @escaping @MainActor (TDLibClient) async throws -> Void) {
        guard scope.isCurrent else { return }
        let client = client
        let scope = scope
        let host = host
        Task { [weak host] in
            do {
                try await scope.perform { try await request(client) }
                guard let host else { return }
                TelegramUndoToast.show(text: toast, in: host.view, bottomInset: 12, undo: nil)
            } catch {
                guard scope.isCurrent, let host else { return }
                host.presentChatListActionFailure()
            }
        }
    }
}

// MARK: - Helpers

private extension ChatMemberStatus {
    var isOwner: Bool {
        if case .chatMemberStatusCreator = self { return true }
        return false
    }
}

private extension ChatNotificationSettings {
    func settingMuteFor(_ muteFor: Int) -> ChatNotificationSettings {
        updating(muteFor: muteFor, useDefaultMuteFor: false, soundId: soundId, useDefaultSound: useDefaultSound)
    }

    func settingSound(enabled: Bool) -> ChatNotificationSettings {
        updating(
            muteFor: muteFor,
            useDefaultMuteFor: useDefaultMuteFor,
            soundId: enabled ? soundId : 0,
            useDefaultSound: enabled,
        )
    }

    private func updating(
        muteFor: Int,
        useDefaultMuteFor: Bool,
        soundId: Int64,
        useDefaultSound: Bool,
    ) -> ChatNotificationSettings {
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
            useDefaultMuteStories: useDefaultMuteStories,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: useDefaultSound,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}
