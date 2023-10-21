// RootViewModel+Publishers.swift

import TDLibKit

extension RootViewModel {
    func setPublishers() {
        nc.publisher(&cancellables, for: .ready) { [weak self] _ in
            self?.loadMainChats()
        }
        
        nc.publisher(&cancellables, for: .chatLastMessage) { [weak self] notification in
            guard let self, let chatLastMessage = notification.object as? UpdateChatLastMessage else { return }
            self.chatLastMessage(chatLastMessage)
        }
        
        nc.publisher(&cancellables, for: .chatDraftMessage) { [weak self] notification in
            guard let self, let chatDraftMessage = notification.object as? UpdateChatDraftMessage else { return }
            self.chatDraftMessage(chatDraftMessage)
        }
        
        nc.publisher(&cancellables, for: .chatPosition) { [weak self] notification in
            guard let self, let chatPosition = notification.object as? UpdateChatPosition else { return }
            self.chatPosition(chatPosition)
        }
        
        nc.publisher(&cancellables, for: .newChat) { [weak self] notification in
            guard let self, let newChat = notification.object as? UpdateNewChat else { return }
            self.newChat(newChat)
        }
        
        nc.publisher(&cancellables, for: .chatReadInbox) { [weak self] notification in
            guard let self, let chatReadInbox = notification.object as? UpdateChatReadInbox else { return }
            self.chatReadInbox(chatReadInbox)
        }
    }
    
    func chatReadInbox(_ chatReadInbox: UpdateChatReadInbox) {
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatReadInbox.chatId }) else { return }
            mainChats[index].unreadCount = chatReadInbox.unreadCount
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
    }
    
    func chatDraftMessage(_ chatDraftMessage: UpdateChatDraftMessage) {
        Task.main {
            guard let index = mainChats.firstIndex(where: { $0.chat.id == chatDraftMessage.chatId }) else { return }
            mainChats[index].draftMessage = chatDraftMessage.draftMessage
            mainChats[index].positions = chatDraftMessage.positions
        }
    }
}
