// ChatViewModel+Load.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func loadPhotos() async {
        await MainActor.run {
            withAnimation {
                self.displayedPhotos.removeAll()
            }
        }
        
        let processedImages: [SelectedImage] = await selectedPhotos.asyncCompactMap {
            do {
                if let selectedImage = try await $0.loadTransferable(type: SelectedImage.self) {
                    return selectedImage
                }
                return nil
            } catch {
                log("Error transfering image data: \(error)")
                return nil
            }
        }
        
        await MainActor.run {
            withAnimation {
                self.displayedPhotos = processedImages
            }
        }
    }
    
    func loadMessages(isInit: Bool = false) async {
        await MainActor.run {
            self.loadingMessages = true
            
            if isInit {
                self.initLoadingMessages = true
            }
        }
        
        guard let chatHistory = await tdGetChatHistory() else { return }
        
        let customMessages = await chatHistory.asyncMap { chatMessage in
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
            self.messages += filteredSavedMessages
            self.offset = self.messages.count
            self.loadingMessages = false
            
            if isInit {
                self.initLoadingMessages = false
            }
        }
    }
}
