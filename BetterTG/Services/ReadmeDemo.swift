// ReadmeDemo.swift

#if DEBUG
import Foundation
import TDLibKit
import UIKit

/// The README's screenshots: launch with `-readme-demo` on a simulator with no account. The client never signs in and
/// everything on screen is made up here: its people, chats, messages and pictures. TDLib's updates are dropped, the
/// demo's take their place, and `TDClientDemoResponses` answers the requests the screens wait for.
@MainActor enum ReadmeDemo {
    nonisolated static let isActive = ProcessInfo.processInfo.arguments.contains("-readme-demo")

    /// Called each time a client becomes the active one.
    static func clientDidActivate() {
        guard isActive else { return }
        // The first menus' tip about selecting text isn't part of what the screenshots show.
        UserDefaults.standard.set(100, forKey: "chatTextSelectionTips")
        let world = ReadmeDemoWorld()
        TDClientDemoResponses.answer = { request, arguments in world.answer(request, arguments) }
        TDLib.shared.startReadmeDemo(me: world.me, updates: world.updates)
        let root = RootVM.shared
        root.folders = [CustomFolder(chats: [], type: .main)] + world.folders.map {
            CustomFolder(chats: [], type: .folder($0.info, $0.definition))
        }
        root.currentFolder = 0
        root.synchronizeChatLists()
    }
}

// MARK: - ReadmeDemoWorld

private final class ReadmeDemoWorld: @unchecked Sendable {
    private enum ID {
        static let me: Int64 = 1000
        static let mia: Int64 = 1001
        static let liam: Int64 = 1002
        static let sofia: Int64 = 1003
        static let noah: Int64 = 1004
        static let ava: Int64 = 1005
        static let ethan: Int64 = 1006
        static let zoe: Int64 = 1007
        static let hikeGroup: Int64 = 2001
        static let designGroup: Int64 = 2002
        static let bookGroup: Int64 = 2003
        static let digestChannel: Int64 = 3001
        static let productChannel: Int64 = 3002
        static let travelChannel: Int64 = 3003
        static let newsChannel: Int64 = 3004
        static let dealsChannel: Int64 = 3005
        static let oldGroup: Int64 = 2004
        static let personalFolder = 11
        static let workFolder = 12
        static let channelsFolder = 13
    }

    private enum Presence { case online, recently }

    // MARK: Pieces

    private static let permissions = TDNativeChatPermissions(
        canSendBasicMessages: true, canSendAudios: true, canSendDocuments: true, canSendPhotos: true,
        canSendVideos: true, canSendVideoNotes: true, canSendVoiceNotes: true, canSendPolls: true,
        canSendOtherMessages: true, canAddLinkPreviews: true, canReactToMessages: true, canEditTag: false,
        canChangeInfo: true, canInviteUsers: true, canPinMessages: true, canCreateTopics: false,
    )

    let me: TDNativeUser
    private(set) var updates = [TDNativeUpdate]()
    private(set) var folders = [(info: TDNativeChatFolderInfo, definition: TDNativeChatFolder)]()

    private let now: Int
    private var users = [Int64: TDNativeUser]()
    private var basicGroups = [Int64: TDNativeBasicGroup]()
    private var supergroups = [Int64: TDNativeSupergroup]()
    private var chats = [Int64: TDNativeChat]()
    private var messages = [Int64: [TDNativeMessage]]()
    private var files = [Int: TDNativeFile]()
    private var nextFileID = 5000
    private var pinned = [Int64: TDNativeMessage]()
    private var unreadOutgoingChats = Set<Int64>()
    /// The attachment sheet's recently sent files, newest first.
    private var recentFiles = [TDNativeMessage]()
    /// A chat's Media tab, newest first.
    private var sharedPhotos = [Int64: [TDNativeMessage]]()
    private let directory: URL

    private var messageProperties: TDNativeMessageProperties {
        TDNativeMessageProperties(
            canAddOffer: false, canAddTasks: false, canBeApproved: false, canBeCopied: true,
            canBeCopiedToSecretChat: false, canBeDeclined: false, canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: true, canBeEdited: false, canBeForwarded: true, canBePaid: false,
            canBePinned: true, canBeReplied: true, canBeRepliedInAnotherChat: true, canBeSaved: true,
            canBeSharedInStory: false, canDeleteReactions: false, canEditMedia: false,
            canEditSchedulingState: false, canEditSuggestedPostInfo: false, canGetAuthor: false,
            canGetEmbeddingCode: false, canGetLink: false, canGetMediaTimestampLinks: false,
            canGetMessageThread: false, canGetPollVoteStatistics: false, canGetReadDate: false,
            canGetStatistics: false, canGetVideoAdvertisements: false, canGetViewers: false,
            canMarkTasksAsDone: false, canRecognizeSpeech: false, canReportChat: false, canReportReactions: false,
            canReportSupergroupSpam: false, canSetFactCheck: false, customEmojiIds: [],
            hasProtectedContentByCurrentUser: false, hasProtectedContentByOtherUser: false,
            needShowStatistics: false,
        )
    }

    init() {
        let calendar = Calendar.current
        // The moment Apple's screenshots show; the status bar is set to it too.
        let moment = calendar.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now
        self.now = Int(moment.timeIntervalSince1970)
        self.directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("readme-demo")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.me = TDNativeUser(
            id: ID.me, firstName: "Alex", lastName: "Morgan",
            usernames: Self.usernames("alexmorgan"), phoneNumber: "15550100123",
            status: .userStatusOnline(.init(expires: Int(Date.now.timeIntervalSince1970) + 3600)),
            profilePhoto: nil, accentColorId: 1, backgroundCustomEmojiId: 0, upgradedGiftColors: nil,
            profileAccentColorId: -1, profileBackgroundCustomEmojiId: 0, emojiStatus: nil, isContact: false,
            isMutualContact: false, isCloseFriend: false, verificationStatus: nil, isPremium: true, isSupport: false,
            restrictionInfo: nil, activeStoryState: nil, restrictsNewChats: false, paidMessageStarCount: 0,
            haveAccess: true, type: .userTypeRegular, languageCode: "en", addedToAttachmentMenu: false,
        )
        build()
    }

    private static func groupChatID(_ id: Int64) -> Int64 { -id }
    private static func channelChatID(_ id: Int64) -> Int64 { -1_000_000_000_000 - id }

    private static func messageID(_ number: Int) -> Int64 { Int64(number) << 20 }

