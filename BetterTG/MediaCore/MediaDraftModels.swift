// MediaDraftModels.swift

import Foundation
import TDLibKit

// MARK: - MediaDraftDateTimeFormattingType

// Stable value snapshots for on-disk media drafts. Keep the original TDLibKit 1
// JSON field names and tagged unions so existing recordings survive the migration.
// Native TDLibKit 2 objects are reconstructed only at the request boundary.

enum MediaDraftDateTimeFormattingType: Codable, Equatable {
    case dateTimeFormattingTypeRelative
    case dateTimeFormattingTypeAbsolute(MediaDraftDateTimeFormattingTypeAbsolute)

    private enum Kind: String, Codable {
        case dateTimeFormattingTypeRelative
        case dateTimeFormattingTypeAbsolute
    }

    var native: TDNativeDateTimeFormattingType {
        switch self {
        case .dateTimeFormattingTypeRelative:
            .dateTimeFormattingTypeRelative
        case .dateTimeFormattingTypeAbsolute(let value):
            .dateTimeFormattingTypeAbsolute(value.native)
        }
    }

    init(_ value: TDNativeDateTimeFormattingType) {
        self =
            switch value {
            case .dateTimeFormattingTypeRelative:
                .dateTimeFormattingTypeRelative
            case .dateTimeFormattingTypeAbsolute(let value):
                .dateTimeFormattingTypeAbsolute(MediaDraftDateTimeFormattingTypeAbsolute(value))
            }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MediaDraftTypeKey.self)
        self =
            switch try container.decode(Kind.self, forKey: .type) {
            case .dateTimeFormattingTypeRelative:
                .dateTimeFormattingTypeRelative
            case .dateTimeFormattingTypeAbsolute:
                try .dateTimeFormattingTypeAbsolute(MediaDraftDateTimeFormattingTypeAbsolute(from: decoder))
            }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MediaDraftTypeKey.self)
        switch self {
        case .dateTimeFormattingTypeRelative:
            try container.encode(Kind.dateTimeFormattingTypeRelative, forKey: .type)
        case .dateTimeFormattingTypeAbsolute(let value):
            try container.encode(Kind.dateTimeFormattingTypeAbsolute, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}

// MARK: - MediaDraftDateTimeFormattingTypeAbsolute

struct MediaDraftDateTimeFormattingTypeAbsolute: Codable, Equatable {
    let datePrecision: MediaDraftDateTimePartPrecision
    let showDayOfWeek: Bool
    let timePrecision: MediaDraftDateTimePartPrecision

    var native: TDNativeDateTimeFormattingTypeAbsolute {
        TDNativeDateTimeFormattingTypeAbsolute(
            timePrecision: timePrecision.native,
            datePrecision: datePrecision.native,
            showDayOfWeek: showDayOfWeek,
        )
    }

    init(_ value: TDNativeDateTimeFormattingTypeAbsolute) {
        self.datePrecision = MediaDraftDateTimePartPrecision(value.datePrecision)
        self.showDayOfWeek = value.showDayOfWeek
        self.timePrecision = MediaDraftDateTimePartPrecision(value.timePrecision)
    }
}

// MARK: - MediaDraftDateTimePartPrecision

enum MediaDraftDateTimePartPrecision: Codable, Equatable {
    case dateTimePartPrecisionNone
    case dateTimePartPrecisionShort
    case dateTimePartPrecisionLong

    private enum Kind: String, Codable {
        case dateTimePartPrecisionNone
        case dateTimePartPrecisionShort
        case dateTimePartPrecisionLong
    }

    var native: TDNativeDateTimePartPrecision {
        switch self {
        case .dateTimePartPrecisionNone:
            .dateTimePartPrecisionNone
        case .dateTimePartPrecisionShort:
            .dateTimePartPrecisionShort
        case .dateTimePartPrecisionLong:
            .dateTimePartPrecisionLong
        }
    }

    init(_ value: TDNativeDateTimePartPrecision) {
        self =
            switch value {
            case .dateTimePartPrecisionNone:
                .dateTimePartPrecisionNone
            case .dateTimePartPrecisionShort:
                .dateTimePartPrecisionShort
            case .dateTimePartPrecisionLong:
                .dateTimePartPrecisionLong
            }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MediaDraftTypeKey.self)
        self =
            switch try container.decode(Kind.self, forKey: .type) {
            case .dateTimePartPrecisionNone:
                .dateTimePartPrecisionNone
            case .dateTimePartPrecisionShort:
                .dateTimePartPrecisionShort
            case .dateTimePartPrecisionLong:
                .dateTimePartPrecisionLong
            }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MediaDraftTypeKey.self)
        switch self {
        case .dateTimePartPrecisionNone:
            try container.encode(Kind.dateTimePartPrecisionNone, forKey: .type)
        case .dateTimePartPrecisionShort:
            try container.encode(Kind.dateTimePartPrecisionShort, forKey: .type)
        case .dateTimePartPrecisionLong:
            try container.encode(Kind.dateTimePartPrecisionLong, forKey: .type)
        }
    }
}

