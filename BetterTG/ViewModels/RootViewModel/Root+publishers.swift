// Root+publishers.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func setPublishers() {
        nc.mergeMany([
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut),
            nc.publisher(for: .waitPhoneNumber),
            nc.publisher(for: .waitCode),
            nc.publisher(for: .waitPassword)
        ]) { _ in
            Task.main {
                loggedIn = false
            }
        }
        
        nc.publisher(for: .ready) { _ in
            Task {
                let ok = await tdLoadChats()
                
                await MainActor.run {
                    mainChatsLoaded = ok
                    loggedIn = true
                }
            }
        }
        
        nc.publisher(for: .chatLastMessage) { notification in
            guard let chatLastMessage = notification.object as? UpdateChatLastMessage else { return }
            self.chatLastMessage(chatLastMessage)
        }
        
        nc.publisher(for: .chatDraftMessage) { notification in
            guard let chatDraftMessage = notification.object as? UpdateChatDraftMessage else { return }
            self.chatDraftMessage(chatDraftMessage)
        }
        
        nc.publisher(for: .chatPosition) { notification in
            guard let chatPosition = notification.object as? UpdateChatPosition else { return }
            self.chatPosition(chatPosition)
        }
        
        nc.publisher(for: .newChat) { notification in
            guard let newChat = notification.object as? UpdateNewChat else { return }
            self.newChat(newChat)
        }
    }
    
    func newChat(_ newChat: UpdateNewChat) {
        Task {
            guard let customChat = await getCustomChat(from: newChat.chat.id),
                  !mainChats.contains(where: { $0.chat.id == customChat.chat.id })
            else { return }
            
            await MainActor.run {
                withAnimation {
                    mainChats.append(customChat)
                    sortMainChats()
                }
            }
        }
    }
    
    func chatPosition(_ chatPosition: UpdateChatPosition) {
        guard let index = mainChats.firstIndex(where: { $0.chat.id == chatPosition.chatId }) else { return }
        guard chatPosition.position.order != 0 else {
            return Task.main {
                withAnimation {
                    _ = mainChats.remove(at: index)
                    sortMainChats()
                }
            }
        }
        
        Task {
            guard let customChat = await getCustomChat(from: chatPosition.chatId) else { return }
            
            await MainActor.run {
                withAnimation {
                    mainChats[index] = customChat
                    sortMainChats()
                }
            }
        }
    }
    
    func chatLastMessage(_ chatLastMessage: UpdateChatLastMessage) {
        if mainChatsLoaded != nil, !self.mainChats.contains(where: { $0.chat.id == chatLastMessage.chatId }) {
            Task {
                guard let customChat = await getCustomChat(from: chatLastMessage.chatId) else { return }
                
                await MainActor.run {
                    withAnimation {
                        mainChats.append(customChat)
                        sortMainChats()
                    }
                }
            }
        }
        
        guard let index = self.mainChats.firstIndex(where: { $0.chat.id == chatLastMessage.chatId })
        else { return }
        
        Task {
            guard let customChat = await self.getCustomChat(from: mainChats[index].chat.id) else { return }
            
            await MainActor.run {
                withAnimation {
                    mainChats[index] = customChat
                    sortMainChats()
                }
            }
        }
    }
    
    func chatDraftMessage(_ chatDraftMessage: UpdateChatDraftMessage) {
        guard let index = mainChats.firstIndex(where: { $0.chat.id == chatDraftMessage.chatId })
        else { return }
        
        Task {
            guard let customChat = await self.getCustomChat(from: mainChats[index].chat.id) else { return }
            
            await MainActor.run {
                withAnimation {
                    mainChats[index] = customChat
                    sortMainChats()
                }
            }
        }
    }
}