    private static func usernames(_ name: String) -> TDNativeUsernames {
        TDNativeUsernames(
            activeUsernames: [name], disabledUsernames: [], editableUsername: name, collectibleUsernames: [],
            secondaryUsername: "",
        )
    }

    private static func text(_ string: String, entities: [TDNativeTextEntity] = []) -> TDNativeFormattedText {
        TDNativeFormattedText(text: string, entities: entities)
    }

    private static func chatPhoto(_ file: TDNativeFile) -> TDNativeChatPhotoInfo {
        TDNativeChatPhotoInfo(small: file, big: file, minithumbnail: nil, hasAnimation: false, isPersonal: false)
    }

    // MARK: Answers

    func answer(_ request: String, _ arguments: [String: Any]) -> Any? {
        let chatID = arguments["chatId"] as? Int64 ?? 0
        let messageID = arguments["messageId"] as? Int64 ?? 0
        switch request {
        case "getMe":
            return users[ID.me]
        case "getUser":
            return (arguments["userId"] as? Int64).flatMap { users[$0] }
        case "getChat":
            return chats[chatID]
        case "createPrivateChat":
            return (arguments["userId"] as? Int64).flatMap { chats[$0] }
        case "getBasicGroup":
            return (arguments["basicGroupId"] as? Int64).flatMap { basicGroups[$0] }
        case "getSupergroup":
            return (arguments["supergroupId"] as? Int64).flatMap { supergroups[$0] }
        case "getUserFullInfo":
            return (arguments["userId"] as? Int64).flatMap { userFullInfo($0) }
        case "getBasicGroupFullInfo":
            return (arguments["basicGroupId"] as? Int64).flatMap { basicGroupFullInfo($0) }
        case "getSupergroupFullInfo":
            return (arguments["supergroupId"] as? Int64).flatMap { supergroupFullInfo($0) }
        case "getChatHistory":
            return history(
                chatID: chatID,
                from: arguments["fromMessageId"] as? Int64 ?? 0,
                limit: arguments["limit"] as? Int ?? 50,
            )
        case "getMessage":
            return messages[chatID]?.first { $0.id == messageID }
        case "getMessages":
            let ids = arguments["messageIds"] as? [Int64] ?? []
            let found = ids.compactMap { id in messages[chatID]?.first { $0.id == id } }
            return TDNativeMessages(totalCount: found.count, messages: found)
        case "getRepliedMessage":
            guard let message = messages[chatID]?.first(where: { $0.id == messageID }),
                  case .messageReplyToMessage(let reply) = message.replyTo else { return nil }
            return messages[chatID]?.first { $0.id == reply.messageId }
        case "getChatPinnedMessage":
            return pinned[chatID]
        case "getMessageProperties":
            return messageProperties
        case "getMessageAvailableReactions":
            return TDNativeAvailableReactions(
                topReactions: ["👍", "❤️", "🔥", "😂", "😮", "🎉", "🙏"].map {
                    TDNativeAvailableReaction(type: .reactionTypeEmoji(.init(emoji: $0)), needsPremium: false)
                },
                recentReactions: [], popularReactions: [], allowCustomEmoji: false, areTags: false,
                unavailabilityReason: nil,
            )
        case "closeChat",
             "openChat",
             "viewMessages":
            return TDNativeOk()
        case "downloadFile",
             "getFile":
            return (arguments["fileId"] as? Int).flatMap { files[$0] }
        case "getChats":
            return TDNativeChats(totalCount: chats.count, chatIds: Array(chats.keys))
        case "getTopChats":
            let top = [ID.mia, ID.liam, ID.sofia, ID.noah, ID.ava, ID.ethan, ID.zoe]
            return TDNativeChats(totalCount: top.count, chatIds: top)
        case "searchRecentlyFoundChats":
            let recent = [ID.mia, Self.groupChatID(ID.hikeGroup), Self.channelChatID(ID.digestChannel), ID.liam]
            return TDNativeChats(totalCount: recent.count, chatIds: recent)
        case "searchChats":
            let query = (arguments["query"] as? String ?? "").lowercased()
            let found = chats.values
                .filter { $0.title.lowercased().contains(query) }
                .sorted { $0.title < $1.title }
                .map(\.id)
            return TDNativeChats(totalCount: found.count, chatIds: found)
        case "getChatMessageCount":
            if case .searchMessagesFilterPhotoAndVideo? = arguments["filter"] as? TDNativeSearchMessagesFilter {
                return TDNativeCount(count: sharedPhotos[chatID]?.count ?? 0)
            }
            return TDNativeCount(count: 0)
        case "searchChatMessages":
            let isFirstPage = arguments["fromMessageId"] as? Int64 == 0
            guard isFirstPage,
                  case .searchMessagesFilterPhotoAndVideo? = arguments["filter"] as? TDNativeSearchMessagesFilter
            else { return TDNativeFoundChatMessages(totalCount: 0, messages: [], nextFromMessageId: 0) }
            let found = sharedPhotos[chatID] ?? []
            return TDNativeFoundChatMessages(totalCount: found.count, messages: found, nextFromMessageId: 0)
        case "searchOutgoingDocumentMessages":
            return TDNativeFoundMessages(totalCount: recentFiles.count, messages: recentFiles, nextOffset: "")
        case "getUserProfilePhotos":
            return TDNativeChatPhotos(totalCount: 0, photos: [])
        default:
            return nil
        }
    }

    private func history(chatID: Int64, from: Int64, limit: Int) -> TDNativeMessages {
        let newestFirst = (messages[chatID] ?? []).sorted { $0.id > $1.id }
        let page = newestFirst.filter { from == 0 || $0.id < from }.prefix(limit)
        return TDNativeMessages(totalCount: newestFirst.count, messages: Array(page))
    }

