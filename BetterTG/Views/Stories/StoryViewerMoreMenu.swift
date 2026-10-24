// StoryViewerMoreMenu.swift

import Photos
import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - StoryMoreMenu

/// StoryItemSetContainerComponent.performOtherMoreAction: the More menu on someone else's story. A video story
/// starts with the playback speed, a contact offers to notify about their stories, a public story with a username
/// copies its link, a poster's stories hide to the archive and back, a forwardable story saves to the gallery (for
/// Premium), a caption in a language the user doesn't read translates, and anyone but a service account can be
/// reported. Telegram's HD (TDLib offers stories in one quality), stealth mode (Premium) and statistics are left out.
/// Where the reply panel has no share button, as under a channel's story, whose footer BetterTG doesn't have, Share
/// joins the menu after Copy Link.
/// performMyMoreAction builds the account's own story's menu: the speed, Save to or Remove from Profile, Save to
/// Gallery, and Copy Link and Share for a public story that is still active or saved to the profile. Telegram's Who
/// Can See, Edit Story and Edit Cover (BetterTG has no story editor yet) and stealth mode (Premium) are left out.
/// performMyChannelMoreAction builds the menu of a channel's or group's story the account may edit or delete: the
/// speed, Save to or Remove from Posts, Save to Gallery, Copy Link and Share, Hide or Unhide Stories and Delete Story.
/// Telegram's Edit, Edit Cover and View Statistics (BetterTG has no story editor or statistics) are left out.
enum StoryMoreMenu {
    enum Item: Equatable {
        /// Playback Speed with the viewer's rate, and Telegram's speeds a level down.
        case speed(rate: Double)
        /// toggleStoryIsPostedToChatPage: Save to Profile for a story the profile doesn't show, Remove otherwise.
        case profile(isPosted: Bool)
        /// togglePeerStoriesMuted: Notify About Stories while they're muted, Do Not Notify otherwise.
        case notify(isMuted: Bool)
        case copyLink
        /// performShareAction's chat picker, offered by Telegram's footer for public, forwardable stories.
        case share
        /// toggleStoryIsPostedToChatPage on a channel's or group's story: Save to Posts, or Remove from Posts.
        case channelPage(isPosted: Bool, isGroup: Bool)
        /// performDeleteAction on a channel's or group's story the account may delete.
        case delete
        /// updatePeerStoriesHidden: Hide Stories moves them to the archive, Unhide Stories back.
        case archive(isHidden: Bool)
        case save
        /// performTranslateTextAction: the caption's translation from its language.
        case translate(language: String)
        case report
    }

    /// What performOtherMoreAction reads about the poster and the account before it builds the menu.
    struct Poster: Equatable {
        enum Kind: Equatable {
            case user(isContact: Bool, isBot: Bool)
            /// Telegram's channel peers: channels and supergroups.
            case supergroup(isChannel: Bool)
            case other
        }

        let chatID: Int64
        /// The poster's display title, for the notification tooltips.
        let title: String
        /// compactDisplayTitle, a user's first name, for the hide tooltips.
        let compactTitle: String
        let kind: Kind
        let isService: Bool
        /// The poster is the account itself (performMoreAction's peer id check).
        var isSelf = false
        let username: String?
        let storiesMuted: Bool
        let storiesHidden: Bool
        /// ChatActiveStories.canBeArchived: the stories show in the main list and TDLib can move them to the archive.
        let canBeArchived: Bool
        let accountIsPremium: Bool
        /// The poster's active stories (getChatActiveStories), so the menu knows an expired one.
        var activeStoryIDs = Set<Int>()
    }

    /// speedList: Telegram's story speeds.
    static let speeds: [Double] = [0.5, 1, 1.5, 2]

    /// EnginePeer.isService: Telegram's notifications, support and replies accounts and the verification codes bot.
    static let serviceUserIDs: Set<Int64> = [777_000, 333_000, 708_513, 1_271_266_957, 489_000]

    /// performMoreAction sends the account's own stories to performMyMoreAction, those a channel admin may edit or
    /// delete to performMyChannelMoreAction and the rest to performOtherMoreAction; every story has the button.
    static func showsButton(for story: Story?, accountUserID _: Int64?) -> Bool {
        story != nil
    }

    /// The story was posted by the account itself: its private chat's id is the user's.
    static func isOwn(_ story: Story, accountUserID: Int64?) -> Bool {
        accountUserID != nil && story.posterChatId == accountUserID
    }

    /// EngineStoryItem.isPublic: a story everyone may see.
    static func isPublic(_ story: Story) -> Bool {
        if case .storyPrivacySettingsEveryone = story.privacySettings { return true }
        return false
    }

