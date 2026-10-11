// TDNativeValueConformances.swift

import TDLibKit

// MARK: - TDNativeAlternativeVideo + @retroactive Hashable

// Compare immutable native model contents used by media, profile and reaction UI.

extension TDNativeAlternativeVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.codec == rhs.codec
            && lhs.hlsFile == rhs.hlsFile
            && lhs.video == rhs.video
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(codec)
        hasher.combine(hlsFile)
        hasher.combine(video)
    }
}

// MARK: - TDNativeAnimatedChatPhoto + @retroactive Hashable

extension TDNativeAnimatedChatPhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.length == rhs.length
            && lhs.file == rhs.file
            && lhs.mainFrameTimestamp == rhs.mainFrameTimestamp
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
        hasher.combine(file)
        hasher.combine(mainFrameTimestamp)
    }
}

// MARK: - TDNativeAnimation + @retroactive Hashable

extension TDNativeAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.duration == rhs.duration
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.fileName == rhs.fileName
            && lhs.mimeType == rhs.mimeType
            && lhs.hasStickers == rhs.hasStickers
            && lhs.minithumbnail == rhs.minithumbnail
            && lhs.thumbnail == rhs.thumbnail
            && lhs.animation == rhs.animation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(fileName)
        hasher.combine(mimeType)
        hasher.combine(hasStickers)
        hasher.combine(minithumbnail)
        hasher.combine(thumbnail)
        hasher.combine(animation)
    }
}

// MARK: - TDNativeChatPhotoInfo + @retroactive Hashable

extension TDNativeChatPhotoInfo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.small == rhs.small
            && lhs.big == rhs.big
            && lhs.minithumbnail == rhs.minithumbnail
            && lhs.hasAnimation == rhs.hasAnimation
            && lhs.isPersonal == rhs.isPersonal
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(small)
        hasher.combine(big)
        hasher.combine(minithumbnail)
        hasher.combine(hasAnimation)
        hasher.combine(isPersonal)
    }
}

// MARK: - TDNativeMaskPosition + @retroactive Hashable

extension TDNativeMaskPosition: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.point == rhs.point
            && lhs.xShift == rhs.xShift
            && lhs.yShift == rhs.yShift
            && lhs.scale == rhs.scale
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(point)
        hasher.combine(xShift)
        hasher.combine(yShift)
        hasher.combine(scale)
    }
}

// MARK: - TDNativeMessageAnimation + @retroactive Hashable

extension TDNativeMessageAnimation: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.animation == rhs.animation
            && lhs.caption == rhs.caption
            && lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia
            && lhs.hasSpoiler == rhs.hasSpoiler
            && lhs.isSecret == rhs.isSecret
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(animation)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(hasSpoiler)
        hasher.combine(isSecret)
    }
}

// MARK: - TDNativeMessagePhoto + @retroactive Hashable

extension TDNativeMessagePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.photo == rhs.photo
            && lhs.video == rhs.video
            && lhs.caption == rhs.caption
            && lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia
            && lhs.hasSpoiler == rhs.hasSpoiler
            && lhs.isSecret == rhs.isSecret
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(photo)
        hasher.combine(video)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(hasSpoiler)
        hasher.combine(isSecret)
    }
}

// MARK: - TDNativeMessageReaction + @retroactive Hashable

extension TDNativeMessageReaction: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type
            && lhs.totalCount == rhs.totalCount
            && lhs.isChosen == rhs.isChosen
            && lhs.usedSenderId == rhs.usedSenderId
            && lhs.recentSenderIds == rhs.recentSenderIds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(totalCount)
        hasher.combine(isChosen)
        hasher.combine(usedSenderId)
        hasher.combine(recentSenderIds)
    }
}

// MARK: - TDNativeMessageReactions + @retroactive Hashable

extension TDNativeMessageReactions: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reactions == rhs.reactions
            && lhs.areTags == rhs.areTags
            && lhs.paidReactors == rhs.paidReactors
            && lhs.canGetAddedReactions == rhs.canGetAddedReactions
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(reactions)
        hasher.combine(areTags)
        hasher.combine(paidReactors)
        hasher.combine(canGetAddedReactions)
    }
}

// MARK: - TDNativeMessageSender + @retroactive Hashable

extension TDNativeMessageSender: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.messageSenderUser(let lhs), .messageSenderUser(let rhs)):
            lhs == rhs
        case (.messageSenderChat(let lhs), .messageSenderChat(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeID)
        switch self {
        case .messageSenderUser(let value):
            hasher.combine(value)
        case .messageSenderChat(let value):
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeMessageSenderChat + @retroactive Hashable

extension TDNativeMessageSenderChat: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chatId == rhs.chatId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(chatId)
    }
}

// MARK: - TDNativeMessageSenderUser + @retroactive Hashable

extension TDNativeMessageSenderUser: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.userId == rhs.userId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
    }
}

// MARK: - TDNativeMessageSticker + @retroactive Hashable

extension TDNativeMessageSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sticker == rhs.sticker
            && lhs.isPremium == rhs.isPremium
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(sticker)
        hasher.combine(isPremium)
    }
}

// MARK: - TDNativeMessageVideo + @retroactive Hashable

extension TDNativeMessageVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.video == rhs.video
            && lhs.alternativeVideos == rhs.alternativeVideos
            && lhs.storyboards == rhs.storyboards
            && lhs.cover == rhs.cover
            && lhs.startTimestamp == rhs.startTimestamp
            && lhs.caption == rhs.caption
            && lhs.showCaptionAboveMedia == rhs.showCaptionAboveMedia
            && lhs.hasSpoiler == rhs.hasSpoiler
            && lhs.isSecret == rhs.isSecret
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(alternativeVideos)
        hasher.combine(storyboards)
        hasher.combine(cover)
        hasher.combine(startTimestamp)
        hasher.combine(caption)
        hasher.combine(showCaptionAboveMedia)
        hasher.combine(hasSpoiler)
        hasher.combine(isSecret)
    }
}

