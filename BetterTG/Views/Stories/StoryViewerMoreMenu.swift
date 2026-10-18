// StoryViewerMoreMenu.swift

import Photos
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - StoryMoreMenu

/// StoryItemSetContainerComponent.performOtherMoreAction: the More menu on someone else's story. A contact offers
/// to notify about their stories, a public story with a username copies its link, a poster's stories hide to the
/// archive and back, a forwardable story saves to the gallery (for Premium) and anyone but a service account can be
/// reported. Telegram's playback speed, HD, stealth mode, statistics and translation are left out, and the footer's
/// share button, which BetterTG has no footer for, joins the menu after Copy Link.
enum StoryMoreMenu {
    enum Item: Equatable {
        /// togglePeerStoriesMuted: Notify About Stories while they're muted, Do Not Notify otherwise.
        case notify(isMuted: Bool)
        case copyLink
        /// performShareAction's chat picker, offered by Telegram's footer for public, forwardable stories.
        case share
        /// updatePeerStoriesHidden: Hide Stories moves them to the archive, Unhide Stories back.
        case archive(isHidden: Bool)
        case save
        case report
    }

    /// What performOtherMoreAction reads about the poster and the account before it builds the menu.
    struct Poster: Equatable {
        enum Kind: Equatable {
            case user(isContact: Bool, isBot: Bool)
            /// Telegram's channel peers: channels and supergroups.
            case supergroup
            case other
        }

        let chatID: Int64
        /// The poster's display title, for the notification tooltips.
        let title: String
        /// compactDisplayTitle, a user's first name, for the hide tooltips.
        let compactTitle: String
        let kind: Kind
        let isService: Bool
        let username: String?
        let storiesMuted: Bool
        let storiesHidden: Bool
        /// ChatActiveStories.canBeArchived: the stories show in the main list and TDLib can move them to the archive.
        let canBeArchived: Bool
        let accountIsPremium: Bool
    }

    /// EnginePeer.isService: Telegram's notifications, support and replies accounts and the verification codes bot.
    static let serviceUserIDs: Set<Int64> = [777_000, 333_000, 708_513, 1_271_266_957, 489_000]

    /// performMoreAction sends the account's own stories and those a channel admin may edit or delete to their own
    /// menus, which BetterTG doesn't port; the button shows for everyone else's.
    static func showsButton(for story: Story?) -> Bool {
        guard let story else { return false }
        return !story.canBeEdited && !story.canBeDeleted
    }

    /// EngineStoryItem.isPublic: a story everyone may see.
    static func isPublic(_ story: Story) -> Bool {
        if case .storyPrivacySettingsEveryone = story.privacySettings { return true }
        return false
    }

    /// The menu's items in performOtherMoreAction's order; a bot's previews have no menu.
    /// With sharesFromPanel set, the reply panel's share button stands in for Share, as in Telegram's menu.
    static func items(story: Story, poster: Poster, sharesFromPanel: Bool = false) -> [Item] {
        if case .user(isContact: _, isBot: true) = poster.kind { return [] }
        var isLive = false
        if case .storyContentLive = story.content { isLive = true }
        var items = [Item]()
        if !poster.isService, case .user(isContact: true, isBot: _) = poster.kind {
            items.append(.notify(isMuted: poster.storiesMuted))
        }
        if !poster.isService, isPublic(story), poster.username != nil {
            items.append(.copyLink)
        }
        if !sharesFromPanel, !isLive, isPublic(story), story.canBeForwarded {
            items.append(.share)
        }
        var canArchive = poster.storiesHidden
        if !canArchive {
            switch poster.kind {
            case .user: canArchive = !poster.isService && poster.canBeArchived
            case .supergroup: canArchive = poster.canBeArchived
            case .other: break
            }
        }
        if canArchive {
            items.append(.archive(isHidden: poster.storiesHidden))
        }
        // A live stream offers picture in picture here instead; protected stories can't be saved.
        if !isLive, story.canBeForwarded {
            items.append(.save)
        }
        if !poster.isService {
            items.append(.report)
        }
        return items
    }

    static func title(of item: Item) -> String {
        switch item {
        case .notify(let isMuted):
            L10n.telegram(isMuted ? "StoryFeed.ContextNotifyOn" : "StoryFeed.ContextNotifyOff")
        case .copyLink:
            L10n.telegram("Story.Context.CopyLink")
        case .share:
            L10n.telegram("Story.Context.Share")
        case .archive(let isHidden):
            L10n.telegram(isHidden ? "StoryFeed.ContextUnarchive" : "StoryFeed.ContextArchive")
        case .save:
            L10n.telegram("Story.Context.SaveToGallery")
        case .report:
            L10n.telegram("Story.Context.Report")
        }
    }

    /// Telegram's Chat/Context Menu glyphs as their SF Symbols.
    static func image(of item: Item) -> UIImage? {
        let name =
            switch item {
            case .notify(let isMuted): isMuted ? "bell" : "bell.slash"
            case .copyLink: "link"
            case .share: "arrowshape.turn.up.right"
            case .archive(let isHidden): isHidden ? "tray.and.arrow.up" : "archivebox"
            case .save: "square.and.arrow.down"
            case .report: "exclamationmark.bubble"
            }
        return UIImage(systemName: name)
    }