    /// The menu's items in performOtherMoreAction's order; a bot's previews have no menu.
    /// With sharesFromPanel set, the reply panel's share button stands in for Share, as in Telegram's menu.
    static func items(
        story: Story,
        poster: Poster,
        sharesFromPanel: Bool = false,
        baseRate: Double = 1,
        translatableLanguage: (String) -> String? = MessageTranslation.translatableLanguage(of:),
    ) -> [Item] {
        if poster.isSelf { return ownItems(story: story, poster: poster, baseRate: baseRate) }
        if case .supergroup = poster.kind, story.canBeEdited || story.canBeDeleted {
            return channelItems(story: story, poster: poster, baseRate: baseRate)
        }
        if case .user(isContact: _, isBot: true) = poster.kind { return [] }
        var isLive = false
        if case .storyContentLive = story.content { isLive = true }
        var items = [Item]()
        if case .storyContentVideo = story.content {
            items.append(.speed(rate: baseRate))
        }
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
        if !story.caption.text.isEmpty, let language = translatableLanguage(story.caption.text) {
            items.append(.translate(language: language))
        }
        if !poster.isService {
            items.append(.report)
        }
        return items
    }

    /// performMyMoreAction's items on the account's own story, in Telegram's order.
    static func ownItems(story: Story, poster: Poster, baseRate: Double = 1) -> [Item] {
        var isLive = false
        if case .storyContentLive = story.content { isLive = true }
        var items = [Item]()
        if case .storyContentVideo = story.content {
            items.append(.speed(rate: baseRate))
        }
        if !isLive {
            if story.canToggleIsPostedToChatPage {
                items.append(.profile(isPosted: story.isPostedToChatPage))
            }
            items.append(.save)
        }
        // A link opens only while the story is active or the profile shows it.
        let isReachable = poster.activeStoryIDs.contains(story.id) || story.isPostedToChatPage
        if isPublic(story), poster.username != nil, isReachable {
            items.append(.copyLink)
            items.append(.share)
        }
        return items
    }

    /// performMyChannelMoreAction's items on a story the account may edit or delete, in Telegram's order.
    static func channelItems(story: Story, poster: Poster, baseRate: Double = 1) -> [Item] {
        var isLive = false
        if case .storyContentLive = story.content { isLive = true }
        var isGroup = false
        if case .supergroup(isChannel: false) = poster.kind { isGroup = true }
        var items = [Item]()
        if case .storyContentVideo = story.content {
            items.append(.speed(rate: baseRate))
        }
        if !isLive, story.canToggleIsPostedToChatPage {
            items.append(.channelPage(isPosted: story.isPostedToChatPage, isGroup: isGroup))
        }
        if !isLive {
            items.append(.save)
        }
        let isReachable = poster.activeStoryIDs.contains(story.id) || story.isPostedToChatPage
        if isPublic(story), poster.username != nil, isReachable {
            items.append(.copyLink)
            items.append(.share)
        }
        if poster.storiesHidden || poster.canBeArchived {
            items.append(.archive(isHidden: poster.storiesHidden))
        }
        if story.canBeDeleted {
            items.append(.delete)
        }
        return items
    }

    /// The speed's name in speedList: Normal at 1x.
    static func speedTitle(_ rate: Double) -> String {
        if abs(rate - 1) < 0.01 { return L10n.telegram("PlaybackSpeed.Normal") }
        return speedText(rate)
    }

