// ChatVM+Publishers.swift

import Combine
import Foundation
import TDLibKitDynamic

extension ChatVM {
    func setPublishers() {
        observeCurrentUpdate(.updateChatReadInbox) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.chatId == customChat.id else { return }
            customChat.unreadCount = update.unreadCount
        }
        observeCurrentUpdate(.updateNewMessage) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateNewMessage(update, authority: authority)
        }
        observeCurrentUpdate(.updateDeleteMessages) { [weak self] update, authority in
            guard let self else { return }
            if update.chatId == customChat.id {
                updateDeleteMessages(update, authority: authority)
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
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: Set(update.messageIds), authority: authority)
            if update.isPermanent {
                invalidateDeletedForwardTargets(chatID: update.chatId, messageIDs: Set(update.messageIds))
            }
        }
        observeCurrentUpdate(.updateMessageEdited) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                updateMessageEdited(update, authority: authority)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId], authority: authority)
        }
        observeCurrentUpdate(.updateMessageContent) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            if update.chatId == customChat.id {
                refreshMessage(id: update.messageId, authority: authority)
                if TDLib.shared.activeAccountID == accountID,
                   TDLib.shared.activeClient.id == client.id,
                   pinnedMessage?.id == update.messageId
                {
                    refreshPinnedMessages()
                }
            }
            refreshReferencedMetadata(chatID: update.chatId, messageIDs: [update.messageId], authority: authority)
        }
        observeCurrentUpdate(.updateMessageInteractionInfo) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  let message = messages.first(where: { $0.id == update.messageId })
            else { return }
            message.reactions = update.interactionInfo?.reactions
        }
        observeCurrentUpdate(.updateMessageUnreadReactions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  let message = messages.first(where: { $0.id == update.messageId })
            else { return }
            message.unreadReactions = update.unreadReactions
        }
        observeCurrentUpdate(.updateMessageIsPinned) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            applyPinnedMessageUpdate(messageID: update.messageId, isPinned: update.isPinned)
        }
        observeCurrentUpdate(.updateChatPermissions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateChatPermissions(update.permissions)
        }
        observeCurrentUpdate(.updateChatAvailableReactions) { [weak self] update, _ in
            guard let self, update.chatId == customChat.id,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateAvailableReactions(update.availableReactions)
        }
        observeCurrentUpdate(.updateSupergroup) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.supergroup.id == customChat.supergroup?.id
            else { return }
            customChat.type = .supergroup(update.supergroup)
            objectWillChange.send()
        }
        observeCurrentUpdate(.updateForumTopicInfo) { [weak self] update, _ in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            updateForumTopicInfo(update.info)
        }
        observeCurrentUpdate(.updateForumTopic) { [weak self] update, _ in
            guard let self,
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id,
                  update.chatId == location.chatID,
                  update.forumTopicId == location.forumTopicID
            else { return }
            loadForumTopic()
        }
        observeCurrentUpdate(.updateMessageSendSucceeded) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendSucceeded(update, authority: authority)
        }
        observeCurrentUpdate(.updateMessageSendFailed) { [weak self] update, authority in
            guard let self,
                  locationContextIsCurrent,
                  location.matches(message: update.message)
            else { return }
            updateMessageSendFailed(update, authority: authority)
        }
        nc.publisher(&cancellables, for: .voiceNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VoiceNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVoiceNoteDraftResolution(resolution)
        }
        nc.publisher(&cancellables, for: .voiceNoteDraftChanged) { [weak self] notification in
            guard let self, locationContextIsCurrent,
                  let change = notification.object as? VoiceNoteDraftChange,
                  change.destination == location.draftKey
            else { return }
            Task { [weak self] in await self?.refreshPendingVoiceDraft(id: change.draftID) }
        }
        nc.publisher(&cancellables, for: .videoNoteDraftResolved) { [weak self] notification in
            guard let self,
                  locationContextIsCurrent,
                  let resolution = notification.object as? VideoNoteDraftResolution,
                  resolution.draft.destination == location.draftKey
            else { return }
            handleVideoNoteDraftResolution(resolution)
        }
        observeCurrentUpdate(.updateUserStatus) { [weak self] update, _ in
            guard let self, locationContextIsCurrent, update.userId == customChat.user?.id else { return }
            onlineStatus = getOnlineStatus(from: update.status)
        }
        observeCurrentUpdate(.updateUser) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.update(user: update.user)
            for message in messages {
                if message.senderUser?.id == update.user.id {
                    message.senderUser = update.user
                }
            }
            refreshReferencedMetadata(userID: update.user.id, authority: authority)
        }
        observeCurrentUpdate(.updateChatTitle) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId, authority: authority)
        }
        observeCurrentUpdate(.updateChatPhoto) { [weak self] update, authority in
            guard let self, locationContextIsCurrent else { return }
            metadataResolver.invalidateChat(id: update.chatId)
            refreshReferencedMetadata(chatID: update.chatId, authority: authority)
        }
        observeCurrentUpdate(.updateChatAction) { [weak self] update, _ in
            guard let self,
                  locationContextIsCurrent,
                  update.chatId == customChat.id,
                  isAllMessagesForum
                  ? update.topicId == acceptedChatActionTopic
                  : (location.topic == nil || update.topicId == location.topic)
            else { return }
            updateChatAction(update)
        }
    }

    private func observeCurrentUpdate<Value>(
        _ notification: TdNotification<Value>,
        perform: @escaping (Value, ChatUpdateDeliveryAuthority) -> Void,
    ) {
        ChatUpdateDeliveryAuthority.observe(
            notification, center: nc, subscriptions: &cancellables, location: location,
            currentLocation: { [weak self] in self?.location },
            currentSource: { TDLib.shared.activeUpdateSource },
            ownerIsCurrent: { [weak self] in self?.locationContextIsCurrent == true },
            perform: perform,
        )
    }

    private func acceptsUpdate(_ authority: ChatUpdateDeliveryAuthority) -> Bool {
        !Task.isCancelled && authority.permits(
            currentLocation: location, currentSource: TDLib.shared.activeUpdateSource,
            ownerIsCurrent: locationContextIsCurrent,
        )
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

    private func updateMessageSendSucceeded(
        _ update: UpdateMessageSendSucceeded,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        sendTransitionMessageIDReplaced.send((update.oldMessageId, update.message.id))
        releaseOutgoingDocumentFile(messageID: update.oldMessageId)
        Task { [weak self] in
            guard let self, acceptsUpdate(authority) else { return }
            let replacement = await getCustomMessage(from: update.message)
            guard acceptsUpdate(authority) else { return }
            replaceSourceMessage(oldID: update.oldMessageId, with: replacement)
        }
    }

    private func updateMessageSendFailed(
        _ update: UpdateMessageSendFailed,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        sendTransitionMessageIDReplaced.send((update.oldMessageId, update.message.id))
        replaceOutgoingDocumentMessageID(old: update.oldMessageId, new: update.message.id)
        Task { [weak self] in
            guard let self, acceptsUpdate(authority) else { return }
            let replacement = await getCustomMessage(from: update.message)
            guard acceptsUpdate(authority) else { return }
            replacement.sendFailed = true
            replaceSourceMessage(oldID: update.oldMessageId, with: replacement)
        }
    }

    private func updateDeleteMessages(_ update: UpdateDeleteMessages, authority: ChatUpdateDeliveryAuthority) {
        guard !update.fromCache, update.isPermanent else { return }
        bufferPotentialVoiceMessageDeletions(update.messageIds)
        handlePotentialVideoMessageDeletions(update.messageIds)
        let deletedIDs = Set(update.messageIds)
        update.messageIds.forEach { releaseOutgoingDocumentFile(messageID: $0) }
        let deletedBubbleIDs = Set(messages.compactMap { message -> DisplayedMessageID? in
            message.sourceMessages.allSatisfy { deletedIDs.contains($0.id) }
                ? message.displayedID
                : nil
        })
        if !deletedBubbleIDs.isEmpty {
            messageBubblesWillDelete.send(deletedBubbleIDs)
        }
        var promotedRepresentativeIDs = [Int64]()
        messages = messages.compactMap { message in
            let remaining = message.sourceMessages.filter { !deletedIDs.contains($0.id) }
            guard !remaining.isEmpty else { return nil }
            guard case .album = message.displayedID else { return message }
            message.album = remaining.sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date
            }
            if deletedIDs.contains(message.message.id), let representative = message.album.first {
                message.message = representative
                message.formattedText = nil
                message.replyPresentation = nil
                message.forwardPresentation = nil
                message.reactions = representative.interactionInfo?.reactions
                message.unreadReactions = representative.unreadReactions
                message.isPinned = representative.isPinned
                promotedRepresentativeIDs.append(representative.id)
            }
            return message
        }
        promotedRepresentativeIDs.forEach { refreshMessage(id: $0, authority: authority) }
    }

    private func updateNewMessage(_ update: UpdateNewMessage, authority: ChatUpdateDeliveryAuthority) {
        Task { [weak self] in
            guard let self, acceptsUpdate(authority) else { return }
            let customMessage = await getCustomMessage(from: update.message)
            guard acceptsUpdate(authority) else { return }
            mergeIncomingMessages([customMessage])
        }
    }

    private func updateMessageEdited(_ update: UpdateMessageEdited, authority: ChatUpdateDeliveryAuthority) {
        refreshMessage(id: update.messageId, authority: authority)
    }

    private func refreshMessage(id: Int64, authority: ChatUpdateDeliveryAuthority) {
        Task { [weak self] in
            guard let self, acceptsUpdate(authority) else { return }
            guard let message = try? await client.getMessage(chatId: chatID, messageId: id),
                  acceptsUpdate(authority), location.matches(message: message)
            else { return }
            let replacement = await getCustomMessage(from: message)
            guard acceptsUpdate(authority) else { return }
            replaceSourceMessage(oldID: id, with: replacement)
        }
    }

    private func refreshReferencedMetadata(
        chatID: Int64,
        messageIDs: Set<Int64>,
        authority: ChatUpdateDeliveryAuthority,
    ) {
        let candidates = messages.filter { message in
            guard let reply = message.replyPresentation else { return false }
            return reply.targetChatID == chatID
                && reply.targetMessageID.map(messageIDs.contains) == true
        }
        for message in candidates {
            refreshMetadata(for: message, authority: authority)
        }
    }

    private func refreshReferencedMetadata(userID: Int64, authority: ChatUpdateDeliveryAuthority) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedUserID == userID
            let refreshForward = message.forwardPresentation?.referencedUserIDs.contains(userID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message, authority: authority)
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

    private func refreshReferencedMetadata(chatID: Int64, authority: ChatUpdateDeliveryAuthority) {
        for message in messages {
            let refreshReply = message.replyPresentation?.referencedChatID == chatID
                || message.replyPresentation?.targetChatID == chatID
            let refreshForward = message.forwardPresentation?.referencedChatIDs.contains(chatID) == true
            if refreshReply || refreshForward {
                refreshMetadata(for: message, authority: authority)
            }
        }
    }

    private func refreshMetadata(for message: CustomMessage, authority: ChatUpdateDeliveryAuthority) {
        let generation = UUID()
        metadataRefreshGenerations[message.id] = generation
        Task { [weak self, weak message] in
            guard let self, let message, acceptsUpdate(authority) else { return }
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
            guard acceptsUpdate(authority), metadataRefreshGenerations[message.id] == generation,
                  messages.contains(where: { $0 === message })
            else { return }
            message.replyPresentation = resolvedReply
            message.forwardPresentation = resolvedForward
            metadataRefreshGenerations[message.id] = nil
        }
    }
}
