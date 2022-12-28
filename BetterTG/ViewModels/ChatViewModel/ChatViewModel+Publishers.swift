// ChatViewModel+Publishers.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setPublishers() {
        setMediaPublishers()
        
        nc.publisher(for: .messageEdited) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == self.chat.id
            else { return }
            self.messageEdited(messageEdited)
        }
        
        nc.publisher(for: .newMessage) { notification in
            guard let message = (notification.object as? UpdateNewMessage)?.message,
                  message.chatId == self.chat.id
            else { return }
            self.newMessage(message)
        }
        
        nc.publisher(for: .deleteMessages) { notification in
            guard let deleteMessages = notification.object as? UpdateDeleteMessages,
                  deleteMessages.chatId == self.chat.id
            else { return }
            self.deleteMessages(deleteMessages)
        }
        
        nc.publisher(for: .messageSendFailed) { notification in
            guard let messageSendFailed = notification.object as? UpdateMessageSendFailed,
                  messageSendFailed.message.chatId == self.chat.id
            else { return }
            self.messageSendFailed(messageSendFailed)
        }
        
        nc.publisher(for: .messageSendSucceeded) { notification in
            guard let messageSendSucceeded = notification.object as? UpdateMessageSendSucceeded,
                  messageSendSucceeded.message.chatId == self.chat.id
            else { return }
            self.messageSendSucceeded(messageSendSucceeded)
        }
    }
    
    func messageSendSucceeded(_ messageSendSucceeded: UpdateMessageSendSucceeded) {
        let message = messageSendSucceeded.message
        
        if message.mediaAlbumId == 0 {
            guard let index = self.messages.firstIndex(where: {
                $0.message.id == messageSendSucceeded.oldMessageId
            }) else { return }
            Task {
                let customMessage = await self.getCustomMessage(from: message)
                await MainActor.run {
                    self.messages[index] = customMessage
                }
            }
            return
        }
        
        if self.sentPhotosCount == 0 {
            self.savedAlbumMainMessageIdTemp = messageSendSucceeded.oldMessageId
            self.savedAlbumMainMessageId = message.id
            self.sentPhotosCount += 1
        } else if self.sentPhotosCount != self.toBeSentPhotosCount {
            self.sentPhotosCount += 1
            self.savedPhotoMessages.append(message)
            
            if self.sentPhotosCount == self.toBeSentPhotosCount {
                guard let index = self.messages.firstIndex(where: {
                    $0.message.id == self.savedAlbumMainMessageIdTemp
                })
                else { return }
                
                Task {
                    guard var customMessage = await self.getCustomMessage(fromId: self.savedAlbumMainMessageId)
                    else { return }
                    
                    self.savedPhotoMessages.forEach {
                        customMessage.album.append($0)
                    }
                    
                    await MainActor.run { [customMessage] in
                        self.messages[index] = customMessage
                    }
                    
                    self.sentPhotosCount = 0
                    self.toBeSentPhotosCount = 0
                    self.savedAlbumMainMessageId = 0
                    self.savedAlbumMainMessageIdTemp = 0
                    self.savedPhotoMessages = []
                }
            }
        }
    }
    
    func messageSendFailed(_ messageSendFailed: UpdateMessageSendFailed) {
        guard let index = self.messages.firstIndex(where: { $0.message.id == messageSendFailed.oldMessageId })
        else { return }
        
        Task { @MainActor in
            withAnimation {
                self.messages[index].sendFailed = true
            }
        }
    }
    
    func newMessage(_ message: Message) {
        Task {
            let customMessage = await self.getCustomMessage(from: message)
            await MainActor.run { [customMessage] in
                withAnimation {
                    if message.mediaAlbumId == 0 {
                        self.messages.append(customMessage)
                    } else if !self.loadedAlbums.contains(message.mediaAlbumId.rawValue) {
                        self.messages.append(customMessage)
                        self.loadedAlbums.insert(message.mediaAlbumId.rawValue)
                    } else if self.loadedAlbums.contains(message.mediaAlbumId.rawValue) {
                        guard let index = self.messages.firstIndex(where: {
                            $0.message.mediaAlbumId == message.mediaAlbumId
                        }) else { return }
                        
                        self.messages[index].album.append(message)
                    }
                }
            }
        }
    }
    
    func deleteMessages(_ deleteMessages: UpdateDeleteMessages) {
        if deleteMessages.fromCache || !deleteMessages.isPermanent { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.15) {
            withAnimation {
                self.messages.removeAll(where: { customMessage in
                    deleteMessages.messageIds.contains(customMessage.message.id)
                })
            }
        }
    }
    
    func messageEdited(_ messageEdited: UpdateMessageEdited) {
        if messageEdited.messageId == self.editMessage?.message.id {
            Task {
                let message = await self.tdGetMessage(id: messageEdited.messageId)
                await MainActor.run {
                    self.setEditMessageText(from: message)
                }
            }
        }
        
        if let index = self.messages.firstIndex(where: { $0.message.id == messageEdited.messageId }) {
            Task {
                guard let customMessage = await self.getCustomMessage(fromId: messageEdited.messageId)
                else { return }
                
                await MainActor.run {
                    self.messages[index] = customMessage
                }
            }
        }
        
        let indices = self.messages.enumerated().compactMap { index, customMessage in
            return customMessage.replyToMessage?.id == messageEdited.messageId ? index : nil
        }
        if indices == [] { return }
        Task {
            let reply = await self.tdGetMessage(id: messageEdited.messageId)
            for index in indices {
                await MainActor.run {
                    self.messages[index].replyToMessage = reply
                }
            }
        }
    }
}