    /// optionsRateImage: the rate in Telegram's rounded type inside the speed gauge.
    static func speedImage(_ rate: Double) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let gauge = UIBezierPath(
                arcCenter: CGPoint(x: 12, y: 12),
                radius: 10.5,
                startAngle: .pi * 0.75,
                endAngle: .pi * 2.25,
                clockwise: true,
            )
            gauge.lineWidth = 1.33
            gauge.lineCapStyle = .round
            UIColor.black.setStroke()
            gauge.stroke()
            let text = speedText(rate)
            let base = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base
            let kern: CGFloat = text.count >= 3 ? (text == "0.5x" ? -0.8 : -0.5) : 0
            let string = NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: UIColor.black, .kern: kern],
            )
            let bounds = string.boundingRect(with: size, options: [], context: nil)
            string.draw(at: CGPoint(
                x: floor((size.width - bounds.width) / 2),
                y: floor((size.height - bounds.height) / 2),
            ))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    static func title(of item: Item) -> String {
        switch item {
        case .speed:
            L10n.telegram("PlaybackSpeed.Title")
        case .profile(let isPosted):
            L10n.telegram(isPosted ? "Story.Context.RemoveFromProfile" : "Story.Context.SaveToProfile")
        case .notify(let isMuted):
            L10n.telegram(isMuted ? "StoryFeed.ContextNotifyOn" : "StoryFeed.ContextNotifyOff")
        case .copyLink:
            L10n.telegram("Story.Context.CopyLink")
        case .share:
            L10n.telegram("Story.Context.Share")
        case .channelPage(let isPosted, _):
            L10n.telegram(isPosted ? "Story.Context.RemoveFromChannel" : "Story.Context.SaveToChannel")
        case .delete:
            L10n.telegram("Story.ContextDeleteStory")
        case .archive(let isHidden):
            L10n.telegram(isHidden ? "StoryFeed.ContextUnarchive" : "StoryFeed.ContextArchive")
        case .save:
            L10n.telegram("Story.Context.SaveToGallery")
        case .translate:
            L10n.telegram("Conversation.ContextMenuTranslate")
        case .report:
            L10n.telegram("Story.Context.Report")
        }
    }

    /// Telegram's Chat/Context Menu glyphs as their SF Symbols.
    static func image(of item: Item) -> UIImage? {
        if case .speed(let rate) = item { return speedImage(rate) }
        let name =
            switch item {
            case .speed: "gauge.with.needle"
            case .profile(let isPosted): isPosted ? "pin.slash" : "pin"
            case .notify(let isMuted): isMuted ? "bell" : "bell.slash"
            case .copyLink: "link"
            case .share: "arrowshape.turn.up.right"
            case .channelPage(let isPosted, _): isPosted ? "pin.slash" : "pin"
            case .delete: "trash"
            case .archive(let isHidden): isHidden ? "tray.and.arrow.up" : "archivebox"
            case .save: "square.and.arrow.down"
            case .translate: "translate"
            case .report: "exclamationmark.bubble"
            }
        return UIImage(systemName: name)
    }

    /// The probe's name for an item.
    static func identifier(of item: Item) -> String {
        switch item {
        case .speed: "speed"
        case .profile(let isPosted): isPosted ? "remove-from-profile" : "save-to-profile"
        case .notify(let isMuted): isMuted ? "notify-on" : "notify-off"
        case .copyLink: "copy-link"
        case .share: "share"
        case .channelPage(let isPosted, _): isPosted ? "remove-from-channel" : "save-to-channel"
        case .delete: "delete"
        case .archive(let isHidden): isHidden ? "unhide" : "hide"
        case .save: "save"
        case .translate: "translate"
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
        var isSelf = false
        var username: String?
        var compactTitle = chat.title
        switch chat.type {
        case .chatTypePrivate(let info):
            let user = try? await client.send(TDNativeRequests.getUser(userId: info.userId))
            var isBot = false
            if case .userTypeBot = user?.type { isBot = true }
            kind = .user(isContact: user?.isContact ?? false, isBot: isBot)
            isService = serviceUserIDs.contains(info.userId)
            isSelf = me?.id == info.userId
            username = user?.usernames?.activeUsernames.first
            if let user {
                let firstName = user.firstName.isEmpty ? user.lastName : user.firstName
                if !firstName.isEmpty { compactTitle = firstName }
            }
        case .chatTypeSupergroup(let info):
            kind = .supergroup(isChannel: info.isChannel)
            let group = try? await client.send(TDNativeRequests.getSupergroup(supergroupId: info.supergroupId))
            username = group?.usernames?.activeUsernames.first
        case .chatTypeBasicGroup,
             .chatTypeSecret:
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
            isSelf: isSelf,
            username: username,
            storiesMuted: isMuted,
            storiesHidden: isHidden,
            canBeArchived: active?.canBeArchived ?? false,
            accountIsPremium: me?.isPremium ?? false,
            activeStoryIDs: Set(active?.stories.map(\.storyId) ?? []),
        )
    }

    /// The story's media for Save to Gallery: the largest photo or the video.
    static func savedFile(of story: Story) -> (file: File, isVideo: Bool)? {
        switch story.content {
        case .storyContentPhoto(let content):
            StoryMedia.photoFile(content.photo).map { ($0, false) }
        case .storyContentVideo(let content):
            (content.video.video, true)
        case .storyContentLive,
             .storyContentUnsupported:
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

    private static func speedText(_ rate: Double) -> String {
        if abs(rate - rate.rounded()) < 0.01 { return "\(Int(rate.rounded()))x" }
        return String(format: "%.1fx", rate)
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
        replacingOccurrences(of: "]()", with: "").replacing("[", with: "")
    }
}
