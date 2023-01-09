// RootViewModel+Publishers.swift

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
            Task { @MainActor in
                self.loggedIn = false
            }
        }
        
        nc.publisher(for: .ready) { _ in
            Task {
                await self.loadMainChats()
                
                await MainActor.run {
                    self.loggedIn = true
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
    }
    
    func chatPosition(_ chatPosition: UpdateChatPosition) {
        Task { @MainActor in
            withAnimation {
                sortMainChats()
            }
        }
    }
    
    func chatLastMessage(_ chatLastMessage: UpdateChatLastMessage) {
        guard let index = self.mainChats.firstIndex(where: { $0.chat.id == chatLastMessage.chatId })
        else { return }
        
        Task {
            guard let customChat = await self.getCustomChat(from: self.mainChats[index].chat.id) else { return }
            
            await MainActor.run {
                withAnimation {
                    self.mainChats[index] = customChat
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        self.sortMainChats()
                    }
                }
            }
        }
    }
    
    func chatDraftMessage(_ chatDraftMessage: UpdateChatDraftMessage) {
        guard let index = self.mainChats.firstIndex(where: { $0.chat.id == chatDraftMessage.chatId })
        else { return }
        
        Task {
            guard let customChat = await self.getCustomChat(from: self.mainChats[index].chat.id) else { return }
            
            await MainActor.run {
                withAnimation {
                    self.mainChats[index] = customChat
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        self.sortMainChats()
                    }
                }
            }
        }
    }
}
