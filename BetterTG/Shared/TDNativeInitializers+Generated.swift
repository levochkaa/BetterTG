// TDNativeInitializers+Generated.swift

import TDLibKit

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

extension TDNativeDeviceTokenWebPush {
    init(authBase64url: String, endpoint: String, p256dhBase64url: String) {
        self.init(endpoint: endpoint, p256dhBase64url: p256dhBase64url, authBase64url: authBase64url)
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

extension TDNativeFormattedText {
    init(entities: [TDNativeTextEntity], text: String) {
        self.init(text: text, entities: entities)
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

extension TDNativeInputMessageReplyToMessage {
    init(checklistTaskId: Int, messageId: Int64, pollOptionId: String, quote: TDNativeInputTextQuote?) {
        self.init(messageId: messageId, quote: quote, checklistTaskId: checklistTaskId, pollOptionId: pollOptionId)
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

extension TDNativeInputThumbnail {
    init(height: Int, thumbnail: TDNativeInputFile, width: Int) {
        self.init(thumbnail: thumbnail, width: width, height: height)
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
            hasProtectedContentByCurrentUser: hasProtectedContentByCurrentUser,
            hasProtectedContentByOtherUser: hasProtectedContentByOtherUser,
            needShowStatistics: needShowStatistics,
        )
    }
}
