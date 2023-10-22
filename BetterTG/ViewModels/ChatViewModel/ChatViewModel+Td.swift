// ChatViewModel+Td.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func tdGetChat(id: Int64) async -> Chat? {
        do {
            return try await td.getChat(chatId: id)
        } catch {
            log("Error getting chat: \(error)")
            return nil
        }
    }
    
    func tdDeleteMessages(ids: [Int64], deleteForBoth: Bool) async {
        guard let customChat else { return }
        do {
            try await td.deleteMessages(chatId: customChat.chat.id, messageIds: ids, revoke: deleteForBoth)
        } catch {
            log("Error deleting messages: \(error)")
        }
    }
    
    func tdGetMessage(id: Int64) async -> Message? {
        guard let customChat else { return nil }
        do {
            return try await td.getMessage(chatId: customChat.chat.id, messageId: id)
        } catch {
            log("Error getting message: \(error)")
            return nil
        }
    }
    
    func tdGetUser(id: Int64) async -> User? {
        do {
            return try await td.getUser(userId: id)
        } catch {
            log("Error getting user: \(error)")
            return nil
        }
    }
    
    func tdEditMessageText(_ editMessage: Message) async {
        guard let customChat else { return }
        do {
            _ = try await td.editMessageText(
                chatId: customChat.chat.id,
                inputMessageContent:
                        .inputMessageText(
                            .init(
                                clearDraft: true,
                                disableWebPagePreview: true,
                                text: FormattedText(
                                    entities: getEntities(from: editMessageText),
                                    text: editMessageText.string
                                )
                            )
                        ),
                messageId: editMessage.id,
                replyMarkup: nil
            )
        } catch {
            log("Error editing messageText: \(error)")
        }
    }
    
    func tdGetCustomEmojiSticker(id: TdInt64) async -> Sticker? {
        return await tdGetCustomEmojiStickers(ids: [id])?.first
    }
    
    func tdGetCustomEmojiStickers(ids: [TdInt64]) async -> [Sticker]? {
        do {
            return try await td.getCustomEmojiStickers(customEmojiIds: ids).stickers
        } catch {
            log("Error getting customEmojiStickers: \(error)")
            return nil
        }
    }
    
    func tdDownloadFile(id: Int, synchronous: Bool, priority: Int = 4) async -> File? {
        do {
            return try await td.downloadFile(
                fileId: id,
                limit: 0,
                offset: 0,
                priority: priority,
                synchronous: synchronous
            )
        } catch {
            log("Error downloading file: \(error)")
            return nil
        }
    }
    
    func tdEditMessageCaption(_ editMessage: Message) async {
        guard let customChat else { return }
        do {
            _ = try await td.editMessageCaption(
                caption: FormattedText(
                    entities: getEntities(from: editMessageText),
                    text: editMessageText.string
                ),
                chatId: customChat.chat.id,
                messageId: editMessage.id,
                replyMarkup: nil
            )
        } catch {
            log("Error editing messageCaption: \(error)")
        }
    }
    
    func tdSetChatDraftMessage(_ draftMessage: DraftMessage) async {
        guard let customChat else { return }
        do {
            try await td.setChatDraftMessage(
                chatId: customChat.chat.id,
                draftMessage: draftMessage,
                messageThreadId: 0
            )
        } catch {
            log("Error setting draftMessage: \(error)")
        }
    }
    
    func tdSendMessage(with inputMessageContent: InputMessageContent) async {
        guard let customChat else { return }
        do {
            _ = try await td.sendMessage(
                chatId: customChat.chat.id,
                inputMessageContent: inputMessageContent,
                messageThreadId: 0,
                options: nil,
                replyMarkup: nil,
                replyTo: getMessageReplyTo(from: replyMessage)
            )
        } catch {
            await tdSendChatAction(.chatActionCancel)
            log("Error sending message: \(error)")
        }
    }
    
    func tdSendMessageAlbum(with inputMessageContents: [InputMessageContent]) async {
        guard let customChat else { return }
        do {
            _ = try await td.sendMessageAlbum(
                chatId: customChat.chat.id,
                inputMessageContents: inputMessageContents,
                messageThreadId: nil,
                onlyPreview: nil,
                options: nil,
                replyTo: getMessageReplyTo(from: replyMessage)
            )
        } catch {
            await tdSendChatAction(.chatActionCancel)
            log("Error sending messageAlbum: \(error)")
        }
    }
    
    func tdGetChatHistory() async -> [Message]? {
        guard let customChat else { return nil }
        do {
            return try await td.getChatHistory(
                chatId: customChat.chat.id,
                fromMessageId: messages.first?.message.id ?? 0,
                limit: limit,
                offset: messages.first == nil ? -offset : 0,
                onlyLocal: false
            ).messages
        } catch {
            log("Error getting chatHistory: \(error)")
            return nil
        }
    }
    
    func tdViewMessages(ids: [Int64]) async {
        guard let customChat else { return }
        do {
            try await td.viewMessages(
                chatId: customChat.chat.id,
                forceRead: true,
                messageIds: ids,
                source: .messageSourceChatHistory
            )
        } catch {
//            log("Error viewing messages: \(error)")
        }
    }
    
    func tdSendChatAction(_ chatAction: ChatAction) async {
        guard let customChat else { return }
        do {
            try await td.sendChatAction(action: chatAction, chatId: customChat.chat.id, messageThreadId: 0)
        } catch {
            log("Error sending chatAction: \(error)")
        }
    }
    
    func tdRecognizeSpeech(for messageId: Int64) async {
        guard let customChat else { return }
        do {
            try await td.recognizeSpeech(chatId: customChat.chat.id, messageId: messageId)
        } catch {
            log("Error recognizing speech: \(error)")
        }
    }
}