// MARK: - TDNativeMinithumbnail + @retroactive Hashable

extension TDNativeMinithumbnail: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.data == rhs.data
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(data)
    }
}

// MARK: - TDNativePaidReactor + @retroactive Hashable

extension TDNativePaidReactor: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.senderId == rhs.senderId
            && lhs.starCount == rhs.starCount
            && lhs.isTop == rhs.isTop
            && lhs.isMe == rhs.isMe
            && lhs.isAnonymous == rhs.isAnonymous
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(senderId)
        hasher.combine(starCount)
        hasher.combine(isTop)
        hasher.combine(isMe)
        hasher.combine(isAnonymous)
    }
}

// MARK: - TDNativePhoto + @retroactive Hashable

extension TDNativePhoto: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasStickers == rhs.hasStickers
            && lhs.minithumbnail == rhs.minithumbnail
            && lhs.sizes == rhs.sizes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hasStickers)
        hasher.combine(minithumbnail)
        hasher.combine(sizes)
    }
}

// MARK: - TDNativePhotoSize + @retroactive Hashable

extension TDNativePhotoSize: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type
            && lhs.photo == rhs.photo
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.progressiveSizes == rhs.progressiveSizes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(photo)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(progressiveSizes)
    }
}

// MARK: - TDNativeReactionType + @retroactive Hashable

extension TDNativeReactionType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.reactionTypeEmoji(let lhs), .reactionTypeEmoji(let rhs)):
            lhs == rhs
        case (.reactionTypeCustomEmoji(let lhs), .reactionTypeCustomEmoji(let rhs)):
            lhs == rhs
        case (.reactionTypePaid, .reactionTypePaid):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeID)
        switch self {
        case .reactionTypeEmoji(let value):
            hasher.combine(value)
        case .reactionTypeCustomEmoji(let value):
            hasher.combine(value)
        case .reactionTypePaid:
            break
        }
    }
}

// MARK: - TDNativeReactionTypeCustomEmoji + @retroactive Hashable

extension TDNativeReactionTypeCustomEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.customEmojiId == rhs.customEmojiId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
    }
}

// MARK: - TDNativeReactionTypeEmoji + @retroactive Hashable

extension TDNativeReactionTypeEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.emoji == rhs.emoji
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(emoji)
    }
}

// MARK: - TDNativeSticker + @retroactive Hashable

extension TDNativeSticker: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.setId == rhs.setId
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.emoji == rhs.emoji
            && lhs.format == rhs.format
            && lhs.fullType == rhs.fullType
            && lhs.thumbnail == rhs.thumbnail
            && lhs.sticker == rhs.sticker
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(setId)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(emoji)
        hasher.combine(format)
        hasher.combine(fullType)
        hasher.combine(thumbnail)
        hasher.combine(sticker)
    }
}

// MARK: - TDNativeStickerFullType + @retroactive Hashable

extension TDNativeStickerFullType: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.stickerFullTypeRegular(let lhs), .stickerFullTypeRegular(let rhs)):
            lhs == rhs
        case (.stickerFullTypeMask(let lhs), .stickerFullTypeMask(let rhs)):
            lhs == rhs
        case (.stickerFullTypeCustomEmoji(let lhs), .stickerFullTypeCustomEmoji(let rhs)):
            lhs == rhs
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeID)
        switch self {
        case .stickerFullTypeRegular(let value):
            hasher.combine(value)
        case .stickerFullTypeMask(let value):
            hasher.combine(value)
        case .stickerFullTypeCustomEmoji(let value):
            hasher.combine(value)
        }
    }
}

// MARK: - TDNativeStickerFullTypeCustomEmoji + @retroactive Hashable

extension TDNativeStickerFullTypeCustomEmoji: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.customEmojiId == rhs.customEmojiId
            && lhs.needsRepainting == rhs.needsRepainting
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(customEmojiId)
        hasher.combine(needsRepainting)
    }
}

// MARK: - TDNativeStickerFullTypeMask + @retroactive Hashable

extension TDNativeStickerFullTypeMask: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.maskPosition == rhs.maskPosition
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(maskPosition)
    }
}

// MARK: - TDNativeStickerFullTypeRegular + @retroactive Hashable

extension TDNativeStickerFullTypeRegular: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.premiumAnimation == rhs.premiumAnimation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(premiumAnimation)
    }
}

// MARK: - TDNativeThumbnail + @retroactive Hashable

extension TDNativeThumbnail: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.format == rhs.format
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.file == rhs.file
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(format)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(file)
    }
}

// MARK: - TDNativeVideo + @retroactive Hashable

extension TDNativeVideo: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.duration == rhs.duration
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.fileName == rhs.fileName
            && lhs.mimeType == rhs.mimeType
            && lhs.hasStickers == rhs.hasStickers
            && lhs.supportsStreaming == rhs.supportsStreaming
            && lhs.minithumbnail == rhs.minithumbnail
            && lhs.thumbnail == rhs.thumbnail
            && lhs.video == rhs.video
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(duration)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(fileName)
        hasher.combine(mimeType)
        hasher.combine(hasStickers)
        hasher.combine(supportsStreaming)
        hasher.combine(minithumbnail)
        hasher.combine(thumbnail)
        hasher.combine(video)
    }
}

// MARK: - TDNativeVideoStoryboard + @retroactive Hashable

extension TDNativeVideoStoryboard: @retroactive Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storyboardFile == rhs.storyboardFile
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.mapFile == rhs.mapFile
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storyboardFile)
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(mapFile)
    }
}