// MARK: - MediaDraftFormattedText

struct MediaDraftFormattedText: Codable, Equatable {
    let entities: [MediaDraftTextEntity]
    let text: String

    var native: TDNativeFormattedText {
        TDNativeFormattedText(
            text: text,
            entities: entities.map(\.native),
        )
    }

    init(_ value: TDNativeFormattedText) {
        self.entities = value.entities.map(MediaDraftTextEntity.init)
        self.text = value.text
    }
}

// MARK: - MediaDraftInputMessageReplyTo

enum MediaDraftInputMessageReplyTo: Codable, Equatable {
    case inputMessageReplyToMessage(MediaDraftInputMessageReplyToMessage)
    case inputMessageReplyToExternalMessage(MediaDraftInputMessageReplyToExternalMessage)
    case inputMessageReplyToStory(MediaDraftInputMessageReplyToStory)
    case inputMessageReplyToEphemeralMessage(MediaDraftInputMessageReplyToEphemeralMessage)

    private enum Kind: String, Codable {
        case inputMessageReplyToMessage
        case inputMessageReplyToExternalMessage
        case inputMessageReplyToStory
        case inputMessageReplyToEphemeralMessage
    }

    var native: TDNativeInputMessageReplyTo {
        switch self {
        case .inputMessageReplyToMessage(let value):
            .inputMessageReplyToMessage(value.native)
        case .inputMessageReplyToExternalMessage(let value):
            .inputMessageReplyToExternalMessage(value.native)
        case .inputMessageReplyToStory(let value):
            .inputMessageReplyToStory(value.native)
        case .inputMessageReplyToEphemeralMessage(let value):
            .inputMessageReplyToEphemeralMessage(value.native)
        }
    }

