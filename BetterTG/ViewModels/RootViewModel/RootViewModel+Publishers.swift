// RootViewModel+Publishers.swift

import SwiftUI
@preconcurrency import TDLibKit

extension RootViewModel {
    func setPublishers() {
        nc.mergeMany([.closed, .closing, .loggingOut, .waitPhoneNumber, .waitCode, .waitPassword]) { _ in
            Task.main {
                loggedIn = false
            }
        }
        
        nc.publisher(for: .ready) { _ in
            Task.main {
                loggedIn = true
                loadMainChats()
                loadArchivedChats()
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
        
        nc.publisher(for: .chatReadInbox) { notification in
            guard let chatReadInbox = notification.object as? UpdateChatReadInbox else { return }
            self.chatReadInbox(chatReadInbox)
        }
    }
    
    func chatReadInbox(_ chatReadInbox: UpdateChatReadInbox) {
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatReadInbox.chatId }) else { return }
            
            mainChats[index].unreadCount = chatReadInbox.unreadCount
        }
        
        Task.main {
            guard let index = archivedChats.firstIndex(where: { $0.chat.id == chatReadInbox.chatId }) else { return }
            
            archivedChats[index].unreadCount = chatReadInbox.unreadCount
        }
    }
    
    func newChat(_ newChat: UpdateNewChat) {
        Task {
            guard let customChat = await getCustomChat(from: newChat.chat.id) else { return }
            
            await MainActor.run {
                mainChats.append(customChat)
            }
        }
    }
    
    func chatPosition(_ chatPosition: UpdateChatPosition) {
//        guard chatPosition.position.order != 0 else {
//            return Task.main {
//                mainChats.removeAll(where: { $0.chat.id == chatPosition.chatId })
//            }
//        }
        
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatPosition.chatId }),
                  let positionIndex = mainChats[index].positions.firstIndex(where: {
                      $0.list == chatPosition.position.list
                  })
            else { return }
            
            mainChats[index].positions[positionIndex] = chatPosition.position
        }
        
        Task.main {
            guard let index = archivedChats.firstIndex(where: { $0.chat.id == chatPosition.chatId }),
                  let positionIndex = archivedChats[index].positions.firstIndex(where: {
                      $0.list == chatPosition.position.list
                  })
            else { return }
            
            archivedChats[index].positions[positionIndex] = chatPosition.position
        }
    }
    
    func chatLastMessage(_ chatLastMessage: UpdateChatLastMessage) {
        if !mainChats.isEmpty, !mainChats.contains(where: { $0.chat.id == chatLastMessage.chatId }) {
            Task {
                guard let customChat = await getCustomChat(from: chatLastMessage.chatId) else { return }

                await MainActor.run {
                    mainChats.append(customChat)
                }
            }
            return
        }
        
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatLastMessage.chatId }) else { return }
            mainChats[index].lastMessage = chatLastMessage.lastMessage
            mainChats[index].positions = chatLastMessage.positions
        }
        
        Task.main {
            guard let index = archivedChats.firstIndex(where: { $0.chat.id == chatLastMessage.chatId }) else { return }
            archivedChats[index].lastMessage = chatLastMessage.lastMessage
            archivedChats[index].positions = chatLastMessage.positions
        }
    }
    
    func chatDraftMessage(_ chatDraftMessage: UpdateChatDraftMessage) {
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatDraftMessage.chatId }) else { return }
            mainChats[index].draftMessage = chatDraftMessage.draftMessage
            mainChats[index].positions = chatDraftMessage.positions
        }
        
        Task.main {
            guard let index = archivedChats.firstIndex(where: { $0.chat.id == chatDraftMessage.chatId }) else { return }
            archivedChats[index].draftMessage = chatDraftMessage.draftMessage
            archivedChats[index].positions = chatDraftMessage.positions
        }
    }
}
