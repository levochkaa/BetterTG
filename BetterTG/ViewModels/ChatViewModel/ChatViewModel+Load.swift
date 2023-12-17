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
        guard let chatHistory = await tdGetChatHistory() else { return }
        
        let customMessages = await chatHistory.asyncMap { chatMessage in
            await self.getCustomMessage(from: chatMessage)
        }
        
        var savedMessages = [CustomMessage]()
        for customMessage in customMessages {
            if customMessage.message.mediaAlbumId != 0 {
                if let index = savedMessages.firstIndex(where: {
                    $0.message.mediaAlbumId == customMessage.message.mediaAlbumId
                }) {
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
        
        await MainActor.run { [savedMessages] in
            messages.append(contentsOf: savedMessages)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadingMessagesTask = nil
            }
        }
    }
}
