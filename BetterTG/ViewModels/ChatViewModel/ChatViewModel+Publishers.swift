// ChatViewModel+Publishers.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setPublishers() {
        nc.publisher(for: .messageEdited) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == self.chat.id
            else { return }
            
            self.onMessageEdited(messageEdited)
        }
        
        nc.publisher(for: .newMessage) { notification in
            guard let newMessage = notification.object as? UpdateNewMessage,
                  newMessage.message.chatId == self.chat.id
            else { return }
            
            Task {
                let customMessage = await self.getCustomMessage(from: newMessage.message)
                await MainActor.run {
                    withAnimation {
                        self.messages.append(customMessage)
                        
                        if newMessage.message.isOutgoing {
                            self.scrollToLast()
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
    
    func onMessageEdited(_ messageEdited: UpdateMessageEdited) {
        if messageEdited.messageId == self.editMessage?.message.id {
            Task {
                let message = await self.tdGetMessage(id: messageEdited.messageId)
                if case let .messageText(messageText) = message?.content {
                    await MainActor.run {
                        withAnimation {
                            self.editMessageText = messageText.text.text
                        }
                    }
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
