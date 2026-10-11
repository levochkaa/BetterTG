// TDNativeInitializers+Generated.swift

import Foundation
import TDLibKit

extension TDNativeAnimatedEmoji {
    init(fitzpatrickType: Int, sound: TDNativeFile?, sticker: TDNativeSticker?, stickerHeight: Int, stickerWidth: Int) {
        self.init(
            sticker: sticker,
            stickerWidth: stickerWidth,
            stickerHeight: stickerHeight,
            fitzpatrickType: fitzpatrickType,
            sound: sound,
        )
    }
}

extension TDNativeAudio {
    init(
        albumCoverMinithumbnail: TDNativeMinithumbnail?,
        albumCoverThumbnail: TDNativeThumbnail?,
        audio: TDNativeFile,
        duration: Int,
        externalAlbumCovers: [TDNativeThumbnail],
        fileName: String,
        mimeType: String,
        performer: String,
        title: String,
    ) {
        self.init(
            duration: duration,
            title: title,
            performer: performer,
            fileName: fileName,
            mimeType: mimeType,
            albumCoverMinithumbnail: albumCoverMinithumbnail,
            albumCoverThumbnail: albumCoverThumbnail,
            externalAlbumCovers: externalAlbumCovers,
            audio: audio,
        )
    }
}

extension TDNativeChatFolder {
    init(
        colorId: Int,
        excludeArchived: Bool,
        excludeMuted: Bool,
        excludeRead: Bool,
        excludedChatIds: [Int64],
        icon: TDNativeChatFolderIcon?,
        includeBots: Bool,
        includeChannels: Bool,
        includeContacts: Bool,
        includeGroups: Bool,
        includeNonContacts: Bool,
        includedChatIds: [Int64],
        isShareable: Bool,
        name: TDNativeChatFolderName,
        pinnedChatIds: [Int64],
    ) {
        self.init(
            name: name,
            icon: icon,
            colorId: colorId,
            isShareable: isShareable,
            pinnedChatIds: pinnedChatIds,
            includedChatIds: includedChatIds,
            excludedChatIds: excludedChatIds,
            excludeMuted: excludeMuted,
            excludeRead: excludeRead,
            excludeArchived: excludeArchived,
            includeContacts: includeContacts,
            includeNonContacts: includeNonContacts,
            includeBots: includeBots,
            includeGroups: includeGroups,
            includeChannels: includeChannels,
        )
    }
}

extension TDNativeChatFolderInfo {
    init(
        colorId: Int,
        hasMyInviteLinks: Bool,
        icon: TDNativeChatFolderIcon,
        id: Int,
        isShareable: Bool,
        name: TDNativeChatFolderName,
    ) {
        self.init(
            id: id,
            name: name,
            icon: icon,
            colorId: colorId,
            isShareable: isShareable,
            hasMyInviteLinks: hasMyInviteLinks,
        )
    }
}

extension TDNativeChatFolderName {
    init(animateCustomEmoji: Bool, text: TDNativeFormattedText) {
        self.init(text: text, animateCustomEmoji: animateCustomEmoji)
    }
}

extension TDNativeChatNotificationSettings {
    init(
        disableMentionNotifications: Bool,
        disablePinnedMessageNotifications: Bool,
        muteFor: Int,
        muteStories: Bool,
        showPreview: Bool,
        showStoryPoster: Bool,
        soundId: Int64,
        storySoundId: Int64,
        useDefaultDisableMentionNotifications: Bool,
        useDefaultDisablePinnedMessageNotifications: Bool,
        useDefaultMuteFor: Bool,
        useDefaultMuteStories: Bool,
        useDefaultShowPreview: Bool,
        useDefaultShowStoryPoster: Bool,
        useDefaultSound: Bool,
        useDefaultStorySound: Bool,
    ) {
        self.init(
            useDefaultMuteFor: useDefaultMuteFor,
            muteFor: muteFor,
            useDefaultSound: useDefaultSound,
            soundId: soundId,
            useDefaultShowPreview: useDefaultShowPreview,
            showPreview: showPreview,
            useDefaultMuteStories: useDefaultMuteStories,
            muteStories: muteStories,
            useDefaultStorySound: useDefaultStorySound,
            storySoundId: storySoundId,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            showStoryPoster: showStoryPoster,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            disableMentionNotifications: disableMentionNotifications,
        )
    }
}

extension TDNativeChatPhotoInfo {
    init(
        big: TDNativeFile,
        hasAnimation: Bool,
        isPersonal: Bool,
        minithumbnail: TDNativeMinithumbnail?,
        small: TDNativeFile,
    ) {
        self.init(
            small: small,
            big: big,
            minithumbnail: minithumbnail,
            hasAnimation: hasAnimation,
            isPersonal: isPersonal,
        )
    }
}

