// ChatViewModel+Td.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func tdDeleteMessages(ids: [Int64], deleteForBoth: Bool) async {
        do {
            _ = try await tdApi.deleteMessages(chatId: self.chat.id, messageIds: ids, revoke: deleteForBoth)
        } catch {
            logger.log("Error deleting messages: \(error)")
        }
    }
    
    func tdGetMessage(id: Int64) async -> Message? {
        do {
            return try await tdApi.getMessage(chatId: chat.id, messageId: id)
        } catch {
            logger.log("Error getting message: \(error)")
            return nil
        }
    }
    
    func tdGetUser(id: Int64) async -> User? {
        do {
            return try await tdApi.getUser(userId: id)
        } catch {
            logger.log("Error getting user: \(error)")
            return nil
        }
    }
    
    func tdEditMessageText(_ editMessage: Message) async {
        do {
            _ = try await tdApi.editMessageText(
                chatId: chat.id,
                inputMessageContent:
                        .inputMessageText(
                            .init(
                                clearDraft: true,
                                disableWebPagePreview: true,
                                text: FormattedText(
                                    entities: [],
                                    text: editMessageText
                                )
                            )
                        ),
                messageId: editMessage.id,
                replyMarkup: nil
            )
        } catch {
            logger.log("Error editing messageText: \(error)")
        }
    }
    
    func tdGetCustomEmojiSticker(id: TdInt64) async -> Sticker? {
        return await tdGetCustomEmojiStickers(ids: [id])?.first
    }
    
    func tdGetCustomEmojiStickers(ids: [TdInt64]) async -> [Sticker]? {
        do {
            return try await tdApi.getCustomEmojiStickers(customEmojiIds: ids).stickers
        } catch {
            logger.log("Error getting customEmojiStickers: \(error)")
            return nil
        }
    }
    
    func tdDownloadFile(id: Int) async -> File? {
        do {
            return try await tdApi.downloadFile(fileId: id, limit: 0, offset: 0, priority: 4, synchronous: false)
        } catch {
            logger.log("Error downloading file: \(error)")
            return nil
        }
    }
    
    func tdEditMessageCaption(_ editMessage: Message) async {
        do {
            _ = try await tdApi.editMessageCaption(
                caption: FormattedText(
                    entities: [],
                    text: editMessageText
                ),
                chatId: chat.id,
                messageId: editMessage.id,
                replyMarkup: nil
            )
        } catch {
            logger.log("Error editing messageCaption: \(error)")
        }
    }
    
    func tdSetChatDraftMessage(_ draftMessage: DraftMessage) async {
        do {
            _ = try await tdApi.setChatDraftMessage(
                chatId: chat.id,
                draftMessage: draftMessage,
                messageThreadId: 0
            )
        } catch {
            logger.log("Error setting draftMessage: \(error)")
        }
    }
    
    func tdSendMessage(with inputMessageContent: InputMessageContent) async {
        do {
            _ = try await tdApi.sendMessage(
                chatId: chat.id,
                inputMessageContent: inputMessageContent,
                messageThreadId: 0,
                options: nil,
                replyMarkup: nil,
                replyToMessageId: replyMessage?.message.id ?? 0
            )
        } catch {
            logger.log("Error sending message: \(error)")
        }
    }
    
    func tdSendMessageAlbum(with inputMessageContents: [InputMessageContent]) async {
        do {
            _ = try await tdApi.sendMessageAlbum(
                chatId: chat.id,
                inputMessageContents: inputMessageContents,
                messageThreadId: nil,
                onlyPreview: nil,
                options: nil,
                replyToMessageId: replyMessage?.message.id ?? 0
            )
        } catch {
            logger.log("Error sending messageAlbum: \(error)")
        }
    }
    
    func tdGetChatHistory() async -> Messages? {
        do {
            return try await self.tdApi.getChatHistory(
                chatId: chat.id,
                fromMessageId: self.messages.first?.message.id ?? 0,
                limit: limit,
                offset: messages.first == nil ? -offset : 0,
                onlyLocal: false
            )
        } catch {
            logger.log("Error getting chatHistory: \(error)")
            return nil
        }
    }
    
    func tdRecognizeSpeech(for messageId: Int64) async {
        do {
            _ = try await tdApi.recognizeSpeech(chatId: chat.id, messageId: messageId)
        } catch {
            logger.log("Error recognizing speech: \(error)")
        }
    }
}
