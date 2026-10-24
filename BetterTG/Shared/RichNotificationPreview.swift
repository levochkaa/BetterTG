// RichNotificationPreview.swift

import Foundation
import TDLibKit

// MARK: - RichNotificationPreview

/// Missing evidence is not permission, and an explicit denial never falls back
/// to an older attachment. Cached evidence is added separately by the v2 store.
enum RichNotificationPreview: Equatable {
    case denied
    case unresolved
    case allowed(Data?)

    var attachmentData: Data? {
        if case .allowed(let data) = self { return data }
        return nil
    }

    func bodyOverride(_ body: String?) -> String? {
        if case .allowed = self { return body }
        return nil
    }
}

// MARK: - RichNotificationPreviewPolicy

enum RichNotificationPreviewPolicy {
    /// Mutated only inside the session lifetime lock. Single-notification updates
    /// omit chat IDs, so they need a previously observed exact group's identity.
    struct Observation {
        private var groups = Set<Int>()

        mutating func revokes(_ update: Update, target: RichNotificationTarget) -> Bool {
            if case .updateNotificationGroup(let value) = update,
               value.addedNotifications.contains(where: {
                   target.matches(notification: $0, groupChatID: value.chatId)
               })
            {
                groups.insert(value.notificationGroupId)
            }
            if case .updateNotification(let value) = update {
                return groups.contains(value.notificationGroupId)
                    && target.matches(notification: value.notification, groupChatID: target.expectedChatID ?? 0)
                    && denies(value.notification.type)
            }
            return RichNotificationPreviewPolicy.revokes(update, target: target)
        }
    }

    enum Selection {
        case denied
        case unresolved
        case nonMedia
        case message(Message)

        func preview(data: Data?) -> RichNotificationPreview {
            switch self {
            case .denied: .denied
            case .nonMedia,
                 .unresolved: .unresolved
            case .message: .allowed(data)
            }
        }
    }

    /// Media concealment and caption entities are separate. Keep the original
    /// APNs body when its replacement would expose spoiler text; this does not
    /// revoke permission to attach an otherwise eligible image.
    static func captionedBody(icon: String, caption: FormattedText, fallback: String) -> String? {
        guard !caption.entities.contains(where: {
            if case .textEntityTypeSpoiler = $0.type { return true }
            return false
        }) else { return nil }
        return "\(icon) \(caption.text.isEmpty ? fallback : caption.text)"
    }

    /// Called inside the session lifetime's publication lock. Inspect the whole
    /// exact batch before admitting its resolver; a later allowed entry cannot
    /// erase a denial. Unrelated chats/messages cannot revoke this request.
    static func revokes(_ update: Update, target: RichNotificationTarget) -> Bool {
        switch update {
        case .updateNotificationGroup(let value):
            value.addedNotifications.contains {
                target.matches(notification: $0, groupChatID: value.chatId) && denies($0.type)
            }
        case .updateMessageContent(let value):
            value.chatId == target.expectedChatID && value.messageId == target.messageID
        case .updateMessageEdited(let value):
            value.chatId == target.expectedChatID && value.messageId == target.messageID
        case .updateDeleteMessages(let value):
            value.chatId == target.expectedChatID && value.messageIds.contains(target.messageID)
        default:
            false
        }
    }

    static func denies(_ type: NotificationType) -> Bool {
        switch type {
        case .notificationTypeNewMessage(let value):
            !value.showPreview || concealed(value.message)
        case .notificationTypeNewPushMessage(let value):
            switch value.content {
            case .pushMessageContentHidden: true
            case .pushMessageContentPhoto(let photo): photo.isSecret
            case .pushMessageContentVideo(let video): video.isSecret
            default: false
            }
        default: false
        }
    }

    /// A push thumbnail omits spoiler/self-destruct evidence. Only an exact full
    /// Message can authorize its media or a generated caption/body override.
    static func select(
        notification: TDNativeNotification,
        target: RichNotificationTarget,
        chatID: Int64,
        isCurrent: () -> Bool,
        fetch: () async -> Message?,
    ) async -> Selection {
        guard isCurrent(), target.matches(notification: notification, groupChatID: chatID) else {
            return .unresolved
        }
        guard !denies(notification.type) else { return .denied }
        let message: Message
        switch notification.type {
        case .notificationTypeNewMessage(let value):
            message = value.message
        case .notificationTypeNewPushMessage(let value):
            guard isMedia(value.content) else { return .nonMedia }
            guard let fetched = await fetch(), isCurrent(), target.matches(message: fetched, chatID: chatID) else {
                return .unresolved
            }
            message = fetched
        default:
            return .unresolved
        }
        guard !concealed(message) else { return .denied }
        return RichNotificationMediaEligibility.allows(message) ? .message(message) : .nonMedia
    }

    private static func concealed(_ message: Message) -> Bool {
        if message.selfDestructType != nil || message.selfDestructIn > 0 { return true }
        switch message.content {
        case .messagePhoto(let value): return value.isSecret || value.hasSpoiler
        case .messageVideo(let value): return value.isSecret || value.hasSpoiler
        case .messageAnimation(let value): return value.isSecret || value.hasSpoiler
        case .messageVideoNote(let value): return value.isSecret
        default: return false
        }
    }

    private static func isMedia(_ content: PushMessageContent) -> Bool {
        switch content {
        case .pushMessageContentAnimation,
             .pushMessageContentDocument,
             .pushMessageContentPhoto,
             .pushMessageContentSticker,
             .pushMessageContentVideo,
             .pushMessageContentVideoNote:
            true
        default: false
        }
    }
}
