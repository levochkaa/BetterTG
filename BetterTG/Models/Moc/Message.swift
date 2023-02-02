// Message.swift

import SwiftUI
import TDLibKit

extension Message {
    static let moc = Message(
        authorSignature: "",
        canBeDeletedForAllUsers: false,
        canBeDeletedOnlyForSelf: false,
        canBeEdited: false,
        canBeForwarded: false,
        canBeSaved: false,
        canGetAddedReactions: false,
        canGetMediaTimestampLinks: false,
        canGetMessageThread: false,
        canGetStatistics: false,
        canGetViewers: false,
        canReportReactions: false,
        chatId: 0,
        containsUnreadMention: false,
        content: .messageText(.init(text: .init(entities: [], text: "lastMessage"), webPage: nil)),
        date: 0,
        editDate: 0,
        forwardInfo: nil,
        hasTimestampedMedia: false,
        id: 0,
        interactionInfo: nil,
        isChannelPost: false,
        isOutgoing: false,
        isPinned: false,
        isTopicMessage: false,
        mediaAlbumId: 0,
        messageThreadId: 0,
        replyInChatId: 0,
        replyMarkup: nil,
        replyToMessageId: 0,
        restrictionReason: "",
        schedulingState: nil,
        senderId: .messageSenderUser(.init(userId: 0)),
        sendingState: nil,
        ttl: 0,
        ttlExpiresIn: 0,
        unreadReactions: [],
        viaBotUserId: 0
    )
}
