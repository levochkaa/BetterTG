// TDNativeInitializers+Generated.swift

import Foundation
import TDLibKit

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

extension TDNativeChatPosition {
    init(isPinned: Bool, list: TDNativeChatList, order: Int64, source: TDNativeChatSource?) {
        self.init(list: list, order: order, isPinned: isPinned, source: source)
    }
}

extension TDNativeChecklist {
    init(
        canAddTasks: Bool,
        canMarkTasksAsDone: Bool,
        othersCanAddTasks: Bool,
        othersCanMarkTasksAsDone: Bool,
        tasks: [TDNativeChecklistTask],
        title: TDNativeFormattedText,
    ) {
        self.init(
            title: title,
            tasks: tasks,
            othersCanAddTasks: othersCanAddTasks,
            canAddTasks: canAddTasks,
            othersCanMarkTasksAsDone: othersCanMarkTasksAsDone,
            canMarkTasksAsDone: canMarkTasksAsDone,
        )
    }
}

extension TDNativeChecklistTask {
    init(completedBy: TDNativeMessageSender?, completionDate: Int, id: Int, text: TDNativeFormattedText) {
        self.init(id: id, text: text, completedBy: completedBy, completionDate: completionDate)
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

extension TDNativeGame {
    init(
        animation: TDNativeAnimation?,
        description: String,
        id: Int64,
        photo: TDNativePhoto,
        shortName: String,
        text: TDNativeFormattedText,
        title: String,
    ) {
        self.init(
            id: id,
            shortName: shortName,
            title: title,
            text: text,
            description: description,
            photo: photo,
            animation: animation,
        )
    }
}

extension TDNativeImportedContact {
    init(firstName: String, lastName: String, note: TDNativeFormattedText, phoneNumber: String) {
        self.init(phoneNumber: phoneNumber, firstName: firstName, lastName: lastName, note: note)
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

extension TDNativeInputMessageDice {
    init(clearDraft: Bool, emoji: String) {
        self.init(emoji: emoji, clearDraft: clearDraft)
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

extension TDNativeInputVideoNote {
    init(duration: Int, length: Int, thumbnail: TDNativeInputThumbnail?, videoNote: TDNativeInputFile) {
        self.init(videoNote: videoNote, thumbnail: thumbnail, duration: duration, length: length)
    }
}

extension TDNativeLiveLocation {
    init(heading: Int, livePeriod: Int, location: TDNativeLocation, proximityAlertRadius: Int) {
        self.init(
            location: location,
            livePeriod: livePeriod,
            heading: heading,
            proximityAlertRadius: proximityAlertRadius,
        )
    }
}

extension TDNativeLocalFile {
    init(
        canBeDeleted: Bool,
        canBeDownloaded: Bool,
        downloadOffset: Int64,
        downloadedPrefixSize: Int64,
        downloadedSize: Int64,
        isDownloadingActive: Bool,
        isDownloadingCompleted: Bool,
        path: String,
    ) {
        self.init(
            path: path,
            canBeDownloaded: canBeDownloaded,
            canBeDeleted: canBeDeleted,
            isDownloadingActive: isDownloadingActive,
            isDownloadingCompleted: isDownloadingCompleted,
            downloadOffset: downloadOffset,
            downloadedPrefixSize: downloadedPrefixSize,
            downloadedSize: downloadedSize,
        )
    }
}

extension TDNativeLocation {
    init(horizontalAccuracy: Double, latitude: Double, longitude: Double) {
        self.init(latitude: latitude, longitude: longitude, horizontalAccuracy: horizontalAccuracy)
    }
}

extension TDNativeMessage {
    init(
        authorSignature: String,
        autoDeleteIn: Double,
        canBeSaved: Bool,
        chatId: Int64,
        containsUnreadMention: Bool,
        containsUnreadPollVotes: Bool,
        content: TDNativeMessageContent,
        date: Int,
        editDate: Int,
        effectId: Int64,
        ephemeralMessageId: Int,
        factCheck: TDNativeFactCheck?,
        forwardInfo: TDNativeMessageForwardInfo?,
        guestBotCallerId: TDNativeMessageSender?,
        hasTimestampedMedia: Bool,
        id: Int64,
        importInfo: TDNativeMessageImportInfo?,
        interactionInfo: TDNativeMessageInteractionInfo?,
        isChannelPost: Bool,
        isFromOffline: Bool,
        isOutgoing: Bool,
        isPaidGramSuggestedPost: Bool,
        isPaidStarSuggestedPost: Bool,
        isPinned: Bool,
        mediaAlbumId: Int64,
        paidMessageStarCount: Int64,
        receiverId: TDNativeMessageSender?,
        replyMarkup: TDNativeReplyMarkup?,
        replyTo: TDNativeMessageReplyTo?,
        restrictionInfo: TDNativeRestrictionInfo?,
        schedulingState: TDNativeMessageSchedulingState?,
        selfDestructIn: Double,
        selfDestructType: TDNativeMessageSelfDestructType?,
        senderBoostCount: Int,
        senderBusinessBotUserId: Int64,
        senderId: TDNativeMessageSender,
        senderTag: String,
        sendingState: TDNativeMessageSendingState?,
        suggestedPostInfo: TDNativeSuggestedPostInfo?,
        summaryLanguageCode: String,
        topicId: TDNativeMessageTopic?,
        unreadReactions: [TDNativeUnreadReaction],
        viaBotUserId: Int64,
        ephemeralContent: TDNativeEphemeralMessageContent?,
        chatInstance: Int64,
    ) {
        self.init(
            id: id,
            senderId: senderId,
            receiverId: receiverId,
            chatId: chatId,
            sendingState: sendingState,
            schedulingState: schedulingState,
            isOutgoing: isOutgoing,
            isPinned: isPinned,
            isFromOffline: isFromOffline,
            canBeSaved: canBeSaved,
            hasTimestampedMedia: hasTimestampedMedia,
            isChannelPost: isChannelPost,
            isPaidStarSuggestedPost: isPaidStarSuggestedPost,
            isPaidGramSuggestedPost: isPaidGramSuggestedPost,
            containsUnreadMention: containsUnreadMention,
            containsUnreadPollVotes: containsUnreadPollVotes,
            date: date,
            editDate: editDate,
            forwardInfo: forwardInfo,
            importInfo: importInfo,
            interactionInfo: interactionInfo,
            unreadReactions: unreadReactions,
            factCheck: factCheck,
            suggestedPostInfo: suggestedPostInfo,
            replyTo: replyTo,
            topicId: topicId,
            selfDestructType: selfDestructType,
            selfDestructIn: selfDestructIn,
            autoDeleteIn: autoDeleteIn,
            viaBotUserId: viaBotUserId,
            guestBotCallerId: guestBotCallerId,
            senderBusinessBotUserId: senderBusinessBotUserId,
            senderBoostCount: senderBoostCount,
            senderTag: senderTag,
            paidMessageStarCount: paidMessageStarCount,
            authorSignature: authorSignature,
            mediaAlbumId: mediaAlbumId,
            effectId: effectId,
            restrictionInfo: restrictionInfo,
            summaryLanguageCode: summaryLanguageCode,
            content: content,
            ephemeralContent: ephemeralContent,
            replyMarkup: replyMarkup,
            ephemeralMessageId: ephemeralMessageId,
            chatInstance: chatInstance,
        )
    }
}

extension TDNativeMessageCall {
    init(discardReason: TDNativeCallDiscardReason, duration: Int, isVideo: Bool, uniqueId: Int64) {
        self.init(uniqueId: uniqueId, isVideo: isVideo, discardReason: discardReason, duration: duration)
    }
}

extension TDNativeMessageChatSetMessageAutoDeleteTime {
    init(fromUserId: Int64, messageAutoDeleteTime: Int) {
        self.init(messageAutoDeleteTime: messageAutoDeleteTime, fromUserId: fromUserId)
    }
}

extension TDNativeMessageDice {
    init(
        emoji: String,
        finalState: TDNativeDiceStickers?,
        initialState: TDNativeDiceStickers?,
        successAnimationFrameNumber: Int,
        value: Int,
    ) {
        self.init(
            initialState: initialState,
            finalState: finalState,
            emoji: emoji,
            value: value,
            successAnimationFrameNumber: successAnimationFrameNumber,
        )
    }
}

extension TDNativeMessageDocument {
    init(caption: TDNativeFormattedText, document: TDNativeDocument) {
        self.init(document: document, caption: caption)
    }
}

extension TDNativeMessageForwardInfo {
    init(
        date: Int,
        origin: TDNativeMessageOrigin,
        publicServiceAnnouncementType: String,
        source: TDNativeForwardSource?,
    ) {
        self.init(
            origin: origin,
            date: date,
            source: source,
            publicServiceAnnouncementType: publicServiceAnnouncementType,
        )
    }
}

extension TDNativeMessageGameScore {
    init(gameId: Int64, gameMessageId: Int64, score: Int) {
        self.init(gameMessageId: gameMessageId, gameId: gameId, score: score)
    }
}

extension TDNativeMessageGroupCall {
    init(
        duration: Int,
        isActive: Bool,
        isVideo: Bool,
        otherParticipantIds: [TDNativeMessageSender],
        uniqueId: Int64,
        wasMissed: Bool,
    ) {
        self.init(
            uniqueId: uniqueId,
            isActive: isActive,
            wasMissed: wasMissed,
            isVideo: isVideo,
            duration: duration,
            otherParticipantIds: otherParticipantIds,
        )
    }
}

extension TDNativeMessageInteractionInfo {
    init(
        forwardCount: Int,
        reactions: TDNativeMessageReactions?,
        replyInfo: TDNativeMessageReplyInfo?,
        viewCount: Int,
    ) {
        self.init(viewCount: viewCount, forwardCount: forwardCount, replyInfo: replyInfo, reactions: reactions)
    }
}

extension TDNativeMessageLiveLocation {
    init(expiresIn: Int, location: TDNativeLiveLocation) {
        self.init(location: location, expiresIn: expiresIn)
    }
}

extension TDNativeMessagePoll {
    init(canAddOption: Bool, description: TDNativeFormattedText, media: TDNativePollMedia?, poll: TDNativePoll) {
        self.init(poll: poll, description: description, media: media, canAddOption: canAddOption)
    }
}

extension TDNativeMessageProperties {
    init(
        canAddOffer: Bool,
        canAddTasks: Bool,
        canBeApproved: Bool,
        canBeCopied: Bool,
        canBeCopiedToSecretChat: Bool,
        canBeDeclined: Bool,
        canBeDeletedForAllUsers: Bool,
        canBeDeletedOnlyForSelf: Bool,
        canBeEdited: Bool,
        canBeForwarded: Bool,
        canBePaid: Bool,
        canBePinned: Bool,
        canBeReplied: Bool,
        canBeRepliedInAnotherChat: Bool,
        canBeSaved: Bool,
        canBeSharedInStory: Bool,
        canDeleteReactions: Bool,
        canEditMedia: Bool,
        canEditSchedulingState: Bool,
        canEditSuggestedPostInfo: Bool,
        canGetAuthor: Bool,
        canGetEmbeddingCode: Bool,
        canGetLink: Bool,
        canGetMediaTimestampLinks: Bool,
        canGetMessageThread: Bool,
        canGetPollVoteStatistics: Bool,
        canGetReadDate: Bool,
        canGetStatistics: Bool,
        canGetVideoAdvertisements: Bool,
        canGetViewers: Bool,
        canMarkTasksAsDone: Bool,
        canRecognizeSpeech: Bool,
        canReportChat: Bool,
        canReportReactions: Bool,
        canReportSupergroupSpam: Bool,
        canSetFactCheck: Bool,
        customEmojiIds: [Int64],
        hasProtectedContentByCurrentUser: Bool,
        hasProtectedContentByOtherUser: Bool,
        needShowStatistics: Bool,
    ) {
        self.init(
            canAddOffer: canAddOffer,
            canAddTasks: canAddTasks,
            canBeApproved: canBeApproved,
            canBeCopied: canBeCopied,
            canBeCopiedToSecretChat: canBeCopiedToSecretChat,
            canBeDeclined: canBeDeclined,
            canBeDeletedOnlyForSelf: canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: canBeDeletedForAllUsers,
            canBeEdited: canBeEdited,
            canBeForwarded: canBeForwarded,
            canBePaid: canBePaid,
            canBePinned: canBePinned,
            canBeReplied: canBeReplied,
            canBeRepliedInAnotherChat: canBeRepliedInAnotherChat,
            canBeSaved: canBeSaved,
            canBeSharedInStory: canBeSharedInStory,
            canDeleteReactions: canDeleteReactions,
            canEditMedia: canEditMedia,
            canEditSchedulingState: canEditSchedulingState,
            canEditSuggestedPostInfo: canEditSuggestedPostInfo,
            canGetAuthor: canGetAuthor,
            canGetEmbeddingCode: canGetEmbeddingCode,
            canGetLink: canGetLink,
            canGetMediaTimestampLinks: canGetMediaTimestampLinks,
            canGetMessageThread: canGetMessageThread,
            canGetPollVoteStatistics: canGetPollVoteStatistics,
            canGetReadDate: canGetReadDate,
            canGetStatistics: canGetStatistics,
            canGetVideoAdvertisements: canGetVideoAdvertisements,
            canGetViewers: canGetViewers,
            canMarkTasksAsDone: canMarkTasksAsDone,
            canRecognizeSpeech: canRecognizeSpeech,
            canReportChat: canReportChat,
            canReportReactions: canReportReactions,
            canReportSupergroupSpam: canReportSupergroupSpam,
            canSetFactCheck: canSetFactCheck,
            customEmojiIds: customEmojiIds,
            hasProtectedContentByCurrentUser: hasProtectedContentByCurrentUser,
            hasProtectedContentByOtherUser: hasProtectedContentByOtherUser,
            needShowStatistics: needShowStatistics,
        )
    }
}

extension TDNativeMessageProximityAlertTriggered {
    init(distance: Int, travelerId: TDNativeMessageSender, watcherId: TDNativeMessageSender) {
        self.init(travelerId: travelerId, watcherId: watcherId, distance: distance)
    }
}

extension TDNativeMessageReaction {
    init(
        isChosen: Bool,
        recentSenderIds: [TDNativeMessageSender],
        totalCount: Int,
        type: TDNativeReactionType,
        usedSenderId: TDNativeMessageSender?,
    ) {
        self.init(
            type: type,
            totalCount: totalCount,
            isChosen: isChosen,
            usedSenderId: usedSenderId,
            recentSenderIds: recentSenderIds,
        )
    }
}

extension TDNativeMessageReactions {
    init(
        areTags: Bool,
        canGetAddedReactions: Bool,
        paidReactors: [TDNativePaidReactor],
        reactions: [TDNativeMessageReaction],
    ) {
        self.init(
            reactions: reactions,
            areTags: areTags,
            paidReactors: paidReactors,
            canGetAddedReactions: canGetAddedReactions,
        )
    }
}

extension TDNativeMessageReplyInfo {
    init(
        lastMessageId: Int64,
        lastReadInboxMessageId: Int64,
        lastReadOutboxMessageId: Int64,
        recentReplierIds: [TDNativeMessageSender],
        replyCount: Int,
    ) {
        self.init(
            replyCount: replyCount,
            recentReplierIds: recentReplierIds,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            lastMessageId: lastMessageId,
        )
    }
}

extension TDNativeMessageReplyToMessage {
    init(
        chatId: Int64,
        checklistTaskId: Int,
        content: TDNativeMessageContent?,
        messageId: Int64,
        origin: TDNativeMessageOrigin?,
        originSendDate: Int,
        pollOptionId: String,
        quote: TDNativeTextQuote?,
    ) {
        self.init(
            chatId: chatId,
            messageId: messageId,
            quote: quote,
            checklistTaskId: checklistTaskId,
            pollOptionId: pollOptionId,
            origin: origin,
            originSendDate: originSendDate,
            content: content,
        )
    }
}

extension TDNativeMessageStory {
    init(storyId: Int, storyPosterChatId: Int64, viaMention: Bool) {
        self.init(storyPosterChatId: storyPosterChatId, storyId: storyId, viaMention: viaMention)
    }
}

extension TDNativeMessageText {
    init(
        linkPreview: TDNativeLinkPreview?,
        linkPreviewOptions: TDNativeLinkPreviewOptions?,
        text: TDNativeFormattedText,
    ) {
        self.init(text: text, linkPreview: linkPreview, linkPreviewOptions: linkPreviewOptions)
    }
}

extension TDNativeMessageThreadInfo {
    init(
        chatId: Int64,
        draftMessage: TDNativeDraftMessage?,
        messageThreadId: Int64,
        messages: [TDNativeMessage],
        replyInfo: TDNativeMessageReplyInfo?,
        unreadMessageCount: Int,
    ) {
        self.init(
            chatId: chatId,
            messageThreadId: messageThreadId,
            replyInfo: replyInfo,
            unreadMessageCount: unreadMessageCount,
            messages: messages,
            draftMessage: draftMessage,
        )
    }
}

extension TDNativeMinithumbnail {
    init(data: Data, height: Int, width: Int) {
        self.init(width: width, height: height, data: data)
    }
}

extension TDNativePhotoSize {
    init(height: Int, photo: TDNativeFile, progressiveSizes: [Int], type: String, width: Int) {
        self.init(type: type, photo: photo, width: width, height: height, progressiveSizes: progressiveSizes)
    }
}

extension TDNativePoll {
    init(
        allowsMultipleAnswers: Bool,
        allowsRevoting: Bool,
        canGetVoters: Bool,
        canSeeResults: Bool,
        closeDate: Int,
        countryCodes: [String],
        id: Int64,
        isAnonymous: Bool,
        isClosed: Bool,
        membersOnly: Bool,
        openPeriod: Int,
        optionOrder: [Int],
        options: [TDNativePollOption],
        question: TDNativeFormattedText,
        recentVoterIds: [TDNativeMessageSender],
        totalVoterCount: Int,
        type: TDNativePollType,
        voteRestrictionReason: TDNativePollVoteRestrictionReason?,
    ) {
        self.init(
            id: id,
            question: question,
            options: options,
            totalVoterCount: totalVoterCount,
            recentVoterIds: recentVoterIds,
            canGetVoters: canGetVoters,
            canSeeResults: canSeeResults,
            isAnonymous: isAnonymous,
            allowsMultipleAnswers: allowsMultipleAnswers,
            allowsRevoting: allowsRevoting,
            membersOnly: membersOnly,
            countryCodes: countryCodes,
            optionOrder: optionOrder,
            type: type,
            openPeriod: openPeriod,
            closeDate: closeDate,
            isClosed: isClosed,
            voteRestrictionReason: voteRestrictionReason,
        )
    }
}

extension TDNativePollOption {
    init(
        additionDate: Int,
        author: TDNativeMessageSender?,
        id: String,
        isBeingChosen: Bool,
        isChosen: Bool,
        media: TDNativePollMedia?,
        recentVoterIds: [TDNativeMessageSender],
        text: TDNativeFormattedText,
        votePercentage: Int,
        voterCount: Int,
    ) {
        self.init(
            id: id,
            text: text,
            media: media,
            voterCount: voterCount,
            votePercentage: votePercentage,
            recentVoterIds: recentVoterIds,
            isChosen: isChosen,
            isBeingChosen: isBeingChosen,
            author: author,
            additionDate: additionDate,
        )
    }
}

extension TDNativeRemoteFile {
    init(id: String, isUploadingActive: Bool, isUploadingCompleted: Bool, uniqueId: String, uploadedSize: Int64) {
        self.init(
            id: id,
            uniqueId: uniqueId,
            isUploadingActive: isUploadingActive,
            isUploadingCompleted: isUploadingCompleted,
            uploadedSize: uploadedSize,
        )
    }
}

extension TDNativeScopeNotificationSettings {
    init(
        disableMentionNotifications: Bool,
        disablePinnedMessageNotifications: Bool,
        muteFor: Int,
        muteStories: Bool,
        showPreview: Bool,
        showStoryPoster: Bool,
        soundId: Int64,
        storySoundId: Int64,
        useDefaultMuteStories: Bool,
    ) {
        self.init(
            muteFor: muteFor,
            soundId: soundId,
            showPreview: showPreview,
            useDefaultMuteStories: useDefaultMuteStories,
            muteStories: muteStories,
            storySoundId: storySoundId,
            showStoryPoster: showStoryPoster,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            disableMentionNotifications: disableMentionNotifications,
        )
    }
}

extension TDNativeTextEntity {
    init(length: Int, offset: Int, type: TDNativeTextEntityType) {
        self.init(offset: offset, length: length, type: type)
    }
}

extension TDNativeTextQuote {
    init(isManual: Bool, position: Int, text: TDNativeFormattedText) {
        self.init(text: text, position: position, isManual: isManual)
    }
}

extension TDNativeThumbnail {
    init(file: TDNativeFile, format: TDNativeThumbnailFormat, height: Int, width: Int) {
        self.init(format: format, width: width, height: height, file: file)
    }
}

extension TDNativeUnreadReaction {
    init(isBig: Bool, senderId: TDNativeMessageSender, type: TDNativeReactionType) {
        self.init(type: type, senderId: senderId, isBig: isBig)
    }
}

extension TDNativeUpdateDeleteMessages {
    init(chatId: Int64, fromCache: Bool, isPermanent: Bool, messageIds: [Int64]) {
        self.init(chatId: chatId, messageIds: messageIds, isPermanent: isPermanent, fromCache: fromCache)
    }
}

extension TDNativeUpdateForumTopic {
    init(
        chatId: Int64,
        draftMessage: TDNativeDraftMessage?,
        forumTopicId: Int,
        isPinned: Bool,
        lastReadInboxMessageId: Int64,
        lastReadOutboxMessageId: Int64,
        notificationSettings: TDNativeChatNotificationSettings,
        unreadMentionCount: Int,
        unreadPollVoteCount: Int,
        unreadReactionCount: Int,
    ) {
        self.init(
            chatId: chatId,
            forumTopicId: forumTopicId,
            isPinned: isPinned,
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

extension TDNativeUpdateMessageEdited {
    init(chatId: Int64, editDate: Int, messageId: Int64, replyMarkup: TDNativeReplyMarkup?) {
        self.init(chatId: chatId, messageId: messageId, editDate: editDate, replyMarkup: replyMarkup)
    }
}

extension TDNativeUpdateMessageSendFailed {
    init(error: TDNativeError, message: TDNativeMessage, oldMessageId: Int64) {
        self.init(message: message, oldMessageId: oldMessageId, error: error)
    }
}

extension TDNativeUser {
    init(
        accentColorId: Int,
        activeStoryState: TDNativeActiveStoryState?,
        addedToAttachmentMenu: Bool,
        backgroundCustomEmojiId: Int64,
        emojiStatus: TDNativeEmojiStatus?,
        firstName: String,
        haveAccess: Bool,
        id: Int64,
        isCloseFriend: Bool,
        isContact: Bool,
        isMutualContact: Bool,
        isPremium: Bool,
        isSupport: Bool,
        languageCode: String,
        lastName: String,
        paidMessageStarCount: Int64,
        phoneNumber: String,
        profileAccentColorId: Int,
        profileBackgroundCustomEmojiId: Int64,
        profilePhoto: TDNativeProfilePhoto?,
        restrictionInfo: TDNativeRestrictionInfo?,
        restrictsNewChats: Bool,
        status: TDNativeUserStatus,
        type: TDNativeUserType,
        upgradedGiftColors: TDNativeUpgradedGiftColors?,
        usernames: TDNativeUsernames?,
        verificationStatus: TDNativeVerificationStatus?,
    ) {
        self.init(
            id: id,
            firstName: firstName,
            lastName: lastName,
            usernames: usernames,
            phoneNumber: phoneNumber,
            status: status,
            profilePhoto: profilePhoto,
            accentColorId: accentColorId,
            backgroundCustomEmojiId: backgroundCustomEmojiId,
            upgradedGiftColors: upgradedGiftColors,
            profileAccentColorId: profileAccentColorId,
            profileBackgroundCustomEmojiId: profileBackgroundCustomEmojiId,
            emojiStatus: emojiStatus,
            isContact: isContact,
            isMutualContact: isMutualContact,
            isCloseFriend: isCloseFriend,
            verificationStatus: verificationStatus,
            isPremium: isPremium,
            isSupport: isSupport,
            restrictionInfo: restrictionInfo,
            activeStoryState: activeStoryState,
            restrictsNewChats: restrictsNewChats,
            paidMessageStarCount: paidMessageStarCount,
            haveAccess: haveAccess,
            type: type,
            languageCode: languageCode,
            addedToAttachmentMenu: addedToAttachmentMenu,
        )
    }
}