extension TDNativeChatPosition {
    init(isPinned: Bool, list: TDNativeChatList, order: Int64, source: TDNativeChatSource?) {
        self.init(list: list, order: order, isPinned: isPinned, source: source)
    }
}

extension TDNativeContact {
    init(firstName: String, lastName: String, phoneNumber: String, userId: Int64, vcard: String) {
        self.init(phoneNumber: phoneNumber, firstName: firstName, lastName: lastName, vcard: vcard, userId: userId)
    }
}

extension TDNativeDeviceTokenWebPush {
    init(authBase64url: String, endpoint: String, p256dhBase64url: String) {
        self.init(endpoint: endpoint, p256dhBase64url: p256dhBase64url, authBase64url: authBase64url)
    }
}

extension TDNativeDocument {
    init(
        document: TDNativeFile,
        fileName: String,
        mimeType: String,
        minithumbnail: TDNativeMinithumbnail?,
        thumbnail: TDNativeThumbnail?,
    ) {
        self.init(
            fileName: fileName,
            mimeType: mimeType,
            minithumbnail: minithumbnail,
            thumbnail: thumbnail,
            document: document,
        )
    }
}

extension TDNativeDraftMessage {
    init(
        content: TDNativeDraftMessageContent,
        date: Int,
        effectId: Int64,
        replyTo: TDNativeInputMessageReplyTo?,
        suggestedPostInfo: TDNativeInputSuggestedPostInfo?,
    ) {
        self.init(
            replyTo: replyTo,
            date: date,
            content: content,
            effectId: effectId,
            suggestedPostInfo: suggestedPostInfo,
        )
    }
}

extension TDNativeDraftMessageContentText {
    init(linkPreviewOptions: TDNativeLinkPreviewOptions?, text: TDNativeFormattedText) {
        self.init(text: text, linkPreviewOptions: linkPreviewOptions)
    }
}

extension TDNativeFile {
    init(expectedSize: Int64, id: Int, local: TDNativeLocalFile, remote: TDNativeRemoteFile, size: Int64) {
        self.init(id: id, size: size, expectedSize: expectedSize, local: local, remote: remote)
    }
}

extension TDNativeFormattedText {
    init(entities: [TDNativeTextEntity], text: String) {
        self.init(text: text, entities: entities)
    }
}

extension TDNativeForumTopic {
    init(
        draftMessage: TDNativeDraftMessage?,
        info: TDNativeForumTopicInfo,
        isPinned: Bool,
        lastMessage: TDNativeMessage?,
        lastReadInboxMessageId: Int64,
        lastReadOutboxMessageId: Int64,
        notificationSettings: TDNativeChatNotificationSettings,
        order: Int64,
        unreadCount: Int,
        unreadMentionCount: Int,
        unreadPollVoteCount: Int,
        unreadReactionCount: Int,
    ) {
        self.init(
            info: info,
            lastMessage: lastMessage,
            order: order,
            isPinned: isPinned,
            unreadCount: unreadCount,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            unreadMentionCount: unreadMentionCount,
            unreadReactionCount: unreadReactionCount,
            unreadPollVoteCount: unreadPollVoteCount,
            notificationSettings: notificationSettings,
            draftMessage: draftMessage,
        )
    }
}

extension TDNativeForumTopicInfo {
    init(
        chatId: Int64,
        creationDate: Int,
        creatorId: TDNativeMessageSender,
        forumTopicId: Int,
        icon: TDNativeForumTopicIcon,
        isClosed: Bool,
        isGeneral: Bool,
        isHidden: Bool,
        isNameImplicit: Bool,
        isOutgoing: Bool,
        name: String,
    ) {
        self.init(
            chatId: chatId,
            forumTopicId: forumTopicId,
            name: name,
            icon: icon,
            creationDate: creationDate,
            creatorId: creatorId,
            isGeneral: isGeneral,
            isOutgoing: isOutgoing,
            isClosed: isClosed,
            isHidden: isHidden,
            isNameImplicit: isNameImplicit,
        )
    }
}

extension TDNativeForumTopics {
    init(
        nextOffsetDate: Int,
        nextOffsetForumTopicId: Int,
        nextOffsetMessageId: Int64,
        topics: [TDNativeForumTopic],
        totalCount: Int,
    ) {
        self.init(
            totalCount: totalCount,
            topics: topics,
            nextOffsetDate: nextOffsetDate,
            nextOffsetMessageId: nextOffsetMessageId,
            nextOffsetForumTopicId: nextOffsetForumTopicId,
        )
    }
}

