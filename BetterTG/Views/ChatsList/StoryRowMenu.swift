// StoryRowMenu.swift

import TDLibKit
import UIKit

// MARK: - StoryRowMenu

/// ChatListController's storyContextPeerAction, for the chat list's and the archive's story rows. The account: Add
/// Story, Saved Stories, Archived Stories. A channel or group: Add Story for an admin who posts stories, Open Channel
/// or Group, Hide or Unhide Stories. A person: Send Message, Open Profile, Notify or Do Not Notify About Stories, Hide
/// or Unhide Stories. Nothing for a service account. Telegram's View Anonymously (stealth mode) isn't ported.
@MainActor enum StoryRowMenu {
    /// `isCurrent` says whether the host still acts for the client the menu reads.
    static func present(
        chatID: Int64,
        source: UIView,
        gesture: ContextMenuPressGestureRecognizer,
        from host: UIViewController,
        client: TDLibClient,
        isCurrent: @escaping () -> Bool,
    ) {
        Task { [weak host] in
            guard let poster = await StoryMoreMenu.resolvePoster(chatID: chatID, client: client), !poster.isService
            else { return }
            var canPost = false
            if case .supergroup = poster.kind,
               let chat = try? await client.getChat(chatId: chatID),
               case .chatTypeSupergroup(let info) = chat.type,
               let group = try? await client.getSupergroup(supergroupId: info.supergroupId)
            {
                switch group.status {
                case .chatMemberStatusCreator: canPost = true
                case .chatMemberStatusAdministrator(let admin): canPost = admin.rights.canPostStories
                default: break
                }
            }
            guard let host, isCurrent(), source.window != nil else { return }
            host.presentTelegramContextMenu(
                sourceView: source,
                actions: actions(poster, canPost: canPost, host: host, client: client, isCurrent: isCurrent),
                tracking: gesture,
                // ChatListHeaderBarContextExtractedContentSource: the item lifts over the dimmed list in its place, the
                // menu under it.
                presentationStyle: .message,
            )
        }
    }

