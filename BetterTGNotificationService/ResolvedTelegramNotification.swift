// ResolvedTelegramNotification.swift

import Foundation

struct ResolvedTelegramNotification {
    let senderName: String
    let conversationTitle: String?
    let senderAvatarData: Data?
    let conversationAvatarData: Data?
    let mediaData: Data?
    let canQuickReply: Bool
}
