// Chat+publishers.swift

import SwiftUI
import TDLibKit

extension ChatViewModel {
    func setPublishers() {
        setMediaPublishers()
        
        nc.publisher(for: .messageEdited) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == customChat.chat.id
            else { return }
            self.messageEdited(messageEdited)
        }
        
        nc.publisher(for: .newMessage) { notification in
            guard let message = (notification.object as? UpdateNewMessage)?.message,
                  message.chatId == customChat.chat.id
            else { return }
            self.newMessage(message)
        }
        
        nc.publisher(for: .deleteMessages) { notification in
            guard let deleteMessages = notification.object as? UpdateDeleteMessages,
                  deleteMessages.chatId == customChat.chat.id
            else { return }
            self.deleteMessages(deleteMessages)
        }
        
        nc.publisher(for: .messageSendFailed) { notification in
            guard let messageSendFailed = notification.object as? UpdateMessageSendFailed,
                  messageSendFailed.message.chatId == customChat.chat.id
            else { return }
            self.messageSendFailed(messageSendFailed)
        }
        
        nc.publisher(for: .messageSendSucceeded) { notification in
            guard let messageSendSucceeded = notification.object as? UpdateMessageSendSucceeded,
                  messageSendSucceeded.message.chatId == customChat.chat.id
            else { return }
            self.messageSendSucceeded(messageSendSucceeded)
        }
        
        nc.publisher(for: .chatAction) { notification in
            guard let chatAction = notification.object as? UpdateChatAction,
                  chatAction.chatId == customChat.chat.id
            else { return }
            self.chatAction(chatAction)
        }
        