    private func userFullInfo(_ id: Int64) -> TDNativeUserFullInfo? {
        guard users[id] != nil else { return nil }
        let bios: [Int64: String] = [
            ID.mia: "Landscape photographer. Usually somewhere above the tree line.",
            ID.liam: "Coffee, code and cycling.",
            ID.me: "Building things on my iPhone.",
        ]
        return TDNativeUserFullInfo(
            personalPhoto: nil, photo: nil, publicPhoto: nil, communityId: 0, blockList: nil, canBeCalled: true,
            supportsVideoCalls: true, hasPrivateCalls: false, hasPrivateForwards: false,
            hasRestrictedVoiceAndVideoNoteMessages: false, hasPostedToProfileStories: false,
            hasSponsoredMessagesEnabled: false, needPhoneNumberPrivacyException: false, setChatBackground: false,
            usesUnofficialApp: false, bio: bios[id].map { Self.text($0) },
            birthdate: nil, personalChatId: 0, giftCount: 0,
            groupInCommonCount: id == ID.mia ? 2 : 0, incomingPaidMessageStarCount: 0,
            outgoingPaidMessageStarCount: 0,
            giftSettings: .init(
                showGiftButton: false,
                acceptedGiftTypes: .init(
                    unlimitedGifts: false, limitedGifts: false, upgradedGifts: false, giftsFromChannels: false,
                    premiumSubscription: false,
                ),
            ),
            botVerification: nil, mainProfileTab: nil, firstProfileAudio: nil, rating: nil, pendingRating: nil,
            pendingRatingDate: 0, note: nil, tonWalletCard: nil, shareTheme: nil, businessInfo: nil, botInfo: nil,
        )
    }

    private func basicGroupFullInfo(_ id: Int64) -> TDNativeBasicGroupFullInfo? {
        guard basicGroups[id] != nil else { return nil }
        let members = [ID.me, ID.noah, ID.ava, ID.mia, ID.ethan, ID.zoe].enumerated().map { index, user in
            TDNativeChatMember(
                memberId: .messageSenderUser(.init(userId: user)), tag: "", inviterUserId: ID.me,
                joinedChatDate: now - 86400 * (30 - index),
                status: user == ID.me
                    ? .chatMemberStatusCreator(.init(isAnonymous: false, isMember: true))
                    : .chatMemberStatusMember(.init(memberUntilDate: 0)),
            )
        }
        return TDNativeBasicGroupFullInfo(
            photo: nil, description: "Planning the next trip, one poll at a time.", creatorUserId: ID.me,
            members: members, canHideMembers: false, canToggleAggressiveAntiSpam: false, inviteLink: nil,
            botCommands: [],
        )
    }

    private func supergroupFullInfo(_ id: Int64) -> TDNativeSupergroupFullInfo? {
        guard let group = supergroups[id] else { return nil }
        return TDNativeSupergroupFullInfo(
            photo: nil, communityId: 0, description: "The week in Swift, iOS and everything around them.",
            memberCount: group.memberCount, administratorCount: 2, restrictedCount: 0, bannedCount: 0,
            linkedChatId: 0, directMessagesChatId: 0, slowModeDelay: 0, slowModeDelayExpiresIn: 0,
            canEnablePaidMessages: false, canEnablePaidReaction: false, canGetMembers: false,
            hasHiddenMembers: false, canHideMembers: false, canSetStickerSet: false, canSetLocation: false,
            canGetStatistics: false, canGetRevenueStatistics: false, canGetStarRevenueStatistics: false,
            canSendGift: false, canToggleAggressiveAntiSpam: false, isAllHistoryAvailable: true,
            canHaveSponsoredMessages: false, hasAggressiveAntiSpamEnabled: false, hasPaidMediaAllowed: false,
            hasPinnedStories: false, giftCount: 0, myBoostCount: 0, unrestrictBoostCount: 0,
            outgoingPaidMessageStarCount: 0, stickerSetId: 0, customEmojiStickerSetId: 0, location: nil,
            inviteLink: nil, guardBotUserId: 0, botCommands: [], botVerification: nil, mainProfileTab: nil,
            shareTheme: nil, upgradedFromBasicGroupId: 0, upgradedFromMaxMessageId: 0,
        )
    }

    // MARK: Building

    private func build() {
        users[ID.me] = me
        addUser(
            ID.mia,
            "Mia",
            "Chen",
            username: "miachen",
            accent: 2,
            status: .online,
            avatar: ("🏔️", [0x4F8EF7, 0x7ED6DF]),
        )
        addUser(
            ID.liam,
            "Liam",
            "Carter",
            username: "liamc",
            accent: 0,
            status: .recently,
            avatar: ("🚴", [0xF7971E, 0xFFD200]),
        )
        addUser(
            ID.sofia,
            "Sofia",
            "Rossi",
            username: nil,
            accent: 4,
            status: .recently,
            avatar: ("🌿", [0x56AB2F, 0xA8E063]),
        )
        addUser(ID.noah, "Noah", "Kim", username: "noahk", accent: 5, status: .online, avatar: nil)
        addUser(
            ID.ava,
            "Ava",
            "Patel",
            username: nil,
            accent: 3,
            status: .recently,
            avatar: ("🎨", [0xC471F5, 0xFA71CD]),
        )
        addUser(ID.ethan, "Ethan", "Brooks", username: nil, accent: 6, status: .recently, avatar: nil)
        addUser(
            ID.zoe,
            "Zoe",
            "Martin",
            username: nil,
            accent: 1,
            status: .recently,
            avatar: ("☕️", [0x8E6E53, 0xD7B899]),
        )

        basicGroups[ID.hikeGroup] = TDNativeBasicGroup(
            id: ID.hikeGroup, memberCount: 6, status: .chatMemberStatusCreator(
                .init(isAnonymous: false, isMember: true),
            ), isActive: true, upgradedToSupergroupId: 0,
        )
        basicGroups[ID.designGroup] = TDNativeBasicGroup(
            id: ID.designGroup, memberCount: 9, status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
            isActive: true, upgradedToSupergroupId: 0,
        )
        basicGroups[ID.bookGroup] = TDNativeBasicGroup(
            id: ID.bookGroup, memberCount: 5, status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
            isActive: true, upgradedToSupergroupId: 0,
        )
        addChannel(ID.digestChannel, members: 48210)
        addChannel(ID.productChannel, members: 12904)
        addChannel(ID.travelChannel, members: 7350)
        addChannel(ID.newsChannel, members: 31200)
        addChannel(ID.dealsChannel, members: 5400)
        basicGroups[ID.oldGroup] = TDNativeBasicGroup(
            id: ID.oldGroup, memberCount: 7, status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
            isActive: true, upgradedToSupergroupId: 0,
        )

        buildMiaChat()
        buildHikeChat()
        buildDigestChannel()
        buildShortChats()
        buildFolders()
        recentFiles = [
            ("Ridge Loop.gpx", "application/gpx+xml", 1_240_000, 40),
            ("Trip budget.xlsx", "application/vnd.ms-excel", 86000, 260),
            ("Design review.pdf", "application/pdf", 4_300_000, 1500),
            ("Release notes.md", "text/markdown", 12000, 3100),
            ("Trail photos.zip", "application/zip", 48_600_000, 6200),
            ("Packing list.docx", "application/msword", 31000, 9000),
        ]
.enumerated()
.map { index, file in
            message(
                Self.messageID(800 + index), ID.liam, from: ID.me, minutesAgo: file.3,
                document(file.0, size: Int64(file.2), mimeType: file.1),
            )
        }

        updates.append(.updateConnectionState(.init(state: .connectionStateReady)))
        for user in users.values {
            updates.append(.updateUser(.init(user: user)))
        }
        for group in basicGroups.values {
            updates.append(.updateBasicGroup(.init(basicGroup: group)))
        }
        for group in supergroups.values {
            updates.append(.updateSupergroup(.init(supergroup: group)))
        }
        for chat in chats.values {
            updates.append(.updateNewChat(.init(chat: chat)))
        }
    }

