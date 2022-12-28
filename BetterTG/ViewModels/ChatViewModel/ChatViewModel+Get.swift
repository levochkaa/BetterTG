// ChatViewModel+Get.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = await tdGetMessage(id: id) else { return nil }
        let customMessage = await getCustomMessage(from: message)
        return customMessage
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(id: message.replyToMessageId)
        var customMessage = CustomMessage(message: message, replyToMessage: replyToMessage)
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            let senderUser = await tdGetUser(id: messageSenderUser.userId)
            customMessage.senderUser = senderUser
        }
        
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            let replyUser = await tdGetUser(id: messageSenderUser.userId)
            customMessage.replyUser = replyUser
            return customMessage
        }
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        return customMessage
    }
    
    func getReplyToMessage(id: Int64) async -> Message? {
        return id != 0 ? await tdGetMessage(id: id) : nil
    }
}
