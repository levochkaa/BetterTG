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
    /// A bot's commands and privacy policy, for its Share, Privacy Policy, Settings and Help.
    var botInfo: TDNativeBotInfo?
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
        case .group,
             .supergroup: canChangeInfo
        }
    }

    /// Telegram's `muteForIntervalString` / `mutedForTimeIntervalString`: hours below a day, days above.
    private static func intervalText(_ prefix: String, seconds: Int) -> String {
        let (key, count) = seconds < 24 * 60 * 60
            ? ("\(prefix).Hours", max(1, seconds / (60 * 60)))
            : ("\(prefix).Days", max(1, seconds / (24 * 60 * 60)))
        return L10n.telegramPlural(key, count: count, formattedCount: count.formatted(.number))
    }

    /// Telegram's timeIntervalString for the auto-delete periods: days, weeks, months or years.
    private static func timeInterval(_ seconds: Int) -> String {
        let day = 24 * 60 * 60
        let (key, count): (String, Int) =
            if seconds < day * 7 {
                ("MessageTimer.Days", seconds / day)
            } else if seconds < day * 30 {
                ("MessageTimer.Weeks", seconds / (day * 7))
            } else if seconds < day * 365 {
                ("MessageTimer.Months", seconds / (day * 30))
            } else {
                ("MessageTimer.Years", seconds / (day * 365))
            }
        return L10n.telegramPlural(key, count: max(1, count))
    }

    private static func sendBotCommand(
        _ command: String,
        to customChat: CustomChat,
        client: TDLibClient,
        scope: ChatListActionScope,
    ) {
        let content = InputMessageContent.inputMessageText(InputMessageText(
            clearDraft: false, linkPreviewOptions: nil, text: FormattedText(entities: [], text: "/" + command),
        ))
        Task {
            _ = try? await client.sendMessage(
                chatId: customChat.chat.id, inputMessageContent: content, options: nil, replyMarkup: nil,
                replyTo: nil, topicId: nil,
            )
            guard scope.isCurrent else { return }
            NavigationStorage.shared.push(.customChat(customChat))
        }
    }

    /// The leave alert's title and text for a group or channel the account doesn't own; nil for the rest, which keep
    /// the chat list's sheet.
    private static func leaveAlertTexts(for customChat: CustomChat) -> (title: String, text: String)? {
        let isChannel: Bool
        switch customChat.type {
        case .group(let group):
            guard !group.status.isOwner else { return nil }
            isChannel = false
        case .supergroup(let group):
            guard !group.status.isOwner else { return nil }
            isChannel = group.isChannel
        case .bot,
             .user:
            return nil
        }
        let name = customChat.chat.title
        return isChannel
            ? (
                L10n.telegram("PeerInfo.LeaveChannelTitle"),
                L10n.telegram("PeerInfo.LeaveChannelText", name).withoutTelegramMarkup,
            )
            : (
                L10n.telegram("PeerInfo.LeaveGroupTitle"),
                L10n.telegram("PeerInfo.LeaveGroupText", name).withoutTelegramMarkup,
            )
    }

    func actions() -> [TelegramContextMenuAction] {
        var actions = [muteAction()]
        if let discussion = viewDiscussionAction() {
            actions.append(discussion)
        }
        actions += botActions()
        if let secretChat = startSecretChatAction() {
            actions.append(secretChat)
        }
        if let shareContact = shareContactAction() {
            actions.append(shareContact)
        }
        if canSetAutoDelete {
            actions.append(autoDeleteAction())
        }
        if let report = reportAction() {
            actions.append(report)
        }
        if let clear = clearMessagesAction() {
            actions.append(clear)
        }
        if let block = blockAction() {
            actions.append(block)
        }
        actions.append(removalAction())
        return actions
    }

    // MARK: Block

    /// Conversation.BlockUser for a contact not yet blocked (others block from the chat's bar), behind updateBlocked's
    /// sheet: "Do you want to block … from messaging and calling you on Telegram?" with Block ….
    private func blockAction() -> TelegramContextMenuAction? {
        guard case .user(let user) = customChat.type, user.isContact, !user.isSupport, !customChat.isSavedMessages,
              chat.blockList == nil
        else { return nil }
        let name = user.firstName.isEmpty ? user.lastName : user.firstName
        return TelegramContextMenuAction(
            title: L10n.telegram("Conversation.BlockUser"),
            image: UIImage(systemName: "hand.raised"),
            isDestructive: true,
        ) { [weak host, client, scope] in
            guard let host else { return }
            let sheet = UIAlertController(
                title: nil,
                message: L10n.telegram("UserInfo.BlockConfirmationTitle", name),
                preferredStyle: .actionSheet,
            )
            sheet
                .addAction(UIAlertAction(title: L10n.telegram("UserInfo.BlockActionTitle", name), style: .destructive) {
                    [weak host] _ in
                    Task { [weak host] in
                        do {
                            _ = try await client.send(TDNativeRequests.setMessageSenderBlockList(
                                senderId: .messageSenderUser(.init(userId: user.id)), blockList: .blockListMain,
                            ))
                        } catch {
                            if scope.isCurrent { host?.presentChatListActionFailure() }
                        }
                    }
                })
            sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            // A popover only where the sheet is one: on a phone the source makes it a popover without Cancel.
            if host.traitCollection.horizontalSizeClass == .regular, let popover = sheet.popoverPresentationController {
                popover.sourceView = host.view
                popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
            }
            host.present(sheet, animated: true)
        }
    }

    // MARK: Share Contact

    /// Profile.ShareContactButton for a contact with a phone number: the chat picker, then the contact sent there
    /// (inputMessageContact) with Telegram's "Contact forwarded to …".
    private func shareContactAction() -> TelegramContextMenuAction? {
        guard case .user(let user) = customChat.type, user.isContact, !user.phoneNumber.isEmpty,
              !customChat.isSavedMessages
        else { return nil }
        let contact = TDNativeContact(
            phoneNumber: user.phoneNumber, firstName: user.firstName, lastName: user.lastName, vcard: "",
            userId: user.id,
        )
        return TelegramContextMenuAction(
            title: L10n.telegram("Profile.ShareContactButton"),
            image: UIImage(systemName: "square.and.arrow.up"),
        ) { [weak host, client] in
            guard let host else { return }
            var pickerNavigation: UIViewController?
            pickerNavigation = StoryForwarding.picker(client: client) { [weak host] chat, topic in
                let target = chat.chat
                let topicID = topic.map {
                    MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.info.forumTopicId))
                }
                let tooltip = target.id == TDLib.shared.activeAccount?.userID
                    ? L10n.telegram("UserInfo.ContactForwardTooltip.SavedMessages.One")
                    : L10n.telegram("UserInfo.ContactForwardTooltip.Chat.One", target.title)
                pickerNavigation?.dismiss(animated: true)
                Task { [weak host] in
                    do {
                        _ = try await client.send(TDNativeRequests.sendMessage(
                            chatId: target.id, topicId: topicID, replyTo: nil, options: nil, replyMarkup: nil,
                            inputMessageContent: .inputMessageContact(TDNativeInputMessageContact(contact: contact)),
                        ))
                        guard let view = host?.view else { return }
                        TelegramUndoToast.show(
                            text: tooltip.withoutTelegramMarkup, in: view, bottomInset: 12, undo: nil,
                        )
                    } catch {
                        host?.presentChatListActionFailure()
                    }
                }
            }
            if let pickerNavigation { host.present(pickerNavigation, animated: true) }
        }
    }

    // MARK: Discussion

    /// PeerInfo.ViewDiscussion for a channel with a discussion group, which BetterTG's header has no button for: the
    /// group (getSupergroupFullInfo's linkedChatId) opens.
    private func viewDiscussionAction() -> TelegramContextMenuAction? {
        guard case .supergroup(let group) = customChat.type, group.isChannel, group.hasLinkedChat else { return nil }
        return TelegramContextMenuAction(
            title: L10n.telegram("PeerInfo.ViewDiscussion"),
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
        ) { [client, scope] in
            Task {
                guard let info = try? await client.getSupergroupFullInfo(supergroupId: group.id),
                      info.linkedChatId != 0, scope.isCurrent,
                      let discussion = await RootVM.shared.getCustomChatForNavigation(
                          from: info.linkedChatId, client: client,
                      )
                else { return }
                NavigationStorage.shared.push(.customChat(discussion))
            }
        }
    }

    // MARK: Report

    /// ReportPeer.Report for a group or channel the account doesn't own or administer (a basic group's admins may
    /// report it), opening ContentReportScreen over the chat; Telegram's toast once it's sent.
    private func reportAction() -> TelegramContextMenuAction? {
        let isChannel: Bool
        switch customChat.type {
        case .group(let group):
            if case .chatMemberStatusCreator = group.status { return nil }
            isChannel = false
        case .supergroup(let group):
            switch group.status {
            case .chatMemberStatusAdministrator,
                 .chatMemberStatusCreator: return nil
            default: break
            }
            isChannel = group.isChannel
        case .bot,
             .user:
            return nil
        }
        let chatID = customChat.chat.id
        return TelegramContextMenuAction(
            title: L10n.telegram("ReportPeer.Report"),
            image: UIImage(systemName: "exclamationmark.bubble"),
        ) { [weak host] in
            guard let host else { return }
            ReportContentViewController.present(chatID: chatID, isChannel: isChannel, from: host) { [weak host] in
                guard let view = host?.view else { return }
                TelegramUndoToast.show(text: L10n.telegram("Report.Succeed"), in: view, bottomInset: 12, undo: nil)
            }
        }
    }

    // MARK: Secret Chat

    /// Start Secret Chat for a person (not the account, Telegram's support or a deleted account, and not one who asks
    /// for paid messages), behind openStartSecretChat's confirmation; the new chat opens.
    private func startSecretChatAction() -> TelegramContextMenuAction? {
        guard case .user(let user) = customChat.type, !customChat.isSavedMessages, !user.isSupport,
              user.paidMessageStarCount == 0
        else { return nil }
        if case .userTypeDeleted = user.type { return nil }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return TelegramContextMenuAction(
            title: L10n.telegram("UserInfo.StartSecretChat"),
            image: UIImage(systemName: "lock"),
        ) { [weak host, client, scope] in
            guard let host else { return }
            let alert = UIAlertController(
                title: nil,
                message: L10n.telegram("UserInfo.StartSecretChatConfirmation", name),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.telegram("UserInfo.StartSecretChatStart"), style: .default) {
                [weak host] _ in
                Task { [weak host] in
                    do {
                        let chat = try await client.send(TDNativeRequests.createNewSecretChat(userId: user.id))
                        guard scope.isCurrent,
                              let customChat = await RootVM.shared.getCustomChatForNavigation(
                                  from: chat.id, client: client,
                              )
                        else { return }
                        NavigationStorage.shared.push(.customChat(customChat))
                    } catch {
                        host?.presentChatListActionFailure()
                    }
                }
            })
            host.present(alert, animated: true)
        }
    }

    // MARK: Bot

    /// PeerInfoScreenPerformButtonAction's bot items: Share for a bot with a username; Privacy Policy by the bot's
    /// link, Telegram's default terms when the bot has neither a link nor /privacy, or its /privacy command; and its
    /// /settings and /help commands, in the bot's order. A command is sent to the bot (performBotCommand), whose chat
    /// opens.
    private func botActions() -> [TelegramContextMenuAction] {
        guard case .bot(let user) = customChat.type else { return [] }
        var actions = [TelegramContextMenuAction]()
        if let username = user.usernames?.activeUsernames.first, let link = URL(string: "https://t.me/\(username)") {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("UserInfo.ShareBot"),
                image: UIImage(systemName: "arrowshape.turn.up.right"),
            ) { [weak host] in
                guard let host else { return }
                let sheet = UIActivityViewController(activityItems: [link], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = host.view
                host.present(sheet, animated: true)
            })
        }
        guard let botInfo else { return actions }
        let commands = botInfo.commands.map(\.command)
        var addedPrivacy = false
        let privacyURL: String? =
            if !botInfo.privacyPolicyUrl.isEmpty {
                botInfo.privacyPolicyUrl
            } else if commands.contains("privacy") {
                nil
            } else {
                L10n.telegram("WebApp.PrivacyPolicy_URL")
            }
        if let privacyURL, let url = URL(string: privacyURL) {
            addedPrivacy = true
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("UserInfo.BotPrivacy"),
                image: UIImage(systemName: "info.circle"),
            ) { [weak host] in
                WebBrowser.open(url, from: host)
            })
        }
        for command in commands {
            let title: String
            let symbol: String
            switch command {
            case "settings": (title, symbol) = ("UserInfo.BotSettings", "gearshape")
            case "help": (title, symbol) = ("UserInfo.BotHelp", "questionmark.circle")
            case "privacy" where !addedPrivacy: (title, symbol) = ("UserInfo.BotPrivacy", "info.circle")
            default: continue
            }
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(title),
                image: UIImage(systemName: symbol),
            ) { [customChat, client, scope] in
                Self.sendBotCommand(command, to: customChat, client: client, scope: scope)
            })
        }
        return actions
    }

    /// Muted: Unmute. Otherwise Telegram's Mute menu: Mute for… presets, the sound toggle, Customize and Mute Forever.
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
                    } + [TelegramContextMenuAction(title: L10n.telegram("PeerInfo.MuteForCustom")) {
                        openCustomMute()
                    }],
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
                    title: L10n.telegram("PeerInfo.NotificationsCustomize"),
                    image: UIImage(systemName: "slider.horizontal.3"),
                ) { openCustomization() },
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

    private func updateNotifications(_ settings: ChatNotificationSettings, toast: String?) {
        let chatID = chat.id
        perform(toast: toast) { client in
            _ = try await client.setChatNotificationSettings(chatId: chatID, notificationSettings: settings)
        }
    }

    /// PeerInfoScreenPerformButtonAction's Customize: the chat's notification exception screen, with story
    /// notifications for a person or bot.
    private func openCustomization() {
        guard scope.isCurrent, let host else { return }
        let menu = self
        let offersStories =
            switch customChat.type {
            case .bot,
                 .user: true
            case .group,
                 .supergroup: false
            }
        NotificationExceptionViewController(
            title: chat.title,
            scope: customChat.notificationSettingsScope,
            settings: chat.notificationSettings,
            offersStories: offersStories,
        ) { settings in
            menu.updateNotifications(
                settings,
                toast: settings.muteFor > 0 ? L10n.telegram("PeerInfo.TooltipMutedForever") : nil,
            )
        }.present(from: host)
    }

    /// PeerInfoScreen.openCustomMute: mute until a picked date, with "Notifications are muted until …".
    private func openCustomMute() {
        guard scope.isCurrent, let host else { return }
        let settings = chat.notificationSettings
        let menu = self
        PeerProfileTimerPickerViewController(mode: .muteUntil(onApply: { seconds in
            let until = Foundation.Date(timeIntervalSinceNow: TimeInterval(seconds))
            menu.updateNotifications(
                settings.settingMuteFor(seconds),
                toast: L10n.telegram(
                    "PeerInfo.TooltipMutedUntil",
                    PeerProfileTimerPickerViewController.preciseText(for: until),
                ),
            )
        })).present(from: host)
    }

    private func autoDeleteAction() -> TelegramContextMenuAction {
        let current = chat.messageAutoDeleteTime
        let day = 24 * 60 * 60
        var children = [day, 7 * day, 31 * day].map { seconds in
            TelegramContextMenuAction(title: Self.timeInterval(seconds)) {
                setAutoDelete(seconds)
            }
        }
        children.append(TelegramContextMenuAction(title: L10n.telegram("PeerInfo.AutoDeleteSettingOther")) {
            openAutoDeletePicker(current: current)
        })
        if current > 0 {
            children.append(TelegramContextMenuAction(
                title: L10n.telegram("PeerInfo.AutoDeleteDisable"),
                isDestructive: true,
            ) { setAutoDelete(0) })
        }
        // The submenu's note after a separator, whose link opens the account's default timer
        // (AutoremoveSetup.AdditionalGlobalSettingsInfo's textLinkAction).
        let isChannel =
            if case .supergroup(let group) = customChat.type {
                group.isChannel
            } else {
                false
            }
        var note = TelegramContextMenuAction(
            title: L10n.telegram(isChannel ? "PeerInfo.ChannelAutoDeleteInfo" : "PeerInfo.AutoDeleteInfo") + "\n\n"
                + L10n.telegram("AutoremoveSetup.AdditionalGlobalSettingsInfo")
                .replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.1) },
            startsNewSection: true,
        ) { [weak host, client] in
            Task { [weak host] in
                let time = await (try? client.send(TDNativeRequests.getDefaultMessageAutoDeleteTime()))?.time ?? 0
                host?.navigationController?.pushViewController(
                    GlobalAutoDeleteViewController(currentTime: time), animated: true,
                )
            }
        }
        note.usesSmallText = true
        note.isMultiline = true
        children.append(note)
        return TelegramContextMenuAction(
            title: L10n.telegram(current == 0 ? "PeerInfo.EnableAutoDelete" : "PeerInfo.AdjustAutoDelete"),
            image: UIImage(systemName: "timer"),
            children: children,
        )
    }

    /// PeerInfoScreen.openAutoremove: Telegram's full list of periods, and Disable Auto-Delete while one is set.
    private func openAutoDeletePicker(current: Int) {
        guard scope.isCurrent, let host else { return }
        let menu = self
        PeerProfileTimerPickerViewController(mode: .autoDelete(
            current: current,
            format: { Self.timeInterval($0) },
            onApply: { seconds in menu.setAutoDelete(seconds) },
        )).present(from: host)
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
        case .bot,
             .group:
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
        // openClearHistory's question above the choices, by the person's or the group's name.
        let isPerson =
            switch customChat.type {
            case .bot,
                 .user: true
            case .group,
                 .supergroup: false
            }
        let compactTitle = customChat.user.map { $0.firstName.isEmpty ? customChat.displayTitle : $0.firstName }
            ?? customChat.displayTitle
        var question = TelegramContextMenuAction(title: L10n.telegram(
            isPerson ? "PeerInfo.ClearConfirmationUser" : "PeerInfo.ClearConfirmationGroup",
            compactTitle,
        ))
        question.isInformational = true
        return TelegramContextMenuAction(
            title: L10n.telegram("PeerInfo.ClearMessages"),
            image: UIImage(systemName: "eraser"),
            children: [question] + children,
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
            case .bot,
                 .user:
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
            let removal = ChatListChatRemoval(chat: customChat, client: client, scope: scope, host: host) {
                [weak host] status in
                guard let navigation = host?.navigationController else { return }
                // Clearing keeps the chat; leaving or deleting returns to the chat list, as Telegram does.
                if status != L10n.telegram("Undo.ChatCleared") {
                    navigation.popToRootViewController(animated: true)
                }
                if let root = navigation.viewControllers.first?.view {
                    TelegramUndoToast.show(text: status, in: root, bottomInset: 12, undo: nil)
                }
            }
            guard let leave = Self.leaveAlertTexts(for: customChat) else {
                removal.start()
                return
            }
            // openLeavePeer: Leave Group or Leave Channel, asked about the chat by name.
            let alert = UIAlertController(title: leave.title, message: leave.text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.telegram("PeerInfo.AlertLeaveAction"), style: .destructive) {
                _ in removal.leaveConfirmed()
            })
            host.present(alert, animated: true)
        }
    }

    // MARK: Helpers

    private func perform(toast: String?, _ request: @escaping @MainActor (TDLibClient) async throws -> Void) {
        guard scope.isCurrent else { return }
        let client = client
        let scope = scope
        let host = host
        Task { [weak host] in
            do {
                try await scope.perform { try await request(client) }
                guard let host, let toast else { return }
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
