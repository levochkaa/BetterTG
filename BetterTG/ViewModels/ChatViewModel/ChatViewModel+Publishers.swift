// ChatViewModel+Publishers.swift

import SwiftUI
import Combine
import TDLibKit
import Observation

extension ChatViewModel {
    func setPublishers() {
        setMediaPublishers()
        
        nc.publisher(&cancellables, for: .messageEdited) { [weak self] notification in
            guard let self,
                  let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == customChat.chat.id
            else { return }
            self.messageEdited(messageEdited)
        }
        
        nc.publisher(&cancellables, for: .newMessage) { [weak self] notification in
            guard let self,
                  let message = (notification.object as? UpdateNewMessage)?.message,
                  message.chatId == customChat.chat.id
            else { return }
            self.newMessage(message)
        }
        
        nc.publisher(&cancellables, for: .deleteMessages) { [weak self] notification in
            guard let self,
                  let deleteMessages = notification.object as? UpdateDeleteMessages,
                  deleteMessages.chatId == customChat.chat.id
            else { return }
            self.deleteMessages(deleteMessages)
        }
        
        nc.publisher(&cancellables, for: .messageSendSucceeded) { [weak self] notification in
            guard let self,
                  let messageSendSucceeded = notification.object as? UpdateMessageSendSucceeded,
                  messageSendSucceeded.message.chatId == customChat.chat.id
            else { return }
            self.messageSendSucceeded(messageSendSucceeded)
        }
        
        nc.publisher(&cancellables, for: .chatAction) { [weak self] notification in
            guard let self,
                  let chatAction = notification.object as? UpdateChatAction,
                  chatAction.chatId == customChat.chat.id
            else { return }
            self.chatAction(chatAction)
        }
        
        nc.publisher(&cancellables, for: .userStatus) { [weak self] notification in
            guard let self,
                  let userStatus = notification.object as? UpdateUserStatus,
                  userStatus.userId == customChat.chat.id
            else { return }
            self.userStatus(userStatus.status)
        }
        
        nc.publisher(&cancellables, for: .chatReadInbox) { [weak self] notification in
            guard let self,
                  let chatReadInbox = notification.object as? UpdateChatReadInbox,
                  chatReadInbox.chatId == customChat.chat.id
            else { return }
            self.chatReadInbox(chatReadInbox)
        }
    }
    
    func chatReadInbox(_ chatReadInbox: UpdateChatReadInbox) {
        customChat.unreadCount = chatReadInbox.unreadCount
    }
    
    func userStatus(_ status: UserStatus) {
        let onlineStatus: String
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
        self.onlineStatus = onlineStatus
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
        
        let actionStatus: String
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
        withAnimation {
            self.actionStatus = actionStatus
        }
    }
    
    func messageSendSucceeded(_ messageSendSucceeded: UpdateMessageSendSucceeded) {
        let message = messageSendSucceeded.message
        let oldMessageId = messageSendSucceeded.oldMessageId
        
        if message.mediaAlbumId == 0 {
            guard let index = messages.firstIndex(where: { $0.message.id == oldMessageId  }) else { return }
            Task {
                let customMessage = await getCustomMessage(from: message)
                await MainActor.run {
                    withAnimation {
                        messages[index] = customMessage
                    }
                }
            }
        } else {
            messages.enumerated().forEach { outerIndex, outerMessage in
                outerMessage.album.enumerated().forEach { innerIndex, innerMessage in
                    guard innerMessage.id == oldMessageId else { return }
                    withAnimation {
                        messages[outerIndex].album[innerIndex] = message
                    }
                    nc.post(name: .localScrollToLastOnFocus)
                }
            }
        }
    }
    
    func newMessage(_ message: Message) {
        Task { @MainActor in
            let customMessage = await self.getCustomMessage(from: message)
            if message.mediaAlbumId == 0 {
                withAnimation {
                    self.messages.add(customMessage)
                }
            } else {
                if let index = messages.firstIndex(where: {
                    $0.message.mediaAlbumId == message.mediaAlbumId
                }) {
                    withAnimation {
                        messages[index].album.append(customMessage.message)
                    }
                } else {
                    withAnimation {
                        messages.add(customMessage)
                    }
                }
            }
            nc.post(name: .localScrollToLastOnFocus)
        }
    }
    
    func deleteMessages(_ deleteMessages: UpdateDeleteMessages) {
        if deleteMessages.fromCache || !deleteMessages.isPermanent { return }
        
        Task.main(delay: Utils.defaultAnimationDuration + 0.15) {
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
                    withAnimation {
                        messages[index] = customMessage
                        
                        if messageEdited.messageId == replyMessage?.message.id {
                            withAnimation {
                                replyMessage = customMessage
                            }
                        }
                    }
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
                    withAnimation {
                        messages[index].replyToMessage = reply
                    }
                }
            }
        }
    }
}
