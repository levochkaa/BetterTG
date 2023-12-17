// ChatViewModel+Get.swift

import SwiftUI
import TDLibKit
import PhotosUI

extension ChatViewModel {
    func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        guard let customMessage else { return nil }
        return .inputMessageReplyToMessage(
            .init(
                chatId: 0,
                messageId: customMessage.message.id,
                quote: nil
            )
        )
    }
    
    func getReplyToMessage(_ replyTo: MessageReplyTo?) async -> Message? {
        if case .messageReplyToMessage(let messageReplyToMessage) = replyTo {
            return messageReplyToMessage.messageId != 0 ? await tdGetMessage(id: messageReplyToMessage.messageId) : nil
        }
        return nil
    }
    
    func getInputReplyToMessage(_ inputMessageReplyTo: InputMessageReplyTo?) async -> CustomMessage? {
        if case .inputMessageReplyToMessage(let message) = inputMessageReplyTo {
            return message.chatId == 0 ? await getCustomMessage(fromId: message.messageId) : nil
        }
        return nil
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = await tdGetMessage(id: id) else { return nil }
        return await getCustomMessage(from: message)
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(message.replyTo)
        var customMessage = CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: await getForwardedFrom(message.forwardInfo?.origin)
        )
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            customMessage.senderUser = await tdGetUser(id: messageSenderUser.userId)
        }
        
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            customMessage.replyUser = await tdGetUser(id: messageSenderUser.userId)
        }
        
        switch message.content {
            case .messageText(let messageText):
                customMessage.formattedText = messageText.text
            case .messagePhoto(let messagePhoto):
                if !messagePhoto.caption.text.isEmpty {
                    customMessage.formattedText = messagePhoto.caption
                }
            case .messageVoiceNote(let messageVoiceNote):
                if !messageVoiceNote.caption.text.isEmpty {
                    customMessage.formattedText = messageVoiceNote.caption
                }
            case .messageUnsupported:
                customMessage.formattedText = FormattedText(entities: [], text: "TDLib not supported")
            default:
                customMessage.formattedText = FormattedText(entities: [], text: "BTG not supported")
        }
        
        return customMessage
    }
    
    func getForwardedFrom(_ origin: MessageOrigin?) async -> String? {
        guard let origin else { return nil }
        
        switch origin {
            case .messageOriginChat(let chat):
                if let title = await tdGetChat(id: chat.senderChatId)?.title {
                    return !chat.authorSignature.isEmpty ? "\(title) (\(chat.authorSignature))" : title
                } else {
                    return !chat.authorSignature.isEmpty ? chat.authorSignature : nil
                }
            case .messageOriginChannel(let channel):
                if let title = await tdGetChat(id: channel.chatId)?.title {
                    return !channel.authorSignature.isEmpty ? "\(title) (\(channel.authorSignature))" : title
                } else {
                    return !channel.authorSignature.isEmpty ? channel.authorSignature : nil
                }
            case .messageOriginHiddenUser(let messageOriginHiddenUser):
                return messageOriginHiddenUser.senderName
            case .messageOriginUser(let messageOriginUser):
                return await tdGetUser(id: messageOriginUser.senderUserId)?.firstName
        }
    }
    
    func getFormattedText(from content: MessageContent) -> FormattedText? {
        switch content {
            case .messageText(let messageText):
                guard !messageText.text.text.isEmpty else { return nil }
                return messageText.text
            case .messagePhoto(let messagePhoto):
                guard !messagePhoto.caption.text.isEmpty else { return nil }
                return messagePhoto.caption
            case .messageVoiceNote(let messageVoiceNote):
                guard !messageVoiceNote.caption.text.isEmpty else { return nil }
                return messageVoiceNote.caption
            default:
                return nil
        }
    }
    
    func getEntities(from text: AttributedString) -> [TextEntity] {
        var entities = [TextEntity]()
        let attributedText = NSAttributedString(text)
        let textRange = NSRange(location: 0, length: text.string.count)
        attributedText.enumerateAttributes(in: textRange) { attributes, range, _ in
            for attribute in attributes {
                guard let entity = getEntity(from: attribute, using: range) else { continue }
                entities.append(entity)
            }
        }
        return entities
    }
    
    func getEntity(from attribute: (key: NSAttributedString.Key, value: Any), using range: NSRange) -> TextEntity? {
        switch attribute.key {
            case .font:
                guard let uiFont = attribute.value as? UIFont else { return nil }
                switch uiFont {
                    case UIFont.bold:
                        return .init(.textEntityTypeBold, range: range)
                    case UIFont.italic:
                        return .init(.textEntityTypeItalic, range: range)
                    case UIFont.monospaced:
                        return .init(.textEntityTypeCode, range: range)
                    default:
                        break
                }
            case .link:
                guard let url = attribute.value as? URL else { return nil }
                return .init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range)
            case .strikethroughStyle:
                return .init(.textEntityTypeStrikethrough, range: range)
            case .underlineStyle:
                return .init(.textEntityTypeUnderline, range: range)
            case .backgroundColor:
                return .init(.textEntityTypeSpoiler, range: range)
            default:
                return nil
        }
        return nil
    }
}
