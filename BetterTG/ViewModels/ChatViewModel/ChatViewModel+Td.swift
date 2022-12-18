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
    
    func tdEditMessageText(_ editMessage: CustomMessage) async {
        do {
            switch editMessage.message.content {
                case .messageText:
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
                        messageId: editMessage.message.id,
                        replyMarkup: nil
                    )
                case .messagePhoto:
                    _ = try await tdApi.editMessageCaption(
                        caption: FormattedText(
                            entities: [],
                            text: editMessageText
                        ),
                        chatId: chat.id,
                        messageId: editMessage.message.id,
                        replyMarkup: nil
                    )
                default:
                    throw Error(code: 0, message: "Not supported edit message type")
            }
        } catch {
            logger.log("Error editing message: \(error)")
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
    
    func tdSendMessage() async {
        do {
            if displayedPhotos.isEmpty {
                _ = try await tdApi.sendMessage(
                    chatId: chat.id,
                    inputMessageContent:
                            .inputMessageText(
                                .init(
                                    clearDraft: true,
                                    disableWebPagePreview: true,
                                    text: FormattedText(
                                        entities: [],
                                        text: text
                                    )
                                )
                            ),
                    messageThreadId: 0,
                    options: nil,
                    replyMarkup: nil,
                    replyToMessageId: replyMessage?.message.id ?? 0
                )
            } else {
                if displayedPhotos.count == 1, let photo = displayedPhotos.first {
                    _ = try await tdApi.sendMessage(
                        chatId: chat.id,
                        inputMessageContent: makeInputMessageContent(for: photo.url),
                        messageThreadId: 0,
                        options: nil,
                        replyMarkup: nil,
                        replyToMessageId: replyMessage?.message.id ?? 0
                    )
                } else {
                    let messageContents = displayedPhotos.map {
                        makeInputMessageContent(for: $0.url)
                    }
                    _ = try await tdApi.sendMessageAlbum(
                        chatId: chat.id,
                        inputMessageContents: messageContents,
                        messageThreadId: nil,
                        onlyPreview: nil,
                        options: nil,
                        replyToMessageId: replyMessage?.message.id ?? 0
                    )
                }
            }
        } catch {
            logger.log("Error sending message: \(error)")
        }
    }
    
    func makeInputMessageContent(for url: URL) -> InputMessageContent {
        let path = url.path()
        
        let image = UIImage(contentsOfFile: path)!
        
        let input: InputFile = .inputFileLocal(
            InputFileLocal(path: path)
        )
        
        return .inputMessagePhoto(
            InputMessagePhoto(
                addedStickerFileIds: [],
                caption: FormattedText(entities: [], text: text),
                height: Int(image.size.height),
                photo: input,
                thumbnail: InputThumbnail(
                    height: Int(image.size.height),
                    thumbnail: input,
                    width: Int(image.size.width)
                ),
                ttl: 0,
                width: Int(image.size.width)
            )
        )
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
}
