// ChatVM+Publishers.swift

import SwiftUI
import TDLibKit
import Combine

extension ChatVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .localScrollToLastOnFocus) { [weak self] _ in
            guard let self, scrollOnFocus else { return }
            Task.main { self.scrollToLast() }
        }
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] updateChatReadInbox in
            guard let self, updateChatReadInbox.chatId == customChat.chat.id else { return }
            Task.main { self.customChat.unreadCount = updateChatReadInbox.unreadCount }
        }
        nc.publisher(&cancellables, for: .updateNewMessage) { [weak self] updateNewMessage in
            guard let self, updateNewMessage.message.chatId == customChat.chat.id else { return }
            self.updateNewMessage(updateNewMessage)
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { [weak self] updateDeleteMessages in
            guard let self, updateDeleteMessages.chatId == customChat.chat.id else { return }
            self.updateDeleteMessages(updateDeleteMessages)
        }
        nc.publisher(&cancellables, for: .updateMessageEdited) { [weak self] updateMessageEdited in
            guard let self, updateMessageEdited.chatId == customChat.chat.id else { return }
            self.updateMessageEdited(updateMessageEdited)
        }
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { [weak self] updateMessageSendSucceeded in
            guard let self, updateMessageSendSucceeded.message.chatId == customChat.chat.id else { return }
            self.updateMessageSendSucceeded(updateMessageSendSucceeded)
        }
        nc.publisher(&cancellables, for: .updateUserStatus) { [weak self] updateUserStatus in
            guard let self, updateUserStatus.userId == customChat.chat.id else { return }
            self.updateUserStatus(updateUserStatus)
        }
        nc.publisher(&cancellables, for: .updateChatAction) { [weak self] updateChatAction in
            guard let self, updateChatAction.chatId == customChat.chat.id else { return }
            self.updateChatAction(updateChatAction)
        }
    }
    
    func updateUserStatus(_ updateUserStatus: UpdateUserStatus) {
        let onlineStatus = getOnlineStatus(from: updateUserStatus.status)
        Task.main { self.onlineStatus = onlineStatus }
    }
    
    func updateChatAction(_ updateChatAction: UpdateChatAction) {
        guard case .messageSenderUser(let messageSenderUser) = updateChatAction.senderId,
              messageSenderUser.userId == customChat.chat.id
        else { return }
        let actionStatus = switch updateChatAction.action {
            case .chatActionTyping: "typing..."
            case .chatActionRecordingVideo: "recording video..."
            case .chatActionUploadingVideo: /* (let chatActionUploadingVideo) */ "uploading video..."
            case .chatActionRecordingVoiceNote: "recording voice note..."
            case .chatActionUploadingVoiceNote: /* (let chatActionUploadingVoiceNote) */ "uploading voice note..."
            case .chatActionUploadingPhoto: /* (let chatActionUploadingPhoto) */ "uploading photo..."
            case .chatActionUploadingDocument: /* (let chatActionUploadingDocument) */ "uploading voice document..."
            case .chatActionChoosingSticker: "choosing sticker..."
            case .chatActionChoosingLocation: "choosing location..."
            case .chatActionChoosingContact: "choosing contact..."
            case .chatActionStartPlayingGame: "playing game..."
            case .chatActionRecordingVideoNote: "recording video note..."
            case .chatActionUploadingVideoNote: /* (let chatActionUploadingVideoNote) */ "uploading video note..."
            case .chatActionWatchingAnimations(let watching): "watching animations...\(watching.emoji)"
            case .chatActionCancel: ""
        }
        Task.main {
            withAnimation {
                self.actionStatus = actionStatus
            }
        }
    }
    
    func updateMessageSendSucceeded(_ updateMessageSendSucceeded: UpdateMessageSendSucceeded) {
        let message = updateMessageSendSucceeded.message
        let oldMessageId = updateMessageSendSucceeded.oldMessageId
        
        if message.mediaAlbumId == 0 {
            guard let index = messages.firstIndex(where: { $0.message.id == oldMessageId  }) else { return }
            Task.background {
                let customMessage = await self.getCustomMessage(from: message)
                await main {
                    withAnimation {
                        self.messages[index] = customMessage
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
    
    func updateDeleteMessages(_ updateDeleteMessages: UpdateDeleteMessages) {
        if updateDeleteMessages.fromCache || !updateDeleteMessages.isPermanent { return }
        
        Task.main(delay: 0.5) {
            withAnimation {
                self.messages.removeAll { customMessage in
                    updateDeleteMessages.messageIds.contains(customMessage.message.id)
                }
            }
        }
    }
    
    func updateNewMessage(_ updateNewMessage: UpdateNewMessage) {
        let message = updateNewMessage.message
        Task.background {
            let customMessage = await self.getCustomMessage(from: message)
            if message.mediaAlbumId == 0 {
                await main {
                    withAnimation {
                        self.messages.add(customMessage)
                    }
                }
            } else {
                if let index = self.messages.firstIndex(where: {
                    $0.message.mediaAlbumId == message.mediaAlbumId
                }) {
                    await main {
                        withAnimation {
                            self.messages[index].album.append(customMessage.message)
                        }
                    }
                } else {
                    await main {
                        withAnimation {
                            self.messages.add(customMessage)
                        }
                    }
                }
            }
            nc.post(name: .localScrollToLastOnFocus)
        }
    }
    
    func updateMessageEdited(_ updateMessageEdited: UpdateMessageEdited) {
        if let index = self.messages.firstIndex(where: { $0.message.id == updateMessageEdited.messageId }) {
            Task.background {
                guard let customMessage = await self.getCustomMessage(fromId: updateMessageEdited.messageId) else { return }
                
                await main {
                    withAnimation {
                        self.messages[index] = customMessage
                        
                        if updateMessageEdited.messageId == self.replyMessage?.message.id {
                            self.replyMessage = customMessage
                        }
                    }
                }
            }
        }
        
        let indices = self.messages.enumerated().compactMap { index, customMessage in
            return customMessage.replyToMessage?.id == updateMessageEdited.messageId ? index : nil
        }
        guard !indices.isEmpty else { return }
        Task.background {
            let reply = try? await td.getMessage(chatId: self.customChat.chat.id, messageId: updateMessageEdited.messageId)
            await main {
                for index in indices {
                    withAnimation {
                        self.messages[index].replyToMessage = reply
                    }
                }
            }
        }
    }
}
