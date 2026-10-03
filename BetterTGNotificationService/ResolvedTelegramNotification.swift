// ResolvedTelegramNotification.swift

import Foundation

struct ResolvedTelegramNotification {
    let senderName: String
    let conversationTitle: String?
    let senderAvatarData: Data?
    let conversationAvatarData: Data?
    let preview: RichNotificationPreview
    let body: String?
    let canQuickReply: Bool
}