        nc.publisher(for: .userStatus) { notification in
            guard let userStatus = notification.object as? UpdateUserStatus,
                  userStatus.userId == customChat.chat.id
            else { return }
            self.userStatus(userStatus.status)
        }
    }
    
    func userStatus(_ status: UserStatus) {
        switch status {
            case .userStatusEmpty:
                onlineStatus = "empty"
            case .userStatusOnline: // (let userStatusOnline)
                onlineStatus = "online"
            case .userStatusOffline(let userStatusOffline):
                onlineStatus = "last seen \(getLastSeenTime(from: userStatusOffline.wasOnline))"
            case .userStatusRecently:
                onlineStatus = "last seen recently"
            case .userStatusLastWeek:
                onlineStatus = "last seen last week"
            case .userStatusLastMonth:
                onlineStatus = "last seen last month"
        }
    }
    
    func getLastSeenTime(from time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        
        let difference = Date().timeIntervalSince1970 - TimeInterval(time)
        if difference < 60 {
            return "now"
        } else if difference < 60 * 60 {
            return "\(Int(difference / 60)) minutes ago"
        } else if difference < 60 * 60 * 24 {
            return "\(Int(difference / 60 / 60)) hours ago"
        } else if difference < 60 * 60 * 24 * 2 {
            dateFormatter.dateFormat = "HH:mm"
            return "yesterday at \(dateFormatter.string(from: date))"
        } else {
            dateFormatter.dateFormat = "dd.MM.yy"
            return dateFormatter.string(from: date)
        }
    }
    
    func chatAction(_ chatAction: UpdateChatAction) {
        guard case .messageSenderUser(let messageSenderUser) = chatAction.senderId,
              messageSenderUser.userId == customChat.chat.id
        else { return }
        
        switch chatAction.action {
            case .chatActionTyping:
                actionStatus = "typing..."
            case .chatActionRecordingVideo:
                actionStatus = "recording video..."
            case .chatActionUploadingVideo: // (let chatActionUploadingVideo)
                actionStatus = "uploading video..."
            case .chatActionRecordingVoiceNote:
                actionStatus = "recording voice note..."
            case .chatActionUploadingVoiceNote: // (let chatActionUploadingVoiceNote)
                actionStatus = "uploading voice note..."
            case .chatActionUploadingPhoto: // (let chatActionUploadingPhoto)
                actionStatus = "uploading photo..."
            case .chatActionUploadingDocument: // (let chatActionUploadingDocument)
                actionStatus = "uploading voice document..."
            case .chatActionChoosingSticker:
                actionStatus = "choosing sticker..."
            case .chatActionChoosingLocation:
                actionStatus = "choosing location..."
            case .chatActionChoosingContact:
                actionStatus = "choosing contact..."
            case .chatActionStartPlayingGame:
                actionStatus = "playing game..."
            case .chatActionRecordingVideoNote:
                actionStatus = "recording video note..."
            case .chatActionUploadingVideoNote: // (let chatActionUploadingVideoNote)
                actionStatus = "uploading video note..."
            case .chatActionWatchingAnimations(let chatActionWatchingAnimations):
                actionStatus = "watching animations...\(chatActionWatchingAnimations.emoji)"
            case .chatActionCancel:
                actionStatus = ""
        }
    }
    
    func messageSendSucceeded(_ messageSendSucceeded: UpdateMessageSendSucceeded) {
        let message = messageSendSucceeded.message
        
        if message.mediaAlbumId == 0 {
            guard let index = self.messages.firstIndex(where: {
                $0.message.id == messageSendSucceeded.oldMessageId
            }) else { return }
            Task {
                let customMessage = await self.getCustomMessage(from: message)
                await MainActor.run {
                    self.messages[index] = customMessage
                }
            }
            return
        }
        
        if self.sentPhotosCount == 0 {
            self.savedAlbumMainMessageIdTemp = messageSendSucceeded.oldMessageId
            self.savedAlbumMainMessageId = message.id
            self.sentPhotosCount += 1
        } else if self.sentPhotosCount != self.toBeSentPhotosCount {
            self.sentPhotosCount += 1
            self.savedPhotoMessages.append(message)
            
            if self.sentPhotosCount == self.toBeSentPhotosCount {
                guard let index = self.messages.firstIndex(where: {
                    $0.message.id == self.savedAlbumMainMessageIdTemp
                })
                else { return }
                
                Task {
                    guard var customMessage = await self.getCustomMessage(fromId: self.savedAlbumMainMessageId)
                    else { return }
                    
                    self.savedPhotoMessages.forEach {
                        customMessage.album.append($0)
                    }
                    
                    await MainActor.run { [customMessage] in
                        self.messages[index] = customMessage
                    }
                    
                    self.sentPhotosCount = 0
                    self.toBeSentPhotosCount = 0
                    self.savedAlbumMainMessageId = 0
                    self.savedAlbumMainMessageIdTemp = 0
                    self.savedPhotoMessages = []
                }
            }
        }
    }
    
    func messageSendFailed(_ messageSendFailed: UpdateMessageSendFailed) {
        guard let index = self.messages.firstIndex(where: { $0.message.id == messageSendFailed.oldMessageId })
        else { return }
        
        Task.main {
            withAnimation {
                self.messages[index].sendFailed = true
            }
        }
    }
    
    func newMessage(_ message: Message) {
        Task {
            let customMessage = await self.getCustomMessage(from: message)
            await MainActor.run { [customMessage] in
                withAnimation {
                    if message.mediaAlbumId == 0 {
                        self.messages.add(customMessage)
                    } else if !self.loadedAlbums.contains(message.mediaAlbumId.rawValue) {
                        self.messages.add(customMessage)
                        self.loadedAlbums.insert(message.mediaAlbumId.rawValue)
                    } else if self.loadedAlbums.contains(message.mediaAlbumId.rawValue) {
                        guard let index = self.messages.firstIndex(where: {
                            $0.message.mediaAlbumId == message.mediaAlbumId
                        }) else { return }
                        
                        self.messages[index].album.append(message)
                    }
                }
            }
        }
    }
    
    func deleteMessages(_ deleteMessages: UpdateDeleteMessages) {
        if deleteMessages.fromCache || !deleteMessages.isPermanent { return }
        
        Task.async(after: Utils.defaultAnimationDuration + 0.15) {
            withAnimation {
                self.messages.removeAll(where: { customMessage in
                    deleteMessages.messageIds.contains(customMessage.message.id)
                })
            }
        }
    }
    
    func messageEdited(_ messageEdited: UpdateMessageEdited) {
        if let index = self.messages.firstIndex(where: { $0.message.id == messageEdited.messageId }) {
            Task {
                guard let customMessage = await self.getCustomMessage(fromId: messageEdited.messageId)
                else { return }
                
                await MainActor.run {
                    self.messages[index] = customMessage
                }
            }
        }
        
        let indices = self.messages.enumerated().compactMap { index, customMessage in
            return customMessage.replyToMessage?.id == messageEdited.messageId ? index : nil
        }
        if indices == [] { return }
        Task {
            let reply = await self.tdGetMessage(id: messageEdited.messageId)
            for index in indices {
                await MainActor.run {
                    self.messages[index].replyToMessage = reply
                }
            }
        }
    }
}