    /// The probe's name for an item.
    static func identifier(of item: Item) -> String {
        switch item {
        case .notify(let isMuted): isMuted ? "notify-on" : "notify-off"
        case .copyLink: "copy-link"
        case .share: "share"
        case .archive(let isHidden): isHidden ? "unhide" : "hide"
        case .save: "save"
        case .report: "report"
        }
    }

    /// The engine data performOtherMoreAction combines: the poster, its notification settings, whether its stories
    /// are hidden and whether the account has Premium.
    static func resolvePoster(chatID: Int64, client: TDLibClient) async -> Poster? {
        guard let chat = try? await client.send(TDNativeRequests.getChat(chatId: chatID)) else { return nil }
        let me = try? await client.send(TDNativeRequests.getMe())
        let active = try? await client.send(TDNativeRequests.getChatActiveStories(chatId: chatID))
        var kind = Poster.Kind.other
        var isService = false
        var username: String?
        var compactTitle = chat.title
        switch chat.type {
        case .chatTypePrivate(let info):
            let user = try? await client.send(TDNativeRequests.getUser(userId: info.userId))
            var isBot = false
            if case .userTypeBot = user?.type { isBot = true }
            kind = .user(isContact: user?.isContact ?? false, isBot: isBot)
            isService = serviceUserIDs.contains(info.userId)
            username = user?.usernames?.activeUsernames.first
            if let user {
                let firstName = user.firstName.isEmpty ? user.lastName : user.firstName
                if !firstName.isEmpty { compactTitle = firstName }
            }
        case .chatTypeSupergroup(let info):
            kind = .supergroup
            let group = try? await client.send(TDNativeRequests.getSupergroup(supergroupId: info.supergroupId))
            username = group?.usernames?.activeUsernames.first
        case .chatTypeBasicGroup, .chatTypeSecret:
            break
        }
        var isHidden = false
        if case .storyListArchive? = active?.list { isHidden = true }
        let isMuted = await storiesMuted(chat, client: client)
        return Poster(
            chatID: chatID,
            title: chat.title,
            compactTitle: compactTitle,
            kind: kind,
            isService: isService,
            username: username,
            storiesMuted: isMuted,
            storiesHidden: isHidden,
            canBeArchived: active?.canBeArchived ?? false,
            accountIsPremium: me?.isPremium ?? false,
        )
    }

    /// The story's media for Save to Gallery: the largest photo or the video.
    static func savedFile(of story: Story) -> (file: File, isVideo: Bool)? {
        switch story.content {
        case .storyContentPhoto(let content):
            StoryMedia.photoFile(content.photo).map { ($0, false) }
        case .storyContentVideo(let content):
            (content.video.video, true)
        case .storyContentLive, .storyContentUnsupported:
            nil
        }
    }

    /// saveToCameraRoll: the whole file from TDLib, then a new Photos asset from it.
    static func saveToPhotos(_ file: File, isVideo: Bool, client: TDLibClient) async throws {
        var local = file
        if !local.local.isDownloadingCompleted || !FileManager.default.fileExists(atPath: local.local.path) {
            local = try await client.send(TDNativeRequests.downloadFile(
                fileId: file.id,
                priority: 32,
                offset: 0,
                limit: 0,
                synchronous: true,
            ))
        }
        guard local.local.isDownloadingCompleted, FileManager.default.fileExists(atPath: local.local.path) else {
            throw MediaGallerySaveError.downloadFailed
        }
        try await MediaGalleryExport.requestPhotosAccess()
        try Task.checkCancellation()
        let url = URL(filePath: local.local.path)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            options.uniformTypeIdentifier = isVideo ? UTType.mpeg4Movie.identifier : UTType.jpeg.identifier
            request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
        }
    }

    /// resolvedAreStoriesMuted: the chat's own setting, else the private chats' default, and by default (TDLib's
    /// automatic story notifications) muted unless the user is among the five top chats.
    private static func storiesMuted(_ chat: Chat, client: TDLibClient) async -> Bool {
        let settings = chat.notificationSettings
        if !settings.useDefaultMuteStories { return settings.muteStories }
        let scope = try? await client.send(TDNativeRequests.getScopeNotificationSettings(
            scope: .notificationSettingsScopePrivateChats,
        ))
        if let scope, !scope.useDefaultMuteStories { return scope.muteStories }
        let top = try? await client.send(TDNativeRequests.getTopChats(category: .topChatCategoryUsers, limit: 5))
        return !(top?.chatIds.prefix(5).contains(chat.id) ?? false)
    }
}

extension ChatNotificationSettings {
    /// togglePeerStoriesMuted's chat settings: the story setting stops following the default.
    func settingMuteStories(_ muteStories: Bool) -> ChatNotificationSettings {
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
            useDefaultMuteStories: false,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: useDefaultSound,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}

extension String {
    /// Telegram's inline link markup, `[text]()`, as plain text for a toast.
    var withoutTelegramLinkMarkup: String {
        replacingOccurrences(of: "]()", with: "").replacingOccurrences(of: "[", with: "")
    }
}
