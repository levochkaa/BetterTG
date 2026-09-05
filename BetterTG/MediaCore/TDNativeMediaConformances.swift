// TDNativeMediaConformances.swift

import Foundation
import TDLibKit

// MARK: - TDNativeFormattedText + @retroactive Codable, @retroactive Hashable

// Native model values retain the legacy archive format through value snapshots.
// Equality compares model contents rather than the identity of native handles.

extension TDNativeFormattedText: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftFormattedText(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftFormattedText(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftFormattedText(lhs) == MediaDraftFormattedText(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftFormattedText(self).hash(into: &hasher)
    }
}

// MARK: - TDNativeInputMessageReplyTo + @retroactive Codable, @retroactive Hashable

extension TDNativeInputMessageReplyTo: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftInputMessageReplyTo(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftInputMessageReplyTo(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftInputMessageReplyTo(lhs) == MediaDraftInputMessageReplyTo(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftInputMessageReplyTo(self).hash(into: &hasher)
    }
}

// MARK: - TDNativeMessageTopic + @retroactive Codable, @retroactive Hashable

extension TDNativeMessageTopic: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftMessageTopic(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftMessageTopic(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftMessageTopic(lhs) == MediaDraftMessageTopic(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftMessageTopic(self).hash(into: &hasher)
    }
}

// MARK: - TDNativeTextEntity + @retroactive Codable, @retroactive Hashable

extension TDNativeTextEntity: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftTextEntity(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftTextEntity(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftTextEntity(lhs) == MediaDraftTextEntity(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftTextEntity(self).hash(into: &hasher)
    }
}

// MARK: - TDNativeTextEntityType + @retroactive Codable, @retroactive Hashable

extension TDNativeTextEntityType: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftTextEntityType(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftTextEntityType(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftTextEntityType(lhs) == MediaDraftTextEntityType(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftTextEntityType(self).hash(into: &hasher)
    }
}

// MARK: - TDNativeInputTextQuote + @retroactive Codable, @retroactive Hashable

extension TDNativeInputTextQuote: @retroactive Codable, @retroactive Hashable {
    public init(from decoder: any Decoder) throws {
        self = try MediaDraftInputTextQuote(from: decoder).native
    }

    public func encode(to encoder: any Encoder) throws {
        try MediaDraftInputTextQuote(self).encode(to: encoder)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        MediaDraftInputTextQuote(lhs) == MediaDraftInputTextQuote(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        MediaDraftInputTextQuote(self).hash(into: &hasher)
    }
}