    private static func actions(
        _ poster: StoryMoreMenu.Poster,
        canPost: Bool,
        host: UIViewController,
        client: TDLibClient,
        isCurrent: @escaping () -> Bool,
    ) -> [TelegramContextMenuAction] {
        weak let host = host
        let addStory = TelegramContextMenuAction(
            title: L10n.telegram("StoryFeed.ContextAddStory"),
            image: UIImage(systemName: "plus.circle"),
        ) {
            guard let host else { return }
            StoryComposer.start(from: host, client: client, accountID: TDLib.shared.activeAccountID)
        }
        let hide = TelegramContextMenuAction(
            title: L10n.telegram(poster.storiesHidden ? "StoryFeed.ContextUnarchive" : "StoryFeed.ContextArchive"),
            image: UIImage(systemName: poster.storiesHidden ? "tray.and.arrow.up" : "archivebox"),
        ) {
            guard let host else { return }
            setStoriesHidden(!poster.storiesHidden, of: poster, in: host.view, client: client, offersUndo: true)
        }
        if poster.isSelf {
            return [
                addStory,
                TelegramContextMenuAction(
                    title: L10n.telegram("StoryFeed.ContextSavedStories"),
                    image: UIImage(systemName: "rectangle.stack"),
                ) { openMyStories(.posts, client: client, isCurrent: isCurrent) },
                TelegramContextMenuAction(
                    title: L10n.telegram("StoryFeed.ContextArchivedStories"),
                    image: UIImage(systemName: "archivebox"),
                ) { openMyStories(.archivedPosts, client: client, isCurrent: isCurrent) },
            ]
        }
        switch poster.kind {
        case .supergroup(let isChannel):
            var actions = canPost ? [addStory] : []
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isChannel ? "ChatList.ContextOpenChannel" : "ChatList.ContextOpenGroup"),
                image: UIImage(systemName: isChannel ? "megaphone" : "person.2"),
            ) { openChat(poster.chatID, client: client, isCurrent: isCurrent) })
            actions.append(hide)
            return actions
        default:
            return [
                TelegramContextMenuAction(
                    title: L10n.telegram("StoryFeed.ContextOpenChat"),
                    image: UIImage(systemName: "bubble.left"),
                ) { openChat(poster.chatID, client: client, isCurrent: isCurrent) },
                TelegramContextMenuAction(
                    title: L10n.telegram("StoryFeed.ContextOpenProfile"),
                    image: UIImage(systemName: "person.crop.circle"),
                ) { openProfile(poster.chatID, client: client, isCurrent: isCurrent) },
                TelegramContextMenuAction(
                    title: L10n.telegram(
                        poster.storiesMuted ? "StoryFeed.ContextNotifyOn" : "StoryFeed.ContextNotifyOff",
                    ),
                    image: UIImage(systemName: poster.storiesMuted ? "bell" : "bell.slash"),
                ) {
                    guard let host else { return }
                    toggleNotifications(of: poster, in: host.view, client: client)
                },
                hide,
            ]
        }
    }

    /// PeerInfoStoryGridScreen's saved or archive scope, as My Profile's Posts or Archive pane.
    private static func openMyStories(
        _ tab: PeerProfileViewController.SharedTab,
        client: TDLibClient,
        isCurrent: @escaping () -> Bool,
    ) {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        Task {
            guard let me = try? await client.getMe(),
                  let chat = try? await client.createPrivateChat(force: false, userId: me.id),
                  let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  isCurrent()
            else { return }
            let profile = PeerProfileViewController(
                customChat: customChat, topic: nil, client: client, accountID: accountID, isMyProfile: true,
            )
            profile.preferredSharedTab = tab
            NavigationStorage.shared.activeNavigationController.pushViewController(profile, animated: true)
        }
    }

    private static func openChat(_ chatID: Int64, client: TDLibClient, isCurrent: @escaping () -> Bool) {
        Task {
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client), isCurrent()
            else { return }
            NavigationStorage.shared.push(.customChat(chat))
        }
    }

    private static func openProfile(_ chatID: Int64, client: TDLibClient, isCurrent: @escaping () -> Bool) {
        guard let accountID = TDLib.shared.activeAccountID else { return }
        Task {
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client), isCurrent()
            else { return }
            let profile = PeerProfileViewController(customChat: chat, topic: nil, client: client, accountID: accountID)
            profile.configureOpensChatItself()
            NavigationStorage.shared.activeNavigationController.pushViewController(profile, animated: true)
        }
    }

    /// togglePeerStoriesMuted with Telegram's tooltip naming the poster.
    private static func toggleNotifications(of poster: StoryMoreMenu.Poster, in view: UIView, client: TDLibClient) {
        let chatID = poster.chatID
        let wereMuted = poster.storiesMuted
        Task {
            guard let chat = try? await client.send(TDNativeRequests.getChat(chatId: chatID)) else { return }
            _ = try? await client.send(TDNativeRequests.setChatNotificationSettings(
                chatId: chatID,
                notificationSettings: chat.notificationSettings.settingMuteStories(!wereMuted),
            ))
        }
        let key = wereMuted ? "StoryFeed.TooltipNotifyOn" : "StoryFeed.TooltipNotifyOff"
        TelegramUndoToast.show(
            text: L10n.telegram(key, poster.title).withoutTelegramMarkup,
            in: view,
            bottomInset: 66,
            undo: nil,
        )
    }

    /// updatePeerStoriesHidden with Telegram's tooltip and its Undo.
    private static func setStoriesHidden(
        _ isHidden: Bool,
        of poster: StoryMoreMenu.Poster,
        in view: UIView,
        client: TDLibClient,
        offersUndo: Bool,
    ) {
        let chatID = poster.chatID
        let list: TDNativeStoryList = isHidden ? .storyListArchive : .storyListMain
        Task { _ = try? await client.send(TDNativeRequests.setChatActiveStoriesList(chatId: chatID, storyList: list)) }
        guard offersUndo else { return }
        let key = isHidden ? "StoryFeed.TooltipArchive" : "StoryFeed.TooltipUnarchive"
        TelegramUndoToast.show(
            text: L10n.telegram(key, poster.compactTitle).withoutTelegramMarkup,
            in: view,
            bottomInset: 66,
        ) { [weak view] in
            guard let view else { return }
            setStoriesHidden(!isHidden, of: poster, in: view, client: client, offersUndo: false)
        }
    }
}
