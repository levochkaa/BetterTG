// ChatViewModel+Get.swift

import SwiftUI
import TDLibKit
import Lottie
import Gzip

extension ChatViewModel {
    func getReplyToMessage(id: Int64) async -> Message? {
        return id != 0 ? await tdGetMessage(id: id) : nil
    }
    
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
        }
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        customMessage.customEmojiAnimations = await getCustomEmojiAnimations(from: customMessage.message.content)
        
        return customMessage
    }
    
    func getCustomEmojiAnimations(from content: MessageContent) async -> [CustomEmojiAnimation] {
        switch content {
            case .messageText(let messageText):
                return await getCustomEmojiAnimations(from: messageText.text.entities)
            case .messagePhoto(let messagePhoto):
                return await getCustomEmojiAnimations(from: messagePhoto.caption.entities)
            case .messageVoiceNote(let messageVoiceNote):
                return await getCustomEmojiAnimations(from: messageVoiceNote.caption.entities)
            default:
                return []
        }
    }
    
    func getCustomEmojiAnimations(from entities: [TextEntity]) async -> [CustomEmojiAnimation] {
        var customEmojiAnimations = [CustomEmojiAnimation]()
        
        for entity in entities {
            if case .textEntityTypeCustomEmoji(let textEntityTypeCustomEmoji) = entity.type,
               let animoji = await tdGetCustomEmojiSticker(id: textEntityTypeCustomEmoji.customEmojiId),
               case .stickerTypeCustomEmoji = animoji.type,
               case .stickerFormatTgs = animoji.format,
               let file = await tdDownloadFile(id: animoji.sticker.id) {
                do {
                    let url = URL(filePath: file.local.path)
                    let data = try Data(contentsOf: url)
                    let decompressed = try data.gunzipped()
                    let animation = try LottieAnimation.from(data: decompressed)
                    let customEmojiAnimation = CustomEmojiAnimation(
                        lottieAnimation: animation,
                        realEmoji: animoji.emoji
                    )
                    customEmojiAnimations.append(customEmojiAnimation)
                } catch {
                    logger.log("Error loading custom emoji animation: \(error)")
                }
            }
        }
        
        return customEmojiAnimations
    }
}
