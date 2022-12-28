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
    }
    
    func chatLastMessage(_ chatLastMessage: UpdateChatLastMessage) {
        guard let index = self.mainChats.firstIndex(where: { $0.id == chatLastMessage.chatId }) else { return }
        
        Task {
            guard let chat = await self.tdGetChat(id: self.mainChats[index].id) else { return }
            
            await MainActor.run {
                withAnimation {
                    self.mainChats[index] = chat
                }
            }
        }
    }
    
    func chatDraftMessage(_ chatDraftMessage: UpdateChatDraftMessage) {
        guard let index = self.mainChats.firstIndex(where: { $0.id == chatDraftMessage.chatId }) else { return }
        
        Task {
            guard let chat = await self.tdGetChat(id: self.mainChats[index].id) else { return }
            
            await MainActor.run {
                withAnimation {
                    self.mainChats[index] = chat
                }
            }
        }
    }
}
