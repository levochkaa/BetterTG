// +Chat.swift

import SwiftUI
import TDLibKit

extension Chat {
    static let moc = Chat(
        actionBar: nil,
        availableReactions: .chatAvailableReactionsAll,
        background: nil,
        canBeDeletedForAllUsers: false,
        canBeDeletedOnlyForSelf: false,
        canBeReported: false,
        clientData: "",
        defaultDisableNotification: false,
        draftMessage: nil,
        hasProtectedContent: false,
        hasScheduledMessages: false,
        id: 0,
        isBlocked: false,
        isMarkedAsUnread: false,
        isTranslatable: false,
        lastMessage: nil,
        lastReadInboxMessageId: 0,
        lastReadOutboxMessageId: 0,
        messageAutoDeleteTime: 0,
        messageSenderId: nil,
        notificationSettings: .moc,
        pendingJoinRequests: nil,
        permissions: .moc,
        photo: nil,
        positions: [],
        replyMarkupMessageId: 0,
        themeName: "",
        title: "titletitletitle",
        type: .chatTypePrivate(.init(userId: 0)),
        unreadCount: 0,
        unreadMentionCount: 0,
        unreadReactionCount: 0,
        videoChat: .init(defaultParticipantId: nil, groupCallId: 0, hasParticipants: false)
    )
}