    private func addUser(
        _ id: Int64, _ first: String, _ last: String, username: String?, accent: Int, status: Presence,
        avatar: (emoji: String, colors: [UInt32])?,
    ) {
        let photo: TDNativeProfilePhoto? = avatar.map {
            let file = imageFile(name: "user-\(id)") { DemoPicture.avatar(emoji: $0.emoji, colors: $0.colors) }($0)
            return TDNativeProfilePhoto(
                id: id, small: file, big: file, minithumbnail: nil, hasAnimation: false, isPersonal: false,
            )
        }
        users[id] = TDNativeUser(
            id: id, firstName: first, lastName: last, usernames: username.map(Self.usernames), phoneNumber: "",
            status: status == .online
                ? .userStatusOnline(.init(expires: Int(Date.now.timeIntervalSince1970) + 3600))
                : .userStatusRecently(.init(byMyPrivacySettings: false)),
            profilePhoto: photo, accentColorId: accent, backgroundCustomEmojiId: 0, upgradedGiftColors: nil,
            profileAccentColorId: -1, profileBackgroundCustomEmojiId: 0, emojiStatus: nil, isContact: true,
            isMutualContact: true, isCloseFriend: false, verificationStatus: nil, isPremium: false,
            isSupport: false, restrictionInfo: nil, activeStoryState: nil, restrictsNewChats: false,
            paidMessageStarCount: 0, haveAccess: true, type: .userTypeRegular, languageCode: "en",
            addedToAttachmentMenu: false,
        )
    }

    private func addChannel(_ id: Int64, members: Int) {
        supergroups[id] = TDNativeSupergroup(
            id: id, usernames: nil, date: now - 86400 * 400, status: .chatMemberStatusMember(.init(memberUntilDate: 0)),
            memberCount: members, boostLevel: 0, hasAutomaticTranslation: false, hasLinkedChat: false,
            hasLocation: false, signMessages: false, showMessageSender: false, joinToSendMessages: false,
            joinByRequest: false, isSlowModeEnabled: false, isChannel: true, isBroadcastGroup: false, isForum: false,
            isDirectMessagesGroup: false, isAdministeredDirectMessagesGroup: false, verificationStatus: nil,
            hasDirectMessagesGroup: false, hasForumTabs: false, restrictionInfo: nil, paidMessageStarCount: 0,
            activeStoryState: nil,
        )
    }

    private func buildMiaChat() {
        let chatID = ID.mia
        var list = [TDNativeMessage]()
        func add(_ make: (Int64) -> TDNativeMessage) {
            let message = make(Self.messageID(list.count + 1))
            list.append(message)
        }
        add { self.message($0, chatID, from: ID.mia, minutesAgo: 45, self.document("Ridge Loop.gpx", size: 1_240_000)) }
        add { self.message($0, chatID, from: ID.mia, minutesAgo: 29, .text("Morning! Did you see the trail photos?")) }
        add { self.message($0, chatID, from: ID.me, minutesAgo: 27, .text("Not yet, send them over 👀")) }
        let ridge = Self.messageID(4)
        add { self.message(
            $0, chatID, from: ID.mia, minutesAgo: 26,
            self.photo("ridge", palette: .sunset, caption: "Sunset from the ridge 🌄"),
            reactions: [("❤️", 1, true)],
        ) }
        add { self.message(
            $0, chatID, from: ID.me, minutesAgo: 25, .text("This is unreal. Where is that?"),
            replyTo: ridge, replyChat: chatID, reactions: [("🔥", 1, false)],
        ) }
        add { self.message($0, chatID, from: ID.mia, minutesAgo: 21, self.voice(seconds: 14)) }
        add { self.message(
            $0, chatID, from: ID.me, minutesAgo: 3,
            .text(
                "Saturday at 7? https://trails.example/ridge-loop",
                entities: [.init(offset: 15, length: 33, type: .textEntityTypeUrl)],
                preview: .init(
                    url: "https://trails.example/ridge-loop", displayUrl: "trails.example/ridge-loop",
                    siteName: "Trails", title: "Ridge Loop", description: Self.text(
                        "An 11 km loop with a long view over the valley.",
                    ), author: "", type: .linkPreviewTypeArticle(.init(photo: nil)), hasLargeMedia: false,
                    showLargeMedia: false, showMediaAboveDescription: false, skipConfirmation: false,
                    showAboveText: false, instantViewVersion: 0,
                ),
            ),
        ) }
        add { self.message($0, chatID, from: ID.mia, minutesAgo: 1, .text("Sure, see you at 7!")) }
        messages[chatID] = list
        let palettes: [DemoPicture.Palette] = [.morning, .sunset, .forest, .dusk]
        sharedPhotos[chatID] = (0..<15).map { index in
            message(
                Self.messageID(500 - index), chatID, from: index.isMultiple(of: 3) ? ID.me : ID.mia,
                minutesAgo: 600 + index * 700,
                photo("shared-\(index)", palette: palettes[index % palettes.count], seed: index),
            )
        }
        addChat(
            id: chatID, type: .chatTypePrivate(.init(userId: ID.mia)), title: "Mia Chen", photo: nil,
            unread: 2, order: 90, pinned: true, folders: [ID.personalFolder],
        )
    }

