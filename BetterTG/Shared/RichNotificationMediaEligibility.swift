// RichNotificationMediaEligibility.swift

import TDLibKitDynamic

/// Notification previews never inherit an in-app spoiler reveal. Full-message
/// admission is required: MessageContent alone omits the self-destruct envelope.
enum RichNotificationMediaEligibility {
    static func allows(_ message: Message) -> Bool {
        message.selfDestructType == nil && message.selfDestructIn <= 0 && allows(content: message.content)
    }

    static func allows(content: MessageContent) -> Bool {
        switch content {
        case .messagePhoto(let value): !value.isSecret && !value.hasSpoiler
        case .messageVideo(let value): !value.isSecret && !value.hasSpoiler
        case .messageAnimation(let value): !value.isSecret && !value.hasSpoiler
        case .messageVideoNote(let value): !value.isSecret
        case .messageDocument, .messageSticker: true
        default: false
        }
    }
}
