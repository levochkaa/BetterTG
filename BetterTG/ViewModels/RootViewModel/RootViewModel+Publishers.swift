// RootViewModel+Publishers.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func setPublishers() {
        setAuthPublishers()
        setChatPublishers()
    }
    
    func setChatPublishers() {
        nc.publisher(for: .chatLastMessage) { notification in
            guard let updateChatLastMessage = notification.object as? UpdateChatLastMessage,
                  let index = self.mainChats.firstIndex(where: { $0.id == updateChatLastMessage.chatId })
            else { return }
            
            Task {
                guard let chat = await self.tdGetChat(id: self.mainChats[index].id) else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.mainChats[index] = chat
                    }
                }
            }
        }
        
        nc.publisher(for: .chatDraftMessage) { notification in
            guard let updateChatDraftMessage = notification.object as? UpdateChatDraftMessage,
                  let index = self.mainChats.firstIndex(where: { $0.id == updateChatDraftMessage.chatId })
            else { return }
            
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
    
    func setAuthPublishers() {
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
    }
}