    private func buildHikeChat() {
        let chatID = Self.groupChatID(ID.hikeGroup)
        var list = [TDNativeMessage]()
        func add(_ make: (Int64) -> TDNativeMessage) {
            list.append(make(Self.messageID(list.count + 1)))
        }
        let meetup = Self.messageID(1)
        add { self.message(
            $0, chatID, from: ID.me, minutesAgo: 95,
            .text(
                "Meet at the north parking lot at 7:00. Bring water!",
                entities: [.init(offset: 8, length: 22, type: .textEntityTypeBold)],
            ),
            pinned: true, reactions: [("👍", 4, true)],
        ) }
        add {
            self.message($0, chatID, from: ID.noah, minutesAgo: 60, .text("I can drive, there's room for three more."))
            }
        add { self.message(
            $0, chatID, from: ID.ava, minutesAgo: 44, self.album(2),
            album: 77001,
        ) }
        add { self.message(
            $0, chatID, from: ID.ava, minutesAgo: 44,
            self.album(3, caption: "Last year's view from the top 🥾"),
            reactions: [("😍", 3, true), ("🔥", 2, false)], album: 77001,
        ) }
        add { self.message(
            $0, chatID, from: ID.noah, minutesAgo: 38, self.poll(),
            reactions: [("👍", 2, false)],
        ) }
        add { self.message($0, chatID, from: ID.ethan, minutesAgo: 2, .text("The lake, no question.")) }
        messages[chatID] = list
        pinned[chatID] = list.first { $0.id == meetup }
        let file = imageFile(name: "hike") { DemoPicture.avatar(emoji: "🥾", colors: [0x2C7744, 0x5FC58E]) }(())
        addChat(
            id: chatID, type: .chatTypeBasicGroup(.init(basicGroupId: ID.hikeGroup)), title: "Weekend Hike",
            photo: Self.chatPhoto(file), unread: 5, order: 80, pinned: false, folders: [ID.personalFolder],
        )
    }

    private func buildDigestChannel() {
        let chatID = Self.channelChatID(ID.digestChannel)
        var list = [TDNativeMessage]()
        func post(_ content: TDNativeMessageContent, minutesAgo: Int, views: Int, reactions: [(String, Int, Bool)]) {
            let id = Self.messageID(list.count + 1)
            list.append(message(
                id, chatID, from: nil, minutesAgo: minutesAgo, content, reactions: reactions, views: views,
            ))
        }
        post(
            .text(
                "This week: new layout APIs, a faster build system and five talks worth your evening.",
                entities: [.init(offset: 0, length: 10, type: .textEntityTypeBold)],
            ),
            minutesAgo: 1500, views: 12800, reactions: [("👍", 214, false), ("🔥", 96, false)],
        )
        post(
            photo("digest", palette: .dusk, caption: "Our favourite wallpaper from this week's submissions."),
            minutesAgo: 400, views: 18400, reactions: [("😍", 512, true), ("👍", 88, false)],
        )
        post(
            .text("Tip of the day: measure before you optimize. Instruments will surprise you."),
            minutesAgo: 34, views: 6120, reactions: [("💯", 143, false)],
        )
        messages[chatID] = list
        let file = imageFile(name: "digest-avatar") { DemoPicture.avatar(emoji: "📰", colors: [0x1F4E8C, 0x3FA7D6]) }(())
        addChat(
            id: chatID, type: .chatTypeSupergroup(.init(supergroupId: ID.digestChannel, isChannel: true)),
            title: "Tech Digest", photo: Self.chatPhoto(file), unread: 128, order: 62, pinned: false,
            muted: true, folders: [ID.channelsFolder],
        )
    }

    private func buildShortChats() {
        unreadOutgoingChats.insert(ID.sofia)
        // Saved Messages stands first, as an account's own chat with itself.
        short(
            ID.me,
            .chatTypePrivate(.init(userId: ID.me)),
            "Saved Messages",
            "Ridge Loop checklist",
            from: ID.me,
            minutes: 200,
            unread: 0,
            order: 99,
            pinned: true,
        )
        short(
            ID.liam,
            .chatTypePrivate(.init(userId: ID.liam)),
            "Liam Carter",
            "Pushed the fix, can you take a look?",
            from: ID.liam,
            minutes: 16,
            unread: 1,
            order: 70,
            folders: [ID.personalFolder, ID.workFolder],
        )
        short(
            Self.groupChatID(ID.designGroup),
            .chatTypeBasicGroup(.init(basicGroupId: ID.designGroup)),
            "Design Team",
            "New icons are in the shared folder",
            from: ID.noah,
            minutes: 32,
            unread: 14,
            order: 65,
            avatar: ("✏️", [0xFF5F6D, 0xFFC371]),
            folders: [ID.workFolder],
        )
        short(
            ID.sofia,
            .chatTypePrivate(.init(userId: ID.sofia)),
            "Sofia Rossi",
            "Thank you, that was so helpful 🙏",
            from: ID.me,
            minutes: 70,
            unread: 0,
            order: 60,
            folders: [ID.personalFolder],
        )
        // One message delivered and one on its way, whose checks the other chats don't show.
        let sofia = ID.sofia
        messages[sofia, default: []].append(message(
            Self.messageID(2), sofia, from: ID.me, minutesAgo: 60, .text("Shall I send you the rest?"),
        ))
        messages[sofia, default: []].append(message(
            Self.messageID(3), sofia, from: ID.me, minutesAgo: 0, .text("On its way"), isSending: true,
        ))
        short(
            Self.channelChatID(ID.productChannel),
            .chatTypeSupergroup(.init(supergroupId: ID.productChannel, isChannel: true)),
            "Product Updates",
            "Version 2.4 is rolling out today",
            from: nil,
            minutes: 150,
            unread: 3,
            order: 55,
            avatar: ("🚀", [0x6A11CB, 0x2575FC]),
            muted: true,
            folders: [ID.channelsFolder],
        )
        short(
            Self.groupChatID(ID.bookGroup),
            .chatTypeBasicGroup(.init(basicGroupId: ID.bookGroup)),
            "Book Club",
            "Chapter 12 changes everything",
            from: ID.zoe,
            minutes: 260,
            unread: 0,
            order: 50,
            avatar: ("📚", [0xB24592, 0xF15F79]),
            folders: [ID.personalFolder],
        )
        short(
            ID.ethan,
            .chatTypePrivate(.init(userId: ID.ethan)),
            "Ethan Brooks",
            "Lunch tomorrow?",
            from: ID.ethan,
            minutes: 400,
            unread: 0,
            order: 45,
            folders: [ID.personalFolder],
        )
        short(
            Self.channelChatID(ID.travelChannel),
            .chatTypeSupergroup(.init(supergroupId: ID.travelChannel, isChannel: true)),
            "Travel Notes",
            "Five quiet towns to visit this autumn",
            from: nil,
            minutes: 900,
            unread: 0,
            order: 40,
            avatar: ("🧭", [0x11998E, 0x38EF7D]),
            folders: [ID.channelsFolder],
        )
        short(
            ID.zoe,
            .chatTypePrivate(.init(userId: ID.zoe)),
            "Zoe Martin",
            "See you there!",
            from: ID.me,
            minutes: 1500,
            unread: 0,
            order: 35,
            folders: [ID.personalFolder],
        )
        short(
            ID.ava,
            .chatTypePrivate(.init(userId: ID.ava)),
            "Ava Patel",
            "Love the new palette",
            from: ID.ava,
            minutes: 1700,
            unread: 0,
            order: 30,
            folders: [ID.workFolder],
        )
        short(
            ID.noah,
            .chatTypePrivate(.init(userId: ID.noah)),
            "Noah Kim",
            "Shipping it 🚢",
            from: ID.noah,
            minutes: 2100,
            unread: 0,
            order: 25,
            folders: [ID.workFolder],
        )
        short(
            Self.channelChatID(ID.newsChannel),
            .chatTypeSupergroup(.init(supergroupId: ID.newsChannel, isChannel: true)),
            "Morning Brief",
            "Three things to know today",
            from: nil,
            minutes: 500,
            unread: 12,
            order: 20,
            avatar: ("🗞️", [0x373B44, 0x4286F4]),
            muted: true,
            archived: true,
        )
        short(
            Self.channelChatID(ID.dealsChannel),
            .chatTypeSupergroup(.init(supergroupId: ID.dealsChannel, isChannel: true)),
            "Weekly Deals",
            "This week's best prices on gear",
            from: nil,
            minutes: 3000,
            unread: 4,
            order: 15,
            avatar: ("🏷️", [0xEB3349, 0xF45C43]),
            muted: true,
            archived: true,
        )
        short(
            Self.groupChatID(ID.oldGroup),
            .chatTypeBasicGroup(.init(basicGroupId: ID.oldGroup)),
            "Summer Trip 2025",
            "Thanks everyone, what a week!",
            from: ID.zoe,
            minutes: 90000,
            unread: 0,
            order: 10,
            avatar: ("🏖️", [0xF7971E, 0x56CCF2]),
            archived: true,
        )
    }