    init(_ value: TDNativeInputMessageReplyTo) {
        self =
            switch value {
            case .inputMessageReplyToMessage(let value):
                .inputMessageReplyToMessage(MediaDraftInputMessageReplyToMessage(value))
            case .inputMessageReplyToExternalMessage(let value):
                .inputMessageReplyToExternalMessage(MediaDraftInputMessageReplyToExternalMessage(value))
            case .inputMessageReplyToStory(let value):
                .inputMessageReplyToStory(MediaDraftInputMessageReplyToStory(value))
            case .inputMessageReplyToEphemeralMessage(let value):
                .inputMessageReplyToEphemeralMessage(MediaDraftInputMessageReplyToEphemeralMessage(value))
            }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MediaDraftTypeKey.self)
        self =
            switch try container.decode(Kind.self, forKey: .type) {
            case .inputMessageReplyToMessage:
                try .inputMessageReplyToMessage(MediaDraftInputMessageReplyToMessage(from: decoder))
            case .inputMessageReplyToExternalMessage:
                try .inputMessageReplyToExternalMessage(MediaDraftInputMessageReplyToExternalMessage(from: decoder))
            case .inputMessageReplyToStory:
                try .inputMessageReplyToStory(MediaDraftInputMessageReplyToStory(from: decoder))
            case .inputMessageReplyToEphemeralMessage:
                try .inputMessageReplyToEphemeralMessage(MediaDraftInputMessageReplyToEphemeralMessage(from: decoder))
            }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MediaDraftTypeKey.self)
        switch self {
        case .inputMessageReplyToMessage(let value):
            try container.encode(Kind.inputMessageReplyToMessage, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageReplyToExternalMessage(let value):
            try container.encode(Kind.inputMessageReplyToExternalMessage, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageReplyToStory(let value):
            try container.encode(Kind.inputMessageReplyToStory, forKey: .type)
            try value.encode(to: encoder)
        case .inputMessageReplyToEphemeralMessage(let value):
            try container.encode(Kind.inputMessageReplyToEphemeralMessage, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}

// MARK: - MediaDraftInputMessageReplyToEphemeralMessage

struct MediaDraftInputMessageReplyToEphemeralMessage: Codable, Equatable {
    let ephemeralMessageId: Int

    var native: TDNativeInputMessageReplyToEphemeralMessage {
        TDNativeInputMessageReplyToEphemeralMessage(
            ephemeralMessageId: ephemeralMessageId,
        )
    }

    init(_ value: TDNativeInputMessageReplyToEphemeralMessage) {
        self.ephemeralMessageId = value.ephemeralMessageId
    }
}

// MARK: - MediaDraftInputMessageReplyToExternalMessage

struct MediaDraftInputMessageReplyToExternalMessage: Codable, Equatable {
    let chatId: Int64
    let checklistTaskId: Int
    let messageId: Int64
    let pollOptionId: String
    let quote: MediaDraftInputTextQuote?

    var native: TDNativeInputMessageReplyToExternalMessage {
        TDNativeInputMessageReplyToExternalMessage(
            chatId: chatId,
            messageId: messageId,
            quote: quote?.native,
            checklistTaskId: checklistTaskId,
            pollOptionId: pollOptionId,
        )
    }

    init(_ value: TDNativeInputMessageReplyToExternalMessage) {
        self.chatId = value.chatId
        self.checklistTaskId = value.checklistTaskId
        self.messageId = value.messageId
        self.pollOptionId = value.pollOptionId
        self.quote = value.quote.map(MediaDraftInputTextQuote.init)
    }
}

// MARK: - MediaDraftInputMessageReplyToMessage

struct MediaDraftInputMessageReplyToMessage: Codable, Equatable {
    let checklistTaskId: Int
    let messageId: Int64
    let pollOptionId: String
    let quote: MediaDraftInputTextQuote?

    var native: TDNativeInputMessageReplyToMessage {
        TDNativeInputMessageReplyToMessage(
            messageId: messageId,
            quote: quote?.native,
            checklistTaskId: checklistTaskId,
            pollOptionId: pollOptionId,
        )
    }

    init(_ value: TDNativeInputMessageReplyToMessage) {
        self.checklistTaskId = value.checklistTaskId
        self.messageId = value.messageId
        self.pollOptionId = value.pollOptionId
        self.quote = value.quote.map(MediaDraftInputTextQuote.init)
    }
}

// MARK: - MediaDraftInputMessageReplyToStory

struct MediaDraftInputMessageReplyToStory: Codable, Equatable {
    let storyId: Int
    let storyPosterChatId: Int64

    var native: TDNativeInputMessageReplyToStory {
        TDNativeInputMessageReplyToStory(
            storyPosterChatId: storyPosterChatId,
            storyId: storyId,
        )
    }

    init(_ value: TDNativeInputMessageReplyToStory) {
        self.storyId = value.storyId
        self.storyPosterChatId = value.storyPosterChatId
    }
}

// MARK: - MediaDraftInputTextQuote

struct MediaDraftInputTextQuote: Codable, Equatable {
    let position: Int
    let text: MediaDraftFormattedText

    var native: TDNativeInputTextQuote {
        TDNativeInputTextQuote(
            text: text.native,
            position: position,
        )
    }

    init(_ value: TDNativeInputTextQuote) {
        self.position = value.position
        self.text = MediaDraftFormattedText(value.text)
    }
}

// MARK: - MediaDraftTextEntity

struct MediaDraftTextEntity: Codable, Equatable {
    let length: Int
    let offset: Int
    let type: MediaDraftTextEntityType

    var native: TDNativeTextEntity {
        TDNativeTextEntity(
            offset: offset,
            length: length,
            type: type.native,
        )
    }

    init(_ value: TDNativeTextEntity) {
        self.length = value.length
        self.offset = value.offset
        self.type = MediaDraftTextEntityType(value.type)
    }
}

// MARK: - MediaDraftTextEntityType

enum MediaDraftTextEntityType: Codable, Equatable {
    case textEntityTypeMention
    case textEntityTypeHashtag
    case textEntityTypeCashtag
    case textEntityTypeBotCommand
    case textEntityTypeUrl
    case textEntityTypeEmailAddress
    case textEntityTypePhoneNumber
    case textEntityTypeBankCardNumber
    case textEntityTypeBold
    case textEntityTypeItalic
    case textEntityTypeUnderline
    case textEntityTypeStrikethrough
    case textEntityTypeSpoiler
    case textEntityTypeCode
    case textEntityTypePre
    case textEntityTypePreCode(MediaDraftTextEntityTypePreCode)
    case textEntityTypeBlockQuote
    case textEntityTypeExpandableBlockQuote
    case textEntityTypeTextUrl(MediaDraftTextEntityTypeTextUrl)
    case textEntityTypeMentionName(MediaDraftTextEntityTypeMentionName)
    case textEntityTypeCustomEmoji(MediaDraftTextEntityTypeCustomEmoji)
    case textEntityTypeMediaTimestamp(MediaDraftTextEntityTypeMediaTimestamp)
    case textEntityTypeDateTime(MediaDraftTextEntityTypeDateTime)

    private enum Kind: String, Codable {
        case textEntityTypeMention
        case textEntityTypeHashtag
        case textEntityTypeCashtag
        case textEntityTypeBotCommand
        case textEntityTypeUrl
        case textEntityTypeEmailAddress
        case textEntityTypePhoneNumber
        case textEntityTypeBankCardNumber
        case textEntityTypeBold
        case textEntityTypeItalic
        case textEntityTypeUnderline
        case textEntityTypeStrikethrough
        case textEntityTypeSpoiler
        case textEntityTypeCode
        case textEntityTypePre
        case textEntityTypePreCode
        case textEntityTypeBlockQuote
        case textEntityTypeExpandableBlockQuote
        case textEntityTypeTextUrl
        case textEntityTypeMentionName
        case textEntityTypeCustomEmoji
        case textEntityTypeMediaTimestamp
        case textEntityTypeDateTime
    }

    var native: TDNativeTextEntityType {
        switch self {
        case .textEntityTypeMention:
            .textEntityTypeMention
        case .textEntityTypeHashtag:
            .textEntityTypeHashtag
        case .textEntityTypeCashtag:
            .textEntityTypeCashtag
        case .textEntityTypeBotCommand:
            .textEntityTypeBotCommand
        case .textEntityTypeUrl:
            .textEntityTypeUrl
        case .textEntityTypeEmailAddress:
            .textEntityTypeEmailAddress
        case .textEntityTypePhoneNumber:
            .textEntityTypePhoneNumber
        case .textEntityTypeBankCardNumber:
            .textEntityTypeBankCardNumber
        case .textEntityTypeBold:
            .textEntityTypeBold
        case .textEntityTypeItalic:
            .textEntityTypeItalic
        case .textEntityTypeUnderline:
            .textEntityTypeUnderline
        case .textEntityTypeStrikethrough:
            .textEntityTypeStrikethrough
        case .textEntityTypeSpoiler:
            .textEntityTypeSpoiler
        case .textEntityTypeCode:
            .textEntityTypeCode
        case .textEntityTypePre:
            .textEntityTypePre
        case .textEntityTypePreCode(let value):
            .textEntityTypePreCode(value.native)
        case .textEntityTypeBlockQuote:
            .textEntityTypeBlockQuote
        case .textEntityTypeExpandableBlockQuote:
            .textEntityTypeExpandableBlockQuote
        case .textEntityTypeTextUrl(let value):
            .textEntityTypeTextUrl(value.native)
        case .textEntityTypeMentionName(let value):
            .textEntityTypeMentionName(value.native)
        case .textEntityTypeCustomEmoji(let value):
            .textEntityTypeCustomEmoji(value.native)
        case .textEntityTypeMediaTimestamp(let value):
            .textEntityTypeMediaTimestamp(value.native)
        case .textEntityTypeDateTime(let value):
            .textEntityTypeDateTime(value.native)
        }
    }

    init(_ value: TDNativeTextEntityType) {
        self =
            switch value {
            case .textEntityTypeMention:
                .textEntityTypeMention
            case .textEntityTypeHashtag:
                .textEntityTypeHashtag
            case .textEntityTypeCashtag:
                .textEntityTypeCashtag
            case .textEntityTypeBotCommand:
                .textEntityTypeBotCommand
            case .textEntityTypeUrl:
                .textEntityTypeUrl
            case .textEntityTypeEmailAddress:
                .textEntityTypeEmailAddress
            case .textEntityTypePhoneNumber:
                .textEntityTypePhoneNumber
            case .textEntityTypeBankCardNumber:
                .textEntityTypeBankCardNumber
            case .textEntityTypeBold:
                .textEntityTypeBold
            case .textEntityTypeItalic:
                .textEntityTypeItalic
            case .textEntityTypeUnderline:
                .textEntityTypeUnderline
            case .textEntityTypeStrikethrough:
                .textEntityTypeStrikethrough
            case .textEntityTypeSpoiler:
                .textEntityTypeSpoiler
            case .textEntityTypeCode:
                .textEntityTypeCode
            case .textEntityTypePre:
                .textEntityTypePre
            case .textEntityTypePreCode(let value):
                .textEntityTypePreCode(MediaDraftTextEntityTypePreCode(value))
            case .textEntityTypeBlockQuote:
                .textEntityTypeBlockQuote
            case .textEntityTypeExpandableBlockQuote:
                .textEntityTypeExpandableBlockQuote
            case .textEntityTypeTextUrl(let value):
                .textEntityTypeTextUrl(MediaDraftTextEntityTypeTextUrl(value))
            case .textEntityTypeMentionName(let value):
                .textEntityTypeMentionName(MediaDraftTextEntityTypeMentionName(value))
            case .textEntityTypeCustomEmoji(let value):
                .textEntityTypeCustomEmoji(MediaDraftTextEntityTypeCustomEmoji(value))
            case .textEntityTypeMediaTimestamp(let value):
                .textEntityTypeMediaTimestamp(MediaDraftTextEntityTypeMediaTimestamp(value))
            case .textEntityTypeDateTime(let value):
                .textEntityTypeDateTime(MediaDraftTextEntityTypeDateTime(value))
            }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MediaDraftTypeKey.self)
        self =
            switch try container.decode(Kind.self, forKey: .type) {
            case .textEntityTypeMention:
                .textEntityTypeMention
            case .textEntityTypeHashtag:
                .textEntityTypeHashtag
            case .textEntityTypeCashtag:
                .textEntityTypeCashtag
            case .textEntityTypeBotCommand:
                .textEntityTypeBotCommand
            case .textEntityTypeUrl:
                .textEntityTypeUrl
            case .textEntityTypeEmailAddress:
                .textEntityTypeEmailAddress
            case .textEntityTypePhoneNumber:
                .textEntityTypePhoneNumber
            case .textEntityTypeBankCardNumber:
                .textEntityTypeBankCardNumber
            case .textEntityTypeBold:
                .textEntityTypeBold
            case .textEntityTypeItalic:
                .textEntityTypeItalic
            case .textEntityTypeUnderline:
                .textEntityTypeUnderline
            case .textEntityTypeStrikethrough:
                .textEntityTypeStrikethrough
            case .textEntityTypeSpoiler:
                .textEntityTypeSpoiler
            case .textEntityTypeCode:
                .textEntityTypeCode
            case .textEntityTypePre:
                .textEntityTypePre
            case .textEntityTypePreCode:
                try .textEntityTypePreCode(MediaDraftTextEntityTypePreCode(from: decoder))
            case .textEntityTypeBlockQuote:
                .textEntityTypeBlockQuote
            case .textEntityTypeExpandableBlockQuote:
                .textEntityTypeExpandableBlockQuote
            case .textEntityTypeTextUrl:
                try .textEntityTypeTextUrl(MediaDraftTextEntityTypeTextUrl(from: decoder))
            case .textEntityTypeMentionName:
                try .textEntityTypeMentionName(MediaDraftTextEntityTypeMentionName(from: decoder))
            case .textEntityTypeCustomEmoji:
                try .textEntityTypeCustomEmoji(MediaDraftTextEntityTypeCustomEmoji(from: decoder))
            case .textEntityTypeMediaTimestamp:
                try .textEntityTypeMediaTimestamp(MediaDraftTextEntityTypeMediaTimestamp(from: decoder))
            case .textEntityTypeDateTime:
                try .textEntityTypeDateTime(MediaDraftTextEntityTypeDateTime(from: decoder))
            }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MediaDraftTypeKey.self)
        switch self {
        case .textEntityTypeMention:
            try container.encode(Kind.textEntityTypeMention, forKey: .type)
        case .textEntityTypeHashtag:
            try container.encode(Kind.textEntityTypeHashtag, forKey: .type)
        case .textEntityTypeCashtag:
            try container.encode(Kind.textEntityTypeCashtag, forKey: .type)
        case .textEntityTypeBotCommand:
            try container.encode(Kind.textEntityTypeBotCommand, forKey: .type)
        case .textEntityTypeUrl:
            try container.encode(Kind.textEntityTypeUrl, forKey: .type)
        case .textEntityTypeEmailAddress:
            try container.encode(Kind.textEntityTypeEmailAddress, forKey: .type)
        case .textEntityTypePhoneNumber:
            try container.encode(Kind.textEntityTypePhoneNumber, forKey: .type)
        case .textEntityTypeBankCardNumber:
            try container.encode(Kind.textEntityTypeBankCardNumber, forKey: .type)
        case .textEntityTypeBold:
            try container.encode(Kind.textEntityTypeBold, forKey: .type)
        case .textEntityTypeItalic:
            try container.encode(Kind.textEntityTypeItalic, forKey: .type)
        case .textEntityTypeUnderline:
            try container.encode(Kind.textEntityTypeUnderline, forKey: .type)
        case .textEntityTypeStrikethrough:
            try container.encode(Kind.textEntityTypeStrikethrough, forKey: .type)
        case .textEntityTypeSpoiler:
            try container.encode(Kind.textEntityTypeSpoiler, forKey: .type)
        case .textEntityTypeCode:
            try container.encode(Kind.textEntityTypeCode, forKey: .type)
        case .textEntityTypePre:
            try container.encode(Kind.textEntityTypePre, forKey: .type)
        case .textEntityTypePreCode(let value):
            try container.encode(Kind.textEntityTypePreCode, forKey: .type)
            try value.encode(to: encoder)
        case .textEntityTypeBlockQuote:
            try container.encode(Kind.textEntityTypeBlockQuote, forKey: .type)
        case .textEntityTypeExpandableBlockQuote:
            try container.encode(Kind.textEntityTypeExpandableBlockQuote, forKey: .type)
        case .textEntityTypeTextUrl(let value):
            try container.encode(Kind.textEntityTypeTextUrl, forKey: .type)
            try value.encode(to: encoder)
        case .textEntityTypeMentionName(let value):
            try container.encode(Kind.textEntityTypeMentionName, forKey: .type)
            try value.encode(to: encoder)
        case .textEntityTypeCustomEmoji(let value):
            try container.encode(Kind.textEntityTypeCustomEmoji, forKey: .type)
            try value.encode(to: encoder)
        case .textEntityTypeMediaTimestamp(let value):
            try container.encode(Kind.textEntityTypeMediaTimestamp, forKey: .type)
            try value.encode(to: encoder)
        case .textEntityTypeDateTime(let value):
            try container.encode(Kind.textEntityTypeDateTime, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}

// MARK: - MediaDraftTextEntityTypeCustomEmoji

struct MediaDraftTextEntityTypeCustomEmoji: Codable, Equatable {
    let customEmojiId: MediaDraftInt64

    var native: TDNativeTextEntityTypeCustomEmoji {
        TDNativeTextEntityTypeCustomEmoji(
            customEmojiId: customEmojiId.rawValue,
        )
    }

    init(_ value: TDNativeTextEntityTypeCustomEmoji) {
        self.customEmojiId = MediaDraftInt64(value.customEmojiId)
    }
}

// MARK: - MediaDraftTextEntityTypeDateTime

struct MediaDraftTextEntityTypeDateTime: Codable, Equatable {
    let formattingType: MediaDraftDateTimeFormattingType?
    let unixTime: Int

    var native: TDNativeTextEntityTypeDateTime {
        TDNativeTextEntityTypeDateTime(
            unixTime: unixTime,
            formattingType: formattingType?.native,
        )
    }

    init(_ value: TDNativeTextEntityTypeDateTime) {
        self.formattingType = value.formattingType.map(MediaDraftDateTimeFormattingType.init)
        self.unixTime = value.unixTime
    }
}

// MARK: - MediaDraftTextEntityTypeMediaTimestamp

struct MediaDraftTextEntityTypeMediaTimestamp: Codable, Equatable {
    let mediaTimestamp: Int

    var native: TDNativeTextEntityTypeMediaTimestamp {
        TDNativeTextEntityTypeMediaTimestamp(
            mediaTimestamp: mediaTimestamp,
        )
    }

    init(_ value: TDNativeTextEntityTypeMediaTimestamp) {
        self.mediaTimestamp = value.mediaTimestamp
    }
}

// MARK: - MediaDraftTextEntityTypeMentionName

struct MediaDraftTextEntityTypeMentionName: Codable, Equatable {
    let userId: Int64

    var native: TDNativeTextEntityTypeMentionName {
        TDNativeTextEntityTypeMentionName(
            userId: userId,
        )
    }

    init(_ value: TDNativeTextEntityTypeMentionName) {
        self.userId = value.userId
    }
}

// MARK: - MediaDraftTextEntityTypePreCode

struct MediaDraftTextEntityTypePreCode: Codable, Equatable {
    let language: String

    var native: TDNativeTextEntityTypePreCode {
        TDNativeTextEntityTypePreCode(
            language: language,
        )
    }

    init(_ value: TDNativeTextEntityTypePreCode) {
        self.language = value.language
    }
}

// MARK: - MediaDraftTextEntityTypeTextUrl

struct MediaDraftTextEntityTypeTextUrl: Codable, Equatable {
    let url: String

    var native: TDNativeTextEntityTypeTextUrl {
        TDNativeTextEntityTypeTextUrl(
            url: url,
        )
    }

    init(_ value: TDNativeTextEntityTypeTextUrl) {
        self.url = value.url
    }
}

// MARK: - MediaDraftTypeKey

private enum MediaDraftTypeKey: String, CodingKey {
    case type = "@type"
}

// MARK: - MediaDraftInt64

struct MediaDraftInt64: Codable, Equatable {
    let rawValue: Int64

    init(_ rawValue: Int64) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Int64(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid media draft identifier")
        }
        self.rawValue = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(rawValue))
    }
}
