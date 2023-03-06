// ChatViewModel+Load.swift

import SwiftUI
@preconcurrency import TDLibKit

extension ChatViewModel {
    func loadPhotos() {
        let processedImages = fetchedImages
            .filter { $0.selected }
            .compactMap {
                if let image = $0.thumbnail, let url = $0.url {
                    return SelectedImage(image: image, url: url)
                }
                return nil
            }
        
        fetchedImages = fetchedImages.map { $0.deselected() }
        selectedImagesCount = 0
        
        withAnimation {
            displayedImages = processedImages
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
    
    @available(iOS 16.2, *)
    func loadLiveActivity() async {
        guard let content = customChat.chat.lastMessage?.content,
              let lastMessageText = getText(from: content),
              let photoId = customChat.chat.photo?.small.id,
              let file = await tdDownloadFile(id: photoId, synchronous: true, priority: 32),
              let url = URL(string: file.local.path),
              let destinationUrl = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.levochkaaa.BetterTGWidget"
              )
        else { return }
        
        let destinationPath = destinationUrl.appending(path: url.lastPathComponent).path()
        if !FileManager.default.fileExists(atPath: file.local.path) {
            try? FileManager.default.moveItem(atPath: file.local.path, toPath: destinationPath)
        }
        log("destination: \(destinationPath)", file.local.path)
        
        currentLiveActivityId = LiveActivityManager.startActivity(
            messageAttributes: .init(name: customChat.chat.title, avatarId: url.lastPathComponent),
            contentState: .init(lastMessageText: lastMessageText)
        )
    }
}
