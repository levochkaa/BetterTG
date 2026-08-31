// ChatVM+Publishers.swift

import Combine
import Foundation
import TDLibKitDynamic

extension ChatVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] update in
            guard let self, locationContextIsCurrent, update.chatId == customChat.id else { return }
            customChat.unreadCount = update.unreadCount
        }
        nc.publisher(&cancellables, for: .updateNewMessage) { [weak self] update in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateNewMessage(update)
        }
        nc.publisher(&cancellables, for: .updateDeleteMessages) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                updateDeleteMessages(update)
                if !update.fromCache,
                   update.isPermanent,
                   supportsPinnedMessages,
                   TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage.map({ update.messageIds.contains($0.id) }) == true
                {
                    applyPermanentPinnedMessageDeletion(update.messageIds)
                }
            }
            guard !update.fromCache else { return }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: Set(update.messageIds))
            if update.isPermanent {
                invalidateDeletedForwardTargets(chatID: update.chatId, messageIDs: Set(update.messageIds))
            }
        }
        nc.publisher(&cancellables, for: .updateMessageEdited) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                updateMessageEdited(update)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId])
        }
        nc.publisher(&cancellables, for: .updateMessageContent) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                refreshMessage(id: update.messageId)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId])
        }
        nc.publisher(&cancellables, for: .updateMessageInteractionInfo) { [weak self] update in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  let message = messages.first(where: { $0.id == update.messageId })
            else { return }
            message.reactions = update.interactionInfo?.reactions
        }
        nc.publisher(&cancellables, for: .updateMessageUnreadReactions) { [weak self] update in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  let message = messages.first(where: { $0.id == update.messageId })
            else { return }
            message.unreadReactions = update.unreadReactions
        }
        nc.publisher(&cancellables, for: .updateMessageIsPinned) { [weak self] update in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            applyPinnedMessageUpdate(messageID: update.messageId, isPinned: update.isPinned)
        }
        nc.publisher(&cancellables, for: .updateChatPermissions) { [weak self] update in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateChatPermissions(update.permissions)
        }
        nc.publisher(&cancellables, for: .updateChatAvailableReactions) { [weak self] update in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateAvailableReactions(update.availableReactions)
        }
        nc.publisher(&cancellables, for: .updateSupergroup) { [weak self] update in
            guard let self,
                  locationContextIsCurrent,
                  update.supergroup.id == customChat.supergroup?.id
            else { return }
            customChat.type = .supergroup(update.supergroup)
            objectWillChange.send()
        }
        nc.publisher(&cancellables, for: .updateForumTopicInfo) { [weak self] update in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateForumTopicInfo(update.info)
        }
        nc.publisher(&cancellables, for: .updateForumTopic) { [weak self] update in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  update.chatId == location.chatID,
                  update.forumTopicId == location.forumTopicID
            else { return }
            loadForumTopic()
        }
        nc.publisher(&cancellables, for: .updateMessageSendSucceeded) { [weak self] update in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendSucceeded(update)
        }
        nc.publisher(&cancellables, for: .updateMessageSendFailed) { [weak self] update in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendFailed(update)
        }
        nc.publisher(&cancellables, for: .voiceNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VoiceNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVoiceNoteDraftResolution(resolution)
        }
        nc.publisher(&cancellables, for: .videoNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VideoNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVideoNoteDraftResolution(resolution)
        }
        nc.publisher(&cancellables, for: .updateUserStatus) { [weak self] update in
            guard let self, locationContextIsCurrent, update.userId == customChat.user?.id else { return }
            onlineStatus = getOnlineStatus(from: update.status)
        }
        nc.publisher(&cancellables, for: .updateUser) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.update(user: update.user)
            for message in messages {
                if message.senderUser?.id == update.user.id {
                    message.senderUser = update.user
                }
            }
            refreshReferencedMetadata(userID: update.user.id)
        }
        nc.publisher(&cancellables, for: .updateChatTitle) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateChatPhoto) { [weak self] update in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId)
        }
        nc.publisher(&cancellables, for: .updateChatAction) { [weak self] update in
            guard let self,
                  locationContextIsCurrent,
                  update.chatId == customChat.id,
                  location.topic == nil || update.topicId == location.topic
            else { return }
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
        bufferPotentialVoiceMessageDeletions(update.messageIds)
        handlePotentialVideoMessageDeletions(update.messageIds)
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
            if let replacement,
               let index = messages.firstIndex(where: { $0.id == id })
            {
                messages[index] = replacement
                if replyMessage?.id == id {
                    replyMessage = replacement
                }
            }
        }
    }

    private func refreshReferencedMetadata(chatID: Int64, messageIDs: Set<Int64>) {
        let candidates = messages.filter { message in
            guard let reply = message.replyPresentation else { return false }
            return reply.targetChatID == chatID
                && reply.targetMessageID.map(messageIDs.contains) == true
        }
        for message in candidates {
            refreshMetadata(for: message)
        }
    }

    private func refreshReferencedMetadata(userID: Int64) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedUserID == userID
            let refreshForward = message.forwardPresentation?.referencedUserIDs.contains(userID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message)
            }
        }
    }

    private func invalidateDeletedForwardTargets(chatID: Int64, messageIDs: Set<Int64>) {
        for message in messages {
            guard let forward = message.forwardPresentation,
                  forward.targetChatID == chatID,
                  forward.targetMessageID.map(messageIDs.contains) == true
            else { continue }
            metadataRefreshGenerations[message.id] = UUID()
            message.forwardPresentation = forward.removingNavigationTarget()
        }
    }

    private func refreshReferencedMetadata(chatID: Int64) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedChatID == chatID
                || message.replyPresentation?.targetChatID == chatID
            let refreshForward = message.forwardPresentation?.referencedChatIDs.contains(chatID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message)
            }
        }
    }

    private func refreshMetadata(for message: CustomMessage) {
        let generation = UUID()
        metadataRefreshGenerations[message.id] = generation
        Task { [weak self, weak message] in
            guard let self, let message else { return }
            let previousForward = message.forwardPresentation
            async let replyPresentation = metadataResolver.replyPresentation(for: message.message)
            async let forwardPresentation = metadataResolver.forwardPresentation(for: message.message.forwardInfo)
            let resolvedReply = await replyPresentation
            var resolvedForward = await forwardPresentation
            if let previousForward,
               previousForward.navigationTarget == nil,
               previousForward.targetMessageID != nil,
               previousForward.targetChatID == resolvedForward?.targetChatID,
               previousForward.targetMessageID == resolvedForward?.targetMessageID
            {
                resolvedForward = resolvedForward?.removingNavigationTarget()
            }
            guard metadataRefreshGenerations[message.id] == generation,
                  messages.contains(where: { $0 === message })
            else { return }
            message.replyPresentation = resolvedReply
            message.forwardPresentation = resolvedForward
            metadataRefreshGenerations[message.id] = nil
        }
    }
}
