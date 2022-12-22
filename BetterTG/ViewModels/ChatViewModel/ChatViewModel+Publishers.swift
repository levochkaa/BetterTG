// ChatViewModel+Publishers.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setPublishers() {
        setMessageSendPublishers()
        
        nc.publisher(for: .messageEdited) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == self.chat.id
            else { return }
            
            self.onMessageEdited(messageEdited)
        }
        
        nc.publisher(for: .newMessage) { notification in
            guard let message = (notification.object as? UpdateNewMessage)?.message,
                  message.chatId == self.chat.id
            else { return }
            
            Task {
                let customMessage = await self.getCustomMessage(from: message)
                await MainActor.run { [customMessage] in
                    withAnimation {
                        if message.mediaAlbumId == 0 {
                            self.messages.append(customMessage)
                        } else if !self.loadedAlbums.contains(message.mediaAlbumId) {
                            self.messages.append(customMessage)
                            self.loadedAlbums.append(message.mediaAlbumId)
                        } else if self.loadedAlbums.contains(message.mediaAlbumId) {
                            guard let index = self.messages.firstIndex(where: {
                                $0.message.mediaAlbumId == message.mediaAlbumId
                            }) else { return }
                            
                            self.messages[index].album.append(message)
                        }
                    }
                }
            }
        }
        
        nc.publisher(for: .deleteMessages) { notification in
            guard let deleteMessages = notification.object as? UpdateDeleteMessages else { return }
            if deleteMessages.chatId != self.chat.id
                || deleteMessages.fromCache
                || !deleteMessages.isPermanent { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.15) {
                withAnimation {
                    self.messages.removeAll(where: { customMessage in
                        deleteMessages.messageIds.contains(customMessage.message.id)
                    })
                }
            }
        }
    }
    
    func setMessageSendPublishers() {
        nc.publisher(for: .messageSendFailed) { notification in
            guard let messageSendFailed = notification.object as? UpdateMessageSendFailed,
                  messageSendFailed.message.chatId == self.chat.id,
                  let index = self.messages.firstIndex(where: { $0.message.id == messageSendFailed.oldMessageId })
            else { return }
            
            Task { @MainActor in
                withAnimation {
                    self.messages[index].sendFailed = true
                }
            }
        }
        
        nc.publisher(for: .messageSendSucceeded) { notification in
            guard let messageSendSucceeded = notification.object as? UpdateMessageSendSucceeded,
                  messageSendSucceeded.message.chatId == self.chat.id,
                  let index = self.messages.firstIndex(where: { $0.message.id == messageSendSucceeded.oldMessageId })
            else { return }
            
            Task {
                let customMessage = await self.getCustomMessage(from: messageSendSucceeded.message)
                await MainActor.run {
                    withAnimation {
                        self.messages[index] = customMessage
                    }
                }
            }
        }
    }
    
    func onMessageEdited(_ messageEdited: UpdateMessageEdited) {
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
