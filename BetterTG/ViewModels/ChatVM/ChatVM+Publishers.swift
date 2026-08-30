// ChatVM+Publishers.swift

import Combine
import TDLibKitDynamic

extension ChatVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] update in
            guard let self, update.chatId == customChat.id else { return }
            customChat.unreadCount = update.unreadCount
        }
        nc.publisher(&cancellables, for: .updateNewMessage) { [weak self] update in
            guard let self, update.message.chatId == customChat.id else { return }
            updateNewMessage(update)
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { [weak self] update in
            guard let self, update.chatId == customChat.id else { return }
            updateDeleteMessages(update)
        }
        nc.publisher(&cancellables, for: .updateMessageEdited) { [weak self] update in
            guard let self, update.chatId == customChat.id else { return }
            updateMessageEdited(update)
        }
        nc.publisher(&cancellables, for: .updateMessageContent) { [weak self] update in
            guard let self, update.chatId == customChat.id else { return }
            refreshMessage(id: update.messageId)
        }
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { [weak self] update in
            guard let self, update.message.chatId == customChat.id else { return }
            updateMessageSendSucceeded(update)
        }
        nc.publisher(&cancellables, for: .updateMessageSendFailed) { [weak self] update in
            guard let self, update.message.chatId == customChat.id else { return }
            updateMessageSendFailed(update)
        }
        nc.publisher(&cancellables, for: .updateUserStatus) { [weak self] update in
            guard let self, update.userId == customChat.user?.id else { return }
            onlineStatus = getOnlineStatus(from: update.status)
        }
        nc.publisher(&cancellables, for: .updateUser) { [weak self] update in
            guard let self else { return }
            for message in messages {
                if message.senderUser?.id == update.user.id {
                    message.senderUser = update.user
                }
                if message.replyUser?.id == update.user.id {
                    message.replyUser = update.user
                }
            }
        }
        nc.publisher(&cancellables, for: .updateChatAction) { [weak self] update in
            guard let self, update.chatId == customChat.id else { return }
            updateChatAction(update)
        }
    }

    func updateChatAction(_ update: UpdateChatAction) {
        actionStatus =
            switch update.action {
            case .chatActionTyping: "typing..."
            case .chatActionRecordingVideo: "recording video..."
            case .chatActionUploadingVideo: "uploading video..."
            case .chatActionRecordingVoiceNote: "recording voice note..."
            case .chatActionUploadingVoiceNote: "uploading voice note..."
            case .chatActionUploadingPhoto: "uploading photo..."
            case .chatActionUploadingDocument: "uploading document..."
            case .chatActionChoosingSticker: "choosing sticker..."
            case .chatActionChoosingLocation: "choosing location..."
            case .chatActionChoosingContact: "choosing contact..."
            case .chatActionStartPlayingGame: "playing game..."
            case .chatActionRecordingVideoNote: "recording video note..."
            case .chatActionUploadingVideoNote: "uploading video note..."
            case .chatActionWatchingAnimations(let action): "watching animations...\(action.emoji)"
            case .chatActionCancel: ""
            }
    }

    func updateMessageSendSucceeded(_ update: UpdateMessageSendSucceeded) {
        if update.message.mediaAlbumId != 0 {
            for outerMessage in messages {
                guard let index = outerMessage.album.firstIndex(where: { $0.id == update.oldMessageId })
                else { continue }
                outerMessage.album[index] = update.message
                return
            }
        }
        Task {
            let replacement = await self.getCustomMessage(from: update.message)
            await main {
                guard let index = self.messages.firstIndex(where: { $0.id == update.oldMessageId }) else { return }
                self.messages[index] = replacement
            }
        }
    }

    func updateMessageSendFailed(_ update: UpdateMessageSendFailed) {
        Task {
            let replacement = await self.getCustomMessage(from: update.message)
            await main {
                replacement.sendFailed = true
                guard let index = self.messages.firstIndex(where: { $0.id == update.oldMessageId }) else { return }
                self.messages[index] = replacement
            }
        }
    }

    func updateDeleteMessages(_ update: UpdateDeleteMessages) {
        guard !update.fromCache, update.isPermanent else { return }
        messages.removeAll { update.messageIds.contains($0.id) }
    }

    func updateNewMessage(_ update: UpdateNewMessage) {
        Task {
            let customMessage = await self.getCustomMessage(from: update.message)
            await main {
                if update.message.mediaAlbumId == 0 {
                    self.messages.add(customMessage)
                } else if let existing = self.messages.first(where: {
                    $0.message.mediaAlbumId == update.message.mediaAlbumId
                }) {
                    existing.album.append(update.message)
                } else {
                    self.messages.add(customMessage)
                }
            }
        }
    }

    func updateMessageEdited(_ update: UpdateMessageEdited) {
        refreshMessage(id: update.messageId)
    }

    private func refreshMessage(id: Int64) {
        Task {
            let replacement = await getCustomMessage(fromId: id)
            let reply = try? await td.getMessage(chatId: chatID, messageId: id)
            if let replacement,
               let index = messages.firstIndex(where: { $0.id == id })
            {
                messages[index] = replacement
                if replyMessage?.id == id {
                    replyMessage = replacement
                }
            }
            for message in messages where message.replyToMessage?.id == id {
                message.replyToMessage = reply
            }
        }
    }
}