    private func short(
        _ chatID: Int64, _ type: TDNativeChatType, _ title: String, _ text: String, from: Int64?, minutes: Int,
        unread: Int, order: Int64, pinned: Bool = false, avatar: (String, [UInt32])? = nil, muted: Bool = false,
        folders: [Int] = [], archived: Bool = false,
    ) {
        messages[chatID] = [message(Self.messageID(1), chatID, from: from, minutesAgo: minutes, .text(text))]
        let photo = avatar.map { avatar in
            Self.chatPhoto(imageFile(name: "chat-\(chatID)") {
                DemoPicture.avatar(emoji: avatar.0, colors: avatar.1)
            }(()))
        }
        addChat(
            id: chatID, type: type, title: title, photo: photo, unread: unread, order: order, pinned: pinned,
            muted: muted, folders: folders, archived: archived,
        )
    }

    private func addChat(
        id: Int64, type: TDNativeChatType, title: String, photo: TDNativeChatPhotoInfo?, unread: Int, order: Int64,
        pinned: Bool, muted: Bool = false, folders: [Int] = [], archived: Bool = false,
    ) {
        var resolvedPhoto = photo
        if resolvedPhoto == nil, case .chatTypePrivate(let peer) = type,
           let profile = users[peer.userId]?.profilePhoto
        {
            resolvedPhoto = TDNativeChatPhotoInfo(
                small: profile.small, big: profile.big, minithumbnail: nil, hasAnimation: false, isPersonal: false,
            )
        }
        let home: TDNativeChatList = archived ? .chatListArchive : .chatListMain
        var positions = [TDNativeChatPosition(list: home, order: order * 1000, isPinned: pinned, source: nil)]
        var lists = [home]
        for folder in folders {
            let list = TDNativeChatList.chatListFolder(.init(chatFolderId: folder))
            positions.append(.init(list: list, order: order * 1000, isPinned: false, source: nil))
            lists.append(list)
        }
        chats[id] = TDNativeChat(
            id: id, type: type, title: title, photo: resolvedPhoto, accentColorId: abs(Int(id % 7)),
            backgroundCustomEmojiId: 0, upgradedGiftColors: nil, profileAccentColorId: -1,
            profileBackgroundCustomEmojiId: 0, permissions: Self.permissions,
            lastMessage: messages[id]?.max { $0.id < $1.id }, positions: positions, chatLists: lists,
            messageSenderId: nil, blockList: nil, hasProtectedContent: false, isTranslatable: false,
            isMarkedAsUnread: false, viewAsTopics: false, hasScheduledMessages: false, hasWelcomeMessages: false,
            canBeDeletedOnlyForSelf: true, canBeDeletedForAllUsers: true, canBeReported: false,
            defaultDisableNotification: false, unreadCount: unread,
            lastReadInboxMessageId: Self.messageID(1),
            lastReadOutboxMessageId: unreadOutgoingChats.contains(id) ? 0 : Self.messageID(1000),
            unreadMentionCount: 0, unreadReactionCount: 0, unreadPollVoteCount: 0,
            notificationSettings: .init(
                useDefaultMuteFor: !muted, muteFor: muted ? 86400 * 365 : 0, useDefaultSound: true, soundId: 0,
                useDefaultShowPreview: true, showPreview: true, useDefaultMuteStories: true, muteStories: false,
                useDefaultStorySound: true, storySoundId: 0, useDefaultShowStoryPoster: true, showStoryPoster: true,
                useDefaultDisablePinnedMessageNotifications: true, disablePinnedMessageNotifications: false,
                useDefaultDisableMentionNotifications: true, disableMentionNotifications: false,
            ),
            availableReactions: .chatAvailableReactionsAll(.init(maxReactionCount: 3)), messageAutoDeleteTime: 0,
            emojiStatus: nil, background: nil, theme: nil, actionBar: nil, businessBotManageBar: nil,
            videoChat: .init(groupCallId: 0, hasParticipants: false, defaultParticipantId: nil),
            pendingJoinRequests: nil, replyMarkupMessageId: 0, draftMessage: nil, clientData: "",
        )
    }

