// ChatViewModel+Load.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func loadMessages() {
        guard loadingMessagesTask == nil else { return }
        loadingMessagesTask = Task(priority: .high) {
            await _loadMessages()
        }
    }
    
    private func _loadMessages() async {
        guard !loadingMessages else { return }
        
        self.loadingMessages = true
        
        guard let chatHistory = await tdGetChatHistory() else { return }
        
        let customMessages = await chatHistory.reversed().asyncMap { chatMessage in
            await self.getCustomMessage(from: chatMessage)
        }
        
        var savedMessages = [CustomMessage]()
        for customMessage in customMessages {
            if customMessage.message.mediaAlbumId != 0 {
                let index = savedMessages.firstIndex(where: {
                    $0.message.mediaAlbumId == customMessage.message.mediaAlbumId
                })
                if let index {
                    savedMessages[index].album.append(customMessage.message)
                } else {
                    var newMessage = customMessage
                    newMessage.album = [customMessage.message]
                    savedMessages.append(newMessage)
                }
            } else {
                savedMessages.append(customMessage)
            }
        }
        
        let filteredSavedMessages = savedMessages.filter { savedMessage in
            !messages.contains(where: {
                $0.message.id == savedMessage.message.id
            })
        }
        
        await MainActor.run {
            messages.insert(contentsOf: filteredSavedMessages, at: 0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadingMessages = false
                self.loadingMessagesTask = nil
            }
        }
    }
}