extension TDNativeForwardSource {
    init(
        chatId: Int64,
        date: Int,
        isOutgoing: Bool,
        messageId: Int64,
        senderId: TDNativeMessageSender?,
        senderName: String,
    ) {
        self.init(
            chatId: chatId,
            messageId: messageId,
            senderId: senderId,
            senderName: senderName,
            date: date,
            isOutgoing: isOutgoing,
        )
    }
}

extension TDNativeInputAnimation {
    init(
        addedStickerFileIds: [Int],
        animation: TDNativeInputFile,
        duration: Int,
        height: Int,
        thumbnail: TDNativeInputThumbnail?,
        width: Int,
    ) {
        self.init(
            animation: animation,
            thumbnail: thumbnail,
            addedStickerFileIds: addedStickerFileIds,
            duration: duration,
            width: width,
            height: height,
        )
    }
}

extension TDNativeInputDocument {
    init(disableContentTypeDetection: Bool, document: TDNativeInputFile, thumbnail: TDNativeInputThumbnail?) {
        self.init(document: document, thumbnail: thumbnail, disableContentTypeDetection: disableContentTypeDetection)
    }
}

extension TDNativeInputMessageAnimation {
    init(
        animation: TDNativeInputAnimation,
        caption: TDNativeFormattedText?,
        hasSpoiler: Bool,
        showCaptionAboveMedia: Bool,
    ) {
        self.init(
            animation: animation,
            caption: caption,
            showCaptionAboveMedia: showCaptionAboveMedia,
            hasSpoiler: hasSpoiler,
        )
    }
}

extension TDNativeInputMessageDocument {
    init(caption: TDNativeFormattedText?, document: TDNativeInputDocument) {
        self.init(document: document, caption: caption)
    }
}

extension TDNativeInputMessagePhoto {
    init(
        caption: TDNativeFormattedText?,
        hasSpoiler: Bool,
        photo: TDNativeInputPhoto,
        selfDestructType: TDNativeMessageSelfDestructType?,
        showCaptionAboveMedia: Bool,
    ) {
        self.init(
            photo: photo,
            caption: caption,
            showCaptionAboveMedia: showCaptionAboveMedia,
            selfDestructType: selfDestructType,
            hasSpoiler: hasSpoiler,
        )
    }
}

extension TDNativeInputMessageReplyToExternalMessage {
    init(chatId: Int64, checklistTaskId: Int, messageId: Int64, pollOptionId: String, quote: TDNativeInputTextQuote?) {
        self.init(
            chatId: chatId,
            messageId: messageId,
            quote: quote,
            checklistTaskId: checklistTaskId,
            pollOptionId: pollOptionId,
        )
    }
}

extension TDNativeInputMessageReplyToMessage {
    init(checklistTaskId: Int, messageId: Int64, pollOptionId: String, quote: TDNativeInputTextQuote?) {
        self.init(messageId: messageId, quote: quote, checklistTaskId: checklistTaskId, pollOptionId: pollOptionId)
    }
}

extension TDNativeInputMessageSticker {
    init(emoji: String, sticker: TDNativeInputSticker) {
        self.init(sticker: sticker, emoji: emoji)
    }
}

extension TDNativeInputMessageText {
    init(clearDraft: Bool, linkPreviewOptions: TDNativeLinkPreviewOptions?, text: TDNativeFormattedText) {
        self.init(text: text, linkPreviewOptions: linkPreviewOptions, clearDraft: clearDraft)
    }
}

extension TDNativeInputPhoto {
    init(
        addedStickerFileIds: [Int],
        height: Int,
        photo: TDNativeInputFile,
        thumbnail: TDNativeInputThumbnail?,
        video: TDNativeInputFile?,
        width: Int,
    ) {
        self.init(
            photo: photo,
            thumbnail: thumbnail,
            video: video,
            addedStickerFileIds: addedStickerFileIds,
            width: width,
            height: height,
        )
    }
}

extension TDNativeInputSticker {
    init(height: Int, sticker: TDNativeInputFile, thumbnail: TDNativeInputThumbnail?, width: Int) {
        self.init(sticker: sticker, thumbnail: thumbnail, width: width, height: height)
    }
}

extension TDNativeInputTextQuote {
    init(position: Int, text: TDNativeFormattedText) {
        self.init(text: text, position: position)
    }
}

extension TDNativeInputThumbnail {
    init(height: Int, thumbnail: TDNativeInputFile, width: Int) {
        self.init(thumbnail: thumbnail, width: width, height: height)
    }
}
