// ChatSponsoredMessages.swift

import Foundation
import TDLibKit

// MARK: - ChatSponsoredMessage

/// A channel's sponsored message (TDLib's `sponsoredMessage`) with what Telegram keeps in AdMessageAttribute and the
/// ad's made-up author: the label, the sponsor's title, accent colour and link, the button and the sponsor's info.
/// It is no message of the history, so nothing that acts on messages (reply, forward, select, delete, reactions)
/// ever gets it.
struct ChatSponsoredMessage {
    /// AdMessageAttribute's `hasContentMedia`: the photo, video or GIF the ad itself carries.
    enum Media {
        case photo(Photo)
        case video(Video)
        case animation(Animation)
    }

    let chatID: Int64
    /// Unique in the chat among ordinary and sponsored messages; `viewMessages`, `clickChatSponsoredMessage` and
    /// `reportChatSponsoredMessage` take it.
    let id: Int64
    /// AdMessageAttribute's `.recommended`: "Recommended" instead of "Sponsored".
    let isRecommended: Bool
    let canBeReported: Bool
    let title: String
    let buttonText: String
    let url: String
    /// The sponsor's photo, a thumbnail beside the text; nil when it must not be shown.
    let sponsorPhoto: Photo?
    let sponsorInfo: String?
    let additionalInfo: String?
    let accentColorID: Int
    let text: FormattedText
    let media: Media?
    /// The media's file as TDLib left it once downloaded: the ad shows only then.
    var mediaFile: File?

    /// The file TDLib wants downloaded before the ad shows: the photo's largest size, the video or the GIF.
    var contentFile: File? {
        switch media {
        case .photo(let photo): photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
        case .video(let video): video.video
        case .animation(let animation): animation.animation
        case nil: nil
        }
    }

    /// The media's proportions, for its height in the bubble.
    var mediaSize: CGSize? {
        switch media {
        case .photo(let photo):
            photo.sizes
                .max { $0.width * $0.height < $1.width * $1.height }
                .map { CGSize(width: $0.width, height: $0.height) }
        case .video(let video): CGSize(width: video.width, height: video.height)
        case .animation(let animation): CGSize(width: animation.width, height: animation.height)
        case nil: nil
        }
    }

    /// ChatMessageWebpageBubbleContentNode's `isTelegramMeLink`: a link inside Telegram gets no corner arrow.
    var opensInTelegram: Bool {
        guard let url = getUrl(from: url) else { return false }
        if url.scheme == "tg" { return true }
        let host = url.host?.lowercased() ?? ""
        return ["t.me", "telegram.me", "telegram.dog"].contains(host) || host.hasSuffix(".t.me")
    }

    init(chatID: Int64, message: TDNativeSponsoredMessage) {
        self.chatID = chatID
        self.id = message.messageId
        self.isRecommended = message.isRecommended
        self.canBeReported = message.canBeReported
        self.title = message.title
        self.buttonText = message.buttonText
        self.url = message.sponsor.url
        self.sponsorPhoto = message.sponsor.photo
        self.sponsorInfo = message.sponsor.info.isEmpty ? nil : message.sponsor.info
        self.additionalInfo = message.additionalInfo.isEmpty ? nil : message.additionalInfo
        self.accentColorID = message.accentColorId
        switch message.content {
        case .messageText(let content):
            self.text = content.text
            self.media = nil
        case .messagePhoto(let content):
            self.text = content.caption
            self.media = .photo(content.photo)
        case .messageVideo(let content):
            self.text = content.caption
            self.media = .video(content.video)
        case .messageAnimation(let content):
            self.text = content.caption
            self.media = .animation(content.animation)
        default:
            self.text = FormattedText(entities: [], text: "")
            self.media = nil
        }
    }
}

// MARK: - ChatSponsoredMessagesContext