    private func buildFolders() {
        func folder(_ id: Int, _ title: String, _ icon: String) -> (TDNativeChatFolderInfo, TDNativeChatFolder) {
            let name = TDNativeChatFolderName(text: Self.text(title), animateCustomEmoji: false)
            let folderIcon = TDNativeChatFolderIcon(name: icon)
            return (
                TDNativeChatFolderInfo(
                    id: id, name: name, icon: folderIcon, colorId: -1, isShareable: false, hasMyInviteLinks: false,
                ),
                TDNativeChatFolder(
                    name: name, icon: folderIcon, colorId: -1, isShareable: false, pinnedChatIds: [],
                    includedChatIds: [], excludedChatIds: [], excludeMuted: false, excludeRead: false,
                    excludeArchived: false, includeContacts: false, includeNonContacts: false, includeBots: false,
                    includeGroups: false, includeChannels: false,
                ),
            )
        }
        folders = [
            folder(ID.personalFolder, "Personal", "Custom"),
            folder(ID.workFolder, "Work", "Work"),
            folder(ID.channelsFolder, "Channels", "Channels"),
        ].map { (info: $0.0, definition: $0.1) }
        let counts: [(Int, Int)] = [(ID.personalFolder, 8), (ID.workFolder, 15), (ID.channelsFolder, 0)]
        for (id, unread) in counts {
            updates.append(.updateUnreadChatCount(.init(
                chatList: .chatListFolder(.init(chatFolderId: id)), totalCount: 8, unreadCount: unread,
                unreadUnmutedCount: unread, markedAsUnreadCount: 0, markedAsUnreadUnmutedCount: 0,
            )))
        }
    }

    private func message(
        _ id: Int64, _ chatID: Int64, from sender: Int64?, minutesAgo: Int, _ content: TDNativeMessageContent,
        replyTo: Int64? = nil, replyChat: Int64 = 0, pinned: Bool = false,
        reactions: [(String, Int, Bool)] = [], views: Int = 0, album: Int64 = 0, isSending: Bool = false,
    ) -> TDNativeMessage {
        let senderID: TDNativeMessageSender = sender.map { .messageSenderUser(.init(userId: $0)) }
            ?? .messageSenderChat(.init(chatId: chatID))
        let reply: TDNativeMessageReplyTo? = replyTo.map {
            .messageReplyToMessage(.init(
                chatId: replyChat, messageId: $0, quote: nil, checklistTaskId: 0, pollOptionId: "", origin: nil,
                originSendDate: 0, content: nil,
            ))
        }
        let info: TDNativeMessageInteractionInfo? = reactions.isEmpty && views == 0
            ? nil
            : TDNativeMessageInteractionInfo(
                viewCount: views, forwardCount: 0, replyInfo: nil,
                reactions: reactions.isEmpty
                ? nil
                : TDNativeMessageReactions(
                    reactions: reactions.map {
                    TDNativeMessageReaction(
                        type: .reactionTypeEmoji(.init(emoji: $0.0)), totalCount: $0.1, isChosen: $0.2,
                        usedSenderId: $0.2 ? .messageSenderUser(.init(userId: ID.me)) : nil, recentSenderIds: [],
                    )
                },
                    areTags: false, paidReactors: [], canGetAddedReactions: false,
                ),
            )
        return TDNativeMessage(
            id: id, senderId: senderID, receiverId: nil, chatId: chatID,
            sendingState: isSending ? .messageSendingStatePending(.init(sendingId: 1)) : nil, schedulingState: nil,
            isOutgoing: sender == ID.me, isPinned: pinned, isFromOffline: false, canBeSaved: true,
            hasTimestampedMedia: false, isChannelPost: sender == nil, isPaidStarSuggestedPost: false,
            isPaidGramSuggestedPost: false, containsUnreadMention: false, containsUnreadPollVotes: false,
            date: now - minutesAgo * 60, editDate: 0, forwardInfo: nil, importInfo: nil, interactionInfo: info,
            unreadReactions: [], factCheck: nil, suggestedPostInfo: nil, replyTo: reply, topicId: nil,
            selfDestructType: nil, selfDestructIn: 0, autoDeleteIn: 0, viaBotUserId: 0, guestBotCallerId: nil,
            senderBusinessBotUserId: 0, senderBoostCount: 0, senderTag: "", paidMessageStarCount: 0,
            authorSignature: "", mediaAlbumId: album, effectId: 0, restrictionInfo: nil, summaryLanguageCode: "",
            content: content, ephemeralContent: nil, replyMarkup: nil, ephemeralMessageId: 0, chatInstance: 0,
        )
    }

    private func photo(
        _ name: String, palette: DemoPicture.Palette, caption: String = "", seed: Int = 0,
    ) -> TDNativeMessageContent {
        let size = CGSize(width: 1000, height: 750)
        let file = imageFile(name: "photo-\(name)") {
            DemoPicture.landscape(size: size, palette: palette, seed: seed)
        }(())
        return .messagePhoto(.init(
            photo: .init(
                hasStickers: false, minithumbnail: nil,
                sizes: [.init(
                    type: "y",
                    photo: file,
                    width: Int(size.width),
                    height: Int(size.height),
                    progressiveSizes: [],
                )],
            ),
            video: nil, caption: Self.text(caption), showCaptionAboveMedia: false, hasSpoiler: false, isSecret: false,
        ))
    }

    private func album(_ number: Int, caption: String = "") -> TDNativeMessageContent {
        let palette: [DemoPicture.Palette] = [.dusk, .morning, .forest]
        return photo("album-\(number)", palette: palette[(number - 1) % palette.count], caption: caption)
    }

    private func voice(seconds: Int) -> TDNativeMessageContent {
        // Telegram's waveform: 5 bits a sample, packed.
        var bits = [UInt8]()
        for index in 0..<63 {
            let level = (sin(Double(index) * 0.5) + sin(Double(index) * 0.17) + 2) / 4 * 31
            for bit in 0..<5 {
                bits.append(UInt8((Int(level) >> bit) & 1))
            }
        }
        var waveform = Data(count: bits.count / 8 + 1)
        for (index, bit) in bits.enumerated() {
            waveform[index / 8] |= bit << (index % 8)
        }
        let voice = plainFile(name: "voice.ogg", size: 48000)
        return .messageVoiceNote(.init(
            voiceNote: .init(
                duration: seconds, waveform: waveform, mimeType: "audio/ogg", speechRecognitionResult: nil,
                voice: voice,
            ),
            caption: Self.text(""), isListened: true,
        ))
    }

