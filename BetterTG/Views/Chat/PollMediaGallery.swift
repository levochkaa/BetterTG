// PollMediaGallery.swift

import TDLibKit
import UIKit

/// Telegram's standalone gallery of a poll's media (openPollMedia → openChatMessage with `standalone` and
/// GalleryMediaSubject's poll cases). An answer's photo or video pages through every answer's photo, video and GIF with
/// the answer as the caption (`galleryEntriesForMessageHistoryEntries` for `.pollOption`); the poll's own media and the
/// quiz explanation's open alone under the description or the explanation (`galleryMessageCaptionText`). The footer
/// shares and saves unless the message is protected, and has no delete (ChatItemGalleryFooterContentNode).
struct PollMediaGallery {
    // MARK: Internal

    /// Which of a poll's media a page shows (GalleryMediaSubject's poll cases).
    enum Subject: Equatable {
        case description
        case option(id: String)
        case solution
    }

    let pages: [Message]
    let selection: Int64

    // MARK: Private

    private let subjectsByPage: [Int64: Subject]
    private let message: Message

    init?(media: TDNativePollMedia, in message: Message) {
        guard case .messagePoll(let poll) = message.content, Self.content(media) != nil else { return nil }
        let subjects: [Subject]
        let selected: Subject
        if poll.media == media {
            subjects = [.description]
            selected = .description
        } else if let option = poll.poll.options.first(where: { $0.media == media }) {
            subjects = poll.poll.options.compactMap { option in
                option.media.flatMap(Self.content) == nil ? nil : .option(id: option.id)
            }
            selected = .option(id: option.id)
        } else {
            subjects = [.solution]
            selected = .solution
        }
        // Page ids stand apart from message ids, so each answer's media keeps its own page and playback.
        let subjectsByPage = Dictionary(uniqueKeysWithValues: subjects.enumerated().map { index, subject in
            (-Int64(index) - 1, subject)
        })
        let pages = subjects.indices.compactMap { index in
            Self.page(subjects[index], pageID: -Int64(index) - 1, in: message)
        }
        guard let selection = subjectsByPage.first(where: { $0.value == selected })?.key,
              pages.contains(where: { $0.id == selection })
        else { return nil }
        self.pages = pages
        self.selection = selection
        self.subjectsByPage = subjectsByPage
        self.message = message
    }

    /// GalleryController's `galleryEntriesForMessageHistoryEntries`: a poll's photo, video or GIF as gallery content.
    static func content(_ media: TDNativePollMedia) -> MessageContent? {
        let noCaption = FormattedText(entities: [], text: "")
        return switch media {
        case .pollMediaPhoto(let value):
            .messagePhoto(TDNativeMessagePhoto(
                photo: value.photo,
                video: value.video,
                caption: noCaption,
                showCaptionAboveMedia: false,
                hasSpoiler: false,
                isSecret: false,
            ))
        case .pollMediaVideo(let value):
            .messageVideo(TDNativeMessageVideo(
                video: value.video,
                alternativeVideos: value.alternativeVideos,
                storyboards: value.storyboards,
                cover: value.cover,
                startTimestamp: value.startTimestamp,
                caption: noCaption,
                showCaptionAboveMedia: false,
                hasSpoiler: false,
                isSecret: false,
            ))
        case .pollMediaAnimation(let value):
            .messageAnimation(TDNativeMessageAnimation(
                animation: value.animation,
                caption: noCaption,
                showCaptionAboveMedia: false,
                hasSpoiler: false,
                isSecret: false,
            ))
        default:
            nil
        }
    }

    /// A gallery page for one of the poll's media, read from `message`, with `galleryMessageCaptionText`'s caption:
    /// the answer, the explanation, or the poll's description for its own media.
    private static func page(_ subject: Subject, pageID: Int64, in message: Message) -> Message? {
        guard case .messagePoll(let content) = message.content else { return nil }
        let media: TDNativePollMedia?
        let caption: FormattedText
        switch subject {
        case .description:
            media = content.media
            caption = content.description
        case .option(let id):
            let option = content.poll.options.first { $0.id == id }
            media = option?.media
            caption = option?.text ?? FormattedText(entities: [], text: "")
        case .solution:
            guard case .pollTypeQuiz(let quiz) = content.poll.type else { return nil }
            media = quiz.explanationMedia
            caption = quiz.explanation
        }
        guard let pageContent = media.flatMap(Self.content) else { return nil }
        let captioned: MessageContent =
            switch pageContent {
            case .messagePhoto(let photo):
                .messagePhoto(TDNativeMessagePhoto(
                    photo: photo.photo,
                    video: photo.video,
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: false,
                    isSecret: false,
                ))
            case .messageVideo(let video):
                .messageVideo(TDNativeMessageVideo(
                    video: video.video,
                    alternativeVideos: video.alternativeVideos,
                    storyboards: video.storyboards,
                    cover: video.cover,
                    startTimestamp: video.startTimestamp,
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: false,
                    isSecret: false,
                ))
            case .messageAnimation(let animation):
                .messageAnimation(TDNativeMessageAnimation(
                    animation: animation.animation,
                    caption: caption,
                    showCaptionAboveMedia: false,
                    hasSpoiler: false,
                    isSecret: false,
                ))
            default:
                pageContent
            }
        return Message(
            id: pageID,
            senderId: message.senderId,
            receiverId: message.receiverId,
            chatId: message.chatId,
            sendingState: message.sendingState,
            schedulingState: message.schedulingState,
            isOutgoing: message.isOutgoing,
            isPinned: message.isPinned,
            isFromOffline: message.isFromOffline,
            canBeSaved: message.canBeSaved,
            hasTimestampedMedia: false,
            isChannelPost: message.isChannelPost,
            isPaidStarSuggestedPost: message.isPaidStarSuggestedPost,
            isPaidGramSuggestedPost: message.isPaidGramSuggestedPost,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            date: message.date,
            editDate: message.editDate,
            forwardInfo: message.forwardInfo,
            importInfo: message.importInfo,
            interactionInfo: nil,
            unreadReactions: [],
            factCheck: nil,
            suggestedPostInfo: nil,
            replyTo: nil,
            topicId: message.topicId,
            selfDestructType: nil,
            selfDestructIn: 0,
            autoDeleteIn: 0,
            viaBotUserId: message.viaBotUserId,
            guestBotCallerId: nil,
            senderBusinessBotUserId: message.senderBusinessBotUserId,
            senderBoostCount: message.senderBoostCount,
            senderTag: message.senderTag,
            paidMessageStarCount: 0,
            authorSignature: message.authorSignature,
            mediaAlbumId: 0,
            effectId: 0,
            restrictionInfo: nil,
            summaryLanguageCode: "",
            content: captioned,
            ephemeralContent: nil,
            replyMarkup: nil,
            ephemeralMessageId: 0,
            chatInstance: message.chatInstance,
        )
    }

    func embeddedSource(accountID: UUID, clientID: Int32) -> MediaGalleryEmbeddedMediaSource {
        let subjectsByPage = subjectsByPage
        return MediaGalleryEmbeddedMediaSource(
            accountID: accountID,
            chatID: message.chatId,
            clientID: clientID,
            containerMessageID: message.id,
            resolvePage: { pageID, container in
                subjectsByPage[pageID].flatMap { Self.page($0, pageID: pageID, in: container) }
            },
        )
    }
}