/// Telegram's AdMessagesHistoryContext on TDLib: a channel's sponsored messages, read once when the chat appears
/// (`activate`), the view TDLib counts once per ad while the chat shows (ChatHistoryListNode's `seenAdIds`), a click
/// on the ad and its report. TDLib keeps the ads for five minutes itself and counts each view and click once.
@MainActor final class ChatSponsoredMessagesContext {
    struct State {
        var messages = [ChatSponsoredMessage]()
        /// TDLib's `messages_between` (AdMessagesHistoryContext's `interPostInterval`): the fewest messages between
        /// two ads shown in the history, or 0 for one ad after the newest message.
        var messagesBetween = 0
        /// The chat's newest message when the ads arrived; the ad after the newest message waits for the history to
        /// reach it.
        var latestMessageID: Int64 = 0
        /// ChatPresentationInterfaceState's `isPremium`: Telegram offers Hide only without Premium.
        var isPremium = false
    }

    let chatID: Int64
    let client: TDLibClient
    /// Called on the main actor once the ads arrive or one is removed.
    var onUpdate: (() -> Void)?
    private(set) var state = State()

    private let accountID: UUID?
    private var isActivated = false
    private var seenIDs = Set<Int64>()
    private var loadTask: Task<Void, Never>?

    var isCurrent: Bool {
        accountID != nil && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(chatID: Int64, client: TDLibClient, accountID: UUID?) {
        self.chatID = chatID
        self.client = client
        self.accountID = accountID
    }

    deinit {
        loadTask?.cancel()
    }

    /// The ads whose media downloaded, in TDLib's order; the downloads run side by side.
    private static func downloadingContent(
        of messages: [ChatSponsoredMessage],
        client: TDLibClient,
    ) async -> [ChatSponsoredMessage] {
        let files = await withTaskGroup(of: (Int, File?).self) { group in
            for (index, message) in messages.enumerated() {
                guard let file = message.contentFile else { continue }
                group.addTask {
                    let downloaded = try? await client.downloadFile(
                        fileId: file.id,
                        limit: 0,
                        offset: 0,
                        priority: 16,
                        synchronous: true,
                    )
                    return (index, downloaded)
                }
            }
            var files = [Int: File?]()
            for await (index, file) in group {
                files[index] = file
            }
            return files
        }
        return messages.enumerated().compactMap { index, message in
            guard message.contentFile != nil else { return message }
            guard let file = files[index] ?? nil, file.local.isDownloadingCompleted else { return nil }
            var message = message
            message.mediaFile = file
            return message
        }
    }

    private static func load(
        chatID: Int64,
        client: TDLibClient,
    ) async -> (messages: [TDNativeSponsoredMessage], messagesBetween: Int)? {
        do {
            let result = try await client.send(TDNativeRequests.getChatSponsoredMessages(chatId: chatID))
            #if DEBUG
                log("Sponsored messages: \(result.messages.count), \(result.messagesBetween) between")
            #endif
            return (result.messages, result.messagesBetween)
        } catch {
            #if DEBUG
                log("Sponsored messages: \(error)")
            #endif
            return nil
        }
    }

    func message(id: Int64) -> ChatSponsoredMessage? {
        state.messages.first { $0.id == id }
    }

    /// ChatController's `adMessagesContext?.activate()` when the chat first appears. TDLib asks the content to be
    /// fully downloaded before the ad shows, so an ad whose media can't be downloaded is left out.
    func activate() {
        guard !isActivated, isCurrent else { return }
        isActivated = true
        let client = client
        let chatID = chatID
        loadTask = Task { [weak self] in
            var sponsored: (messages: [TDNativeSponsoredMessage], messagesBetween: Int)
            #if DEBUG
                if Self.probesFakeAds {
                    sponsored = await Self.probeFakeAds(chatID: chatID, client: client)
                } else {
                    guard let loaded = await Self.load(chatID: chatID, client: client) else { return }
                    sponsored = loaded
                }
            #else
                guard let loaded = await Self.load(chatID: chatID, client: client) else { return }
                sponsored = loaded
            #endif
            guard !Task.isCancelled else { return }
            let messages = await Self.downloadingContent(
                of: sponsored.messages.map { ChatSponsoredMessage(chatID: chatID, message: $0) },
                client: client,
            )
            guard !messages.isEmpty, !Task.isCancelled else { return }
            let latestMessageID = await (try? client.getChat(chatId: chatID))?.lastMessage?.id ?? 0
            let isPremium = await (try? client.getMe())?.isPremium ?? false
            guard !Task.isCancelled, let self, isCurrent else { return }
            state = State(
                messages: messages,
                messagesBetween: max(0, sponsored.messagesBetween),
                latestMessageID: latestMessageID,
                isPremium: isPremium,
            )
            onUpdate?()
        }
    }

    /// AdMessagesHistoryContext.markAsSeen: `viewMessages` with the ad's identifier from the chat's history, once per
    /// ad while the chat shows.
    func markAsSeen(_ id: Int64) {
        guard isCurrent, message(id: id) != nil, seenIDs.insert(id).inserted else { return }
        #if DEBUG
            if Self.probesFakeAds {
                log("Fake ads probe: viewed \(id)")
                return
            }
        #endif
        let client = client
        let chatID = chatID
        Task {
            _ = try? await client.send(TDNativeRequests.viewMessages(
                chatId: chatID,
                messageIds: [id],
                source: .messageSourceChatHistory,
                forceRead: false,
            ))
        }
    }

    /// AdMessagesHistoryContext.markAction: the ad's button, body, media or a link in it was opened.
    func markAction(_ id: Int64, isMediaClick: Bool, fromFullscreen: Bool) {
        guard isCurrent, message(id: id) != nil else { return }
        #if DEBUG
            if Self.probesFakeAds {
                log("Fake ads probe: clicked \(id), media \(isMediaClick), full screen \(fromFullscreen)")
                return
            }
        #endif
        let client = client
        let chatID = chatID
        Task {
            _ = try? await client.send(TDNativeRequests.clickChatSponsoredMessage(
                chatId: chatID,
                messageId: id,
                isMediaClick: isMediaClick,
                fromFullscreen: fromFullscreen,
            ))
        }
    }

    /// AdMessagesHistoryContext.remove: a reported ad, or ads the user hid, leave the chat.
    func remove(_ id: Int64) {
        guard let index = state.messages.firstIndex(where: { $0.id == id }) else { return }
        state.messages.remove(at: index)
        onUpdate?()
    }

    /// `reportChatSponsoredMessage` with a chosen option; an empty one asks TDLib for the first options.
    func report(_ id: Int64, optionID: Data) async throws -> TDNativeReportSponsoredResult {
        #if DEBUG
            if Self.probesFakeAds { return Self.probeReport(optionID: optionID) }
        #endif
        return try await client.send(TDNativeRequests.reportChatSponsoredMessage(
            chatId: chatID,
            messageId: id,
            optionId: optionID,
        ))
    }
}

#if DEBUG
    fileprivate extension ChatSponsoredMessagesContext {
        /// `-ui-probe-fake-ads`: Telegram's `fakeAds` debug setting (ChatHistoryListNode), ten made-up ads with ten
        /// messages between them, for an account TDLib shows no ads to. The first can be reported and carries the
        /// sponsor's info and the channel's photo, the second plays the channel's latest video and links out of
        /// Telegram, the third is "Recommended", the fourth shows the channel's latest photo. Views, clicks and reports
        /// only log; the report pages are made up.
        static var probesFakeAds: Bool {
            ProcessInfo.processInfo.arguments.contains("-ui-probe-fake-ads")
        }

        static func probeFakeAds(
            chatID: Int64,
            client: TDLibClient,
        ) async -> (messages: [TDNativeSponsoredMessage], messagesBetween: Int) {
            let chat = try? await client.getChat(chatId: chatID)
            let channelPhoto = chat?.photo.map { photo in
                TDNativePhoto(
                    hasStickers: false,
                    minithumbnail: photo.minithumbnail,
                    sizes: [TDNativePhotoSize(
                        type: "c",
                        photo: photo.big,
                        width: 640,
                        height: 640,
                        progressiveSizes: [],
                    )],
                )
            }
            let latestPhoto = await probeLatestContent(
                chatID: chatID,
                filter: .searchMessagesFilterPhoto,
                client: client,
            )
            let latestVideo = await probeLatestContent(
                chatID: chatID,
                filter: .searchMessagesFilterVideo,
                client: client,
            )
            let messages = (0..<10).map { index in
                let text = "Fake Ad N\(index)"
                let content: TDNativeMessageContent =
                    if index == 3, case .messagePhoto(let photo) = latestPhoto {
                        .messagePhoto(TDNativeMessagePhoto(
                            photo: photo.photo,
                            video: nil,
                            caption: TDNativeFormattedText(text: text, entities: []),
                            showCaptionAboveMedia: false,
                            hasSpoiler: false,
                            isSecret: false,
                        ))
                    } else if index == 1, case .messageVideo(let video) = latestVideo {
                        .messageVideo(TDNativeMessageVideo(
                            video: video.video,
                            alternativeVideos: [],
                            storyboards: [],
                            cover: nil,
                            startTimestamp: 0,
                            caption: TDNativeFormattedText(text: text, entities: []),
                            showCaptionAboveMedia: false,
                            hasSpoiler: false,
                            isSecret: false,
                        ))
                    } else {
                        .messageText(TDNativeMessageText(
                            text: TDNativeFormattedText(text: text, entities: []),
                            linkPreview: nil,
                            linkPreviewOptions: nil,
                        ))
                    }
                return TDNativeSponsoredMessage(
                    messageId: Int64(index + 1),
                    isRecommended: index == 2,
                    canBeReported: index == 0,
                    content: content,
                    sponsor: TDNativeAdvertisementSponsor(
                        url: index == 1 || index == 3 ? "https://telegram.org" : "t.me/telegram",
                        photo: index == 0 ? channelPhoto : nil,
                        info: index == 0 ? "Fake sponsor info" : "",
                    ),
                    title: "Fake Ad",
                    buttonText: "VIEW",
                    accentColorId: index % 7,
                    backgroundCustomEmojiId: 0,
                    additionalInfo: index == 0 ? "Fake additional info" : "",
                )
            }
            return (messages, 10)
        }

        /// The content of the chat's latest message `filter` finds, for a made-up ad's media.
        private static func probeLatestContent(
            chatID: Int64,
            filter: TDNativeSearchMessagesFilter,
            client: TDLibClient,
        ) async -> TDNativeMessageContent? {
            let found = try? await client.searchChatMessages(
                chatId: chatID,
                filter: filter,
                fromMessageId: 0,
                limit: 1,
                offset: 0,
                query: "",
                senderId: nil,
                topicId: nil,
            )
            return found?.messages.first?.content
        }

        /// Made-up report pages: the first asks for a reason, "Fake reason with more" opens a second page, and any
        /// other reason is reported.
        static func probeReport(optionID: Data) -> TDNativeReportSponsoredResult {
            log("Fake ads probe: report \(String(decoding: optionID, as: UTF8.self))")
            func option(_ text: String) -> TDNativeReportOption {
                TDNativeReportOption(id: Data(text.utf8), text: text)
            }
            switch String(decoding: optionID, as: UTF8.self) {
            case "":
                return .reportSponsoredResultOptionRequired(TDNativeReportSponsoredResultOptionRequired(
                    title: "Fake reasons",
                    options: [option("Fake reason with more"), option("Fake reason")],
                ))
            case "Fake reason with more":
                return .reportSponsoredResultOptionRequired(TDNativeReportSponsoredResultOptionRequired(
                    title: "Fake second reasons",
                    options: [option("Fake second reason")],
                ))
            default:
                return .reportSponsoredResultOk
            }
        }
    }
#endif