    private func document(
        _ name: String, size: Int64, mimeType: String = "application/gpx+xml",
    ) -> TDNativeMessageContent {
        let file = plainFile(name: name, size: size)
        return .messageDocument(.init(
            document: .init(
                fileName: name, mimeType: mimeType, minithumbnail: nil, thumbnail: nil, document: file,
            ),
            caption: Self.text(""),
        ))
    }

    private func poll() -> TDNativeMessageContent {
        func option(_ id: String, _ text: String, _ voters: Int, _ percent: Int, chosen: Bool) -> TDNativePollOption {
            TDNativePollOption(
                id: id, text: Self.text(text), media: nil, voterCount: voters, votePercentage: percent,
                recentVoterIds: [], isChosen: chosen, isBeingChosen: false, author: nil, additionDate: 0,
            )
        }
        return .messagePoll(.init(
            poll: .init(
                id: 9001, question: Self.text("Where should we stop for lunch?"),
                options: [
                    option("a", "The lake", 4, 67, chosen: true),
                    option("b", "The summit", 1, 17, chosen: false),
                    option("c", "Back at the cars", 1, 16, chosen: false),
                ],
                totalVoterCount: 6, recentVoterIds: [], canGetVoters: false, canSeeResults: true, isAnonymous: true,
                allowsMultipleAnswers: false, allowsRevoting: true, membersOnly: false, countryCodes: [],
                optionOrder: [], type: .pollTypeRegular, openPeriod: 0, closeDate: 0, isClosed: false,
                voteRestrictionReason: nil,
            ),
            description: Self.text(""), media: nil, canAddOption: false,
        ))
    }

    private func nextFile(path: String, size: Int64) -> TDNativeFile {
        nextFileID += 1
        let file = TDNativeFile(
            id: nextFileID, size: size, expectedSize: size,
            local: .init(
                path: path, canBeDownloaded: false, canBeDeleted: false, isDownloadingActive: false,
                isDownloadingCompleted: true, downloadOffset: 0, downloadedPrefixSize: size, downloadedSize: size,
            ),
            remote: .init(
                id: "demo\(nextFileID)", uniqueId: "demo\(nextFileID)", isUploadingActive: false,
                isUploadingCompleted: true, uploadedSize: size,
            ),
        )
        files[nextFileID] = file
        return file
    }

    private func imageFile<Input>(name: String, _ draw: @escaping (Input) -> UIImage) -> (Input) -> TDNativeFile {
        { [self] input in
            let url = directory.appendingPathComponent("\(name).jpg")
            let data = draw(input).jpegData(compressionQuality: 0.9) ?? Data()
            try? data.write(to: url, options: .atomic)
            return nextFile(path: url.path, size: Int64(data.count))
        }
    }

    private func plainFile(name: String, size: Int64) -> TDNativeFile {
        let url = directory.appendingPathComponent(name)
        try? Data(count: 1024).write(to: url, options: .atomic)
        return nextFile(path: url.path, size: size)
    }
}

private extension TDNativeMessageContent {
    static func text(
        _ string: String, entities: [TDNativeTextEntity] = [], preview: TDNativeLinkPreview? = nil,
    ) -> TDNativeMessageContent {
        .messageText(.init(
            text: .init(text: string, entities: entities), linkPreview: preview, linkPreviewOptions: nil,
        ))
    }
}

// MARK: - DemoPicture

/// The demo's pictures, drawn here so that the screenshots carry nothing anyone else made.
private enum DemoPicture {
    struct Palette {
        static let sunset = Palette(
            sky: [0x2B1B5A, 0xC6426E, 0xF9A03F],
            sun: 0xFFE29A,
            ridges: [0x6B3A6E, 0x452A5C, 0x241A3F],
        )
        static let dusk = Palette(
            sky: [0x0F2027, 0x2C5364, 0x8FB8DE],
            sun: 0xF4F1DE,
            ridges: [0x3A5A78, 0x233D54, 0x101F2E],
        )
        static let morning = Palette(
            sky: [0x7EC8E3, 0xBFE6F5, 0xFDEBD0],
            sun: 0xFFF6D5,
            ridges: [0x7FA99B, 0x4F7F6B, 0x2B5B4A],
        )
        static let forest = Palette(
            sky: [0x134E5E, 0x71B280, 0xE3F1C5],
            sun: 0xFFFBE0,
            ridges: [0x3E7C59, 0x245C43, 0x113B2B],
        )

        var sky: [UInt32]
        var sun: UInt32
        var ridges: [UInt32]
    }

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1,
        )
    }

    static func avatar(emoji: String, colors: [UInt32]) -> UIImage {
        let side: CGFloat = 320
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            if let gradient = gradient(colors) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: side, y: side), options: [],
                )
            }
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: side * 0.5)])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
    }

    static func landscape(size: CGSize, palette: Palette, seed: Int = 0) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            if let sky = gradient(palette.sky) {
                cg.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height * 0.8), options: [])
            }
            let sunX = 0.15 + 0.7 * CGFloat((seed * 37 + 47) % 100) / 100
            let sun = CGRect(
                x: size.width * sunX,
                y: size.height * 0.28,
                width: size.width * 0.14,
                height: size.width * 0.14,
            )
            color(palette.sun).setFill()
            cg.fillEllipse(in: sun)
            for (index, hex) in palette.ridges.enumerated() {
                let base = size.height * (0.55 + CGFloat(index) * 0.15)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: base))
                let steps = 7 + index * 2
                for step in 0...steps {
                    let x = size.width * CGFloat(step) / CGFloat(steps)
                    let phase = Double(seed) * 1.3
                    let wave = sin(Double(step) * 1.7 + Double(index) * 2.3 + phase)
                        + sin(Double(step) * 0.9 + Double(index) + phase * 0.5)
                    path.addLine(to: CGPoint(x: x, y: base - CGFloat(wave) * size.height * 0.06))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.close()
                color(hex).setFill()
                path.fill()
            }
        }
    }

    private static func gradient(_ colors: [UInt32]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map { color($0).cgColor } as CFArray,
            locations: nil,
        )
    }
}
#endif
